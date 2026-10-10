import 'package:flutter_test/flutter_test.dart';
import 'package:syncdance_mobile/features/routines/reference/motion_reference.dart';
import 'package:syncdance_mobile/features/training/comparison/follow_mode.dart';
import 'package:syncdance_mobile/features/training/comparison/pose_matcher.dart';
import 'package:syncdance_mobile/features/training/pose/body_features.dart';
import 'package:syncdance_mobile/features/training/pose/pose_frame.dart';

import '../routines/reference_test_samples.dart';
import 'pose_test_samples.dart';

/// The master's pose as a single 12 Hz sample, like a generated reference.
MotionReference masterReference(PoseFrame master) {
  final features = const BodyFeatureExtractor().extract(master);
  return MotionReference(
    ReferenceMetadata.fromJson({...metadataJson(), 'duration_ms': 83}),
    [
      MotionSample(
        0,
        features.angles,
        'SINGLE_PERSON',
        normalized: features.pose!.points.map(
          (joint, p) => MapEntry(joint, (x: p.x, y: p.y)),
        ),
      ),
    ],
    1,
  );
}

/// What the camera sees when a learner faces it and mirrors the master: the
/// image flipped horizontally, with the learner's own anatomical labels.
PoseFrame mirroredLearner(PoseFrame master) => PoseFrame(
  timestampMs: master.timestampMs,
  imageAspectRatio: master.imageAspectRatio,
  poseConfidence: master.poseConfidence,
  landmarks: [
    for (final p in master.landmarks)
      PoseLandmark(
        joint: mirrorJoint(p.joint),
        x: 1 - p.x,
        y: p.y,
        confidence: p.confidence,
      ),
  ],
);

void main() {
  final master = fixture();
  final reference = masterReference(master);

  test('sides swap in pairs and the center line stays', () {
    expect(mirrorJoint(Joint.leftWrist), Joint.rightWrist);
    expect(mirrorJoint(Joint.rightFootIndex), Joint.leftFootIndex);
    expect(mirrorJoint(Joint.nose), Joint.nose);
    expect(mirrorAngle(BodyAngle.leftKnee), BodyAngle.rightKnee);
    for (final joint in Joint.values) {
      expect(mirrorJoint(mirrorJoint(joint)), joint);
    }
    for (final angle in BodyAngle.values) {
      expect(mirrorAngle(mirrorAngle(angle)), angle);
    }
  });

  test('mirroring the reference twice is the identity', () {
    final twice = mirrorReference(mirrorReference(reference)).samples.single;
    final original = reference.samples.single;
    expect(twice.angles, original.angles);
    for (final entry in original.normalized.entries) {
      expect(twice.normalized[entry.key]!.x, closeTo(entry.value.x, 1e-12));
      expect(twice.normalized[entry.key]!.y, entry.value.y);
    }
  });

  test(
    'a learner mirroring an asymmetric master matches only in mirror mode',
    () {
      final angles = reference.samples.single.angles;
      expect(
        angles[BodyAngle.leftKnee],
        isNot(closeTo(angles[BodyAngle.rightKnee]!, 30)),
        reason: 'the fixture must be asymmetric for this test to mean anything',
      );
      final learner = const BodyFeatureExtractor().extract(
        mirroredLearner(master),
      );
      final mirror = PoseMatcher(
        referenceFor(reference, FollowMode.mirror),
      ).compare(learner, 0)!;
      final sameSide = PoseMatcher(
        referenceFor(reference, FollowMode.sameSide),
      ).compare(learner, 0)!;
      expect(mirror.score, closeTo(100, 1e-6));
      expect(sameSide.score, lessThan(mirror.score - 20));
    },
  );

  test('a learner using the same sides matches only in same-side mode', () {
    final learner = const BodyFeatureExtractor().extract(master);
    final sameSide = PoseMatcher(reference).compare(learner, 0)!;
    final mirror = PoseMatcher(mirrorReference(reference)).compare(learner, 0)!;
    expect(sameSide.score, closeTo(100, 1e-6));
    expect(mirror.score, lessThan(sameSide.score - 20));
  });

  test('codes round trip and unknown codes are rejected', () {
    for (final mode in FollowMode.values) {
      expect(FollowMode.fromCode(mode.code), mode);
    }
    expect(FollowMode.fromCode('espejo'), isNull);
    expect(FollowMode.fromCode(null), isNull);
  });
}
