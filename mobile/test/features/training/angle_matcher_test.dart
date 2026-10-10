import 'package:flutter_test/flutter_test.dart';
import 'package:syncdance_mobile/features/routines/reference/motion_reference.dart';
import 'package:syncdance_mobile/features/training/comparison/angle_matcher.dart';
import 'package:syncdance_mobile/features/training/pose/body_features.dart';

import '../routines/reference_test_samples.dart';

Map<BodyAngle, double> angles(double value) => {
  for (final a in BodyAngle.values) a: value,
};
MotionReference reference(List<Map<BodyAngle, double>> frames) =>
    MotionReference(
      ReferenceMetadata.fromJson({
        ...metadataJson(),
        'duration_ms': (frames.length * 1000 / 12).round(),
      }),
      [
        for (var i = 0; i < frames.length; i++)
          MotionSample(
            (i * 1000 / 12).round(),
            frames[i],
            frames[i].isEmpty ? 'NO_USABLE_POSE' : 'SINGLE_PERSON',
          ),
      ],
      1,
    );

void main() {
  test(
    'identical poses score higher than incorrect ones and score is bounded',
    () {
      final matcher = AngleMatcher(reference(List.filled(12, angles(90))));
      expect(matcher.compare(angles(90), 400)!.score, 100);
      expect(matcher.compare(angles(135), 400)!.score, 50);
      expect(matcher.compare(angles(0), 400)!.score, 0);
      expect(matcher.compare(angles(135), 400)!.meanErrorDegrees, 45);
      final fullError = AngleMatcher(reference([angles(0)]));
      expect(fullError.compare(angles(180), 0)!.score, 0);
    },
  );
  test('nearby movement can match inside window; distant movement cannot', () {
    final frames = List.generate(12, (_) => angles(0));
    frames[6] = angles(90); // 500 ms
    final matcher = AngleMatcher(reference(frames));
    expect(matcher.compare(angles(90), 333)!.score, 100);
    expect(matcher.compare(angles(90), 333)!.offsetMs, 167);
    expect(matcher.compare(angles(90), 250)!.score, 0);
  });
  test(
    'gaps, partial/invalid angles and out of range positions never get a score',
    () {
      final matcher = AngleMatcher(reference([angles(0), {}, angles(90)]));
      expect(matcher.compare(angles(90), 0)!.score, 0); // Cannot cross gap.
      expect(matcher.compare(angles(90), 83), isNull);
      expect(matcher.compare(angles(90), -1), isNull);
      expect(matcher.compare(angles(90), 250), isNull);
      expect(matcher.compare({BodyAngle.leftElbow: 90}, 0), isNull);
      expect(
        matcher.compare({...angles(90), BodyAngle.leftKnee: double.nan}, 0),
        isNull,
      );
      final partial = AngleMatcher(
        reference([
          {BodyAngle.leftElbow: 90},
        ]),
      );
      expect(partial.compare(angles(90), 0), isNull);
    },
  );
  test('anatomical sides are not swapped to improve similarity', () {
    final master = <BodyAngle, double>{
      ...angles(90),
      BodyAngle.leftElbow: 0,
      BodyAngle.rightElbow: 180,
    };
    final learner = <BodyAngle, double>{
      ...master,
      BodyAngle.leftElbow: 180,
      BodyAngle.rightElbow: 0,
    };
    final matcher = AngleMatcher(reference([master]));
    expect(matcher.compare(master, 0)!.score, 100);
    expect(matcher.compare(learner, 0)!.meanErrorDegrees, 60);
  });
}
