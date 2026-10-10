import 'dart:convert';
import 'dart:io';
import 'package:syncdance_mobile/features/training/pose/pose_frame.dart';

PoseFrame fixture() {
  final json =
      jsonDecode(
            File('test/fixtures/poses/body_angles_v1.json').readAsStringSync(),
          )
          as Map<String, dynamic>;
  return PoseFrame(
    timestampMs: json['timestamp_ms'] as int,
    imageAspectRatio: (json['image_aspect_ratio'] as num).toDouble(),
    poseConfidence: (json['pose_confidence'] as num).toDouble(),
    landmarks: [
      for (final p in json['landmarks'] as List<dynamic>)
        PoseLandmark(
          joint: Joint.values.byName(p['joint'] as String),
          x: (p['x'] as num).toDouble(),
          y: (p['y'] as num).toDouble(),
          confidence: (p['confidence'] as num).toDouble(),
        ),
    ],
  );
}

PoseFrame modify(
  PoseFrame original,
  PoseLandmark? Function(PoseLandmark) map, {
  double? aspect,
}) => PoseFrame(
  timestampMs: original.timestampMs,
  imageAspectRatio: aspect ?? original.imageAspectRatio,
  landmarks: original.landmarks.map(map).whereType<PoseLandmark>().toList(),
  poseConfidence: original.poseConfidence,
);
