import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import '../../routines/reference/motion_reference.dart';
import 'saved_session.dart';

class SessionHistory {
  SessionHistory(List<SavedSession> sessions, this.unreadable)
    : sessions = List.unmodifiable(sessions);
  final List<SavedSession> sessions;
  final int unreadable;
}

class SessionStore {
  SessionStore(Directory root, String accountScope)
    : directory = Directory(
        '${root.path}/${sha256.convert(utf8.encode(accountScope))}',
      );
  final Directory directory;
  static const maxFileBytes = 256 * 1024;
  static const maxTotalBytes = 32 * 1024 * 1024;

  static Future<SessionStore> open(String accountScope) async => SessionStore(
    Directory('${(await getApplicationSupportDirectory()).path}/sessions-v1'),
    accountScope,
  );

  File _file(String id) {
    if (!SavedSession.validId.hasMatch(id)) {
      throw const FormatException('UUID inválido.');
    }
    return File('${directory.path}/$id.json');
  }

  Future<void> save(SavedSession session) async {
    // Validate even locally constructed records before publishing.
    SavedSession.fromJson(session.toJson());
    final content = jsonEncode(session.toJson());
    final bytes = utf8.encode(content);
    if (bytes.length > maxFileBytes) {
      throw const FileSystemException('Resumen demasiado grande.');
    }
    await directory.create(recursive: true);
    final file = _file(session.id);
    if (await file.exists()) {
      if (await file.length() <= maxFileBytes &&
          await file.readAsString() == content) {
        return;
      }
      throw const FileSystemException(
        'El identificador ya pertenece a otro resumen.',
      );
    }
    var used = 0;
    await for (final entry in directory.list(followLinks: false)) {
      if (entry is File) used += await entry.length();
    }
    if (used + bytes.length > maxTotalBytes) {
      throw const FileSystemException(
        'Historial lleno. Elimina una práctica guardada.',
      );
    }
    final pending = await directory.createTemp('pending-');
    final temp = File('${pending.path}/session.tmp');
    try {
      await temp.writeAsBytes(bytes, flush: true);
      await temp.rename(file.path);
    } finally {
      if (await temp.exists()) await temp.delete();
      await pending.delete();
    }
  }

  Future<SessionHistory> readAll() async {
    if (!await directory.exists()) return SessionHistory([], 0);
    final sessions = <SavedSession>[];
    var unreadable = 0;
    await for (final entry in directory.list(followLinks: false)) {
      if (entry is! File || !entry.path.endsWith('.json')) continue;
      try {
        if (await entry.length() > maxFileBytes) throw const FormatException();
        final record = SavedSession.fromJson(
          object(jsonDecode(await entry.readAsString())),
        );
        if (entry.uri.pathSegments.last != '${record.id}.json') {
          throw const FormatException();
        }
        sessions.add(record);
      } on Object {
        unreadable++;
      }
    }
    sessions.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return SessionHistory(sessions, unreadable);
  }

  Future<void> remove(String id) async {
    final file = _file(id);
    if (await file.exists()) await file.delete();
  }
}
