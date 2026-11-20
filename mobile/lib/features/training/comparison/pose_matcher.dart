import 'dart:math' as math;

import '../../routines/reference/motion_reference.dart';
import '../playback/reference_timeline.dart';
import '../pose/body_features.dart';
import '../pose/pose_frame.dart';
import 'angle_matcher.dart';

/// Both errors describe the same reference sample, never separate best matches.
class PoseMatch {
  const PoseMatch(
    this.meanErrorDegrees,
    this.meanPositionError,
    this.offsetMs, {
    this.referenceSample,
  });

  /// The exact common sample selected for both metrics and live guidance.
  final MotionSample? referenceSample;
  final double meanErrorDegrees;

  /// Mean 2D distance in hip-to-shoulder torso lengths.
  final double meanPositionError;
  final int offsetMs;
  double get angleScore => (100 * (1 - meanErrorDegrees / 90)).clamp(0, 100);
  double get positionScore => (100 * (1 - meanPositionError)).clamp(0, 100);
  double get score => (angleScore + positionScore) / 2;
}

/// Initial equal component weights and one-torso cutoff require physical validation.
class PoseMatcher {
  const PoseMatcher(this.reference);

  /// v2: frames are bound to the video position at capture time (between
  /// the player's reports, at its speed); v1 used the last report.
  static const version = 'pose-window-v2';
  static const joints = [
    Joint.leftShoulder,
    Joint.rightShoulder,
    Joint.leftElbow,
    Joint.rightElbow,
    Joint.leftWrist,
    Joint.rightWrist,
    Joint.leftHip,
    Joint.rightHip,
    Joint.leftKnee,
    Joint.rightKnee,
    Joint.leftAnkle,
    Joint.rightAnkle,
  ];
  final MotionReference reference;

  PoseMatch? compare(BodyFeatures features, int videoMs) {
    final pose = features.pose;
    if (pose == null ||
        joints.any((joint) => !pose.points.containsKey(joint))) {
      return null;
    }
    final centerIndex = ReferenceTimeline(
      reference,
    ).indexAt(Duration(milliseconds: videoMs));
    if (centerIndex == null) return null;
    final samples = reference.samples;
    final center = samples[centerIndex];
    PoseMatch? measure(MotionSample sample) {
      if (sample.quality != 'SINGLE_PERSON') return null;
      final angularError = AngleMatcher.meanError(
        features.angles,
        sample.angles,
      );
      if (angularError == null) return null;
      var distance = 0.0;
      for (final joint in joints) {
        final master = sample.normalized[joint];
        if (master == null || !master.x.isFinite || !master.y.isFinite) {
          return null;
        }
        final learner = pose.points[joint]!;
        final dx = learner.x - master.x;
        final dy = learner.y - master.y;
        final error = math.sqrt(dx * dx + dy * dy);
        if (!error.isFinite) return null;
        distance += error;
      }
      final mean = distance / joints.length;
      if (!mean.isFinite) return null;
      return PoseMatch(
        angularError,
        mean,
        sample.timestampMs - videoMs,
        referenceSample: sample,
      );
    }

    var best = measure(center);
    if (best == null) return null;
    for (final direction in [-1, 1]) {
      for (
        var i = centerIndex + direction;
        i >= 0 && i < samples.length;
        i += direction
      ) {
        final sample = samples[i];
        if ((sample.timestampMs - videoMs).abs() > AngleMatcher.windowMs) break;
        final candidate = measure(sample);
        // Never jump across missing angles, joints or ambiguous reference poses.
        if (candidate == null) break;
        if (candidate.score > best!.score ||
            (candidate.score == best.score &&
                candidate.offsetMs.abs() < best.offsetMs.abs())) {
          best = candidate;
        }
      }
    }
    return best;
  }
}
