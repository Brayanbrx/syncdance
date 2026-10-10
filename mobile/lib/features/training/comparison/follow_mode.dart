import '../../routines/reference/motion_reference.dart';
import '../pose/body_features.dart';
import '../pose/pose_frame.dart';

/// How the learner follows a master filmed facing the camera.
///
/// The learner's anatomical sides are never swapped. In [mirror] mode the
/// *choreography* is reflected instead: the reference becomes the master's
/// mirror image, so the learner's right follows the master's left, as anyone
/// naturally does in front of a screen or a dance class mirror.
enum FollowMode {
  /// Learner mirrors the screen (Just Dance style). Default for frontal masters.
  mirror('mirror'),

  /// Same anatomical sides, e.g. a master filmed from behind.
  sameSide('same-side');

  const FollowMode(this.code);

  /// Stored in summaries and uploads; part of the comparability basis.
  final String code;

  static FollowMode? fromCode(Object? code) {
    for (final mode in values) {
      if (mode.code == code) return mode;
    }
    return null;
  }
}

Joint mirrorJoint(Joint joint) => Joint.values.byName(_swapSide(joint.name));

BodyAngle mirrorAngle(BodyAngle angle) =>
    BodyAngle.values.byName(_swapSide(angle.name));

String _swapSide(String name) {
  if (name.startsWith('left')) return 'right${name.substring(4)}';
  if (name.startsWith('right')) return 'left${name.substring(5)}';
  return name;
}

/// Reflects every sample across the body midline (x = 0 is the hip midpoint in
/// body-normalized-v1) and swaps anatomical sides. Unsigned angles keep their
/// values under reflection; only their side changes. Applying it twice is the
/// identity. Quality and timing are unchanged.
MotionReference mirrorReference(MotionReference reference) =>
    MotionReference(reference.metadata, [
      for (final sample in reference.samples)
        MotionSample(
          sample.timestampMs,
          {
            for (final entry in sample.angles.entries)
              mirrorAngle(entry.key): entry.value,
          },
          sample.quality,
          normalized: {
            for (final entry in sample.normalized.entries)
              mirrorJoint(entry.key): (x: -entry.value.x, y: entry.value.y),
          },
        ),
    ], reference.coverage);

MotionReference referenceFor(MotionReference reference, FollowMode mode) =>
    mode == FollowMode.mirror ? mirrorReference(reference) : reference;
