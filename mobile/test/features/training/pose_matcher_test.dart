import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:syncdance_mobile/features/routines/reference/motion_reference.dart';
import 'package:syncdance_mobile/features/training/comparison/pose_matcher.dart';
import 'package:syncdance_mobile/features/training/pose/body_features.dart';
import 'package:syncdance_mobile/features/training/pose/pose_frame.dart';

import '../routines/reference_test_samples.dart';
import 'pose_test_samples.dart';

void main() {
  const extractor = BodyFeatureExtractor();
  final source = fixture();
  final features = extractor.extract(source);
  final points = features.pose!.points.map(
    (j, p) => MapEntry(j, (x: p.x, y: p.y)),
  );
  MotionSample sample(
    int index, {
    Map<Joint, ReferencePoint>? coordinates,
    Map<BodyAngle, double>? angles,
    String quality = 'SINGLE_PERSON',
  }) => MotionSample(
    (index * 1000 / 12).round(),
    angles ?? features.angles,
    quality,
    normalized: coordinates ?? points,
  );
  MotionReference reference(List<MotionSample> samples) => MotionReference(
    ReferenceMetadata.fromJson({
      ...metadataJson(),
      'duration_ms': (samples.length * 1000 / 12).round(),
    }),
    samples,
    1,
  );

  test('Python reference positions and Flutter body geometry agree', () {
    final result = PoseMatcher(
      decodeReference(referenceBytes(), metadata()),
    ).compare(features, 0)!;
    expect(result.meanPositionError, closeTo(0, 1e-9));
    expect(result.score, closeTo(100, 1e-9));
  });

  test(
    'translation, uniform scale and aspect ratio do not reduce similarity',
    () {
      final matcher = PoseMatcher(reference([sample(0)]));
      for (final scale in [0.4, 0.75, 1.0]) {
        for (final aspect in [0.75, 1.0, 1.5]) {
          final moved = modify(
            source,
            (p) => PoseLandmark(
              joint: p.joint,
              x: (p.x - 0.5) * 0.75 * scale / aspect + 0.52,
              y: (p.y - 0.55) * scale + 0.52,
              confidence: p.confidence,
            ),
            aspect: aspect,
          );
          final result = matcher.compare(extractor.extract(moved), 0)!;
          expect(result.score, closeTo(100, 1e-9));
          expect(result.meanPositionError, closeTo(0, 1e-9));
        }
      }
    },
  );

  test(
    'torso rotation remains observable even with identical joint angles',
    () {
      final rotated = points.map(
        (j, p) => MapEntry(j, (
          x: p.x * math.cos(0.4) - p.y * math.sin(0.4),
          y: p.x * math.sin(0.4) + p.y * math.cos(0.4),
        )),
      );
      final result = PoseMatcher(
        reference([sample(0, coordinates: rotated)]),
      ).compare(features, 0)!;
      expect(result.angleScore, 100);
      expect(result.positionScore, lessThan(100));
      expect(result.score, lessThan(100));
      expect(result.meanPositionError, greaterThan(0));
    },
  );

  test('anatomical positions are not swapped or mirrored to improve score', () {
    final swapped = {
      ...points,
      Joint.leftWrist: points[Joint.rightWrist]!,
      Joint.rightWrist: points[Joint.leftWrist]!,
    };
    final result = PoseMatcher(
      reference([sample(0, coordinates: swapped)]),
    ).compare(features, 0)!;
    expect(result.positionScore, lessThan(100));
  });

  test(
    'window selects one common sample instead of mixing component maxima',
    () {
      final displaced = points.map(
        (j, p) => MapEntry(j, (x: p.x, y: p.y + 0.9)),
      );
      final bent = features.angles.map((j, a) => MapEntry(j, a - 45));
      final matcher = PoseMatcher(
        reference([sample(0, coordinates: displaced), sample(1, angles: bent)]),
      );
      final result = matcher.compare(features, 0)!;
      expect(result.offsetMs, 83);
      expect(result.angleScore, closeTo(50, 1e-9));
      expect(result.positionScore, 100);
      expect(result.score, closeTo(75, 1e-9));
    },
  );

  test(
    'joint gaps cannot be crossed; incomplete center and learner are unscored',
    () {
      final missing = {...points}..remove(Joint.leftWrist);
      final displaced = points.map(
        (j, p) => MapEntry(j, (x: p.x, y: p.y + 0.5)),
      );
      final matcher = PoseMatcher(
        reference([
          sample(0, coordinates: displaced),
          sample(1, coordinates: missing),
          sample(2),
        ]),
      );
      expect(matcher.compare(features, 0)!.score, closeTo(75, 1e-9));
      expect(matcher.compare(features, 83), isNull);
      expect(matcher.compare(features, -1), isNull);
      expect(matcher.compare(features, 250), isNull);
      final partial = extractor.extract(
        modify(source, (p) => p.joint == Joint.leftWrist ? null : p),
      );
      expect(matcher.compare(partial, 0), isNull);
      expect(
        PoseMatcher(reference([sample(0, angles: {})])).compare(features, 0),
        isNull,
      );
      expect(
        PoseMatcher(
          reference([sample(0, quality: 'MULTIPLE_PEOPLE')]),
        ).compare(features, 0),
        isNull,
      );
    },
  );

  test('window is bounded and equal scores prefer closest timestamp', () {
    final bent = features.angles.map((j, a) => MapEntry(j, a - 45));
    final ref = reference([
      for (var i = 0; i < 8; i++)
        sample(i, angles: i == 6 ? features.angles : bent),
    ]);
    expect(PoseMatcher(ref).compare(features, 333)!.score, 100);
    expect(PoseMatcher(ref).compare(features, 250)!.score, closeTo(75, 1e-9));
    final equal = PoseMatcher(reference([sample(0), sample(1), sample(2)]));
    expect(equal.compare(features, 100)!.offsetMs, -17);
  });

  test(
    'invalid reference coordinates cannot create a score; severe finite errors stay bounded',
    () {
      for (final x in [double.nan, double.infinity, 1e308]) {
        final invalid = {...points, Joint.leftWrist: (x: x, y: 0.0)};
        expect(
          PoseMatcher(
            reference([sample(0, coordinates: invalid)]),
          ).compare(features, 0),
          isNull,
        );
      }
      final far = points.map((j, p) => MapEntry(j, (x: p.x + 3, y: p.y)));
      final result = PoseMatcher(
        reference([sample(0, coordinates: far)]),
      ).compare(features, 0)!;
      expect(result.positionScore, 0);
      expect(result.score, 50);
    },
  );
}
