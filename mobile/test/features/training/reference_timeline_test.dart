import 'package:flutter_test/flutter_test.dart';
import 'package:syncdance_mobile/features/routines/reference/motion_reference.dart';
import 'package:syncdance_mobile/features/training/playback/reference_timeline.dart';

import '../routines/reference_test_samples.dart';

void main() {
  test(
    'video seeks select exact samples including gaps, without carrying old measures',
    () {
      final timeline = ReferenceTimeline(
        decodeReference(referenceBytes(), metadata()),
      );
      expect(timeline.at(const Duration(milliseconds: -1)), isNull);
      expect(timeline.at(Duration.zero)!.angles, isNotEmpty);
      expect(timeline.at(const Duration(milliseconds: 82))!.timestampMs, 0);
      expect(timeline.at(const Duration(milliseconds: 83))!.angles, isEmpty);
      expect(
        timeline.at(const Duration(milliseconds: 167))!.quality,
        'MULTIPLE_PEOPLE',
      );
      expect(timeline.at(Duration.zero)!.angles, isNotEmpty);
      expect(timeline.at(const Duration(milliseconds: 250)), isNull);
      expect(timeline.at(const Duration(seconds: 1)), isNull);
    },
  );
  test('rejects missing or incompatible native video duration', () {
    final timeline = ReferenceTimeline(
      decodeReference(referenceBytes(), metadata()),
    );
    expect(timeline.acceptsDuration(Duration.zero), isFalse);
    expect(timeline.acceptsDuration(const Duration(milliseconds: 250)), isTrue);
    expect(timeline.acceptsDuration(const Duration(milliseconds: 333)), isTrue);
    expect(timeline.acceptsDuration(const Duration(seconds: 1)), isFalse);
  });
}
