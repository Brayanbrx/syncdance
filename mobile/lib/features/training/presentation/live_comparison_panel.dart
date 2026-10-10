import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:video_player/video_player.dart';

import '../../routines/reference/motion_reference.dart';
import '../camera/camera_capture.dart';
import '../camera/camera_frame.dart';
import '../comparison/pose_matcher.dart';
import '../comparison/capture_video_clock.dart';
import '../comparison/session_summary.dart';
import '../feedback/feedback_rules.dart';
import '../feedback/live_feedback.dart';
import '../pose/adapters/mlkit_pose_estimator.dart';
import '../pose/body_features.dart';
import '../pose/pose_estimator.dart';
import '../pose/pose_frame.dart';
import '../pose/pose_measurements.dart';
import 'camera_training_screen.dart';

class LiveComparisonPanel extends StatefulWidget {
  const LiveComparisonPanel({
    required this.player,
    required this.reference,
    required this.enabled,
    required this.epoch,
    this.session,
    this.capture,
    this.createPoseEstimator,
    this.nowMs,
    super.key,
  });
  final VideoPlayerController player;
  final MotionReference reference;
  final bool enabled;
  final int epoch;
  final SessionAccumulator? session;
  final CameraCapture? capture;
  final PoseEstimator Function(CameraCapture)? createPoseEstimator;
  final int Function()? nowMs;

  @override
  State<LiveComparisonPanel> createState() => _LiveComparisonPanelState();
}

class _LiveComparisonPanelState extends State<LiveComparisonPanel> {
  final _watch = Stopwatch()..start();
  final _clock = CaptureVideoClock();
  var _feedback = LiveFeedback();
  PoseMatch? _match;
  Timer? _expiry;
  int? _generation;
  Object? _orientation;
  int get _now => widget.nowMs?.call() ?? _watch.elapsedMilliseconds;
  bool get _running {
    final value = widget.player.value;
    return widget.enabled &&
        value.isInitialized &&
        value.isPlaying &&
        !value.isBuffering &&
        !value.isCompleted &&
        !value.hasError;
  }

  @override
  void initState() {
    super.initState();
    widget.player.addListener(_videoChanged);
  }

  @override
  void didUpdateWidget(LiveComparisonPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.player != widget.player) {
      oldWidget.player.removeListener(_videoChanged);
      widget.player.addListener(_videoChanged);
    }
    if (oldWidget.epoch != widget.epoch ||
        oldWidget.enabled != widget.enabled ||
        oldWidget.player != widget.player ||
        oldWidget.reference != widget.reference ||
        oldWidget.session != widget.session) {
      _invalidate();
    }
    if (oldWidget.session != widget.session ||
        oldWidget.reference != widget.reference) {
      _feedback = LiveFeedback();
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

  void _invalidate() {
    _clock.invalidate();
    _expiry?.cancel();
    _match = null;
    _feedback.invalidate(_now);
    _redraw();
  }

  void _videoChanged() {
    if (!_running) {
      _invalidate();
      return;
    }
    _clock.report(
      videoMs: widget.player.value.position.inMilliseconds,
      nowMs: _now,
      playing: true,
    );
  }

  void _captured(CameraFrame frame) {
    if (_generation != frame.generation || _orientation != frame.orientation) {
      _invalidate();
      _generation = frame.generation;
      _orientation = frame.orientation;
    }
    _videoChanged();
    _clock.capture(timestampMs: frame.timestampMs, nowMs: _now);
  }

  void _measured(PoseFrame pose, PoseMeasurements measurements) {
    final videoMs = _clock.resolve(timestampMs: pose.timestampMs, nowMs: _now);
    _expiry?.cancel();
    // Reference features are unsmoothed: avoid adding display EMA delay.
    final features = _running && videoMs != null && measurements.canMeasure
        ? const BodyFeatureExtractor().extract(pose)
        : null;
    _match = features != null && videoMs != null
        ? PoseMatcher(widget.reference).compare(features, videoMs)
        : null;
    if (videoMs != null) widget.session?.record(videoMs, _match);
    if (_match != null) {
      final presentations = _feedback.presentations;
      _feedback.update(
        captureMs: pose.timestampMs,
        nowMs: _now,
        cues: const FeedbackRules().evaluate(features!, _match!),
      );
      if (_feedback.presentations != presentations && videoMs != null) {
        widget.session?.recordFeedback(videoMs, _feedback.active!);
      }
      _expiry = Timer(const Duration(milliseconds: 250), () {
        _match = null;
        _feedback.invalidate(_now);
        _redraw();
      });
    } else {
      _feedback.invalidate(_now);
    }
    _redraw();
  }

  @override
  void dispose() {
    widget.player.removeListener(_videoChanged);
    _expiry?.cancel();
    _watch.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      const Text('Tu cámara · sigue los mismos lados anatómicos del maestro'),
      SizedBox(
        height: 220,
        child: CameraTrainingScreen(
          embedded: true,
          capture: widget.capture,
          createPoseEstimator:
              widget.createPoseEstimator ?? MlKitPoseEstimator.new,
          onFrameCaptured: _captured,
          onMeasurements: _measured,
          onInvalidated: _invalidate,
          highlightedJoints: _feedback.active?.highlightedJoints ?? const {},
        ),
      ),
      Text(
        _match == null
            ? 'Similitud: —. Calibra el encuadre y reproduce un tramo con medidas completas.'
            : 'Similitud de pose: ${_match!.score.toStringAsFixed(0)}/100\n'
                  'Ángulos: ${_match!.angleScore.toStringAsFixed(0)}/100 · Posiciones: ${_match!.positionScore.toStringAsFixed(0)}/100\n'
                  'Diferencia media: ${_match!.meanErrorDegrees.toStringAsFixed(1)}° · ${_match!.meanPositionError.toStringAsFixed(2)} largos de torso',
      ),
      if (_feedback.active != null)
        Semantics(
          liveRegion: true,
          child: Card(
            color: Theme.of(context).colorScheme.secondaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_feedback.active!.message),
                  const Text(
                    'Aros amarillos: zona a revisar cuando el esqueleto esté visible.',
                  ),
                ],
              ),
            ),
          ),
        ),
      if (widget.session != null)
        Text(
          'Cobertura estimada: ${(100 * widget.session!.evaluatedMs / widget.session!.durationMs).toStringAsFixed(1)} %',
        ),
      const Text('Similitud experimental; al finalizar podrás ver el resumen.'),
    ],
  );
}
