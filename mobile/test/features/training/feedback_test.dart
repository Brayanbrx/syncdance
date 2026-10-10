import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:syncdance_mobile/features/routines/reference/motion_reference.dart';
import 'package:syncdance_mobile/features/training/comparison/pose_matcher.dart';
import 'package:syncdance_mobile/features/training/feedback/feedback_rules.dart';
import 'package:syncdance_mobile/features/training/feedback/live_feedback.dart';
import 'package:syncdance_mobile/features/training/pose/body_features.dart';
import 'package:syncdance_mobile/features/training/pose/pose_frame.dart';

import 'pose_test_samples.dart';
import '../routines/reference_test_samples.dart';

FeedbackCue cue(String code, {double magnitude = 30, String region = 'arm'}) =>
    FeedbackCue(
      code: code,
      region: region,
      metric: 'degrees',
      magnitude: magnitude,
      threshold: 20,
      message: code,
    );

void main() {
  final features = const BodyFeatureExtractor().extract(fixture());
  final points = features.pose!.points.map(
    (j, p) => MapEntry(j, (x: p.x, y: p.y)),
  );
  List<FeedbackCue> evaluate({
    Map<BodyAngle, double>? angles,
    Map<Joint, ReferencePoint>? positions,
  }) {
    final sample = MotionSample(
      0,
      angles ?? features.angles,
      'SINGLE_PERSON',
      normalized: positions ?? points,
    );
    final match = PoseMatcher(
      MotionReference(metadata(), [sample], 1),
    ).compare(features, 0);
    return match == null ? [] : const FeedbackRules().evaluate(features, match);
  }

  test(
    'identical pose has no corrections; missing selected reference has none',
    () {
      expect(evaluate().where((c) => c.severity >= 1), isEmpty);
      expect(
        const FeedbackRules().evaluate(features, const PoseMatch(0, 0, 0)),
        isEmpty,
      );
    },
  );
  test(
    'signed angle differences choose correct action and anatomical side',
    () {
      for (final angle in [
        BodyAngle.leftElbow,
        BodyAngle.rightElbow,
        BodyAngle.leftKnee,
      ]) {
        for (final delta in [-30.0, 30.0]) {
          final errors = evaluate(
            angles: {
              ...features.angles,
              angle: features.angles[angle]! + delta,
            },
          );
          final error = errors.singleWhere((c) => c.severity >= 1);
          expect(error.code, '${angle.name}_${delta > 0 ? 'extend' : 'flex'}');
          expect(error.magnitude, closeTo(30, 1e-9));
          expect(error.threshold, 20);
          expect(error.message, contains(delta > 0 ? 'Extiende' : 'Flexiona'));
        }
      }
      expect(
        evaluate(
          angles: {...features.angles, BodyAngle.rightKnee: 140},
        ).singleWhere((c) => c.severity >= 1).message,
        contains('rodilla derecha'),
      );
    },
  );
  test('image y direction produces raise/lower for the correct hand', () {
    for (final joint in [Joint.leftWrist, Joint.rightWrist]) {
      for (final delta in [-0.5, 0.5]) {
        final p = points[joint]!;
        final errors = evaluate(
          positions: {...points, joint: (x: p.x, y: p.y + delta)},
        );
        final error = errors.singleWhere((c) => c.severity >= 1);
        expect(error.code, '${joint.name}_${delta < 0 ? 'raise' : 'lower'}');
        expect(error.magnitude, closeTo(0.5, 1e-9));
      }
    }
  });
  test(
    'horizontal ankle separation yields widen/narrow without timing claims',
    () {
      final left = points[Joint.leftAnkle]!;
      for (final delta in [-0.4, 0.4]) {
        final errors = evaluate(
          positions: {
            ...points,
            Joint.leftAnkle: (x: left.x + delta, y: left.y),
          },
        );
        expect(
          errors.singleWhere((c) => c.severity >= 1).code,
          delta < 0 ? 'stance_widen' : 'stance_narrow',
        );
      }
    },
  );
  test(
    'guidance uses the common temporal match rather than the current sample',
    () {
      final wrong = MotionSample(
        0,
        {...features.angles, BodyAngle.leftElbow: 150},
        'SINGLE_PERSON',
        normalized: points,
      );
      final correct = MotionSample(
        83,
        features.angles,
        'SINGLE_PERSON',
        normalized: points,
      );
      final match = PoseMatcher(
        MotionReference(metadata(), [wrong, correct], 1),
      ).compare(features, 0)!;
      expect(identical(match.referenceSample, correct), isTrue);
      expect(
        const FeedbackRules()
            .evaluate(features, match)
            .where((c) => c.severity >= 1),
        isEmpty,
      );
    },
  );

  BodyFeatures tilted(double degrees) {
    final rad = degrees * math.pi / 180;
    return const BodyFeatureExtractor().extract(
      PoseFrame(
        timestampMs: 0,
        imageAspectRatio: 1,
        poseConfidence: 1,
        landmarks: [
          for (final entry in points.entries)
            PoseLandmark(
              joint: entry.key,
              x:
                  0.5 +
                  0.08 *
                      (entry.value.x * math.cos(rad) -
                          entry.value.y * math.sin(rad)),
              y:
                  0.5 +
                  0.08 *
                      (entry.value.x * math.sin(rad) +
                          entry.value.y * math.cos(rad)),
              confidence: 1,
            ),
        ],
      ),
    );
  }

  List<FeedbackCue> torso(double actual, double target) {
    final learner = tilted(actual);
    final master = tilted(target);
    final sample = MotionSample(
      0,
      master.angles,
      'SINGLE_PERSON',
      normalized: master.pose!.points.map(
        (j, p) => MapEntry(j, (x: p.x, y: p.y)),
      ),
    );
    final match = PoseMatcher(
      MotionReference(metadata(), [sample], 1),
    ).compare(learner, 0)!;
    return const FeedbackRules()
        .evaluate(learner, match)
        .where((c) => c.region == 'torso')
        .toList();
  }

  test(
    'torso compares signed projected lean relative to master, not vertical',
    () {
      for (final direction in [-30.0, 30.0]) {
        final error = torso(0, direction).single;
        expect(error.magnitude, closeTo(30, 1e-9));
        expect(error.threshold, 15);
        expect(
          error.code,
          direction > 0 ? 'torso_clockwise' : 'torso_counterclockwise',
        );
        expect(error.highlightedJoints, {
          Joint.leftShoulder,
          Joint.rightShoulder,
          Joint.leftHip,
          Joint.rightHip,
        });
      }
      expect(torso(35, 35).where((c) => c.severity >= 1), isEmpty);
      expect(torso(30, 40).single.severity, lessThan(1));
    },
  );
  test(
    'torso angle wraps across 180 rather than inventing a full turn error',
    () {
      expect(torso(179, -179).single.magnitude, closeTo(2, 1e-9));
      expect(torso(-179, 179).single.magnitude, closeTo(2, 1e-9));
      expect(torso(-20, 20).single.magnitude, closeTo(40, 1e-9));
    },
  );
  test('highlight targets retain anatomical sides and cannot be mutated', () {
    final elbow = evaluate(
      angles: {...features.angles, BodyAngle.leftElbow: 130},
    ).singleWhere((c) => c.severity >= 1);
    expect(elbow.highlightedJoints, {
      Joint.leftShoulder,
      Joint.leftElbow,
      Joint.leftWrist,
    });
    expect(() => elbow.highlightedJoints.clear(), throwsUnsupportedError);
    final knee = evaluate(
      angles: {...features.angles, BodyAngle.rightKnee: 140},
    ).singleWhere((c) => c.severity >= 1);
    expect(knee.highlightedJoints, {
      Joint.rightHip,
      Joint.rightKnee,
      Joint.rightAnkle,
    });
    final wrist = points[Joint.rightWrist]!;
    expect(
      evaluate(
        positions: {
          ...points,
          Joint.rightWrist: (x: wrist.x, y: wrist.y + 0.5),
        },
      ).singleWhere((c) => c.severity >= 1).highlightedJoints,
      {Joint.rightWrist},
    );
  });

  test('requires threshold, duration and several distinct samples', () {
    final engine = LiveFeedback();
    for (var t = 0; t <= 400; t += 100) {
      engine.update(captureMs: t, nowMs: t, cues: [cue('extend')]);
      expect(engine.active?.code, t == 400 ? 'extend' : null);
    }
    final below = LiveFeedback();
    for (var t = 0; t <= 800; t += 100) {
      below.update(
        captureMs: t,
        nowMs: t,
        cues: [cue('extend', magnitude: 19)],
      );
    }
    expect(below.active, isNull);
    final sparse = LiveFeedback();
    for (final t in [0, 200, 400]) {
      sparse.update(captureMs: t, nowMs: t, cues: [cue('extend')]);
    }
    expect(sparse.active, isNull);
  });
  test(
    'duplicates, backwards timestamps and gaps cannot manufacture persistence',
    () {
      final engine = LiveFeedback();
      for (final t in [100, 100, 99, 100, 200, 300]) {
        engine.update(captureMs: t, nowMs: 400, cues: [cue('extend')]);
      }
      expect(engine.active, isNull);
      engine.update(captureMs: 700, nowMs: 700, cues: [cue('extend')]);
      expect(engine.active, isNull);
      for (var t = 800; t <= 1100; t += 100) {
        engine.update(captureMs: t, nowMs: t, cues: [cue('extend')]);
      }
      expect(engine.active?.code, 'extend');
    },
  );
  test(
    'one highest severity cue wins with deterministic ties and no preemption',
    () {
      final engine = LiveFeedback();
      for (var t = 0; t <= 400; t += 100) {
        engine.update(
          captureMs: t,
          nowMs: t,
          cues: [cue('z'), cue('a'), cue('low', magnitude: 20)],
        );
      }
      expect(engine.active?.code, 'a');
      engine.update(
        captureMs: 500,
        nowMs: 500,
        cues: [cue('a'), cue('z', magnitude: 100)],
      );
      expect(engine.active?.code, 'a');
    },
  );
  test(
    'hysteresis avoids threshold flicker and resolved or opposite evidence clears',
    () {
      final engine = LiveFeedback();
      for (var t = 0; t <= 400; t += 100) {
        engine.update(captureMs: t, nowMs: t, cues: [cue('extend')]);
      }
      engine.update(
        captureMs: 500,
        nowMs: 500,
        cues: [cue('extend', magnitude: 15)],
      );
      expect(engine.active?.code, 'extend');
      engine.update(captureMs: 600, nowMs: 600, cues: [cue('flex')]);
      expect(engine.active, isNull);
      for (var t = 700; t <= 2000; t += 100) {
        engine.update(captureMs: t, nowMs: t, cues: [cue('flex')]);
        expect(engine.active, isNull);
      }
      engine.update(captureMs: 2100, nowMs: 2100, cues: [cue('flex')]);
      expect(engine.active?.code, 'flex');
    },
  );
  test(
    'display is bounded and same region rests before another correction',
    () {
      final engine = LiveFeedback();
      for (var t = 0; t <= 1600; t += 100) {
        engine.update(captureMs: t, nowMs: t, cues: [cue('extend')]);
      }
      expect(engine.active, isNull);
      for (var t = 1700; t < 3100; t += 100) {
        engine.update(captureMs: t, nowMs: t, cues: [cue('extend')]);
        expect(engine.active, isNull);
      }
      engine.update(captureMs: 3100, nowMs: 3100, cues: [cue('extend')]);
      expect(engine.active?.code, 'extend');
    },
  );
  test(
    'quality loss invalidates immediately and capture restart requires fresh evidence',
    () {
      final engine = LiveFeedback();
      for (var t = 0; t <= 400; t += 100) {
        engine.update(captureMs: t, nowMs: t, cues: [cue('extend')]);
      }
      engine.invalidate(450);
      expect(engine.active, isNull);
      engine.update(captureMs: 0, nowMs: 2000, cues: [cue('extend')]);
      expect(engine.active, isNull);
      for (var t = 100; t <= 400; t += 100) {
        engine.update(captureMs: t, nowMs: 2000 + t, cues: [cue('extend')]);
      }
      expect(engine.active?.code, 'extend');
      engine.update(captureMs: 500, nowMs: 2500, cues: []);
      expect(engine.active, isNull);
    },
  );
}
