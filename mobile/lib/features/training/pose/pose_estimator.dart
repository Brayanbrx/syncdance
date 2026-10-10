import 'pose_frame.dart';

/// Boundary for an on-device estimator and its capture adapter.
///
/// Implementations must process at most one inference at a time, drop stale
/// frames, report permission/capture failures through the stream, and release
/// the camera and native detector on stop (also after backgrounding the app).
/// Calling stop more than once must be safe. No frames are sent to Django.
abstract interface class PoseEstimator {
  PoseEstimatorStats get stats;
  Stream<PoseFrame> start();
  Future<void> stop();
}

class PoseEstimatorStats {
  const PoseEstimatorStats({
    this.processedFrames = 0,
    this.droppedFrames = 0,
    this.lastInferenceMs = 0,
  });

  final int processedFrames;
  final int droppedFrames;

  /// Includes the native inference and platform-channel round trip.
  final double lastInferenceMs;
}
