import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// What is needed to reopen the app offline and renew the session later.
/// Never contains the password or the short-lived access token.
class StoredCredentials {
  const StoredCredentials(this.accountId, this.username, this.refreshToken);
  final int accountId;
  final String username;

  /// Null after the server rejected it: the identity still opens local data,
  /// but network access requires signing in again.
  final String? refreshToken;
}

abstract interface class CredentialStore {
  Future<StoredCredentials?> read(String server);
  Future<void> write(String server, StoredCredentials credentials);
  Future<void> delete(String server);
}

/// Keychain on iOS and Keystore-wrapped ciphers on Android, one entry per server.
class SecureCredentialStore implements CredentialStore {
  SecureCredentialStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _storage;

  static String _key(String server) => 'session-v1|$server';

  @override
  Future<StoredCredentials?> read(String server) async {
    final raw = await _storage.read(key: _key(server));
    if (raw == null) return null;
    final credentials = _decode(raw);
    // An unreadable entry is discarded, never partially trusted.
    if (credentials == null) await delete(server);
    return credentials;
  }

  static StoredCredentials? _decode(String raw) {
    try {
      final data = jsonDecode(raw);
      if (data is! Map<String, dynamic>) return null;
      final id = data['account_id'];
      final username = data['username'];
      final refresh = data['refresh'];
      if (id is! int || id <= 0 || username is! String || username.isEmpty) {
        return null;
      }
      if (refresh != null && (refresh is! String || refresh.isEmpty)) {
        return null;
      }
      return StoredCredentials(id, username, refresh as String?);
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> write(String server, StoredCredentials credentials) =>
      _storage.write(
        key: _key(server),
        value: jsonEncode({
          'account_id': credentials.accountId,
          'username': credentials.username,
          'refresh': credentials.refreshToken,
        }),
      );

  @override
  Future<void> delete(String server) => _storage.delete(key: _key(server));
}
