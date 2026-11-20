import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../pitch/adapters/audio_route.dart';
import '../pitch/adapters/record_pitch_source.dart';
import '../pitch/pitch_source.dart';
import '../practice/bleed_check.dart';
import '../practice/playback_clock.dart';
import '../practice/vocal_practice.dart';
import '../practice/vocal_turns.dart';
import '../reference/pitch_reference.dart';
import '../reference/voice_store.dart';
import 'cents_meter.dart';
import 'guide_player.dart';
import 'pitch_roll.dart';
import 'vocal_summary_panel.dart';

enum _Phase { setup, running, finished }

/// What a running practice is doing now.
enum _Step {
  /// Together: the guide plays the first note alone while the student keeps
  /// quiet; the microphone must not hear it.
  firstNote,

  /// Together: singing with the guide.
  together,

  /// Echo or drill: the guide sings the turn; the microphone does not count.
  listen,

  /// Echo or drill: the student's turn, timed on screen.
  turn,

  /// Echo or drill: how the turn went, a moment before the next one.
  feedback,
}

/// Sing an exercise and see your pitch against the melody.
///
/// "Escucha y repite" (the default) plays a phrase and then stops while the
/// student repeats it: the microphone never counts while the guide sounds,
/// so it works without headphones. "Con la guía" sings along like karaoke,
/// only with headphones and after checking that the microphone does not hear
/// the guide. Nothing leaves the phone: the voice is measured here and only a
/// summary is kept, on this device.
class SingingPracticeScreen extends StatefulWidget {
  const SingingPracticeScreen({
    required this.routine,
    this.store,
    this.createSource,
    this.createPlayer,
    this.audioRoute,
    this.clock,
    super.key,
  });

  final SavedVoiceRoutine routine;

  /// Keeps the summary in the local history; none in tests.
  final VoiceStore? store;
  final PitchSource Function()? createSource;
  final GuidePlayer Function()? createPlayer;
  final AudioRoute? audioRoute;

  /// Milliseconds since an arbitrary start; injectable for tests.
  final int Function()? clock;

  /// The microphone and the detector, when the student follows the screen
  /// instead of the guide (provisional).
  static const micLatencyMs = 80;

  /// The guide is muted this much before a phrase ends, so a late pause never
  /// lets the next note sound.
  static const muteEarlyMs = 30;

  /// Listening after the test note stops: Bluetooth arrives late.
  static const echoCheckTailMs = 400;
  static const firstNoteMaxMs = 1500;
  static const turnTailMs = 400;
  static const feedbackMs = 1500;
  static const speeds = [0.5, 0.75, 1.0];

  @override
  State<SingingPracticeScreen> createState() => _SingingPracticeScreenState();
}

class _SingingPracticeScreenState extends State<SingingPracticeScreen>
    with WidgetsBindingObserver {
  _Phase _phase = _Phase.setup;
  PracticeMode _mode = PracticeMode.echo;
  double _speed = 0.75;
  double _guideVolume = 0.8;
  GuideOutput? _output;
  String? _message;
  bool _starting = false;

  PitchSource? _source;
  GuidePlayer? _player;
  StreamSubscription<PitchSample>? _samples;
  VocalPractice? _practice;
  PracticeMode _runningMode = PracticeMode.echo;
  final _playback = PlaybackClock();
  final _stopwatch = Stopwatch()..start();
  final _now = ValueNotifier<int>(0);
  final _cents = ValueNotifier<double?>(null);
  final _trail = <TrailPoint>[];
  Timer? _frames, _routeTimer;
  bool _busy = false, _checkingRoute = false;
  LiveVocalState _live = const LiveVocalState();
  VocalSummary? _summary;

  _Step _step = _Step.listen;
  List<VocalTurn> _turns = const [];
  int _turnIndex = 0, _turnStartWall = 0;
  int? _stepUntil, _segmentEnd;
  List<NoteResult>? _turnResults;
  final _echoCheck = <double?>[];

  /// The note being drilled from the summary, and how each attempt went.
  int? _drillIndex;
  final _drillAttempts = <NoteResult>[];

  PitchReference get _reference => widget.routine.reference;
  AudioRoute get _route => widget.audioRoute ?? const PlatformAudioRoute();
  int _wallMs() => widget.clock?.call() ?? _stopwatch.elapsedMilliseconds;
  bool get _active => mounted && _phase == _Phase.running;
  VocalTurn get _turn => _turns[_turnIndex];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_detectOutput());
  }

  Future<void> _detectOutput() async {
    final output = await _route.current();
    if (!mounted) return;
    setState(() {
      _output = output;
      if (!output.allowsTogether && _mode == PracticeMode.together) {
        _mode = PracticeMode.echo;
      }
    });
  }

  /// The microphone is never open in the background. `inactive` is not
  /// enough: the notification shade, a call banner or the permission dialog
  /// cause it too.
  static bool _away(AppLifecycleState? state) =>
      state == AppLifecycleState.paused ||
      state == AppLifecycleState.hidden ||
      state == AppLifecycleState.detached;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_away(state) && _phase == _Phase.running) {
      unawaited(_finish(reachedEnd: false));
    } else if (state == AppLifecycleState.resumed && _phase == _Phase.setup) {
      // Headphones may have been plugged in meanwhile.
      unawaited(_detectOutput());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_release());
    _now.dispose();
    _cents.dispose();
    super.dispose();
  }

  Future<void> _release() async {
    _frames?.cancel();
    _frames = null;
    _routeTimer?.cancel();
    _routeTimer = null;
    final samples = _samples, source = _source, player = _player;
    _samples = null;
    _source = null;
    _player = null;
    await samples?.cancel();
    await source?.stop();
    player?.removeListener(_onPlayer);
    await player?.dispose();
    _busy = false;
    unawaited(WakelockPlus.disable().catchError((_) {}));
  }

  // ---------------------------------------------------------------- start

  Future<void> _start({int? drillIndex}) async {
    final mode = drillIndex != null ? PracticeMode.drill : _mode;
    setState(() {
      _starting = true;
      _message = null;
    });
    final output = await _route.current();
    if (!mounted) return;
    _output = output;
    if (mode == PracticeMode.together && !output.allowsTogether) {
      setState(() {
        _starting = false;
        _mode = PracticeMode.echo;
        _message =
            'No hay audífonos conectados: el micrófono oiría la guía y la '
            'confundiría con tu voz. Conéctalos para cantar con la guía, o '
            'usa «Escucha y repite», que funciona sin ellos.';
      });
      return;
    }
    final source = (widget.createSource ?? RecordPitchSource.new)();
    GuidePlayer? opened;
    try {
      final allowed = await source.requestPermission();
      // Left while the permission dialog was open: only the source to free.
      if (!mounted) {
        await source.stop();
        return;
      }
      if (!allowed) {
        unawaited(source.stop());
        setState(() {
          _starting = false;
          _message =
              'Sin permiso de micrófono no se puede medir tu voz. '
              'Actívalo en los ajustes del teléfono.';
        });
        return;
      }
      final player = opened = (widget.createPlayer ?? VideoGuidePlayer.new)();
      await player.open(widget.routine.audio);
      await player.setVolume(_guideVolume);
      await player.setSpeed(_speed);
      // Left while the guide was opening: dispose() already ran, so the
      // microphone must not be started for a screen that is gone.
      if (!mounted) {
        await player.dispose();
        await source.stop();
        return;
      }
      // Sent to the background while the guide was opening: the lifecycle
      // stop only covers a running practice, so nothing starts from here.
      if (_away(WidgetsBinding.instance.lifecycleState)) {
        await player.dispose();
        await source.stop();
        if (mounted) setState(() => _starting = false);
        return;
      }
      _player = player;
      _source = source;
      _runningMode = mode;
      _practice = VocalPractice(
        _reference,
        latencyMs: mode == PracticeMode.together
            ? output.latencyMs
            : SingingPracticeScreen.micLatencyMs,
        speed: _speed,
        mode: mode,
      );
      _turns = switch (mode) {
        PracticeMode.echo => echoTurns(_reference),
        PracticeMode.drill => drillTurns(_reference, drillIndex!),
        PracticeMode.together => const <VocalTurn>[],
      };
      _turnIndex = 0;
      _drillIndex = drillIndex;
      _drillAttempts.clear();
      _trail.clear();
      _playback
        ..reset()
        ..speed = _speed;
      player.addListener(_onPlayer);
      // Running from here: a microphone error during the start ends it too.
      _phase = _Phase.running;
      _busy = true;
      _samples = source.start().listen(
        _onSample,
        onError: (Object _) {
          _message = 'El micrófono dejó de responder.';
          unawaited(_finish(reachedEnd: false));
        },
      );
      unawaited(WakelockPlus.enable().catchError((_) {}));
      _frames = Timer.periodic(
        const Duration(milliseconds: 33),
        (_) => _tick(),
      );
      if (mode == PracticeMode.together) {
        _routeTimer = Timer.periodic(
          const Duration(seconds: 1),
          (_) => unawaited(_checkRoute()),
        );
        await _playFirstNote();
      } else {
        await _listen(0);
      }
      // dispose() or a microphone error already released everything.
      if (!_active) return;
      _busy = false;
      setState(() => _starting = false);
    } catch (_) {
      // A note drill comes from the summary and goes back to it.
      _phase = drillIndex != null && _summary != null
          ? _Phase.finished
          : _Phase.setup;
      _drillIndex = null;
      await source.stop();
      // A player that never became ours is released here.
      if (opened != null && _player == null) await opened.dispose();
      await _release();
      if (mounted) {
        setState(() {
          _starting = false;
          _message = 'No se pudo abrir el audio o el micrófono.';
        });
      }
    }
  }

  // ------------------------------------------------------------ the guide

  void _onPlayer() {
    final player = _player;
    if (player == null || _phase != _Phase.running) return;
    _playback.report(
      positionMs: player.positionMs,
      nowMs: _wallMs(),
      playing: player.isPlaying,
    );
    if (_step == _Step.together &&
        (player.isCompleted ||
            (player.durationMs > 0 &&
                player.positionMs >= player.durationMs))) {
      unawaited(_finish(reachedEnd: true));
    }
  }

  Future<void> _playSegment(int fromMs) async {
    final player = _player;
    if (player == null) return;
    _playback.reset();
    await player.seekTo(fromMs);
    await player.play();
  }

  /// Muted first, then paused: a pause that lands late plays nothing more.
  Future<void> _silenceGuide() async {
    final player = _player;
    if (player == null) return;
    await player.setVolume(0);
    await player.pause();
    await player.setVolume(_guideVolume);
  }

  /// One change of step at a time; a failure of the guide ends the practice.
  Future<void> _transition(Future<void> Function() action) async {
    if (_busy || !_active) return;
    _busy = true;
    try {
      await action();
    } catch (_) {
      if (_phase == _Phase.running) {
        _message = 'La guía dejó de responder.';
        await _finish(reachedEnd: false);
      }
    } finally {
      _busy = false;
    }
  }

  void _tick() {
    if (_phase != _Phase.running || _busy) return;
    final wall = _wallMs();
    final position = _playback.positionAt(wall);
    final completed = _player?.isCompleted ?? false;
    switch (_step) {
      case _Step.firstNote:
        final end = _segmentEnd;
        if (end != null) {
          if (position != null) _now.value = position;
          if (completed ||
              (position != null &&
                  position >= end - SingingPracticeScreen.muteEarlyMs)) {
            unawaited(
              _transition(() async {
                await _silenceGuide();
                _segmentEnd = null;
                _stepUntil = _wallMs() + SingingPracticeScreen.echoCheckTailMs;
              }),
            );
          }
        } else if (wall >= (_stepUntil ?? wall)) {
          unawaited(_transition(_afterFirstNote));
        }
      case _Step.together:
        if (position != null) _now.value = position - _practice!.lagMs;
      case _Step.listen:
        if (position != null) _now.value = position;
        if (completed ||
            (position != null &&
                position >=
                    _turn.listenToMs - SingingPracticeScreen.muteEarlyMs)) {
          unawaited(_transition(_beginTurn));
        }
      case _Step.turn:
        final timeline = _timeline(wall);
        _now.value = timeline;
        if (timeline >= _turn.endMs + SingingPracticeScreen.turnTailMs) {
          _endTurn();
        }
      case _Step.feedback:
        if (wall >= (_stepUntil ?? wall)) unawaited(_transition(_nextTurn));
    }
  }

  // ------------------------------------------------- together with the guide

  /// The first note alone, before the count-in: the student hears where to
  /// start, and the microphone shows whether it hears the guide.
  Future<void> _playFirstNote() async {
    final first = _reference.notes.first;
    _step = _Step.firstNote;
    _echoCheck.clear();
    _stepUntil = null;
    _segmentEnd = math.min(
      first.endMs,
      first.startMs + SingingPracticeScreen.firstNoteMaxMs,
    );
    if (mounted) setState(() {});
    await _playSegment(first.startMs);
  }

  Future<void> _afterFirstNote() async {
    if (hearsGuide(_echoCheck, _reference.notes.first.midi)) {
      await _abort(
        'El micrófono oyó la guía mientras no cantabas, así que la '
        'confundiría con tu voz. Ajusta los audífonos o baja el volumen y '
        'prueba otra vez, o usa «Escucha y repite».',
      );
      return;
    }
    _step = _Step.together;
    _trail.clear();
    _live = const LiveVocalState();
    if (mounted) setState(() {});
    await _playSegment(0);
  }

  Future<void> _checkRoute() async {
    if (_checkingRoute || _phase != _Phase.running) return;
    _checkingRoute = true;
    try {
      final output = await _route.current();
      if (_phase == _Phase.running &&
          _runningMode == PracticeMode.together &&
          !output.allowsTogether) {
        _message =
            'Se desconectaron los audífonos: desde ahí el micrófono oiría la '
            'guía, así que la práctica se detuvo.';
        await _finish(reachedEnd: false);
      }
    } finally {
      _checkingRoute = false;
    }
  }

  // ------------------------------------------------------- echo and drill

  int _timeline(int wall) =>
      _turn.startMs -
      turnLeadInMs(_reference) +
      ((wall - _turnStartWall) * _speed).round();

  Future<void> _listen(int index) async {
    _turnIndex = index;
    _practice!.restart(_turn);
    _turnResults = null;
    _trail.clear();
    _step = _Step.listen;
    _live = const LiveVocalState();
    _cents.value = null;
    if (mounted) setState(() {});
    await _playSegment(_turn.listenFromMs);
  }

  Future<void> _beginTurn() async {
    await _silenceGuide();
    if (!_active) return;
    _trail.clear();
    _turnStartWall = _wallMs();
    _step = _Step.turn;
    _now.value = _timeline(_turnStartWall);
    setState(() => _live = const LiveVocalState());
  }

  void _endTurn() {
    final results = [for (final i in _turn.indices) _practice!.resultOf(i)];
    if (_runningMode == PracticeMode.drill) _drillAttempts.add(results.single);
    _turnResults = results;
    _step = _Step.feedback;
    _stepUntil = _wallMs() + SingingPracticeScreen.feedbackMs;
    _cents.value = null;
    setState(() => _live = const LiveVocalState());
  }

  Future<void> _nextTurn() async {
    if (_turnIndex + 1 < _turns.length) {
      await _listen(_turnIndex + 1);
    } else {
      await _finish(reachedEnd: true);
    }
  }

  void _repeatTurn() => unawaited(
    _transition(() async {
      await _silenceGuide();
      if (_active) await _listen(_turnIndex);
    }),
  );

  // ---------------------------------------------------------- the voice

  void _onSample(PitchSample sample) {
    final practice = _practice;
    if (practice == null || _phase != _Phase.running) return;
    final wall = _wallMs();
    LiveVocalState live;
    if (_step == _Step.firstNote) {
      _echoCheck.add(sample.midi);
      return;
    } else if (_step == _Step.together) {
      final guide = _playback.positionAt(wall);
      if (guide == null) return;
      live = practice.onSample(sample, guide);
      _addTrail(guide - practice.lagMs, live);
    } else if (_step == _Step.turn) {
      final timeline = _timeline(wall);
      live = practice.onTurnSample(sample, timeline, _turn);
      _addTrail(timeline - practice.lagMs, live);
    } else {
      // The guide is singing, or the turn is over: nothing to measure.
      return;
    }
    _cents.value = live.cents;
    if (live.cue != _live.cue || live.expected != _live.expected) {
      setState(() => _live = live);
    } else {
      _live = live;
    }
  }

  void _addTrail(int atMs, LiveVocalState live) {
    final midi = live.sungMidi, cents = live.cents;
    if (midi == null || cents == null) return;
    _trail.add(TrailPoint(atMs, midi, gradeOf(cents)));
    final keep = atMs - PitchRoll.pastMs - 1000;
    _trail.removeWhere((point) => point.atMs < keep);
  }

  // ---------------------------------------------------------------- end

  Future<void> _finish({required bool reachedEnd}) async {
    if (_phase != _Phase.running) return;
    final practice = _practice!;
    final mode = _runningMode;
    _phase = _Phase.finished;
    await _release();
    if (mode == PracticeMode.drill) {
      if (mounted) setState(() => _starting = false);
      return;
    }
    final summary = practice.finish(reachedEnd: reachedEnd);
    try {
      await widget.store?.addRecord(
        VocalRecord.of(
          widget.routine.name,
          _reference,
          summary,
          DateTime.now(),
        ),
      );
    } catch (_) {
      _message = 'No se pudo guardar el resumen en este teléfono.';
    }
    if (mounted) {
      setState(() {
        _summary = summary;
        _starting = false;
      });
    }
  }

  /// Back to the setup without a summary: the measurement would not be true.
  Future<void> _abort(String message) async {
    if (_phase != _Phase.running) return;
    _phase = _Phase.setup;
    await _release();
    if (mounted) {
      setState(() {
        _message = message;
        _mode = PracticeMode.echo;
        _starting = false;
        _live = const LiveVocalState();
      });
    }
  }

  void _again() => setState(() {
    _phase = _Phase.setup;
    _message = null;
    _summary = null;
    _drillIndex = null;
    _live = const LiveVocalState();
  });

  // ------------------------------------------------------------------ UI

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.routine.name)),
    body: SafeArea(
      child: switch (_phase) {
        _Phase.setup => _setup(context),
        _Phase.running => _running(context),
        _Phase.finished => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_message != null) _notice(context, _message!),
            if (_drillIndex case final index?)
              DrillPanel(
                note: _reference.notes[index],
                attempts: List.of(_drillAttempts),
                busy: _starting,
                onAgain: () => _start(drillIndex: index),
                onBack: () => setState(() {
                  _drillIndex = null;
                  _message = null;
                }),
              )
            else if (_summary != null)
              VocalSummaryPanel(
                summary: _summary!,
                busy: _starting,
                onAgain: _again,
                onDone: () => Navigator.of(context).maybePop(),
                onPractice: (index) => _start(drillIndex: index),
              ),
          ],
        ),
      },
    ),
  );

  Widget _notice(BuildContext context, String text) => Card(
    color: Theme.of(context).colorScheme.errorContainer,
    child: Padding(padding: const EdgeInsets.all(12), child: Text(text)),
  );

  Widget _setup(BuildContext context) {
    final theme = Theme.of(context);
    final output = _output;
    final together = output?.allowsTogether ?? false;
    final first = _reference.notes.first;
    final options = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_message != null) _notice(context, _message!),
        Text('Antes de cantar', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          'Tu primera nota es ${solfege(first.midi)} (${first.name}). Puedes '
          'cantar en tu octava: un hombre puede cantar una octava más abajo.',
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: Icon(
              output == null || output == GuideOutput.speaker
                  ? Icons.volume_up
                  : Icons.headphones,
            ),
            title: Text(output?.label ?? 'Revisando la salida de audio…'),
            subtitle: Text(switch (output) {
              GuideOutput.speaker =>
                'Sin audífonos la guía y tu voz no pueden sonar a la vez: '
                    'practica con «Escucha y repite».',
              GuideOutput.unknown =>
                'Antes de cantar con la guía se comprueba que el micrófono no '
                    'la oiga.',
              null => '',
              _ => 'Puedes cantar con la guía o escuchar y repetir.',
            }),
            trailing: IconButton(
              tooltip: 'Revisar audífonos',
              icon: const Icon(Icons.refresh),
              onPressed: _starting ? null : _detectOutput,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text('¿Cómo quieres practicar?', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        SegmentedButton<PracticeMode>(
          segments: [
            const ButtonSegment(
              value: PracticeMode.echo,
              icon: Icon(Icons.hearing),
              label: Text('Escucha y repite'),
            ),
            ButtonSegment(
              value: PracticeMode.together,
              icon: const Icon(Icons.headphones),
              label: const Text('Con la guía'),
              enabled: together,
            ),
          ],
          selected: {_mode},
          onSelectionChanged: (choice) => setState(() => _mode = choice.first),
        ),
        const SizedBox(height: 8),
        Text(switch (_mode) {
          PracticeMode.together =>
            'Cantas al mismo tiempo que la guía. Primero suena tu primera '
                'nota: no cantes en ese momento, así se comprueba que el '
                'micrófono no oiga los audífonos.',
          _ =>
            'La guía canta una frase corta y se calla; luego la cantas tú '
                'siguiendo las barras. Así aprendes la melodía por partes.',
        }, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 16),
        Text('Velocidad', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        SegmentedButton<double>(
          segments: [
            for (final speed in SingingPracticeScreen.speeds)
              ButtonSegment(
                value: speed,
                label: Text(switch (speed) {
                  0.5 => 'Muy lento',
                  0.75 => 'Lento',
                  _ => 'Normal',
                }),
              ),
          ],
          selected: {_speed},
          onSelectionChanged: (choice) => setState(() => _speed = choice.first),
        ),
        const SizedBox(height: 4),
        Text(
          'Más lento no cambia las notas, solo el tiempo.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        Text('Volumen de la guía', style: theme.textTheme.titleMedium),
        Slider(
          value: _guideVolume,
          divisions: 10,
          label: '${(_guideVolume * 100).round()} %',
          onChanged: (value) => setState(() => _guideVolume = value),
        ),
      ],
    );
    // The start stays in sight however long the options get.
    return Column(
      children: [
        Expanded(child: options),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton.icon(
                onPressed: _starting ? null : _start,
                icon: const Icon(Icons.mic),
                label: Text(_starting ? 'Preparando…' : 'Empezar a cantar'),
              ),
              const SizedBox(height: 8),
              Text(
                'Tu voz se mide en este teléfono y no se graba ni se envía.',
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _running(BuildContext context) {
    final theme = Theme.of(context);
    final echo = _runningMode == PracticeMode.echo;
    final drill = _runningMode == PracticeMode.drill;
    final notes = switch (_step) {
      _Step.turn || _Step.feedback => _turn.notes,
      _Step.listen => [for (final i in _turn.indices) _reference.notes[i]],
      _ => _reference.notes,
    };
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: _header(context),
        ),
        if (echo || drill)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                drill
                    ? 'Intento ${_turnIndex + 1} de ${_turns.length}'
                    : 'Frase ${_turnIndex + 1} de ${_turns.length}',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: CustomPaint(
              size: Size.infinite,
              painter: PitchRoll(
                notes: notes,
                range: _reference.range,
                now: _now,
                trail: _trail,
                colors: theme.colorScheme,
              ),
            ),
          ),
        ),
        if (_step == _Step.feedback && _turnResults != null)
          _TurnFeedback(_turnResults!)
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: CentsMeter(cents: _cents),
          ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              if (echo) ...[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _repeatTurn,
                    icon: const Icon(Icons.replay),
                    label: const Text('Repetir frase'),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _finish(reachedEnd: false),
                  icon: const Icon(Icons.stop),
                  label: const Text('Terminar'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _header(BuildContext context) {
    final theme = Theme.of(context);
    Widget line(IconData icon, String title, [String? subtitle]) => Row(
      children: [
        Icon(icon, color: theme.colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.headlineSmall),
              if (subtitle != null) Text(subtitle),
            ],
          ),
        ),
      ],
    );
    final first = _reference.notes.first;
    return switch (_step) {
      _Step.firstNote => line(
        Icons.hearing,
        'Escucha tu primera nota',
        '${solfege(first.midi)} (${first.name}). No cantes todavía.',
      ),
      _Step.listen => line(Icons.hearing, 'Escucha…', 'Luego la cantas tú.'),
      _Step.feedback => line(
        Icons.flag_outlined,
        turnVerdict(_turnResults ?? const []),
      ),
      _Step.turn => ValueListenableBuilder<int>(
        valueListenable: _now,
        builder: (context, now, _) {
          final ahead = _turn.startMs - now;
          if (ahead > 0) {
            final beat = _reference.beatMs ?? 500;
            return line(
              Icons.mic,
              'Tu turno en ${(ahead / beat).ceil()}…',
              'Canta cuando la barra llegue a la línea.',
            );
          }
          return _cueLine(context, '¡Canta!');
        },
      ),
      _Step.together => _cueLine(context, 'Canta con la guía'),
    };
  }

  Widget _cueLine(BuildContext context, String idle) {
    final theme = Theme.of(context);
    final expected = _live.expected;
    final color = switch (_live.cue) {
      VocalCue.onPitch => Colors.green.shade700,
      VocalCue.slightlyHigher ||
      VocalCue.slightlyLower => Colors.amber.shade900,
      VocalCue.higher || VocalCue.lower => theme.colorScheme.tertiary,
      null => theme.colorScheme.onSurfaceVariant,
    };
    final text = expected == null
        ? idle
        : cueText(_live.cue, expected: expected);
    return Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.headlineSmall?.copyWith(color: color),
            semanticsLabel: text,
          ),
        ),
        if (expected != null)
          Text(
            '${solfege(expected.midi)} (${expected.name})',
            style: theme.textTheme.titleMedium,
          ),
      ],
    );
  }
}

/// One line about a turn the student just sang.
String turnVerdict(List<NoteResult> results) {
  final sung = results.where((r) => r.sung).length;
  if (sung == 0) return 'No se oyó tu voz';
  final inTune = results.where((r) => r.grade == NoteGrade.inTune).length;
  if (inTune == results.length) return '¡Muy bien, todas afinadas!';
  final close = results.where((r) => r.grade == NoteGrade.close).length;
  return [
    '$inTune de ${results.length} afinadas',
    if (close > 0) '$close casi',
  ].join(', ');
}

class _TurnFeedback extends StatelessWidget {
  const _TurnFeedback(this.results);
  final List<NoteResult> results;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (final result in results)
          Chip(
            avatar: Icon(
              gradeText(result).$1,
              size: 18,
              color: gradeColor(result),
            ),
            label: Text(solfege(result.note.midi)),
          ),
      ],
    ),
  );
}
