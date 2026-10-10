import '../../routines/reference/motion_reference.dart';
import '../playback/reference_timeline.dart';
import '../pose/body_features.dart';

class AngleMatch {
  const AngleMatch(this.score, this.meanErrorDegrees, this.offsetMs);
  final double score, meanErrorDegrees;

  /// Reference time minus captured video position. Not a measured timing score.
  final int offsetMs;
}

/// Experimental six-angle similarity. All anatomical sides retain their names.
class AngleMatcher {
  const AngleMatcher(this.reference);
  static const version = 'angle-window-v1';
  static const windowMs = 200;
  final MotionReference reference;

  static bool _complete(Map<BodyAngle, double> angles) =>
      BodyAngle.values.every((joint) {
        final value = angles[joint];
        return value != null && value.isFinite && value >= 0 && value <= 180;
      });

  static double? meanError(Map<BodyAngle, double> a, Map<BodyAngle, double> b) {
    if (!_complete(a) || !_complete(b)) return null;
    return BodyAngle.values.fold<double>(
          0,
          (sum, joint) => sum + (a[joint]! - b[joint]!).abs(),
        ) /
        BodyAngle.values.length;
  }

  AngleMatch? compare(Map<BodyAngle, double> angles, int videoMs) {
    if (!_complete(angles)) return null;
    final center = ReferenceTimeline(
      reference,
    ).at(Duration(milliseconds: videoMs));
    if (center == null || !_complete(center.angles)) return null;
    final samples = reference.samples;
    // The timeline is regular at 12 Hz; locate the already validated sample.
    final centerIndex = samples.indexOf(center);
    AngleMatch? best;
    void consider(MotionSample sample) {
      final error = meanError(angles, sample.angles)!;
      final offset = sample.timestampMs - videoMs;
      if (best == null ||
          error < best!.meanErrorDegrees ||
          (error == best!.meanErrorDegrees &&
              offset.abs() < best!.offsetMs.abs())) {
        best = AngleMatch(
          (100 * (1 - error / 90)).clamp(0, 100),
          error,
          offset,
        );
      }
    }

    consider(center);
    for (final direction in [-1, 1]) {
      for (
        var i = centerIndex + direction;
        i >= 0 && i < samples.length;
        i += direction
      ) {
        final sample = samples[i];
        // Never cross an unusable gap to find a convenient match.
        if ((sample.timestampMs - videoMs).abs() > windowMs ||
            !_complete(sample.angles)) {
          break;
        }
        consider(sample);
      }
    }
    return best;
  }
}
