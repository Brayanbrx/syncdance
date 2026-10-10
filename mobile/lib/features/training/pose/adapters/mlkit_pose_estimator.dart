import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart'
    as ml;

import '../../camera/camera_capture.dart';
import '../../camera/camera_frame.dart';
import '../pose_estimator.dart';
import '../pose_frame.dart';
import 'mlkit_pose_mapper.dart';

/// Android-first spike. One native inference at a time, capped at ~12 inputs/s.
/// One instance belongs to one screen; stop is idempotent and terminal.
class MlKitPoseEstimator implements PoseEstimator {
  MlKitPoseEstimator(this.capture);

  final CameraCapture capture;
  final _poses = StreamController<PoseFrame>.broadcast();
  StreamSubscription<CameraFrame>? _subscription;
  ml.PoseDetector? _detector;
  bool _started = false;
  bool _stopped = false;
  bool _busy = false;
  bool _failed = false;
  int _processed = 0;
  int _dropped = 0;
  int _lastSubmittedMs = -1000;
  double _lastInferenceMs = 0;
  Future<void> _work = Future<void>.value();
  Future<void>? _stopping;

  @override
  PoseEstimatorStats get stats => PoseEstimatorStats(
    processedFrames: _processed,
    droppedFrames: _dropped,
    lastInferenceMs: _lastInferenceMs,
  );

  @override
  Stream<PoseFrame> start() {
    if (_stopped) throw StateError('Create a new estimator after stop.');
    if (!_started) {
      _started = true;
      if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
        scheduleMicrotask(() {
          if (!_stopped) {
            _poses.addError(
              UnsupportedError('Pose disponible en Android en este paso.'),
            );
          }
        });
      } else {
        capture.addListener(_captureChanged);
        _subscription = capture.frames.listen(_onFrame);
        unawaited(capture.start());
      }
    }
    return _poses.stream;
  }

  void _onFrame(CameraFrame frame) {
    if (_stopped || _failed || !capture.isFrameCurrent(frame)) return;
    if (_busy || frame.timestampMs - _lastSubmittedMs < 83) {
      _dropped++;
      return;
    }
    _lastSubmittedMs = frame.timestampMs;
    _busy = true;
    _work = _process(frame).whenComplete(() => _busy = false);
  }

  Future<void> _process(CameraFrame frame) async {
    try {
      final input = androidInputImage(frame);
      _detector ??= ml.PoseDetector(
        options: ml.PoseDetectorOptions(
          model: ml.PoseDetectionModel.base,
          mode: ml.PoseDetectionMode.stream,
        ),
      );
      final watch = Stopwatch()..start();
      final poses = await _detector!.processImage(input);
      if (_stopped || !capture.isFrameCurrent(frame)) return;
      _lastInferenceMs = watch.elapsedMicroseconds / 1000;
      _processed++;
      // ML Kit's streaming pose API tracks one prominent person. It cannot
      // establish a reliable MULTIPLE_PEOPLE quality state.
      _poses.add(
        canonicalAndroidPose(frame, poses.isEmpty ? null : poses.first),
      );
    } catch (error, stack) {
      // Terminal for this screen; log it so device failures are diagnosable.
      final image = frame.image;
      debugPrint(
        'Pose estimator failed: ${error.runtimeType}: $error '
        '(${image.width}x${image.height}, ${image.format.group.name}, '
        '${image.planes.length} planes, ${image.planes.map((p) => '${p.bytes.length}B/${p.bytesPerRow}').join(' ')})',
      );
      if (!_stopped && capture.isFrameCurrent(frame)) {
        _failed = true;
        _poses.addError(error, stack);
      }
    } finally {
      if (_stopped || _failed || !capture.isFrameCurrent(frame)) {
        await _closeNative();
      }
    }
  }

  void _captureChanged() {
    if (_stopped || _busy) return;
    if (capture.status == CaptureStatus.paused ||
        capture.status == CaptureStatus.failed ||
        capture.status == CaptureStatus.idle) {
      _busy = true;
      _work = _closeNative().whenComplete(() => _busy = false);
    }
  }

  Future<void> _closeNative() async {
    final detector = _detector;
    _detector = null;
    if (detector != null) {
      try {
        await detector.close();
      } catch (error) {
        debugPrint('Pose detector cleanup failed: $error');
      }
    }
  }

  @override
  Future<void> stop() => _stopping ??= _stop();

  Future<void> _stop() async {
    _stopped = true;
    capture.removeListener(_captureChanged);
    await _subscription?.cancel();
    await capture.stop();
    await _work;
    await _closeNative();
    await _poses.close();
  }
}
