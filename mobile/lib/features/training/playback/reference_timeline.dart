import '../../routines/reference/motion_reference.dart';

/// Video position is the sole clock. No wall-clock extrapolation or smoothing.
class ReferenceTimeline {
  const ReferenceTimeline(this.reference);
  final MotionReference reference;

  bool acceptsDuration(Duration duration) =>
      duration.inMilliseconds > 0 &&
      (duration.inMilliseconds - reference.metadata.durationMs).abs() <= 250;

  MotionSample? at(Duration position) {
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
    return low == 0 ? null : samples[low - 1];
  }
}
