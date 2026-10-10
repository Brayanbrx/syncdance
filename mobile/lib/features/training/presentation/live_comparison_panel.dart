import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:video_player/video_player.dart';

import '../../routines/reference/motion_reference.dart';
import '../camera/camera_capture.dart';
import '../camera/camera_frame.dart';
import '../comparison/live_practice.dart';
import '../comparison/session_summary.dart';
import '../pose/adapters/mlkit_pose_estimator.dart';
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

/// Presentation only: forwards camera and video events to [LivePractice].
class _LiveComparisonPanelState extends State<LiveComparisonPanel> {
  late final _practice = LivePractice(
    reference: widget.reference,
    session: widget.session,
    nowMs: widget.nowMs,
  );
  int get _position => widget.player.value.position.inMilliseconds;
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
    _practice.addListener(_redraw);
  }

  @override
  void didUpdateWidget(LiveComparisonPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.player != widget.player) {
      oldWidget.player.removeListener(_videoChanged);
      widget.player.addListener(_videoChanged);
    }
    if (oldWidget.session != widget.session ||
        oldWidget.reference != widget.reference) {
      _practice.rebind(reference: widget.reference, session: widget.session);
    } else if (oldWidget.epoch != widget.epoch ||
        oldWidget.enabled != widget.enabled ||
        oldWidget.player != widget.player) {
      _practice.invalidate();
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

  void _videoChanged() =>
      _practice.videoChanged(running: _running, positionMs: _position);

  void _captured(CameraFrame frame) => _practice.frameCaptured(
    generation: frame.generation,
    orientation: frame.orientation,
    timestampMs: frame.timestampMs,
    running: _running,
    positionMs: _position,
  );

  void _measured(PoseFrame pose, PoseMeasurements measurements) =>
      _practice.measured(pose, measurements, running: _running);

  @override
  void dispose() {
    widget.player.removeListener(_videoChanged);
    _practice.removeListener(_redraw);
    _practice.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final match = _practice.match;
    final cue = _practice.activeCue;
    return Column(
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
            onInvalidated: _practice.invalidate,
            highlightedJoints: cue?.highlightedJoints ?? const {},
          ),
        ),
        Text(
          match == null
              ? 'Similitud: —. Calibra el encuadre y reproduce un tramo con medidas completas.'
              : 'Similitud de pose: ${match.score.toStringAsFixed(0)}/100\n'
                    'Ángulos: ${match.angleScore.toStringAsFixed(0)}/100 · Posiciones: ${match.positionScore.toStringAsFixed(0)}/100\n'
                    'Diferencia media: ${match.meanErrorDegrees.toStringAsFixed(1)}° · ${match.meanPositionError.toStringAsFixed(2)} largos de torso',
        ),
        if (cue != null)
          Semantics(
            liveRegion: true,
            child: Card(
              color: Theme.of(context).colorScheme.secondaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(cue.message),
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
        const Text(
          'Similitud experimental; al finalizar podrás ver el resumen.',
        ),
      ],
    );
  }
}
