import '../../../core/network/catalog_session.dart';
import '../../routines/reference/motion_reference.dart';
import 'saved_session.dart';
import 'session_store.dart';

class RestoreReport {
  const RestoreReport({required this.restored, required this.skipped});

  /// Practices written to this phone, already marked as synced.
  final int restored;

  /// Server records that do not meet the local rules (older formats).
  final int skipped;
}

class SessionSyncReport {
  const SessionSyncReport({
    required this.synced,
    required this.rejected,
    required this.pending,
    this.stoppedBy,
  });
  final int synced, rejected, pending;

  /// Why the queue stopped early (offline, expired session, server error).
  final String? stoppedBy;
}

/// Offline queue over the local history: pending summaries are uploaded oldest
/// first, and the queue stops at the first transient failure to retry later.
/// Runs on practice save and when the history opens; never during practice.
class SessionSync {
  SessionSync({required this.store, required this.session});
  final SessionStore store;
  final CatalogSession session;

  static final _running = <String, Future<SessionSyncReport>>{};

  /// Opens the account's store; null for guests.
  static Future<SessionSyncReport?> forSession(CatalogSession session) async {
    if (session.account == null) return null;
    final store = await SessionStore.open(session.cacheScope);
    return SessionSync(store: store, session: session).run();
  }

  /// One run per store: a concurrent caller joins the run in progress.
  Future<SessionSyncReport> run() {
    final key = store.directory.path;
    // Block body: returning the removed future would make it wait on itself.
    return _running[key] ??= _run().whenComplete(() {
      _running.remove(key);
    });
  }

  /// Brings the account's synced practices that this phone lacks (another
  /// phone, a reinstall). Local records are never overwritten. Network and
  /// storage errors propagate to the caller.
  Future<RestoreReport> restore() async {
    final remote = await session.authorized(session.api.sessions);
    final local = {for (final s in (await store.readAll()).sessions) s.id};
    var restored = 0, skipped = 0;
    for (final data in remote) {
      if (local.contains(data['id'])) continue;
      final SavedSession record;
      try {
        record = SavedSession.fromServer(data);
      } on Object {
        skipped++;
        continue;
      }
      await store.save(record);
      await store.markSync(record.id, SyncState.synced);
      restored++;
    }
    return RestoreReport(restored: restored, skipped: skipped);
  }

  Future<SessionSyncReport> _run() async {
    final history = await store.readAll();
    var synced = 0, rejected = 0, pending = 0;
    String? stoppedBy;
    for (final record in history.sessions.reversed) {
      if (history.syncOf(record.id).state != SyncState.pending) continue;
      if (stoppedBy != null) {
        pending++;
        continue;
      }
      try {
        final result = await session.authorized(
          (account) => session.api.uploadSession(account, record.toUpload()),
        );
        if (result.stored) {
          await store.markSync(record.id, SyncState.synced);
          synced++;
        } else {
          await store.markSync(
            record.id,
            SyncState.rejected,
            reason: result.reason,
          );
          rejected++;
        }
      } on ReferenceException catch (error) {
        stoppedBy = error.message;
        pending++;
      } on Object {
        stoppedBy = 'No se pudo sincronizar. Se reintentará más tarde.';
        pending++;
      }
    }
    return SessionSyncReport(
      synced: synced,
      rejected: rejected,
      pending: pending,
      stoppedBy: stoppedBy,
    );
  }
}
