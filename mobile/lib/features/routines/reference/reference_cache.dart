import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import 'motion_reference.dart';
import 'master_video_cache.dart';

class SavedReference {
  SavedReference(this.name, this.reference);
  final String name;
  final MotionReference reference;
}

/// Private application files partitioned by API endpoint and authenticated user.
/// Each version is a self-contained envelope; a failed write cannot replace others.
class ReferenceCache {
  ReferenceCache(Directory root, String accountScope)
    : directory = Directory(
        '${root.path}/${sha256.convert(utf8.encode(accountScope))}',
      );
  final Directory directory;
  static const maxEnvelopeBytes = 12 * 1024 * 1024;
  static final _validName = RegExp(r'^\d+-\d+-[a-f0-9]{64}\.json$');

  String _name(ReferenceMetadata m) =>
      '${m.routineId}-${m.version}-${m.checksum}.json';

  Future<void> save(
    String name,
    ReferenceMetadata metadata,
    List<int> bytes,
  ) async {
    // Parse and verify before publishing to disk, outside the UI isolate.
    await compute(_verify, (bytes, metadata));
    await directory.create(recursive: true);
    var used = 0;
    await for (final entry in directory.list(followLinks: false)) {
      if (entry is File && entry.uri.pathSegments.last != _name(metadata)) {
        used += await entry.length();
      }
    }
    final content = jsonEncode({
      'name': name,
      'metadata': metadata.toJson(),
      'gzip': base64Encode(bytes),
    });
    if (utf8.encode(content).length > maxEnvelopeBytes) {
      throw const ReferenceException('Archivo demasiado grande.');
    }
    if (used + utf8.encode(content).length > 64 * 1024 * 1024) {
      throw const ReferenceException(
        'Almacenamiento de referencias lleno. Elimina una versión guardada.',
      );
    }
    final file = File('${directory.path}/${_name(metadata)}');
    final tempDirectory = await directory.createTemp('pending-');
    final temp = File('${tempDirectory.path}/reference.tmp');
    try {
      await temp.writeAsString(content, flush: true);
      await temp.rename(file.path);
    } finally {
      if (await temp.exists()) await temp.delete();
      await tempDirectory.delete();
    }
  }

  Future<void> remove(ReferenceMetadata metadata) async {
    await MasterVideoCache(directory).remove(metadata);
    final file = File('${directory.path}/${_name(metadata)}');
    if (await file.exists()) await file.delete();
  }

  Future<List<SavedReference>> readAll() async {
    if (!await directory.exists()) return [];
    final saved = <SavedReference>[];
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File ||
          !_validName.hasMatch(entity.uri.pathSegments.last)) {
        continue;
      }
      try {
        if (await entity.length() > maxEnvelopeBytes) continue;
        final result = await compute(
          _readEnvelope,
          await entity.readAsString(),
        );
        if (entity.uri.pathSegments.last != _name(result.reference.metadata)) {
          continue;
        }
        saved.add(result);
      } on Object {
        // A corrupt entry is not offered for practice. Other versions survive.
      }
    }
    saved.sort(
      (a, b) =>
          b.reference.metadata.version.compareTo(a.reference.metadata.version),
    );
    return saved;
  }
}

MotionReference _verify((List<int>, ReferenceMetadata) args) =>
    decodeReference(args.$1, args.$2);

SavedReference _readEnvelope(String content) {
  final data = object(jsonDecode(content));
  return SavedReference(
    data['name'] as String,
    decodeReference(
      base64Decode(data['gzip'] as String),
      ReferenceMetadata.fromJson(object(data['metadata'])),
    ),
  );
}
