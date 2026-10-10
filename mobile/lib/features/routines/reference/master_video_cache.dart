import 'dart:io';

import 'package:crypto/crypto.dart';

import 'motion_reference.dart';

/// Download state for the screen: a fraction when the size is known, so
/// a large master shows how much is left instead of an endless bar.
({double? fraction, String label}) downloadProgress(int received, int? total) {
  if (total != null && total > 0) {
    final fraction = (received / total).clamp(0.0, 1.0);
    return (fraction: fraction, label: '${(fraction * 100).floor()} %');
  }
  return (
    fraction: null,
    label: '${(received / (1024 * 1024)).toStringAsFixed(1)} MB',
  );
}

/// Stored beneath an already account-scoped ReferenceCache directory.
class MasterVideoCache {
  MasterVideoCache(Directory accountDirectory)
    : directory = Directory('${accountDirectory.path}/videos');
  final Directory directory;
  static const maxVideoBytes = 200 * 1024 * 1024;
  static const maxCacheBytes = 512 * 1024 * 1024;

  File _file(ReferenceMetadata metadata) => File(
    '${directory.path}/${metadata.routineId}-${metadata.version}-${metadata.sourceHash}.video',
  );

  Future<File?> read(ReferenceMetadata metadata) async {
    final file = _file(metadata);
    if (!await file.exists()) return null;
    if (await file.length() > maxVideoBytes ||
        (await sha256.bind(file.openRead()).first).toString() !=
            metadata.sourceHash) {
      // Remove unusable data so a retry can replace it and reclaim its quota.
      await file.delete();
      return null;
    }
    return file;
  }

  Future<File> save(ReferenceMetadata metadata, Stream<List<int>> bytes) async {
    await directory.create(recursive: true);
    final target = _file(metadata);
    var used = 0;
    await for (final file in directory.list(followLinks: false)) {
      if (file is File && file.path != target.path) used += await file.length();
    }
    final temporary = await directory.createTemp('pending-');
    final partial = File('${temporary.path}/master.tmp');
    final output = await partial.open(mode: FileMode.write);
    var received = 0;
    try {
      try {
        await for (final chunk in bytes) {
          received += chunk.length;
          if (received > maxVideoBytes || used + received > maxCacheBytes) {
            throw const ReferenceException(
              'No hay espacio para este video. Elimina otros videos guardados.',
            );
          }
          await output.writeFrom(chunk);
        }
        await output.flush();
      } finally {
        await output.close();
      }
      if (received == 0 ||
          (await sha256.bind(partial.openRead()).first).toString() !=
              metadata.sourceHash) {
        throw const ReferenceException(
          'El video no coincide con esta versión de referencia.',
        );
      }
      return await partial.rename(target.path);
    } finally {
      if (await partial.exists()) await partial.delete();
      await temporary.delete();
    }
  }

  Future<void> remove(ReferenceMetadata metadata) async {
    final file = _file(metadata);
    if (await file.exists()) await file.delete();
  }
}
