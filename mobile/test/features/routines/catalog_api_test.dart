import 'dart:async';
import 'dart:convert';
import 'dart:io' show HandshakeException;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:syncdance_mobile/features/routines/reference/catalog_api.dart';
import 'package:syncdance_mobile/features/routines/reference/master_video_cache.dart';
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

  for (final announced in [true, false]) {
    test('video reports its progress (Content-Length: $announced)', () async {
      final cancelled = Completer<void>();
      final api = CatalogApi(
        'http://localhost:8000/api',
        client: MockClient.streaming((request, body) async {
          await body.drain<void>();
          return http.StreamedResponse(
            Stream.fromIterable([
              [1, 2],
              [3, 4],
            ]),
            200,
            contentLength: announced ? 4 : null,
          );
        }),
      );
      addTearDown(api.close);
      addTearDown(() => cancelled.complete());
      final progress = <(int, int?)>[];
      await api
          .video(
            account,
            metadata(),
            cancelled: cancelled.future,
            onProgress: (received, total) => progress.add((received, total)),
          )
          .toList();
      final total = announced ? 4 : null;
      expect(progress, [(0, total), (2, total), (4, total)]);
    });
  }

  test('download progress reads as a percentage or as megabytes', () {
    expect(downloadProgress(0, 200), (fraction: 0.0, label: '0 %'));
    expect(downloadProgress(99, 200).label, '49 %');
    expect(downloadProgress(200, 200).fraction, 1.0);
    // Unknown size: no fraction, the received amount instead.
    expect(downloadProgress(3 * 1024 * 1024, null), (
      fraction: null,
      label: '3.0 MB',
    ));
    expect(downloadProgress(5, 0).fraction, isNull);
  });

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

  testWidgets('a slow media download is cut only after a minute of silence', (
    tester,
  ) async {
    final body = StreamController<List<int>>();
    final api = CatalogApi(
      'http://localhost:8000/api',
      client: MockClient.streaming((request, _) async {
        // MockClient leaves aborting to the handler, like a real socket.
        unawaited(
          (request as http.Abortable).abortTrigger!.then((_) {
            body.addError(http.RequestAbortedException(request.url));
            unawaited(body.close());
          }),
        );
        return http.StreamedResponse(body.stream, 200);
      }),
    );
    addTearDown(api.close);
    final cancelled = Completer<void>();
    addTearDown(cancelled.complete);
    final received = <int>[];
    Object? failure;
    api
        .video(account, metadata(), cancelled: cancelled.future)
        .listen(received.addAll, onError: (Object e) => failure = e);
    // Seven minutes in all, never a minute without data.
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(seconds: 50));
      body.add([i]);
    }
    await tester.pump();
    expect(failure, isNull);
    expect(received, [0, 1, 2, 3, 4, 5, 6, 7]);
    await tester.pump(CatalogApi.mediaIdleTimeout);
    await tester.pump();
    expect(
      failure,
      isA<ReferenceException>().having(
        (e) => e.message,
        'message',
        contains('interrumpida'),
      ),
    );
  });

  testWidgets('a slow reference download finishes; a silent one stops', (
    tester,
  ) async {
    late StreamController<List<int>> body;
    final api = CatalogApi(
      'http://localhost:8000/api',
      client: MockClient.streaming((request, _) async {
        body = StreamController<List<int>>();
        unawaited(
          (request as http.Abortable).abortTrigger!.then((_) {
            body.addError(http.RequestAbortedException(request.url));
            unawaited(body.close());
          }),
        );
        return http.StreamedResponse(body.stream, 200);
      }),
    );
    addTearDown(api.close);

    Future<Object?> fetch(List<Duration> gaps) async {
      Object? outcome;
      unawaited(
        api
            .download(account, metadata())
            .then<void>(
              (bytes) => outcome = bytes,
              onError: (Object e) => outcome = e,
            ),
      );
      await tester.pump();
      for (final gap in gaps) {
        await tester.pump(gap);
        if (outcome != null) return outcome;
        body.add([1]);
      }
      await body.close();
      await tester.pump();
      return outcome;
    }

    // Two and a half minutes in all, never 30 s without data.
    expect(
      await fetch(List.filled(6, const Duration(seconds: 25))),
      List.filled(6, 1),
    );
    expect(
      await fetch([const Duration(seconds: 5), CatalogApi.requestIdleTimeout]),
      isA<ReferenceException>(),
    );
  });

  test('a failed TLS handshake is "no connection", so saved copies are used '
      'and pending practices wait', () async {
    // http's client only wraps socket errors; a captive portal or a phone
    // with the wrong date fails the handshake instead.
    final api = CatalogApi(
      'https://syncdance.example/api',
      client: MockClient(
        (_) async =>
            throw const HandshakeException('CERTIFICATE_VERIFY_FAILED'),
      ),
    );
    addTearDown(api.close);
    final offline = isA<ReferenceException>().having(
      (e) => e.message,
      'message',
      contains('conex'),
    );
    await expectLater(api.routines(account), throwsA(offline));
    await expectLater(api.uploadSession(account, const {}), throwsA(offline));
    await expectLater(
      api.register('ana', 'ana@example.com', 'x', acceptTerms: true),
      throwsA(offline),
    );
    final cancelled = Completer<void>();
    addTearDown(cancelled.complete);
    await expectLater(
      api.video(account, metadata(), cancelled: cancelled.future).toList(),
      throwsA(offline),
    );
  });
}
