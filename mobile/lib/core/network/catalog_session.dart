import 'dart:async';
import 'dart:convert';

import '../../features/routines/reference/catalog_api.dart';
import '../config/api_config.dart';
import 'credential_store.dart';

/// The access token lives only in memory. With a [store], the identity and the
/// refresh token persist so the app reopens offline and renews on first use.
/// Passwords are never kept.
class CatalogSession {
  CatalogSession(this.api, {this.store});
  final CatalogApi api;
  final CredentialStore? store;
  Account? account;
  String? _refreshToken;
  Future<Account>? _renewing;

  String get _server => api.base.toString();
  String get cacheScope => '${api.base}|${account!.id}';

  /// Opens the stored account without network; storage errors mean no session.
  Future<bool> restore() async {
    try {
      final stored = await store?.read(_server);
      if (stored == null) return false;
      account = Account(stored.accountId, stored.username, '');
      _refreshToken = stored.refreshToken;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<Account> signIn(String username, String password) async {
    await signOut();
    final result = await api.login(username, password);
    account = result.account;
    _refreshToken = result.refreshToken;
    await _persist();
    return result.account;
  }

  /// A usable access token before work that cannot be retried midway (streams).
  Future<Account> freshAccount() async {
    final current = account;
    if (current == null) throw const SessionExpiredException();
    if (current.accessToken.isNotEmpty && !_expiresSoon(current.accessToken)) {
      return current;
    }
    if (_refreshToken == null && current.accessToken.isNotEmpty) return current;
    return _renew();
  }

  /// Runs [call] with a valid token and retries once after renewing on a 401.
  Future<T> authorized<T>(Future<T> Function(Account account) call) async {
    final current = await freshAccount();
    try {
      return await call(current);
    } on SessionExpiredException {
      if (_refreshToken == null) rethrow;
      return call(await _renew());
    }
  }

  Future<void> signOut() async {
    final refresh = _refreshToken;
    account = null;
    _refreshToken = null;
    _renewing = null;
    try {
      await store?.delete(_server);
    } catch (_) {
      // Nothing else to clean; the next sign-in overwrites the entry.
    }
    if (refresh != null) unawaited(api.logout(refresh).catchError((_) {}));
  }

  /// Concurrent callers share one refresh: rotation makes the old token single-use.
  Future<Account> _renew() =>
      _renewing ??= _refresh().whenComplete(() => _renewing = null);

  Future<Account> _refresh() async {
    final current = account;
    final refresh = _refreshToken;
    if (current == null || refresh == null) {
      throw const SessionExpiredException();
    }
    try {
      final tokens = await api.refresh(refresh);
      // A sign-out or another sign-in during the request wins.
      if (!identical(account, current)) throw const SessionExpiredException();
      final renewed = Account(current.id, current.username, tokens.access);
      account = renewed;
      _refreshToken = tokens.refresh ?? refresh;
      await _persist();
      return renewed;
    } on SessionExpiredException {
      if (identical(account, current)) {
        // Keep the identity for local data; network needs a new sign-in.
        _refreshToken = null;
        await _persist();
      }
      rethrow;
    }
  }

  Future<void> _persist() async {
    final current = account;
    if (current == null) return;
    try {
      await store?.write(
        _server,
        StoredCredentials(current.id, current.username, _refreshToken),
      );
    } catch (_) {
      // Secure storage unavailable: the session stays memory-only.
    }
  }

  /// Reads `exp` without verifying the signature; only schedules renewal.
  /// Opaque tokens are renewed reactively after a 401.
  static bool _expiresSoon(String token) {
    final parts = token.split('.');
    if (parts.length != 3) return false;
    try {
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      final exp = payload is Map<String, dynamic> ? payload['exp'] : null;
      if (exp is! int) return false;
      final expiry = DateTime.fromMillisecondsSinceEpoch(exp * 1000);
      return DateTime.now().add(const Duration(seconds: 60)).isAfter(expiry);
    } on FormatException {
      return false;
    }
  }
}

final catalogSession = CatalogSession(
  CatalogApi(ApiConfig.baseUrl),
  store: SecureCredentialStore(),
);
