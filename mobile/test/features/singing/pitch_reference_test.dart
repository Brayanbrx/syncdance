import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncdance_mobile/features/routines/reference/motion_reference.dart'
    show ReferenceException;
import 'package:syncdance_mobile/features/singing/reference/pitch_reference.dart';

/// Written by Python (`ai_engine/tests/test_voice.py` checks it is still what
/// the server writes): the "Arpegio de Do" exercise.
List<int> fixtureBytes() => File(
  'test/fixtures/references/pitch_reference_v1.json.gz',
).readAsBytesSync();

Map<String, dynamic> fixtureJson() =>
    jsonDecode(
          File(
            'test/fixtures/references/pitch_reference_v1.meta.json',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>;

PitchReference fixtureReference() => decodePitchReference(
  fixtureBytes(),
  PitchReferenceMetadata.fromJson(fixtureJson()),
);

/// The same artifact with [edit] applied, re-gzipped and with its metadata
/// checksum updated, so only the edited field can be wrong.
(List<int>, PitchReferenceMetadata) tampered(
  void Function(Map<String, dynamic> artifact) edit,
) {
  final artifact =
      jsonDecode(utf8.decode(gzip.decode(fixtureBytes())))
          as Map<String, dynamic>;
  edit(artifact);
  final bytes = gzip.encode(utf8.encode(jsonEncode(artifact)));
  final json = fixtureJson()
    ..['checksum_sha256'] = sha256.convert(bytes).toString();
  return (bytes, PitchReferenceMetadata.fromJson(json));
}

void main() {
  test('the server fixture reads with its notes and tempo', () {
    final reference = fixtureReference();
    expect(reference.notes.map((n) => n.name), [
      'C4',
      'E4',
      'G4',
      'C5',
      'G4',
      'E4',
      'C4',
    ]);
    expect(reference.hopMs, 32);
    expect(reference.frames.length * 32, reference.durationMs);
    expect(reference.metadata.beatGrid!.bpm, 76);
    final first = reference.notes.first;
    expect(reference.noteAt(first.startMs)!.name, 'C4');
    expect(reference.noteAt(first.startMs - 1), isNull); // the count-in
    expect(reference.noteAt(first.endMs), isNull); // the breath after it
    expect(reference.range, (60.0, 72.0));
    expect(solfege(67), 'Sol');
    expect(noteName(66.4), 'F#4');
  });

  test('metadata of another kind or version is refused', () {
    for (final change in <void Function(Map<String, dynamic>)>[
      (json) => json['feature_schema'] = 'motion-features-v1',
      (json) => json['algorithm_version'] = 'voice-pitch-v2+voice-notes-v1',
      (json) => json['status'] = 'PROCESSING',
      (json) => json['duration_ms'] = 400000,
    ]) {
      final json = fixtureJson();
      change(json);
      expect(
        () => PitchReferenceMetadata.fromJson(json),
        throwsA(isA<ReferenceException>()),
      );
    }
  });

  test('a corrupted download is refused before it is expanded', () {
    final bytes = [...fixtureBytes()]..[20] ^= 0xff;
    expect(
      () => decodePitchReference(
        bytes,
        PitchReferenceMetadata.fromJson(fixtureJson()),
      ),
      throwsA(
        isA<ReferenceException>().having(
          (e) => e.message,
          'message',
          contains('dañada'),
        ),
      ),
    );
  });

  test('any field that does not match is refused, never half-read', () {
    final edits = <void Function(Map<String, dynamic>)>[
      (a) => a['schema_version'] = 'pitch-reference-v2',
      (a) => a['source_sha256'] = 'cd' * 32,
      (a) => a['notes_algorithm'] = 'voice-notes-v2',
      (a) => a['hop_ms'] = 0,
      (a) => a['duration_ms'] = 999,
      (a) => (a['frames'] as Map)['midi'] = [
        ...((a['frames'] as Map)['midi'] as List),
        60,
      ],
      (a) => ((a['frames'] as Map)['midi'] as List)[100] = 500,
      (a) => (a['notes'] as List)[1]['start_ms'] = 0,
      (a) => (a['notes'] as List).clear(),
    ];
    for (final edit in edits) {
      final (bytes, metadata) = tampered(edit);
      expect(
        () => decodePitchReference(bytes, metadata),
        throwsA(isA<ReferenceException>()),
      );
    }
  });
}
