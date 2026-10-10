import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncdance_mobile/features/routines/reference/master_video_cache.dart';
import 'package:syncdance_mobile/features/routines/reference/motion_reference.dart';

import 'reference_test_samples.dart';

void main() {
  final bytes = List.generate(400, (i) => i % 256);
  ReferenceMetadata meta({int version = 1}) => ReferenceMetadata.fromJson({
    ...metadataJson(version: version),
    'source_sha256': sha256.convert(bytes).toString(),
  });
  late Directory root;
  late MasterVideoCache cache;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('master-video-test-');
    cache = MasterVideoCache(root);
  });
  tearDown(() => root.delete(recursive: true));

  test(
    'streams, reopens offline, isolates versions and deletes only selected video',
    () async {
      await cache.save(
        meta(),
        Stream.fromIterable([bytes.sublist(0, 100), bytes.sublist(100)]),
      );
      final reopened = await MasterVideoCache(root).read(meta());
      expect(await reopened!.readAsBytes(), bytes);
      expect(await cache.read(meta(version: 2)), isNull);
      await cache.save(meta(version: 2), Stream.value(bytes));
      await cache.remove(meta());
      expect(await cache.read(meta()), isNull);
      expect(await cache.read(meta(version: 2)), isNotNull);
    },
  );

  test(
    'checksum failure and broken stream preserve earlier file and clean partials',
    () async {
      await cache.save(meta(), Stream.value(bytes));
      await expectLater(
        cache.save(meta(), Stream.value([1, 2])),
        throwsA(isA<ReferenceException>()),
      );
      await expectLater(
        cache.save(
          meta(version: 2),
          Stream.error(const SocketException('offline')),
        ),
        throwsA(isA<SocketException>()),
      );
      expect(await (await cache.read(meta()))!.readAsBytes(), bytes);
      expect(await cache.directory.list().length, 1);
      final saved = await cache.read(meta());
      await saved!.writeAsBytes([3, 4]);
      expect(await cache.read(meta()), isNull);
    },
  );

  test('quota rejects new download without evicting a valid version', () async {
    await cache.save(meta(), Stream.value(bytes));
    final occupied = await File(
      '${cache.directory.path}/occupied',
    ).open(mode: FileMode.write);
    await occupied.truncate(MasterVideoCache.maxCacheBytes);
    await occupied.close();
    await expectLater(
      cache.save(meta(version: 2), Stream.value(bytes)),
      throwsA(isA<ReferenceException>()),
    );
    expect(await cache.read(meta()), isNotNull);
  });
}
