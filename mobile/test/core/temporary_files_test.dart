import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:syncdance_mobile/core/storage/temporary_files.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('syncdance-temporaries-');
  });
  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<Directory> folder(String name) async {
    final created = await Directory('${root.path}/$name').create();
    await File('${created.path}/partial.tmp').writeAsBytes([1, 2, 3]);
    return created;
  }

  test('removes write folders left by a killed app, nothing else', () async {
    final download = await folder('download-abc');
    final pending = await folder('pending-def');
    final audio = await folder('audio');
    final kept = File('${root.path}/7-1-${'a' * 64}.json');
    await kept.writeAsString('{}');
    final pendingFile = File('${root.path}/pending-file');
    await pendingFile.writeAsString('not a folder');

    // A download in progress is never touched.
    await removeStaleTemporaries(root);
    expect(await download.exists(), isTrue);
    expect(await pending.exists(), isTrue);

    await removeStaleTemporaries(
      root,
      now: DateTime.now().add(const Duration(hours: 3)),
    );
    expect(await download.exists(), isFalse);
    expect(await pending.exists(), isFalse);
    expect(await audio.exists(), isTrue);
    expect(await kept.exists(), isTrue);
    expect(await pendingFile.exists(), isTrue);
  });

  test('a missing folder is not an error', () async {
    await removeStaleTemporaries(Directory('${root.path}/never-created'));
  });
}
