import '../../../core/network/catalog_session.dart';
import '../../routines/reference/motion_reference.dart';
import 'session_store.dart';

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
