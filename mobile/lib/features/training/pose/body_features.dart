import 'dart:math' as math;

import 'pose_frame.dart';

/// Body coordinates, separate from image coordinates used by the overlay.
class BodyPoint {
  const BodyPoint._(this.x, this.y, this.confidence);

  final double x;
  final double y;
  final double confidence;
}

class NormalizedPose {
  NormalizedPose._(this.timestampMs, Map<Joint, BodyPoint> points)
    : points = Map.unmodifiable(points);

  static const schemaVersion = 'body-normalized-v1';
  final int timestampMs;
  final Map<Joint, BodyPoint> points;
}

/// Translate to the hip midpoint and scale by hip-to-shoulder midpoint distance.
/// Restore image aspect ratio before measuring geometry. Keep anatomical names
/// and torso tilt: mirroring belongs to the preview, not these coordinates.
class PoseNormalizer {
  const PoseNormalizer();

  // Initial filtering thresholds, pending physical calibration.
  static const minimumConfidence = 0.5;
  static const minimumScale = 1e-6;

  NormalizedPose? normalize(PoseFrame frame) {
    final usable = {
      for (final point in frame.landmarks)
        if (point.confidence >= minimumConfidence &&
            point.x >= 0 &&
            point.x <= 1 &&
            point.y >= 0 &&
            point.y <= 1)
          point.joint: point,
    };
    final leftHip = usable[Joint.leftHip];
    final rightHip = usable[Joint.rightHip];
    final leftShoulder = usable[Joint.leftShoulder];
    final rightShoulder = usable[Joint.rightShoulder];
    if (leftHip == null ||
        rightHip == null ||
        leftShoulder == null ||
        rightShoulder == null) {
      return null;
    }

    final originX = (leftHip.x + rightHip.x) / 2;
    final originY = (leftHip.y + rightHip.y) / 2;
    final torsoX =
        ((leftShoulder.x + rightShoulder.x) / 2 - originX) *
        frame.imageAspectRatio;
    final torsoY = (leftShoulder.y + rightShoulder.y) / 2 - originY;
    final scale = math.sqrt(torsoX * torsoX + torsoY * torsoY);
    if (!scale.isFinite || scale <= minimumScale) return null;

    final points = <Joint, BodyPoint>{};
    for (final point in usable.values) {
      final x = (point.x - originX) * frame.imageAspectRatio / scale;
      final y = (point.y - originY) / scale;
      if (!x.isFinite || !y.isFinite) return null;
      points[point.joint] = BodyPoint._(x, y, point.confidence);
    }
    return NormalizedPose._(frame.timestampMs, points);
  }
}

enum BodyAngle {
  leftElbow,
  rightElbow,
  leftShoulder,
  rightShoulder,
  leftKnee,
  rightKnee,
}

class BodyFeatures {
  BodyFeatures._(this.pose, Map<BodyAngle, double> angles)
    : angles = Map.unmodifiable(angles);

  static const schemaVersion = 'body-features-v1';
  final NormalizedPose? pose;

  /// Unsigned projected 2D angles in degrees [0, 180]. Missing is not zero.
  final Map<BodyAngle, double> angles;
}

class BodyFeatureExtractor {
  const BodyFeatureExtractor();

  static const _triplets = {
    BodyAngle.leftElbow: (Joint.leftShoulder, Joint.leftElbow, Joint.leftWrist),
    BodyAngle.rightElbow: (
      Joint.rightShoulder,
      Joint.rightElbow,
      Joint.rightWrist,
    ),
    BodyAngle.leftShoulder: (
      Joint.leftElbow,
      Joint.leftShoulder,
      Joint.leftHip,
    ),
    BodyAngle.rightShoulder: (
      Joint.rightElbow,
      Joint.rightShoulder,
      Joint.rightHip,
    ),
    BodyAngle.leftKnee: (Joint.leftHip, Joint.leftKnee, Joint.leftAnkle),
    BodyAngle.rightKnee: (Joint.rightHip, Joint.rightKnee, Joint.rightAnkle),
  };

  BodyFeatures extract(PoseFrame frame) {
    final pose = const PoseNormalizer().normalize(frame);
    final angles = <BodyAngle, double>{};
    if (pose != null) {
      for (final entry in _triplets.entries) {
        final (a, vertex, b) = entry.value;
        final angle = _angle(
          pose.points[a],
          pose.points[vertex],
          pose.points[b],
        );
        if (angle != null) angles[entry.key] = angle;
      }
    }
    return BodyFeatures._(pose, angles);
  }

  double? _angle(BodyPoint? a, BodyPoint? vertex, BodyPoint? b) {
    if (a == null || vertex == null || b == null) return null;
    final ax = a.x - vertex.x;
    final ay = a.y - vertex.y;
    final bx = b.x - vertex.x;
    final by = b.y - vertex.y;
    final aLength = math.sqrt(ax * ax + ay * ay);
    final bLength = math.sqrt(bx * bx + by * by);
    if (!aLength.isFinite ||
        !bLength.isFinite ||
        aLength <= 1e-6 ||
        bLength <= 1e-6) {
      return null;
    }
    final ux = ax / aLength;
    final uy = ay / aLength;
    final vx = bx / bLength;
    final vy = by / bLength;
    return math.atan2((ux * vy - uy * vx).abs(), ux * vx + uy * vy) *
        180 /
        math.pi;
  }
}
