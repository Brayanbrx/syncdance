import 'dart:math' as math;

import '../comparison/pose_matcher.dart';
import '../pose/body_features.dart';
import '../pose/pose_frame.dart';

class FeedbackCue {
  FeedbackCue({
    required this.code,
    required this.region,
    required this.metric,
    required this.magnitude,
    required this.threshold,
    required this.message,
    Set<Joint> highlightedJoints = const {},
  }) : highlightedJoints = Set.unmodifiable(highlightedJoints);
  final Set<Joint> highlightedJoints;
  final String code, region, metric, message;
  final double magnitude, threshold;
  double get severity => magnitude / threshold;
}

/// Geometric suggestions relative to the selected reference, not diagnoses.
class FeedbackRules {
  const FeedbackRules();
  static const version = 'geometric-feedback-v2';

  List<FeedbackCue> evaluate(BodyFeatures learner, PoseMatch match) {
    final master = match.referenceSample;
    final pose = learner.pose;
    if (master == null ||
        pose == null ||
        master.quality != 'SINGLE_PERSON' ||
        !match.score.isFinite ||
        PoseMatcher.joints.any(
          (j) =>
              !pose.points.containsKey(j) || !master.normalized.containsKey(j),
        )) {
      return const [];
    }
    final cues = <FeedbackCue>[];
    void add(
      String code,
      String region,
      String metric,
      double magnitude,
      double threshold,
      String message,
      Set<Joint> joints,
    ) {
      if (magnitude.isFinite && magnitude > 0) {
        cues.add(
          FeedbackCue(
            code: code,
            region: region,
            metric: metric,
            magnitude: magnitude,
            threshold: threshold,
            message: message,
            highlightedJoints: joints,
          ),
        );
      }
    }

    for (final entry in const [
      (BodyAngle.leftElbow, 'left_arm', 'codo izquierdo'),
      (BodyAngle.rightElbow, 'right_arm', 'codo derecho'),
      (BodyAngle.leftKnee, 'left_leg', 'rodilla izquierda'),
      (BodyAngle.rightKnee, 'right_leg', 'rodilla derecha'),
    ]) {
      final (angle, region, label) = entry;
      final actual = learner.angles[angle];
      final target = master.angles[angle];
      if (actual == null ||
          target == null ||
          !actual.isFinite ||
          !target.isFinite) {
        continue;
      }
      final delta = target - actual;
      final action = delta > 0 ? 'extend' : 'flex';
      final article = label.startsWith('codo') ? 'el' : 'la';
      add(
        '${angle.name}_$action',
        region,
        'angle_degrees',
        delta.abs(),
        20,
        '${delta > 0 ? 'Extiende' : 'Flexiona'} un poco $article $label para seguir al maestro.',
        switch (angle) {
          BodyAngle.leftElbow => const {
            Joint.leftShoulder,
            Joint.leftElbow,
            Joint.leftWrist,
          },
          BodyAngle.rightElbow => const {
            Joint.rightShoulder,
            Joint.rightElbow,
            Joint.rightWrist,
          },
          BodyAngle.leftKnee => const {
            Joint.leftHip,
            Joint.leftKnee,
            Joint.leftAnkle,
          },
          BodyAngle.rightKnee => const {
            Joint.rightHip,
            Joint.rightKnee,
            Joint.rightAnkle,
          },
          _ => const {},
        },
      );
    }
    for (final entry in const [
      (Joint.leftWrist, 'left_arm', 'izquierda'),
      (Joint.rightWrist, 'right_arm', 'derecha'),
    ]) {
      final (joint, region, side) = entry;
      // Image y points down: a larger learner y means the hand is too low.
      final delta = pose.points[joint]!.y - master.normalized[joint]!.y;
      final action = delta > 0 ? 'raise' : 'lower';
      add(
        '${joint.name}_$action',
        region,
        'wrist_height_torso',
        delta.abs(),
        0.25,
        '${delta > 0 ? 'Sube' : 'Baja'} un poco la mano $side para seguir al maestro.',
        {joint},
      );
    }
    final actualWidth =
        (pose.points[Joint.leftAnkle]!.x - pose.points[Joint.rightAnkle]!.x)
            .abs();
    final targetWidth =
        (master.normalized[Joint.leftAnkle]!.x -
                master.normalized[Joint.rightAnkle]!.x)
            .abs();
    final widthDelta = targetWidth - actualWidth;
    add(
      widthDelta > 0 ? 'stance_widen' : 'stance_narrow',
      'legs',
      'ankle_width_torso',
      widthDelta.abs(),
      0.3,
      '${widthDelta > 0 ? 'Separa' : 'Acerca'} un poco los pies para seguir al maestro.',
      const {Joint.leftAnkle, Joint.rightAnkle},
    );
    // Compare projected hip-to-shoulder directions. Wrap at +/-180 degrees;
    // neither frontal orientation nor anatomical correction direction is known.
    final actualX =
        (pose.points[Joint.leftShoulder]!.x +
            pose.points[Joint.rightShoulder]!.x -
            pose.points[Joint.leftHip]!.x -
            pose.points[Joint.rightHip]!.x) /
        2;
    final actualY =
        (pose.points[Joint.leftShoulder]!.y +
            pose.points[Joint.rightShoulder]!.y -
            pose.points[Joint.leftHip]!.y -
            pose.points[Joint.rightHip]!.y) /
        2;
    final targetX =
        (master.normalized[Joint.leftShoulder]!.x +
            master.normalized[Joint.rightShoulder]!.x -
            master.normalized[Joint.leftHip]!.x -
            master.normalized[Joint.rightHip]!.x) /
        2;
    final targetY =
        (master.normalized[Joint.leftShoulder]!.y +
            master.normalized[Joint.rightShoulder]!.y -
            master.normalized[Joint.leftHip]!.y -
            master.normalized[Joint.rightHip]!.y) /
        2;
    if (actualX.isFinite &&
        actualY.isFinite &&
        targetX.isFinite &&
        targetY.isFinite &&
        math.sqrt(actualX * actualX + actualY * actualY) > 1e-6 &&
        math.sqrt(targetX * targetX + targetY * targetY) > 1e-6) {
      final delta =
          math.atan2(targetX, -targetY) - math.atan2(actualX, -actualY);
      final degrees =
          math.atan2(math.sin(delta), math.cos(delta)) * 180 / math.pi;
      add(
        degrees > 0 ? 'torso_clockwise' : 'torso_counterclockwise',
        'torso',
        'torso_tilt_degrees',
        degrees.abs(),
        15,
        'Ajusta la inclinación del torso para seguir al maestro.',
        const {
          Joint.leftShoulder,
          Joint.rightShoulder,
          Joint.leftHip,
          Joint.rightHip,
        },
      );
    }
    return List.unmodifiable(cues);
  }
}
