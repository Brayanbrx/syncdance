import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import '../../routines/reference/motion_reference.dart';
import 'saved_session.dart';

enum SyncState { pending, synced, rejected }

class SyncStatus {
  const SyncStatus(this.state, {this.reason});
  static const pending = SyncStatus(SyncState.pending);
  final SyncState state;

  /// Server-side reason for a rejection; never retried automatically.
  final String? reason;
}

class SessionHistory {
  SessionHistory(
    List<SavedSession> sessions,
    this.unreadable, {
    Map<String, SyncStatus> sync = const {},
  }) : sessions = List.unmodifiable(sessions),
       _sync = Map.unmodifiable(sync);
  final List<SavedSession> sessions;
  final int unreadable;
  final Map<String, SyncStatus> _sync;

  /// Missing or unreadable markers mean pending: re-uploading is idempotent.
  SyncStatus syncOf(String id) => _sync[id] ?? SyncStatus.pending;
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

  File _file(String id, [String extension = 'json']) {
    if (!SavedSession.validId.hasMatch(id)) {
      throw const FormatException('UUID inválido.');
    }
    return File('${directory.path}/$id.$extension');
  }

  /// Temporary file, flush and rename: readers never see a partial file.
  Future<void> _publish(File target, List<int> bytes) async {
    final pending = await directory.createTemp('pending-');
    final temp = File('${pending.path}/publish.tmp');
    try {
      await temp.writeAsBytes(bytes, flush: true);
      await temp.rename(target.path);
    } finally {
      if (await temp.exists()) await temp.delete();
      await pending.delete();
    }
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
    await _publish(file, bytes);
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
    return SessionHistory(
      sessions,
      unreadable,
      sync: {
        for (final session in sessions) session.id: await _readSync(session.id),
      },
    );
  }

  Future<SyncStatus> _readSync(String id) async {
    try {
      final file = _file(id, 'sync');
      if (!await file.exists() || await file.length() > 4096) {
        return SyncStatus.pending;
      }
      final data = object(jsonDecode(await file.readAsString()));
      final state = SyncState.values.asNameMap()[data['state']];
      final reason = data['reason'];
      if (data['schema'] != 'session-sync-v1' ||
          state == null ||
          state == SyncState.pending ||
          (reason != null && reason is! String)) {
        return SyncStatus.pending;
      }
      return SyncStatus(state, reason: reason as String?);
    } on Object {
      return SyncStatus.pending;
    }
  }

  Future<void> markSync(String id, SyncState state, {String? reason}) async {
    if (state == SyncState.pending) return clearSync(id);
    await directory.create(recursive: true);
    final target = _file(id, 'sync');
    if (await target.exists()) await target.delete();
    await _publish(
      target,
      utf8.encode(
        jsonEncode({
          'schema': 'session-sync-v1',
          'state': state.name,
          'reason': reason,
          'at': DateTime.now().toUtc().toIso8601String(),
        }),
      ),
    );
  }

  Future<void> clearSync(String id) async {
    final marker = _file(id, 'sync');
    if (await marker.exists()) await marker.delete();
  }

  /// Deleting a local summary never deletes the server copy.
  Future<void> remove(String id) async {
    final file = _file(id);
    if (await file.exists()) await file.delete();
    await clearSync(id);
  }
}
