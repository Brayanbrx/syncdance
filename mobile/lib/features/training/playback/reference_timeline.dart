import '../../routines/reference/motion_reference.dart';

/// The reference at a video position, with no smoothing. Which position a
/// camera frame belongs to is decided by `CaptureVideoClock`.
class ReferenceTimeline {
  const ReferenceTimeline(this.reference);
  final MotionReference reference;

  bool acceptsDuration(Duration duration) =>
      duration.inMilliseconds > 0 &&
      (duration.inMilliseconds - reference.metadata.durationMs).abs() <= 250;

  MotionSample? at(Duration position) {
    final index = indexAt(position);
    return index == null ? null : reference.samples[index];
  }

  /// Position in the samples of [at]'s sample: the matchers walk from it
  /// without searching the list again for every frame.
  int? indexAt(Duration position) {
    final time = position.inMilliseconds;
    if (time < 0 || time >= reference.metadata.durationMs) return null;
    final samples = reference.samples;
    var low = 0;
    var high = samples.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (samples[middle].timestampMs <= time) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low == 0 ? null : low - 1;
  }
}
