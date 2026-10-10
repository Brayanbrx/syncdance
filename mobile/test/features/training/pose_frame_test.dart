import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:syncdance_mobile/features/training/pose/pose_frame.dart';

void main() {
  late PoseFrame frame;
  late List<PoseLandmark> landmarks;

  setUp(() {
    final fixture =
        jsonDecode(
              File(
                'test/fixtures/poses/partial_pose_v1.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    expect(fixture['schema'], PoseFrame.schemaVersion);
    landmarks = (fixture['landmarks'] as List).map((value) {
      final point = value as Map<String, dynamic>;
      return PoseLandmark(
        joint: Joint.values.byName(point['joint'] as String),
        x: (point['x'] as num).toDouble(),
        y: (point['y'] as num).toDouble(),
        confidence: (point['confidence'] as num).toDouble(),
      );
    }).toList();
    frame = PoseFrame(
      timestampMs: fixture['timestamp_ms'] as int,
      imageAspectRatio: (fixture['image_aspect_ratio'] as num).toDouble(),
      landmarks: landmarks,
      poseConfidence: (fixture['pose_confidence'] as num).toDouble(),
    );
  });

  test('partial detection preserves absence and anatomical sides', () {
    expect(frame.landmark(Joint.leftAnkle), isNull);
    expect(frame.landmark(Joint.leftShoulder)!.x, 0.7);
    expect(frame.landmark(Joint.rightShoulder)!.x, 0.3);
    expect(frame.landmark(Joint.leftWrist)!.x, greaterThan(1));
    expect(frame.landmark(Joint.leftShoulder)!.z, isNull);
  });

  test('adapter buffer reuse cannot mutate previously emitted frames', () {
    landmarks.clear();
    expect(frame.landmarks, hasLength(3));
    expect(() => frame.landmarks.clear(), throwsUnsupportedError);
  });

  test('ambiguous joints and nonfinite confidence fail at the boundary', () {
    expect(
      () => PoseFrame(
        timestampMs: 0,
        imageAspectRatio: 0.75,
        landmarks: [landmarks.first, landmarks.first],
        poseConfidence: 1,
      ),
      throwsArgumentError,
    );
    expect(
      () => PoseFrame(
        timestampMs: 0,
        imageAspectRatio: 0.75,
        landmarks: [],
        poseConfidence: double.nan,
      ),
      throwsArgumentError,
    );
  });
}
