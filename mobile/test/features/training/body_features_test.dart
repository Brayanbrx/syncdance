import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncdance_mobile/features/training/pose/body_features.dart';
import 'package:syncdance_mobile/features/training/pose/pose_frame.dart';
import 'package:syncdance_mobile/features/training/presentation/body_features_panel.dart';

import 'pose_test_samples.dart';

void main() {
  const extractor = BodyFeatureExtractor();
  const normalizer = PoseNormalizer();

  test('fixture yields six known projected angles and hip origin', () {
    final result = extractor.extract(fixture());
    expect(result.angles.length, 6);
    for (final angle in BodyAngle.values) {
      expect(
        result.angles[angle],
        closeTo(angle == BodyAngle.rightKnee ? 180 : 90, 1e-9),
      );
    }
    final p = result.pose!;
    expect(p.timestampMs, 500);
    expect(p.points[Joint.leftShoulder]!.x, closeTo(-0.6, 1e-9));
    expect(p.points[Joint.leftShoulder]!.y, closeTo(-1, 1e-9));
    expect(
      (p.points[Joint.leftHip]!.x + p.points[Joint.rightHip]!.x) / 2,
      closeTo(0, 1e-9),
    );
    expect(p.points[Joint.leftHip]!.y, closeTo(0, 1e-9));
    expect(p.points[Joint.leftHip]!.confidence, 0.95);
    expect(() => p.points.clear(), throwsUnsupportedError);
    expect(() => result.angles.clear(), throwsUnsupportedError);
  });

  test(
    'translation, uniform scale and image aspect retain comparable features',
    () {
      final source = fixture();
      final expected = extractor.extract(source);
      for (final scale in [0.4, 0.75, 1.0]) {
        for (final aspect in [0.75, 1.0, 1.5]) {
          final changed = modify(
            source,
            (p) => PoseLandmark(
              joint: p.joint,
              x: (p.x - 0.5) * 0.75 * scale / aspect + 0.52,
              y: (p.y - 0.55) * scale + 0.52,
              confidence: p.confidence,
            ),
            aspect: aspect,
          );
          final actual = extractor.extract(changed);
          for (final joint in source.landmarks.map((p) => p.joint)) {
            expect(
              actual.pose!.points[joint]!.x,
              closeTo(expected.pose!.points[joint]!.x, 1e-9),
            );
            expect(
              actual.pose!.points[joint]!.y,
              closeTo(expected.pose!.points[joint]!.y, 1e-9),
            );
          }
          for (final angle in BodyAngle.values) {
            expect(
              actual.angles[angle],
              closeTo(expected.angles[angle]!, 1e-9),
            );
          }
        }
      }
    },
  );

  test('diagonal geometry uses image aspect, not stretched normalized xy', () {
    final changed = modify(
      fixture(),
      (p) => p.joint == Joint.leftAnkle
          ? PoseLandmark(
              joint: p.joint,
              x: 0.3 + 0.2 / 0.75,
              y: 0.55,
              confidence: 1,
            )
          : p,
    );
    expect(
      extractor.extract(changed).angles[BodyAngle.leftKnee],
      closeTo(45, 1e-9),
    );
  });

  test('zero angle is valid; collapsed segment is missing', () {
    final zero = modify(
      fixture(),
      (p) => p.joint == Joint.leftWrist
          ? PoseLandmark(joint: p.joint, x: 0.2, y: 0.3, confidence: 1)
          : p,
    );
    expect(
      extractor.extract(zero).angles[BodyAngle.leftElbow],
      closeTo(0, 1e-9),
    );
    final collapsed = modify(
      zero,
      (p) => p.joint == Joint.leftWrist
          ? PoseLandmark(joint: p.joint, x: 0.1, y: 0.3, confidence: 1)
          : p,
    );
    expect(extractor.extract(collapsed).angles[BodyAngle.leftElbow], isNull);
  });

  for (final anchor in [
    Joint.leftHip,
    Joint.rightHip,
    Joint.leftShoulder,
    Joint.rightShoulder,
  ]) {
    test('missing or unreliable $anchor prevents normalization', () {
      final missing = modify(fixture(), (p) => p.joint == anchor ? null : p);
      expect(extractor.extract(missing).pose, isNull);
      expect(extractor.extract(missing).angles, isEmpty);
      final unreliable = modify(
        fixture(),
        (p) => p.joint == anchor
            ? PoseLandmark(joint: p.joint, x: p.x, y: p.y, confidence: 0.49)
            : p,
      );
      expect(normalizer.normalize(unreliable), isNull);
    });
  }

  test(
    'missing, low confidence or offscreen wrist removes only its elbow measure',
    () {
      final source = fixture();
      for (final replacement in <PoseLandmark?>[
        null,
        PoseLandmark(joint: Joint.leftWrist, x: 0.1, y: 0.5, confidence: 0.49),
        PoseLandmark(joint: Joint.leftWrist, x: -0.1, y: 0.5, confidence: 1),
      ]) {
        final result = extractor.extract(
          modify(source, (p) => p.joint == Joint.leftWrist ? replacement : p),
        );
        expect(result.pose, isNotNull);
        expect(result.angles[BodyAngle.leftElbow], isNull);
        expect(result.angles.length, 5);
      }
    },
  );

  test('empty frame and zero torso scale cannot manufacture geometry', () {
    expect(normalizer.normalize(modify(fixture(), (_) => null)), isNull);
    final flat = modify(
      fixture(),
      (p) => PoseLandmark(joint: p.joint, x: p.x, y: 0.55, confidence: 1),
    );
    expect(normalizer.normalize(flat), isNull);
  });

  test('rigid rotation retains angles but preserves torso tilt', () {
    final source = fixture();
    final expected = extractor.extract(source);
    final rotated = modify(source, (p) {
      final x = (p.x - 0.5) * 0.75;
      final y = p.y - 0.55;
      const radians = 0.1;
      return PoseLandmark(
        joint: p.joint,
        x: (x * math.cos(radians) - y * math.sin(radians)) / 0.75 + 0.5,
        y: x * math.sin(radians) + y * math.cos(radians) + 0.55,
        confidence: p.confidence,
      );
    });
    final actual = extractor.extract(rotated);
    for (final angle in BodyAngle.values) {
      expect(actual.angles[angle], closeTo(expected.angles[angle]!, 1e-9));
    }
    expect(actual.pose!.points[Joint.leftHip]!.y, isNot(closeTo(0, 1e-9)));
  });

  test('horizontal reflection never swaps anatomical joints', () {
    final source = fixture();
    final original = extractor.extract(source);
    final reflected = extractor.extract(
      modify(
        source,
        (p) => PoseLandmark(
          joint: p.joint,
          x: 1 - p.x,
          y: p.y,
          confidence: p.confidence,
        ),
      ),
    );
    expect(reflected.angles[BodyAngle.leftKnee], closeTo(90, 1e-9));
    expect(reflected.angles[BodyAngle.rightKnee], closeTo(180, 1e-9));
    expect(
      reflected.pose!.points[Joint.leftShoulder]!.x,
      closeTo(-original.pose!.points[Joint.leftShoulder]!.x, 1e-9),
    );
    expect(source.landmark(Joint.leftShoulder)!.x, 0.3);
  });

  testWidgets(
    'panel distinguishes valid, missing and unnormalizable measurements',
    (tester) async {
      Future<void> show(PoseFrame frame) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: BodyFeaturesPanel(pose: frame)),
        ),
      );
      await show(fixture());
      expect(find.textContaining('Rodillas: 90° / 180°'), findsOneWidget);
      await show(
        modify(fixture(), (p) => p.joint == Joint.leftWrist ? null : p),
      );
      expect(find.textContaining('Codos: — / 90°'), findsOneWidget);
      await show(modify(fixture(), (p) => p.joint == Joint.leftHip ? null : p));
      expect(
        find.textContaining('muestra ambos hombros y caderas'),
        findsOneWidget,
      );
      expect(find.textContaining('Codos:'), findsNothing);
    },
  );
}
