import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../pose/pose_frame.dart';

/// Presentation-only filtering. This is not the scoring quality gate.
Map<Joint, Offset> projectPose(
  PoseFrame pose,
  Size size, {
  required bool mirrored,
  double minimumConfidence = 0.5,
}) => {
  for (final point in pose.landmarks)
    if (point.confidence >= minimumConfidence &&
        point.x >= 0 &&
        point.x <= 1 &&
        point.y >= 0 &&
        point.y <= 1)
      point.joint: Offset(
        (mirrored ? 1 - point.x : point.x) * size.width,
        point.y * size.height,
      ),
};

const poseConnections = <(Joint, Joint)>[
  (Joint.nose, Joint.leftEyeInner),
  (Joint.leftEyeInner, Joint.leftEye),
  (Joint.leftEye, Joint.leftEyeOuter),
  (Joint.leftEyeOuter, Joint.leftEar),
  (Joint.nose, Joint.rightEyeInner),
  (Joint.rightEyeInner, Joint.rightEye),
  (Joint.rightEye, Joint.rightEyeOuter),
  (Joint.rightEyeOuter, Joint.rightEar),
  (Joint.leftMouth, Joint.rightMouth),
  (Joint.leftShoulder, Joint.rightShoulder),
  (Joint.leftShoulder, Joint.leftElbow),
  (Joint.leftElbow, Joint.leftWrist),
  (Joint.leftWrist, Joint.leftPinky),
  (Joint.leftWrist, Joint.leftIndex),
  (Joint.leftWrist, Joint.leftThumb),
  (Joint.leftPinky, Joint.leftIndex),
  (Joint.rightShoulder, Joint.rightElbow),
  (Joint.rightElbow, Joint.rightWrist),
  (Joint.rightWrist, Joint.rightPinky),
  (Joint.rightWrist, Joint.rightIndex),
  (Joint.rightWrist, Joint.rightThumb),
  (Joint.rightPinky, Joint.rightIndex),
  (Joint.leftShoulder, Joint.leftHip),
  (Joint.rightShoulder, Joint.rightHip),
  (Joint.leftHip, Joint.rightHip),
  (Joint.leftHip, Joint.leftKnee),
  (Joint.leftKnee, Joint.leftAnkle),
  (Joint.leftAnkle, Joint.leftHeel),
  (Joint.leftHeel, Joint.leftFootIndex),
  (Joint.leftAnkle, Joint.leftFootIndex),
  (Joint.rightHip, Joint.rightKnee),
  (Joint.rightKnee, Joint.rightAnkle),
  (Joint.rightAnkle, Joint.rightHeel),
  (Joint.rightHeel, Joint.rightFootIndex),
  (Joint.rightAnkle, Joint.rightFootIndex),
];

class PoseOverlayPainter extends CustomPainter {
  PoseOverlayPainter({
    required this.pose,
    required this.mirrored,
    Set<Joint> highlightedJoints = const {},
  }) : highlightedJoints = Set.unmodifiable(highlightedJoints);

  final PoseFrame pose;
  final bool mirrored;
  final Set<Joint> highlightedJoints;

  Color _color(Joint joint) => joint.name.startsWith('left')
      ? Colors.orangeAccent
      : joint.name.startsWith('right')
      ? Colors.cyanAccent
      : Colors.white;

  @override
  void paint(Canvas canvas, Size size) {
    final points = projectPose(pose, size, mirrored: mirrored);
    final stroke = Paint()
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (final (from, to) in poseConnections) {
      final start = points[from];
      final end = points[to];
      if (start == null || end == null) continue;
      stroke.color = _color(from) == _color(to) ? _color(from) : Colors.white;
      canvas.drawLine(start, end, stroke);
    }
    for (final entry in points.entries) {
      canvas.drawCircle(entry.value, 4, Paint()..color = Colors.black87);
      canvas.drawCircle(entry.value, 2.5, Paint()..color = _color(entry.key));
    }
    // Extra rings retain anatomical colors and use the exact same projection.
    for (final joint in highlightedJoints) {
      final point = points[joint];
      if (point == null) continue;
      canvas.drawCircle(
        point,
        8.5,
        Paint()
          ..color = Colors.black87
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5,
      );
      canvas.drawCircle(
        point,
        8.5,
        Paint()
          ..color = Colors.yellowAccent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(PoseOverlayPainter oldDelegate) =>
      oldDelegate.pose != pose ||
      oldDelegate.mirrored != mirrored ||
      !setEquals(oldDelegate.highlightedJoints, highlightedJoints);
}
