import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

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
import '../pose/adapters/mlkit_pose_estimator.dart';
import '../pose/pose_estimator.dart';
import '../pose/pose_frame.dart';
import '../pose/pose_measurements.dart';
import 'camera_training_screen.dart';
import 'game_widgets.dart';
import 'move_pictogram.dart';

enum _Phase { positioning, countdown, playing }

/// Loops one move of the master, slower, and rates every pass with the game
/// rules: learn mode for the moves the results suggest practising. A run-up
/// of one move length precedes it. Passes are rehearsal and are not saved.
class MoveDrillScreen extends StatefulWidget {
  const MoveDrillScreen({
    required this.saved,
    required this.videoFile,
    required this.move,
    this.followMode = FollowMode.mirror,
    this.initialSpeed = 0.5,
    this.createController,
    this.capture,
    this.createPoseEstimator,
    this.nowMs,
    super.key,
  });

  final SavedReference saved;
  final File videoFile;
  final DanceMove move;
  final FollowMode followMode;
  final double initialSpeed;
  final VideoPlayerController Function(File)? createController;
  final CameraCapture? capture;
  final PoseEstimator Function(CameraCapture)? createPoseEstimator;
  final int Function()? nowMs;

  @override
  State<MoveDrillScreen> createState() => _MoveDrillScreenState();
}

class _MoveDrillScreenState extends State<MoveDrillScreen>
    with WidgetsBindingObserver {
  late final MotionReference _reference = referenceFor(
    widget.saved.reference,
    widget.followMode,
  );
  late final MotionSample? _pose = keySample(
    widget.saved.reference,
    widget.move,
  );
  late double _speed = widget.initialSpeed;
  VideoPlayerController? _player;
  String? _error;
  _Phase _phase = _Phase.positioning;
  PoseMeasurements? _measurements;
  String? _poseError;
  int _countdown = 3;
  Timer? _countdownTimer;
  late SessionAccumulator _session = _newSession();
  late final LivePractice _practice = LivePractice(
    reference: _reference,
    session: _session,
    nowMs: widget.nowMs,
    coaching: false,
  )..addListener(_redraw);
  final _passes = <RatedMove>[];
  RatedMove? _lastPass;
  Timer? _ratingTimer;
  bool _looping = false;

  int get _durationMs => widget.saved.reference.metadata.durationMs;
  int get _moveMs => widget.move.endMs - widget.move.startMs;
  int get _loopStart => math.max(0, widget.move.startMs - _moveMs);

  /// Late inference still lands inside the move before the loop restarts.
  int get _loopEnd =>
      math.min(_durationMs, widget.move.endMs + DanceGame.settleMs);

  bool get _running {
    final value = _player?.value;
    return _phase == _Phase.playing &&
        !_looping &&
        value != null &&
        value.isInitialized &&
        value.isPlaying &&
        !value.isBuffering &&
        !value.isCompleted &&
        !value.hasError;
  }

  int get _position => _player?.value.position.inMilliseconds ?? 0;

  SessionAccumulator _newSession() => SessionAccumulator(
    _durationMs,
    followMode: widget.followMode,
    playbackSpeed: _speed,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_openVideo());
  }

  Future<void> _openVideo() async {
    final player =
        widget.createController?.call(widget.videoFile) ??
        VideoPlayerController.file(widget.videoFile);
    _player = player;
    try {
      await player.initialize();
      await player.setPlaybackSpeed(_speed);
      await player.seekTo(Duration(milliseconds: _loopStart));
      if (!mounted) return;
      player.addListener(_videoChanged);
      setState(() {});
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'No se pudo abrir el video del maestro.');
      }
    }
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
    _practice.measured(pose, measurements, running: _running);
    _measurements = measurements;
    if (_phase == _Phase.positioning && measurements.canMeasure) {
      _startCountdown();
    } else if (_phase == _Phase.countdown && !measurements.canMeasure) {
      _cancelCountdown();
    }
    _redraw();
  }

  /// Same as the game: without a live pose nothing counts as framed.
  void _invalidated() {
    _practice.invalidate();
    _measurements = null;
    if (_phase == _Phase.countdown) _cancelCountdown();
    _redraw();
  }

  void _captured(CameraFrame frame) => _practice.frameCaptured(
    generation: frame.generation,
    orientation: frame.orientation,
    timestampMs: frame.timestampMs,
    running: _running,
    positionMs: _position,
  );

  void _startCountdown() {
    if (_player?.value.isInitialized != true) return;
    _countdown = 3;
    _phase = _Phase.countdown;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_countdown <= 1) {
        timer.cancel();
        setState(() => _phase = _Phase.playing);
        unawaited(_restartPass());
      } else {
        setState(() => _countdown--);
      }
    });
  }

  void _cancelCountdown() {
    _countdownTimer?.cancel();
    _phase = _Phase.positioning;
  }

  /// A fresh session per pass: bins of the previous pass never mix in.
  Future<void> _restartPass() async {
    final player = _player;
    if (player == null || _looping) return;
    _looping = true;
    try {
      _session = _newSession();
      _practice
        ..rebind(reference: _reference, session: _session)
        ..invalidate();
      await player.pause();
      await player.seekTo(Duration(milliseconds: _loopStart));
      if (mounted && _phase == _Phase.playing) await player.play();
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'No se pudo controlar la reproducción.');
      }
    } finally {
      _looping = false;
    }
  }

  void _videoChanged() {
    final player = _player;
    if (player == null || !mounted) return;
    _practice.videoChanged(running: _running, positionMs: _position);
    if (_phase != _Phase.playing || _looping) return;
    final value = player.value;
    if (value.hasError) {
      setState(() => _error = 'El reproductor no puede leer este video.');
    } else if (_position >= _loopEnd || value.isCompleted) {
      _show(DanceGame.rate(_session, widget.move));
      unawaited(_restartPass());
    } else {
      setState(() {});
    }
  }

  void _show(RatedMove pass) {
    _ratingTimer?.cancel();
    setState(() {
      _passes.add(pass);
      _lastPass = pass;
    });
    _ratingTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _lastPass = null);
    });
  }

  Future<void> _changeSpeed(double speed) async {
    setState(() => _speed = speed);
    try {
      await _player?.setPlaybackSpeed(speed);
    } catch (_) {}
    // The current pass mixed two speeds: start it again.
    if (_phase == _Phase.playing) await _restartPass();
  }

  void _stop() {
    _countdownTimer?.cancel();
    _phase = _Phase.positioning;
    _practice.invalidate();
    unawaited(_player?.pause().catchError((Object _) {}));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) return;
    // Leaving the app stops the loop; it restarts hands-free on return.
    setState(_stop);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _countdownTimer?.cancel();
    _ratingTimer?.cancel();
    _player?.removeListener(_videoChanged);
    unawaited(_player?.dispose());
    _practice
      ..removeListener(_redraw)
      ..dispose();
    super.dispose();
  }

  String _summary() {
    final rated = _passes.where((p) => p.rating != null).toList();
    if (_passes.isEmpty) return 'Repite el movimiento hasta que salga PERFECT.';
    final best = rated.isEmpty
        ? null
        : rated.reduce((a, b) => b.score! > a.score! ? b : a);
    return 'Pasadas: ${_passes.length}'
        '${best == null ? '' : ' · mejor: ${best.rating!.label}'}';
  }

  @override
  Widget build(BuildContext context) {
    final player = _player;
    final ready = player != null && player.value.isInitialized;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          'Practicar ${clockTime(widget.move.startMs)}–'
          '${clockTime(widget.move.endMs)}',
        ),
      ),
      body: SafeArea(
        child: _error != null
            ? Center(
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.white),
                ),
              )
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        if (_pose != null)
                          MovePictogram(
                            sample: _pose,
                            highlighted: true,
                            size: 72,
                          ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _summary(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 4,
                                children: [
                                  for (final pass in _passes.reversed.take(8))
                                    Icon(
                                      Icons.circle,
                                      size: 14,
                                      color: ratingColor(pass.rating),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: SegmentedButton<double>(
                      segments: const [
                        ButtonSegment(value: 0.5, label: Text('0,5×')),
                        ButtonSegment(value: 0.75, label: Text('0,75×')),
                        ButtonSegment(value: 1.0, label: Text('1×')),
                      ],
                      selected: {_speed},
                      style: SegmentedButton.styleFrom(
                        foregroundColor: Colors.white,
                      ),
                      onSelectionChanged: ready
                          ? (selection) =>
                                unawaited(_changeSpeed(selection.single))
                          : null,
                    ),
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
                          GameBanner(
                            text: positioningGuidance(
                              _measurements,
                              _poseError,
                            ),
                          ),
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
                            child: GameBanner(
                              text: 'Vuelve al encuadre: cuerpo completo',
                            ),
                          ),
                        if (_lastPass != null)
                          Align(
                            alignment: const Alignment(0, -0.6),
                            child: RatingLabel(move: _lastPass!),
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
                          widget.createPoseEstimator ?? MlKitPoseEstimator.new,
                      onFrameCaptured: _captured,
                      onMeasurements: _measured,
                      onInvalidated: _invalidated,
                      onPoseError: (message) => setState(() {
                        _stop();
                        _poseError = message;
                      }),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
