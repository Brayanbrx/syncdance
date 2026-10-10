import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:syncdance_mobile/features/routines/reference/motion_reference.dart';
import 'package:syncdance_mobile/features/routines/reference/reference_cache.dart';
import 'package:syncdance_mobile/features/training/pose/body_features.dart';
import 'package:syncdance_mobile/features/training/pose/pose_frame.dart';
import 'reference_test_samples.dart';

void main() {
  test(
    'reads actual Python artifact, retaining empty samples and immutable angles',
    () {
      final ref = decodeReference(referenceBytes(), metadata());
      expect(ref.samples.map((s) => s.timestampMs), [0, 83, 167]);
      expect(ref.samples.first.angles[BodyAngle.rightKnee], closeTo(180, 1e-9));
      expect(
        ref.samples.first.normalized[Joint.leftShoulder]!.x,
        closeTo(-0.6, 1e-9),
      );
      expect(
        ref.samples.first.normalized[Joint.leftShoulder]!.y,
        closeTo(-1, 1e-9),
      );
      expect(ref.samples[1].angles, isEmpty);
      expect(ref.samples[1].quality, 'NO_USABLE_POSE');
      expect(referenceDocument()['frames'][1]['normalized'], isNotEmpty);
      expect(ref.samples[2].quality, 'MULTIPLE_PEOPLE');
      expect(ref.coverage, closeTo(1 / 3, 1e-9));
      expect(() => ref.samples.clear(), throwsUnsupportedError);
      expect(() => ref.samples.first.angles.clear(), throwsUnsupportedError);
      expect(
        () => ref.samples.first.normalized.clear(),
        throwsUnsupportedError,
      );
    },
  );

  test('checksum is required before gzip parsing', () {
    expect(
      () => decodeReference([1, 2], metadata()),
      throwsA(isA<ReferenceException>()),
    );
    expect(
      () => decodeReference([1, 2], metadata(bytes: [1, 2])),
      throwsA(isA<FormatException>()),
    );
  });

  for (final mutation in <String, void Function(Map<String, dynamic>)>{
    'schema': (j) => j['schema'] = 'unknown',
    'provenance': (j) => j['source_sha256'] = 'c' * 64,
    'duration': (j) => j['duration_ms'] = 999,
    'order': (j) => j['frames'][1]['t'] = 0,
    'angle': (j) => j['frames'][0]['angles']['leftElbow'] = 181,
    'unknown joint': (j) => j['frames'][0]['normalized']['alien'] = [0, 1],
    'coordinate shape': (j) => j['frames'][0]['normalized']['leftWrist'] = [0],
    'coordinate type': (j) =>
        j['frames'][0]['normalized']['leftWrist'] = ['0', 1],
    'coverage': (j) => j['valid_frame_ratio'] = 1,
    'empty quality': (j) => j['frames'][1]['quality'] = 'SINGLE_PERSON',
    'multiple people coordinates': (j) =>
        j['frames'][2]['normalized'] = j['frames'][0]['normalized'],
  }.entries) {
    test('rejects invalid ${mutation.key} despite matching checksum', () {
      final json = referenceDocument();
      mutation.value(json);
      final bytes = gzip.encode(utf8.encode(jsonEncode(json)));
      expect(
        () => decodeReference(bytes, metadata(bytes: bytes)),
        throwsA(anything),
      );
    });
  }

  test('rejects unsupported metadata, hash and nonpositive version', () {
    for (final change in [
      {'version': 0},
      {'status': 'PROCESSING'},
      {'checksum_sha256': '../x'},
      {'sample_rate_hz': 30},
    ]) {
      expect(
        () => ReferenceMetadata.fromJson({...metadataJson(), ...change}),
        throwsA(anything),
      );
    }
  });

  test('decompression stops at the configured expanded limit', () {
    final bytes = gzip.encode(List.filled(maxExpandedBytes + 1, 32));
    expect(
      () => decodeReference(bytes, metadata(bytes: bytes)),
      throwsA(isA<ReferenceException>()),
    );
  });

  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('reference-cache-test-');
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });

  test(
    'cache survives reopening without network and partitions accounts/servers',
    () async {
      final cache = ReferenceCache(root, 'http://server/api|1');
      await cache.save('Demo', metadata(), referenceBytes());
      final reopened = await ReferenceCache(
        root,
        'http://server/api|1',
      ).readAll();
      expect(reopened.single.name, 'Demo');
      expect(reopened.single.reference.samples.length, 3);
      expect(
        await ReferenceCache(root, 'http://server/api|2').readAll(),
        isEmpty,
      );
      expect(
        await ReferenceCache(root, 'http://other/api|1').readAll(),
        isEmpty,
      );
    },
  );

  test(
    'failed update preserves earlier version and exact same version can be saved again',
    () async {
      final cache = ReferenceCache(root, 'scope');
      await cache.save('Demo', metadata(), referenceBytes());
      await cache.save('Demo', metadata(), referenceBytes());
      await expectLater(
        cache.save('Bad', metadata(version: 2), [1, 2]),
        throwsA(anything),
      );
      expect((await cache.readAll()).single.reference.metadata.version, 1);
      await cache.save('Demo', metadata(version: 2), referenceBytes());
      expect((await cache.readAll()).map((s) => s.reference.metadata.version), [
        2,
        1,
      ]);
      await cache.remove(metadata(version: 2));
      expect((await cache.readAll()).single.reference.metadata.version, 1);
    },
  );

  test('corrupt entry and temporary file cannot be offered offline', () async {
    final cache = ReferenceCache(root, 'scope');
    await cache.save('Demo', metadata(), referenceBytes());
    final file = (await cache.directory.list().toList())
        .whereType<File>()
        .single;
    await file.writeAsString('{}', flush: true);
    await File('${cache.directory.path}/leftover.tmp').writeAsString('{}');
    expect(await cache.readAll(), isEmpty);
  });

  test(
    'full cache rejects a new version without deleting earlier versions',
    () async {
      final cache = ReferenceCache(root, 'scope');
      await cache.save('Demo', metadata(), referenceBytes());
      final occupied = await File(
        '${cache.directory.path}/occupied',
      ).open(mode: FileMode.write);
      await occupied.truncate(64 * 1024 * 1024);
      await occupied.close();
      await expectLater(
        cache.save('Demo', metadata(version: 2), referenceBytes()),
        throwsA(isA<ReferenceException>()),
      );
      expect((await cache.readAll()).single.reference.metadata.version, 1);
    },
  );
}
