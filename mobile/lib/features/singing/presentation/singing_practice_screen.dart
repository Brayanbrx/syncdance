import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../pitch/adapters/record_pitch_source.dart';
import '../pitch/pitch_source.dart';
import '../practice/playback_clock.dart';
import '../practice/vocal_practice.dart';
import '../reference/pitch_reference.dart';
import '../reference/voice_store.dart';
import 'guide_player.dart';
import 'pitch_roll.dart';
import 'vocal_summary_panel.dart';

/// How the guide reaches the ears; it decides how late the voice arrives.
enum Headphones {
  wired('Con cable', 120),
  bluetooth('Bluetooth', 300),
  none('Sin audífonos', 120);

  const Headphones(this.label, this.latencyMs);
  final String label;

  /// Guide out, ears, voice, microphone and detector (provisional).
  final int latencyMs;
}

enum _Phase { setup, running, finished }

/// Sing along with the guide and see your pitch against the melody.
/// Nothing leaves the phone: the voice is measured here and only a summary is
/// kept, on this device.
class SingingPracticeScreen extends StatefulWidget {
  const SingingPracticeScreen({
    required this.routine,
    this.store,
    this.createSource,
    this.createPlayer,
    this.clock,
    super.key,
  });

  final SavedVoiceRoutine routine;

  /// Keeps the summary in the local history; none in tests.
  final VoiceStore? store;
  final PitchSource Function()? createSource;
  final GuidePlayer Function()? createPlayer;

  /// Milliseconds since an arbitrary start; injectable for tests.
  final int Function()? clock;

  @override
  State<SingingPracticeScreen> createState() => _SingingPracticeScreenState();
}

class _SingingPracticeScreenState extends State<SingingPracticeScreen>
    with WidgetsBindingObserver {
  _Phase _phase = _Phase.setup;
  Headphones _headphones = Headphones.wired;
  double _guideVolume = 0.8;
  String? _message;
  bool _starting = false;

  PitchSource? _source;
  GuidePlayer? _player;
  StreamSubscription<PitchSample>? _samples;
  VocalPractice? _practice;
  final _playback = PlaybackClock();
  final _stopwatch = Stopwatch()..start();
  final _now = ValueNotifier<int>(0);
  final _trail = <TrailPoint>[];
  Timer? _frames;
  LiveVocalState _live = const LiveVocalState();
  VocalSummary? _summary;

  PitchReference get _reference => widget.routine.reference;
  int _wallMs() => widget.clock?.call() ?? _stopwatch.elapsedMilliseconds;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The microphone is never left open in the background. `inactive` is not
    // enough: the notification shade or a call banner cause it too.
    final away =
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached;
    if (away && _phase == _Phase.running) {
      unawaited(_finish(reachedEnd: false));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_release());
    _now.dispose();
    super.dispose();
  }

  Future<void> _release() async {
    _frames?.cancel();
    _frames = null;
    final samples = _samples, source = _source, player = _player;
    _samples = null;
    _source = null;
    _player = null;
    await samples?.cancel();
    await source?.stop();
    player?.removeListener(_onPlayer);
    await player?.dispose();
    unawaited(WakelockPlus.disable().catchError((_) {}));
  }

  Future<void> _start() async {
    setState(() {
      _starting = true;
      _message = null;
    });
    final source = (widget.createSource ?? RecordPitchSource.new)();
    try {
      if (!await source.requestPermission()) {
        setState(() {
          _starting = false;
          _message =
              'Sin permiso de micrófono no se puede medir tu voz. '
              'Actívalo en los ajustes del teléfono.';
        });
        return;
      }
      final player = (widget.createPlayer ?? VideoGuidePlayer.new)();
      await player.open(widget.routine.audio);
      await player.setVolume(_guideVolume);
      _player = player;
      _source = source;
      _practice = VocalPractice(_reference, latencyMs: _headphones.latencyMs);
      _trail.clear();
      _playback.reset();
      player.addListener(_onPlayer);
      _samples = source.start().listen(
        _onSample,
        onError: (Object _) {
          _message = 'El micrófono dejó de responder.';
          unawaited(_finish(reachedEnd: false));
        },
      );
      unawaited(WakelockPlus.enable().catchError((_) {}));
      await player.play();
      _frames = Timer.periodic(const Duration(milliseconds: 33), (_) {
        final position = _playback.positionAt(_wallMs());
        if (position != null) _now.value = position - _headphones.latencyMs;
      });
      if (mounted) {
        setState(() {
          _phase = _Phase.running;
          _starting = false;
        });
      }
    } catch (_) {
      await source.stop();
      await _release();
      if (mounted) {
        setState(() {
          _starting = false;
          _message = 'No se pudo abrir el audio o el micrófono.';
        });
      }
    }
  }

  void _onPlayer() {
    final player = _player;
    if (player == null || _phase != _Phase.running) return;
    _playback.report(
      positionMs: player.positionMs,
      nowMs: _wallMs(),
      playing: player.isPlaying,
    );
    if (player.isCompleted ||
        (player.durationMs > 0 && player.positionMs >= player.durationMs)) {
      unawaited(_finish(reachedEnd: true));
    }
  }

  void _onSample(PitchSample sample) {
    final practice = _practice;
    final guide = _playback.positionAt(_wallMs());
    if (practice == null || guide == null || _phase != _Phase.running) return;
    final live = practice.onSample(sample, guide);
    if (live.sungMidi != null) {
      _trail.add(
        TrailPoint(
          guide - practice.latencyMs,
          live.sungMidi!,
          (live.cents?.abs() ?? double.infinity) <= VocalPractice.centThreshold,
        ),
      );
      final keep = guide - PitchRoll.pastMs - 1000;
      _trail.removeWhere((point) => point.atMs < keep);
    }
    if (live.cue != _live.cue || live.expected != _live.expected) {
      setState(() => _live = live);
    } else {
      _live = live;
    }
  }

  Future<void> _finish({required bool reachedEnd}) async {
    if (_phase != _Phase.running) return;
    final practice = _practice!;
    _phase = _Phase.finished;
    await _release();
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
    if (mounted) setState(() => _summary = summary);
  }

  void _again() => setState(() {
    _phase = _Phase.setup;
    _summary = null;
    _live = const LiveVocalState();
  });

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
            if (_summary != null)
              VocalSummaryPanel(
                summary: _summary!,
                onAgain: _again,
                onDone: () => Navigator.of(context).maybePop(),
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
    final grid = _reference.metadata.beatGrid;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_message != null) _notice(context, _message!),
        Text('Antes de cantar', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          grid != null
              ? 'Escucha cuatro golpes de cuenta y empieza a cantar con la guía. '
                    'Puedes cantar en tu octava: un hombre puede cantar una '
                    'octava más abajo.'
              : 'Canta junto con la voz del instructor. Puedes cantar en tu '
                    'octava.',
        ),
        const SizedBox(height: 16),
        Text('¿Cómo escuchas la guía?', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        SegmentedButton<Headphones>(
          segments: [
            for (final option in Headphones.values)
              ButtonSegment(value: option, label: Text(option.label)),
          ],
          selected: {_headphones},
          onSelectionChanged: (choice) =>
              setState(() => _headphones = choice.first),
        ),
        if (_headphones == Headphones.none)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Sin audífonos el micrófono también oye la guía y la medición '
              'se confunde. Úsalos si puedes.',
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
        const SizedBox(height: 16),
        Text('Volumen de la guía', style: theme.textTheme.titleMedium),
        Slider(
          value: _guideVolume,
          divisions: 10,
          label: '${(_guideVolume * 100).round()} %',
          onChanged: (value) => setState(() => _guideVolume = value),
        ),
        const SizedBox(height: 8),
        Text(
          'Tu voz se mide en este teléfono y no se graba ni se envía.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _starting ? null : _start,
          icon: const Icon(Icons.mic),
          label: Text(_starting ? 'Preparando…' : 'Empezar a cantar'),
        ),
      ],
    );
  }

  Widget _running(BuildContext context) {
    final theme = Theme.of(context);
    final expected = _live.expected;
    final color = switch (_live.cue) {
      VocalCue.onPitch => Colors.green.shade700,
      VocalCue.higher || VocalCue.lower => theme.colorScheme.tertiary,
      null => theme.colorScheme.onSurfaceVariant,
    };
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  cueText(_live.cue),
                  style: theme.textTheme.headlineSmall?.copyWith(color: color),
                  semanticsLabel: cueText(_live.cue),
                ),
              ),
              if (expected != null)
                Text(
                  '${solfege(expected.midi)} (${expected.name})',
                  style: theme.textTheme.titleMedium,
                ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: CustomPaint(
              size: Size.infinite,
              painter: PitchRoll(
                reference: _reference,
                now: _now,
                trail: _trail,
                colors: theme.colorScheme,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: OutlinedButton.icon(
            onPressed: () => _finish(reachedEnd: false),
            icon: const Icon(Icons.stop),
            label: const Text('Terminar'),
          ),
        ),
      ],
    );
  }
}
