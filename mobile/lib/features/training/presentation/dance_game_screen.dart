import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:video_player/video_player.dart';

import '../../routines/reference/motion_reference.dart';
import '../../routines/reference/reference_cache.dart';
import '../camera/camera_capture.dart';
import '../camera/camera_frame.dart';
import '../comparison/follow_mode.dart';
import '../comparison/live_practice.dart';
import '../comparison/session_summary.dart';
import '../game/dance_game.dart';
import '../history/saved_session.dart';
import '../history/session_store.dart';
import '../pose/adapters/mlkit_pose_estimator.dart';
import '../pose/pose_estimator.dart';
import '../pose/pose_frame.dart';
import '../pose/pose_measurements.dart';
import 'camera_training_screen.dart';

enum _Phase { positioning, countdown, playing, finished }

/// Just Dance style mode: hands-free start, per-move ratings, combo, points and
/// stars. The learner stands 2-3 m away, so nothing requires touching the phone
/// until the results. No textual cues: the game only consumes the scorer output.
class DanceGameScreen extends StatefulWidget {
  const DanceGameScreen({
    required this.saved,
    required this.videoFile,
    required this.storeScope,
    this.followMode = FollowMode.mirror,
    this.sessionStore,
    this.onSessionSaved,
    this.createController,
    this.capture,
    this.createPoseEstimator,
    this.nowMs,
    super.key,
  });

  final SavedReference saved;
  final File videoFile;

  /// Account scope of the local history (`server|account`).
  final String storeScope;
  final FollowMode followMode;
  final SessionStore? sessionStore;
  final Future<void> Function()? onSessionSaved;
  final VideoPlayerController Function(File)? createController;
  final CameraCapture? capture;
  final PoseEstimator Function(CameraCapture)? createPoseEstimator;
  final int Function()? nowMs;

  static const countdownSeconds = 3;

  @override
  State<DanceGameScreen> createState() => _DanceGameScreenState();
}

class _DanceGameScreenState extends State<DanceGameScreen>
    with WidgetsBindingObserver {
  late final MotionReference _reference = referenceFor(
    widget.saved.reference,
    widget.followMode,
  );
  VideoPlayerController? _player;
  String? _error;
  _Phase _phase = _Phase.positioning;
  PoseMeasurements? _measurements;
  String? _poseError;
  int _countdown = DanceGameScreen.countdownSeconds;
  Timer? _countdownTimer;
  LivePractice? _practice;
  SessionAccumulator? _session;
  DanceGame? _game;
  RatedMove? _lastRated;
  Timer? _ratingTimer;
  DanceGameResult? _result;
  String? _sessionId;
  DateTime? _startedAt;
  String? _saveMessage;
  int _round = 0;

  int get _durationMs => widget.saved.reference.metadata.durationMs;

  bool get _running {
    final value = _player?.value;
    return _phase == _Phase.playing &&
        value != null &&
        value.isInitialized &&
        value.isPlaying &&
        !value.isBuffering &&
        !value.isCompleted &&
        !value.hasError;
  }

  int get _position => _player?.value.position.inMilliseconds ?? 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _newRound();
    unawaited(_openVideo());
  }

  Future<void> _openVideo() async {
    final player =
        widget.createController?.call(widget.videoFile) ??
        VideoPlayerController.file(widget.videoFile);
    _player = player;
    try {
      await player.initialize();
      if (!mounted) return;
      player.addListener(_videoChanged);
      setState(() {});
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'No se pudo abrir el video del maestro.');
      }
    }
  }

  void _newRound() {
    _practice?.removeListener(_redraw);
    _practice?.dispose();
    _session = SessionAccumulator(_durationMs, followMode: widget.followMode);
    _game = DanceGame(reference: _reference, session: _session!);
    _practice = LivePractice(
      reference: _reference,
      session: _session,
      nowMs: widget.nowMs,
      coaching: false,
    )..addListener(_redraw);
    _lastRated = null;
    _result = null;
    _saveMessage = null;
    _sessionId = newSessionId();
    _round++;
  }

  void _redraw() {
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  void _measured(PoseFrame pose, PoseMeasurements measurements) {
    _practice?.measured(pose, measurements, running: _running);
    _measurements = measurements;
    if (_phase == _Phase.positioning && measurements.canMeasure) {
      _startCountdown();
    } else if (_phase == _Phase.countdown && !measurements.canMeasure) {
      _cancelCountdown();
    }
    _redraw();
  }

  void _captured(CameraFrame frame) => _practice?.frameCaptured(
    generation: frame.generation,
    orientation: frame.orientation,
    timestampMs: frame.timestampMs,
    running: _running,
    positionMs: _position,
  );

  void _startCountdown() {
    if (_player?.value.isInitialized != true) return;
    _countdown = DanceGameScreen.countdownSeconds;
    _phase = _Phase.countdown;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_countdown <= 1) {
        timer.cancel();
        unawaited(_play());
      } else {
        setState(() => _countdown--);
      }
    });
  }

  void _cancelCountdown() {
    _countdownTimer?.cancel();
    _phase = _Phase.positioning;
  }

  Future<void> _play() async {
    final player = _player;
    if (player == null || !mounted) return;
    setState(() {
      _phase = _Phase.playing;
      _startedAt = DateTime.now().toUtc();
    });
    _practice?.invalidate();
    await player.seekTo(Duration.zero);
    if (mounted && _phase == _Phase.playing) await player.play();
  }

  void _videoChanged() {
    final player = _player;
    if (player == null || !mounted) return;
    _practice?.videoChanged(running: _running, positionMs: _position);
    if (_phase != _Phase.playing) return;
    final rated = _game!.advance(_position);
    if (rated.isNotEmpty) _show(rated.last);
    final value = player.value;
    if (value.isCompleted || value.hasError) {
      unawaited(_finish(reachedVideoEnd: value.isCompleted));
    } else {
      setState(() {});
    }
  }

  void _show(RatedMove move) {
    _ratingTimer?.cancel();
    setState(() => _lastRated = move);
    _ratingTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _lastRated = null);
    });
  }

  Future<void> _finish({required bool reachedVideoEnd}) async {
    if (_phase != _Phase.playing) return;
    final round = _round;
    _practice?.invalidate();
    unawaited(_player?.pause().catchError((Object _) {}));
    final result = _game!.finish();
    final summary = _session!.finish(reachedVideoEnd: reachedVideoEnd);
    setState(() {
      _phase = _Phase.finished;
      _result = result;
      _lastRated = null;
      _saveMessage = 'Guardando resultado…';
    });
    final now = DateTime.now().toUtc();
    final record = SavedSession(
      id: _sessionId!,
      routineName: widget.saved.name,
      reference: widget.saved.reference.metadata,
      startedAt: _startedAt!,
      finishedAt: now.isBefore(_startedAt!) ? _startedAt! : now,
      summary: summary,
      game: GameSummary.of(result),
    );
    try {
      final store =
          widget.sessionStore ?? await SessionStore.open(widget.storeScope);
      await store.save(record);
      unawaited(
        widget.onSessionSaved?.call().then((_) {}, onError: (Object _) {}),
      );
      if (mounted && round == _round) {
        setState(() => _saveMessage = 'Resultado guardado en tu historial.');
      }
    } catch (_) {
      if (mounted && round == _round) {
        setState(
          () => _saveMessage =
              'No se pudo guardar el resultado. Libera espacio en el teléfono.',
        );
      }
    }
  }

  Future<void> _again() async {
    await _player?.pause();
    await _player?.seekTo(Duration.zero);
    if (!mounted) return;
    setState(() {
      _newRound();
      _phase = _Phase.positioning;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) return;
    // Leaving the app ends the song: there is no hands-free way to resume.
    if (_phase == _Phase.playing) {
      unawaited(_finish(reachedVideoEnd: false));
    } else if (_phase == _Phase.countdown) {
      setState(_cancelCountdown);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _countdownTimer?.cancel();
    _ratingTimer?.cancel();
    _player?.removeListener(_videoChanged);
    unawaited(_player?.dispose());
    _practice?.removeListener(_redraw);
    _practice?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = _player;
    final ready = player != null && player.value.isInitialized;
    return PopScope(
      canPop: _phase != _Phase.playing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_finish(reachedVideoEnd: false));
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: _error != null
              ? Center(
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.white),
                  ),
                )
              : _phase == _Phase.finished
              ? _Results(
                  result: _result!,
                  coverage: _session!.evaluatedMs / _durationMs,
                  saveMessage: _saveMessage,
                  onAgain: _again,
                  onExit: () => Navigator.of(context).maybePop(),
                )
              : Column(
                  children: [
                    _Hud(
                      points: _game!.points,
                      combo: _game!.combo,
                      progress:
                          ready && player.value.duration.inMilliseconds > 0
                          ? _position / player.value.duration.inMilliseconds
                          : 0,
                    ),
                    Expanded(
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          if (ready)
                            AspectRatio(
                              aspectRatio: player.value.aspectRatio,
                              child: VideoPlayer(player),
                            )
                          else
                            const CircularProgressIndicator(),
                          if (_phase == _Phase.positioning)
                            _Banner(text: _guidance()),
                          if (_phase == _Phase.countdown)
                            Text(
                              '$_countdown',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 120,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          if (_phase == _Phase.playing &&
                              _measurements?.canMeasure != true)
                            const Align(
                              alignment: Alignment.bottomCenter,
                              child: _Banner(
                                text: 'Vuelve al encuadre: cuerpo completo',
                              ),
                            ),
                          if (_lastRated != null)
                            Align(
                              alignment: const Alignment(0, -0.6),
                              child: _RatingLabel(move: _lastRated!),
                            ),
                        ],
                      ),
                    ),
                    SizedBox(
                      height: MediaQuery.sizeOf(context).height * 0.3,
                      child: CameraTrainingScreen(
                        embedded: true,
                        showDetails: false,
                        capture: widget.capture,
                        createPoseEstimator:
                            widget.createPoseEstimator ??
                            MlKitPoseEstimator.new,
                        onFrameCaptured: _captured,
                        onMeasurements: _measured,
                        onInvalidated: () => _practice?.invalidate(),
                        onPoseError: (message) {
                          if (_phase == _Phase.playing) {
                            unawaited(_finish(reachedVideoEnd: false));
                          } else if (_phase == _Phase.countdown) {
                            _cancelCountdown();
                          }
                          setState(() => _poseError = message);
                        },
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  String _guidance() {
    if (_poseError != null) return _poseError!;
    final measurements = _measurements;
    if (measurements == null) {
      return 'Apoya el teléfono vertical a la altura de la cadera y aléjate '
          '2–3 m hasta verte de cuerpo entero. El baile empieza solo.';
    }
    return switch (measurements.quality) {
      PoseQuality.noPerson => 'Colócate frente a la cámara.',
      PoseQuality.bodyNotVisible =>
        'Que se vean cabeza, brazos y piernas completos.',
      PoseQuality.lowConfidence => 'Necesitas más luz.',
      PoseQuality.tooClose => 'Aléjate un poco.',
      PoseQuality.tooFar => 'Acércate un poco.',
      PoseQuality.ready =>
        'Quieto un momento… '
            '${(measurements.calibrationProgress * 100).round()} %',
    };
  }
}

class _Hud extends StatelessWidget {
  const _Hud({
    required this.points,
    required this.combo,
    required this.progress,
  });
  final int points, combo;
  final double progress;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
    child: Column(
      children: [
        Row(
          children: [
            Text(
              '$points',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Text(' pts', style: TextStyle(color: Colors.white70)),
            const Spacer(),
            if (combo >= 2)
              Text(
                'Combo ×$combo',
                style: const TextStyle(
                  color: Colors.amberAccent,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        LinearProgressIndicator(value: progress.clamp(0, 1)),
      ],
    ),
  );
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.all(16),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.7),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(color: Colors.white, fontSize: 18),
    ),
  );
}

Color ratingColor(MoveRating? rating) => switch (rating) {
  MoveRating.perfect => Colors.amber,
  MoveRating.great => Colors.lightGreenAccent,
  MoveRating.good => Colors.lightBlueAccent,
  MoveRating.miss => Colors.redAccent,
  null => Colors.white70,
};

class _RatingLabel extends StatelessWidget {
  const _RatingLabel({required this.move});
  final RatedMove move;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Text(
      move.rating?.label ?? 'SIN MEDIR',
      style: TextStyle(
        color: ratingColor(move.rating),
        fontSize: move.rating == null ? 28 : 48,
        fontWeight: FontWeight.w900,
        shadows: const [Shadow(blurRadius: 8)],
      ),
    ),
  );
}

class _Results extends StatelessWidget {
  const _Results({
    required this.result,
    required this.coverage,
    required this.saveMessage,
    required this.onAgain,
    required this.onExit,
  });
  final DanceGameResult result;
  final double coverage;
  final String? saveMessage;
  final VoidCallback onAgain, onExit;

  String _time(int ms) {
    final seconds = ms ~/ 1000;
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    const white = TextStyle(color: Colors.white, fontSize: 18);
    final practice = result.toPractice();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '★' * result.stars + '☆' * (5 - result.stars),
            textAlign: TextAlign.center,
            semanticsLabel: '${result.stars} de 5 estrellas',
            style: const TextStyle(color: Colors.amber, fontSize: 48),
          ),
          Text(
            '${result.points} pts',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 40,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            'Combo máximo ×${result.maxCombo} · '
            'te vimos el ${(coverage * 100).toStringAsFixed(0)} % de la canción',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 16),
          for (final rating in MoveRating.values)
            Text(
              '${rating.label}: ${result.count(rating)}',
              style: white.copyWith(color: ratingColor(rating)),
            ),
          if (result.count(null) > 0)
            Text(
              'Sin medir (fuera de encuadre): ${result.count(null)}',
              style: white.copyWith(color: Colors.white70),
            ),
          const SizedBox(height: 16),
          if (practice.isNotEmpty) ...[
            const Text('Movimientos para practicar', style: white),
            for (final move in practice)
              Text(
                '${_time(move.move.startMs)}–${_time(move.move.endMs)} · '
                '${move.rating!.label} (${move.score!.toStringAsFixed(0)})',
                style: white.copyWith(color: Colors.white70),
              ),
          ],
          const SizedBox(height: 8),
          const Text(
            'Calificaciones experimentales: los umbrales se ajustarán '
            'con pruebas reales.',
            style: TextStyle(color: Colors.white54),
          ),
          if (saveMessage != null)
            Text(saveMessage!, style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: onAgain,
            child: const Text('Bailar otra vez'),
          ),
          TextButton(onPressed: onExit, child: const Text('Salir')),
        ],
      ),
    );
  }
}
