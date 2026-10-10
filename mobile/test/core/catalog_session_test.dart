import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:syncdance_mobile/core/network/catalog_session.dart';
import 'package:syncdance_mobile/core/network/credential_store.dart';
import 'package:syncdance_mobile/features/routines/reference/catalog_api.dart';

class MemoryCredentialStore implements CredentialStore {
  final values = <String, StoredCredentials>{};
  @override
  Future<StoredCredentials?> read(String server) async => values[server];
  @override
  Future<void> write(String server, StoredCredentials credentials) async =>
      values[server] = credentials;
  @override
  Future<void> delete(String server) async => values.remove(server);
}

String jwt(DateTime expiry) =>
    'h.${base64Url.encode(utf8.encode(jsonEncode({'exp': expiry.millisecondsSinceEpoch ~/ 1000}))).replaceAll('=', '')}.s';

/// Minimal SimpleJWT double: rotation makes each refresh token single-use.
class FakeAuthServer {
  var refreshCalls = 0;
  var logoutCalls = 0;
  var routineCalls = 0;
  var validRefresh = <String>{};
  var validAccess = <String>{};
  var counter = 0;
  bool online = true;
  Completer<void>? refreshGate;

  String _issue(Set<String> into, String prefix) {
    final token = '$prefix-${counter++}';
    into.add(token);
    return token;
  }

  late final client = MockClient((request) async {
    if (!online) throw http.ClientException('offline');
    final path = request.url.path;
    if (path.endsWith('auth/login/')) {
      return http.Response(
        jsonEncode({
          'access': _issue(validAccess, 'access'),
          'refresh': _issue(validRefresh, 'refresh'),
        }),
        200,
      );
    }
    if (path.endsWith('auth/me/')) {
      return http.Response('{"id":5,"username":"ana"}', 200);
    }
    if (path.endsWith('auth/token/refresh/')) {
      refreshCalls++;
      await refreshGate?.future;
      final token = jsonDecode(request.body)['refresh'] as String;
      if (!validRefresh.remove(token)) return http.Response('{}', 401);
      return http.Response(
        jsonEncode({
          'access': _issue(validAccess, 'access'),
          'refresh': _issue(validRefresh, 'refresh'),
        }),
        200,
      );
    }
    if (path.endsWith('auth/logout/')) {
      logoutCalls++;
      validRefresh.remove(jsonDecode(request.body)['refresh']);
      return http.Response('{}', 200);
    }
    if (path.endsWith('routines/')) {
      routineCalls++;
      final token = request.headers['Authorization']?.substring(7);
      if (!validAccess.contains(token)) return http.Response('{}', 401);
      return http.Response('{"results":[],"next":null}', 200);
    }
    return http.Response('{}', 404);
  });
}

void main() {
  late FakeAuthServer server;
  late CatalogApi api;
  late MemoryCredentialStore store;

  setUp(() {
    server = FakeAuthServer();
    api = CatalogApi('http://localhost:8000/api', client: server.client);
    store = MemoryCredentialStore();
  });

  test(
    'sign-in persists identity and refresh token, never the password',
    () async {
      final session = CatalogSession(api, store: store);
      await session.signIn('ana', 'secret-password');
      final stored = store.values.values.single;
      expect(stored.accountId, 5);
      expect(stored.username, 'ana');
      expect(stored.refreshToken, startsWith('refresh-'));
    },
  );

  test('restore opens offline and renews on first network use', () async {
    await CatalogSession(api, store: store).signIn('ana', 'secret-password');
    server.online = false;
    final reopened = CatalogSession(api, store: store);
    expect(await reopened.restore(), isTrue);
    expect(reopened.account!.id, 5);
    expect(reopened.cacheScope, endsWith('|5'));
    server.online = true;
    final previousRefresh = store.values.values.single.refreshToken;
    expect(await reopened.authorized(api.routines), isEmpty);
    expect(server.refreshCalls, 1);
    expect(store.values.values.single.refreshToken, isNot(previousRefresh));
  });

  test(
    'a rejected access token is renewed once and the call retried',
    () async {
      final session = CatalogSession(api, store: store);
      await session.signIn('ana', 'secret-password');
      server.validAccess.clear();
      expect(await session.authorized(api.routines), isEmpty);
      expect(server.refreshCalls, 1);
      expect(server.routineCalls, 2);
    },
  );

  test('a second rejection does not loop', () async {
    final session = CatalogSession(api, store: store);
    await session.signIn('ana', 'secret-password');
    server.validAccess.clear();
    Future<List<RoutineItem>> alwaysExpired(Account account) async {
      server.routineCalls++;
      throw const SessionExpiredException();
    }

    await expectLater(
      session.authorized(alwaysExpired),
      throwsA(isA<SessionExpiredException>()),
    );
    expect(server.refreshCalls, 1);
    expect(server.routineCalls, 2);
  });

  test('concurrent callers share one rotation', () async {
    await CatalogSession(api, store: store).signIn('ana', 'secret-password');
    final session = CatalogSession(api, store: store);
    await session.restore();
    server.refreshGate = Completer<void>();
    final calls = [
      session.authorized(api.routines),
      session.authorized(api.routines),
      session.freshAccount(),
    ];
    server.refreshGate!.complete();
    await Future.wait(calls);
    expect(server.refreshCalls, 1);
  });

  test('a revoked refresh keeps the identity for local data only', () async {
    await CatalogSession(api, store: store).signIn('ana', 'secret-password');
    server.validRefresh.clear();
    final session = CatalogSession(api, store: store);
    await session.restore();
    await expectLater(
      session.authorized(api.routines),
      throwsA(isA<SessionExpiredException>()),
    );
    expect(session.account!.id, 5);
    expect(store.values.values.single.refreshToken, isNull);
    final reopened = CatalogSession(api, store: store);
    expect(await reopened.restore(), isTrue);
    await expectLater(
      reopened.authorized(api.routines),
      throwsA(isA<SessionExpiredException>()),
    );
    expect(server.refreshCalls, 1);
  });

  test('network failure during renewal keeps the refresh token', () async {
    await CatalogSession(api, store: store).signIn('ana', 'secret-password');
    final session = CatalogSession(api, store: store);
    await session.restore();
    server.online = false;
    await expectLater(session.authorized(api.routines), throwsException);
    expect(store.values.values.single.refreshToken, isNotNull);
  });

  test(
    'sign-out forgets local credentials and revokes on the server',
    () async {
      final session = CatalogSession(api, store: store);
      await session.signIn('ana', 'secret-password');
      await session.signOut();
      await pumpEventQueue();
      expect(session.account, isNull);
      expect(store.values, isEmpty);
      expect(server.logoutCalls, 1);
      expect(server.validRefresh, isEmpty);
      expect(await CatalogSession(api, store: store).restore(), isFalse);
    },
  );

  test('sign-out works offline', () async {
    final session = CatalogSession(api, store: store);
    await session.signIn('ana', 'secret-password');
    server.online = false;
    await session.signOut();
    await pumpEventQueue();
    expect(store.values, isEmpty);
  });

  test('expiring JWT is renewed proactively, a valid one is reused', () async {
    final session = CatalogSession(api, store: store)
      ..account = Account(
        5,
        'ana',
        jwt(DateTime.now().add(const Duration(hours: 1))),
      );
    final same = await session.freshAccount();
    expect(identical(same, session.account), isTrue);
    await session.signIn('ana', 'secret-password');
    session.account = Account(
      5,
      'ana',
      jwt(DateTime.now().add(const Duration(seconds: 20))),
    );
    await session.freshAccount();
    expect(server.refreshCalls, 1);
  });

  group('SecureCredentialStore', () {
    test('round trip and corrupt entries are discarded', () async {
      FlutterSecureStorage.setMockInitialValues({
        'session-v1|http://other/': '{"account_id":"x"}',
      });
      final secure = SecureCredentialStore();
      await secure.write(
        'http://server/',
        const StoredCredentials(5, 'ana', 'refresh-1'),
      );
      final read = await secure.read('http://server/');
      expect(read!.accountId, 5);
      expect(read.refreshToken, 'refresh-1');
      expect(await secure.read('http://other/'), isNull);
      expect(await const FlutterSecureStorage().readAll(), hasLength(1));
      await secure.delete('http://server/');
      expect(await secure.read('http://server/'), isNull);
    });
  });
}
