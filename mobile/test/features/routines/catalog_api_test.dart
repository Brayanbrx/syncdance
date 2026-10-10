import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:syncdance_mobile/features/routines/reference/catalog_api.dart';
import 'package:syncdance_mobile/features/routines/reference/motion_reference.dart';
import 'reference_test_samples.dart';

void main() {
  const account = Account(1, 'demo', 'test-token');
  test(
    'video uses authenticated version endpoint and streams original bytes',
    () async {
      final cancelled = Completer<void>();
      final api = CatalogApi(
        'http://localhost:8000/api',
        client: MockClient((request) async {
          expect(request.url.path, '/api/routines/7/references/2/video/');
          expect(request.headers['Authorization'], 'Bearer test-token');
          expect(request.followRedirects, isFalse);
          return http.Response.bytes([1, 2, 3], 200);
        }),
      );
      addTearDown(api.close);
      addTearDown(() => cancelled.complete());
      final bytes = await api
          .video(account, metadata(version: 2), cancelled: cancelled.future)
          .expand((chunk) => chunk)
          .toList();
      expect(bytes, [1, 2, 3]);
    },
  );

  for (final code in [401, 404, 302]) {
    test('video rejects HTTP $code without saving its body', () async {
      final cancelled = Completer<void>();
      final api = CatalogApi(
        'http://localhost:8000/api',
        client: MockClient((_) async => http.Response('error', code)),
      );
      addTearDown(api.close);
      addTearDown(() => cancelled.complete());
      await expectLater(
        api.video(account, metadata(), cancelled: cancelled.future).toList(),
        throwsA(isA<ReferenceException>()),
      );
    });
  }

  test(
    'video rejects excessive Content-Length before consuming bytes',
    () async {
      final cancelled = Completer<void>();
      final api = CatalogApi(
        'http://localhost:8000/api',
        client: MockClient.streaming((request, body) async {
          await body.drain<void>();
          return http.StreamedResponse(
            const Stream.empty(),
            200,
            contentLength: 200 * 1024 * 1024 + 1,
          );
        }),
      );
      addTearDown(api.close);
      addTearDown(() => cancelled.complete());
      await expectLater(
        api.video(account, metadata(), cancelled: cancelled.future).toList(),
        throwsA(isA<ReferenceException>()),
      );
    },
  );
  test(
    'login obtains identity and sends JWT for catalog, metadata and binary download',
    () async {
      final api = CatalogApi(
        'http://localhost:8000/api',
        client: MockClient((request) async {
          if (request.url.path.endsWith('auth/login/')) {
            expect(jsonDecode(request.body), {
              'username': 'demo',
              'password': 'test-password',
            });
            expect(request.headers['Authorization'], isNull);
            return http.Response('{"access":"test-token"}', 200);
          }
          expect(request.headers['Authorization'], 'Bearer test-token');
          expect(request.followRedirects, isFalse);
          if (request.url.path.endsWith('auth/me/')) {
            return http.Response('{"id":1,"username":"demo"}', 200);
          }
          if (request.url.path.endsWith('reference/')) {
            return http.Response(jsonEncode(metadataJson()), 200);
          }
          if (request.url.path.endsWith('download/')) {
            return http.Response.bytes(referenceBytes(), 200);
          }
          return http.Response(
            '{"results":[{"id":7,"name":"Demo"}],"next":null}',
            200,
          );
        }),
      );
      addTearDown(api.close);
      final user = (await api.login('demo', 'test-password')).account;
      expect(user.id, 1);
      expect((await api.routines(user)).single.id, 7);
      final meta = await api.metadata(user, 7);
      expect(
        decodeReference(await api.download(user, meta), meta).samples.length,
        3,
      );
    },
  );

  test('follows same-origin catalog pagination', () async {
    var calls = 0;
    final api = CatalogApi(
      'http://localhost:8000/api',
      client: MockClient((request) async {
        calls++;
        return http.Response(
          jsonEncode({
            'results': [
              {'id': calls, 'name': 'R$calls'},
            ],
            'next': calls == 1
                ? 'http://localhost:8000/api/routines/?page=2'
                : null,
          }),
          200,
        );
      }),
    );
    addTearDown(api.close);
    expect((await api.routines(account)).map((r) => r.id), [1, 2]);
  });

  test(
    'does not send credentials to external download or pagination URLs',
    () async {
      var calls = 0;
      final api = CatalogApi(
        'http://localhost:8000/api',
        client: MockClient((request) async {
          calls++;
          return http.Response(
            '{"results":[],"next":"https://elsewhere.invalid/api/routines/"}',
            200,
          );
        }),
      );
      addTearDown(api.close);
      for (final url in [
        'https://elsewhere.invalid/api/file',
        'http://localhost:8000/outside/file',
        'http://user@localhost:8000/api/file',
      ]) {
        final meta = ReferenceMetadata.fromJson({
          ...metadataJson(),
          'download_url': url,
        });
        await expectLater(
          api.download(account, meta),
          throwsA(isA<ReferenceException>()),
        );
      }
      expect(calls, 0);
      await expectLater(
        api.routines(account),
        throwsA(isA<ReferenceException>()),
      );
      expect(calls, 1);
    },
  );

  for (final code in [401, 403, 404, 302, 500]) {
    test('status $code is not treated as an artifact', () async {
      final api = CatalogApi(
        'http://localhost:8000/api',
        client: MockClient((_) async => http.Response('error', code)),
      );
      addTearDown(api.close);
      await expectLater(
        api.download(account, metadata()),
        throwsA(isA<ReferenceException>()),
      );
    });
  }

  test('wrong routine metadata is rejected', () async {
    final api = CatalogApi(
      'http://localhost:8000/api',
      client: MockClient(
        (_) async => http.Response(jsonEncode(metadataJson()), 200),
      ),
    );
    addTearDown(api.close);
    await expectLater(api.metadata(account, 8), throwsFormatException);
  });

  for (final declaredLength in [true, false]) {
    test(
      'limits download bytes with Content-Length: $declaredLength',
      () async {
        final api = CatalogApi(
          'http://localhost:8000/api',
          client: MockClient.streaming((request, body) async {
            await body.drain<void>();
            return http.StreamedResponse(
              Stream.fromIterable([
                List.filled(maxReferenceBytes, 0),
                [1],
              ]),
              200,
              contentLength: declaredLength ? maxReferenceBytes + 1 : null,
            );
          }),
        );
        addTearDown(api.close);
        await expectLater(
          api.download(account, metadata()),
          throwsA(isA<ReferenceException>()),
        );
      },
    );
  }

  test('catalog items show style, level, length and credit when known', () {
    final full = RoutineItem.fromJson({
      'id': 3,
      'name': 'Hip hop urbano',
      'style': 'Hip hop',
      'difficulty': 'BEGINNER',
      'duration_ms': 13600,
      'credit': 'Mixkit',
    });
    expect(full.details, 'Hip hop · Principiante · 14 s · Video: Mixkit');
    final bare = RoutineItem.fromJson({'id': 4, 'name': 'Sin datos'});
    expect(bare.details, isEmpty);
    expect(
      RoutineItem.fromJson({'id': 5, 'name': 'X', 'duration_ms': 0}).durationMs,
      0,
    );
  });

  test('catalog sorts beginner first, then by name, unknown levels last', () {
    final items = [
      const RoutineItem(1, 'Zeta', difficulty: 'ADVANCED'),
      const RoutineItem(2, 'Sin nivel'),
      const RoutineItem(3, 'Beta', difficulty: 'BEGINNER'),
      const RoutineItem(4, 'Alfa', difficulty: 'BEGINNER'),
      const RoutineItem(5, 'Media', difficulty: 'INTERMEDIATE'),
    ]..sort(RoutineItem.byLevel);
    expect(items.map((r) => r.name), [
      'Alfa',
      'Beta',
      'Media',
      'Zeta',
      'Sin nivel',
    ]);
  });
}
