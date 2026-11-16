import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:syncdance_mobile/features/routines/reference/motion_reference.dart';

import 'reference_test_samples.dart';

/// `routine-steps-v1` as Python writes it (apps/studio/choreography.py).
Map<String, dynamic> contract() =>
    jsonDecode(
          File(
            'test/fixtures/references/scoring_profile_v1.json',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>;

ReferenceMetadata withProfile(Object? profile, {int durationMs = 15000}) =>
    ReferenceMetadata.fromJson({
      ...metadataJson(),
      'duration_ms': durationMs,
      'scoring_profile': profile,
    });

void main() {
  test('the steps of the shared fixture reach the phone', () {
    final fixture = contract();
    final metadata = withProfile(
      fixture['profile'],
      durationMs: fixture['duration_ms'] as int,
    );
    expect(metadata.beatGrid!.bpm, 112);
    expect(metadata.beatGrid!.firstBeatMs, 1250);
    expect(
      metadata.steps.map(
        (s) => (s.index, s.name, s.startMs, s.endMs, s.counts),
      ),
      [
        (0, 'Paso cruzado', 1250, 5536, 8),
        (1, 'Giro', 5536, 7679, 4),
        (2, 'Cierre con brazos', 9821, 14107, 8),
      ],
    );
    expect(metadata.steps.first.tip, startsWith('Cruza el pie derecho'));
    expect(metadata.steps[1].tip, isEmpty);
  });

  test('steps and beat grid survive the metadata round trip of the cache', () {
    final fixture = contract();
    final metadata = withProfile(fixture['profile']);
    final copy = ReferenceMetadata.fromJson(metadata.toJson());
    expect(copy.toJson()['scoring_profile'], fixture['profile']);
    expect(copy.steps, hasLength(3));
    expect(copy.beatGrid!.bpm, 112);
  });

  test('a malformed step list is ignored, never the download', () {
    Map<String, dynamic> profile(List<Object?> items, {String? version}) => {
      'steps': {'version': version ?? 'routine-steps-v1', 'items': items},
    };
    Map<String, dynamic> step({
      Object name = 'Paso',
      Object start = 0,
      Object end = 1000,
      Object counts = 2,
      Object? tip = '',
    }) => {
      'name': name,
      'start_ms': start,
      'end_ms': end,
      'counts': counts,
      'tip': tip,
    };
    for (final bad in [
      profile([step()], version: 'routine-steps-v9'),
      profile([]),
      profile([step(), step(start: 500, end: 1500)]), // overlaps
      profile([step(end: 20000)]), // past the video
      profile([step(start: 1000, end: 1000)]),
      profile([step(counts: 0)]),
      profile([step(counts: 33)]),
      profile([step(name: '  ')]),
      profile([step(tip: 'x' * 141)]),
      profile([step(start: 1.5)]),
      profile(['x']),
      {'steps': 'x'},
    ]) {
      final metadata = withProfile(bad);
      expect(metadata.steps, isEmpty, reason: '$bad');
      expect(metadata.durationMs, 15000);
    }
    expect(withProfile(null).steps, isEmpty);
    expect(withProfile(null).toJson().containsKey('scoring_profile'), isFalse);
  });

  test('the count being danced starts at the first counted beat', () {
    const grid = BeatGrid(bpm: 120, firstBeatMs: 1000, beatsPerMove: 2);
    expect(grid.beatAt(999), isNull);
    expect(grid.beatAt(1000), 0);
    expect(grid.beatAt(1499), 0);
    expect(grid.beatAt(7499), 12); // the 5 of the second eight
  });
}
