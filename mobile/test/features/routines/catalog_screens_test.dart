import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:syncdance_mobile/core/network/catalog_session.dart';
import 'package:syncdance_mobile/features/auth/login_screen.dart';
import 'package:syncdance_mobile/features/routines/reference/catalog_api.dart';
import 'package:syncdance_mobile/features/routines/reference/master_video_cache.dart';
import 'package:syncdance_mobile/features/routines/reference/motion_reference.dart';
import 'package:syncdance_mobile/features/routines/reference/reference_cache.dart';
import 'package:syncdance_mobile/features/routines/routines_screen.dart';

import '../training/master_playback_screen_test.dart' show MemorySessionStore;
import '../training/routine_progress_test.dart' show practice;
import 'reference_test_samples.dart';

// Disk persistence is covered by reference_cache_test. This substitute keeps
// widget tests independent of real I/O and isolates under Flutter's fake clock.
class MemoryCache extends ReferenceCache {
  MemoryCache() : super(Directory('unused'), 'widget-test');
  final entries = <SavedReference>[];
  @override
  Future<List<SavedReference>> readAll() async => List.of(entries);
  @override
  Future<void> save(
    String name,
    ReferenceMetadata metadata,
    List<int> bytes,
  ) async {
    entries.add(SavedReference(name, decodeReference(bytes, metadata)));
  }

  @override
  Future<void> remove(ReferenceMetadata metadata) async {
    entries.removeWhere(
      (s) => s.reference.metadata.version == metadata.version,
    );
  }
}

/// Keeps "downloaded" masters in memory: no plugin or disk in widget tests.
class MemoryVideos extends MasterVideoCache {
  MemoryVideos() : super(Directory('unused'));
  final saved = <int, List<int>>{};
  @override
  Future<File?> read(ReferenceMetadata metadata) async =>
      saved.containsKey(metadata.version) ? File('master.mp4') : null;
  @override
  Future<File> save(ReferenceMetadata metadata, Stream<List<int>> bytes) async {
    saved[metadata.version] = [
      for (final chunk in await bytes.toList()) ...chunk,
    ];
    return File('master.mp4');
  }

  @override
  Future<void> remove(ReferenceMetadata metadata) async =>
      saved.remove(metadata.version);
}

void main() {
  const account = Account(1, 'demo', 'token');

  testWidgets('Bailar prepares reference and video in one tap, offline too', (
    tester,
  ) async {
    final bytes = referenceBytes();
    final metaJson = metadataJson(bytes: bytes);
    var offline = false;
    var videoRequests = 0;
    final api = CatalogApi(
      'http://localhost:8000/api',
      client: MockClient((request) async {
        if (offline) throw http.ClientException('offline');
        final path = request.url.path;
        if (path.endsWith('reference/')) {
          return http.Response(jsonEncode(metaJson), 200);
        }
        if (path.endsWith('download/')) return http.Response.bytes(bytes, 200);
        if (path.endsWith('video/')) {
          videoRequests++;
          return http.Response.bytes([1, 2, 3], 200);
        }
        return http.Response(
          '{"results":[{"id":7,"name":"Hip hop","style":"Hip hop",'
          '"difficulty":"BEGINNER","duration_ms":250,"credit":"Mixkit"}],'
          '"next":null}',
          200,
        );
      }),
    );
    addTearDown(api.close);
    final session = CatalogSession(api)..account = account;
    final cache = MemoryCache();
    final videos = MemoryVideos();
    final sessions = MemorySessionStore();
    await sessions.save(practice(70, routine: 7, perfectMoves: 2));
    final opened = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: RoutinesScreen(
          session: session,
          cache: cache,
          videos: videos,
          sessions: sessions,
          openGame: (saved, video) {
            opened.add('${saved.name} v${saved.reference.metadata.version}');
            return const Scaffold(body: Text('Juego abierto'));
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Like a song list: the best stars of the routine under its details.
    expect(
      find.text(
        'Hip hop · Principiante · 0.3 s · Video: Mixkit\n'
        'Mejor marca: ★★☆☆☆',
      ),
      findsOneWidget,
    );
    // Streams of MockClient responses complete on the real event loop.
    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('Bailar'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(find.text('Juego abierto'), findsOneWidget);
    expect(opened, ['Hip hop v1']);
    expect(cache.entries, hasLength(1));
    expect(videos.saved[1], [1, 2, 3]);

    // A better game saved while playing shows up on returning.
    await sessions.save(practice(80, day: 2, routine: 7, perfectMoves: 4));

    // Back to the catalog and offline: the saved version and video are reused.
    // The tap ran on the real event loop, and so does the code after the game.
    await tester.runAsync(() async {
      Navigator.of(tester.element(find.text('Juego abierto'))).pop();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(find.textContaining('Mejor marca: ★★★★★'), findsOneWidget);
    offline = true;
    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('Bailar'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(opened, ['Hip hop v1', 'Hip hop v1']);
    expect(videoRequests, 1);
  });

  testWidgets('a newer version fully on the phone replaces the older one', (
    tester,
  ) async {
    final bytes = referenceBytes();
    final api = CatalogApi(
      'http://localhost:8000/api',
      client: MockClient((request) async {
        final path = request.url.path;
        if (path.endsWith('reference/')) {
          return http.Response(
            jsonEncode(metadataJson(bytes: bytes, version: 2)),
            200,
          );
        }
        if (path.endsWith('download/')) return http.Response.bytes(bytes, 200);
        if (path.endsWith('video/')) return http.Response.bytes([9, 9], 200);
        return http.Response(
          '{"results":[{"id":7,"name":"Hip hop"}],"next":null}',
          200,
        );
      }),
    );
    addTearDown(api.close);
    final cache = MemoryCache();
    await cache.save('Hip hop', metadata(bytes: bytes), bytes);
    final videos = MemoryVideos()..saved[1] = [1, 2, 3];
    await tester.pumpWidget(
      MaterialApp(
        home: RoutinesScreen(
          session: CatalogSession(api)..account = account,
          cache: cache,
          videos: videos,
          sessions: MemorySessionStore(),
          openGame: (_, _) => const Scaffold(body: Text('Juego abierto')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('Bailar'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(find.text('Juego abierto'), findsOneWidget);
    expect(cache.entries.map((e) => e.reference.metadata.version), [2]);
    expect(videos.saved.keys, [2]);
  });

  testWidgets('the next step of the path is one tap away', (tester) async {
    final bytes = referenceBytes();
    final api = CatalogApi(
      'http://localhost:8000/api',
      client: MockClient((request) async {
        final path = request.url.path;
        if (path.endsWith('reference/')) {
          // /api/routines/<id>/reference/: the metadata of that routine.
          final id = int.parse(request.url.pathSegments.reversed.elementAt(2));
          return http.Response(
            jsonEncode(metadataJson(bytes: bytes)..['routine'] = id),
            200,
          );
        }
        if (path.endsWith('download/')) return http.Response.bytes(bytes, 200);
        if (path.endsWith('video/')) return http.Response.bytes([1], 200);
        return http.Response(
          jsonEncode({
            'results': [
              {
                'id': 9,
                'name': 'Video libre',
                'difficulty': 'BEGINNER',
                'style': 'Libre',
              },
              {
                'id': 8,
                'name': 'Rodilla arriba',
                'difficulty': 'BEGINNER',
                'style': 'Estándar',
                'curriculum_position': 1,
              },
              {
                'id': 7,
                'name': 'Marcha',
                'difficulty': 'BEGINNER',
                'style': 'Estándar',
                'curriculum_position': 0,
                'description': 'Marcha en el sitio.',
              },
              {
                'id': 6,
                'name': 'Grapevine',
                'difficulty': 'INTERMEDIATE',
                'style': 'Estándar',
                'curriculum_position': 2,
              },
            ],
            'next': null,
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    addTearDown(api.close);
    final sessions = MemorySessionStore();
    // Routine 7 («Marcha») already passed with four stars.
    await sessions.save(practice(80, routine: 7, perfectMoves: 3));
    final opened = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: RoutinesScreen(
          session: CatalogSession(api)..account = account,
          cache: MemoryCache(),
          videos: MemoryVideos(),
          sessions: sessions,
          openGame: (saved, _) {
            opened.add(saved.name);
            return const Scaffold(body: Text('Juego abierto'));
          },
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Tu siguiente paso'), findsOneWidget);
    expect(find.text('Bailar «Rodilla arriba»'), findsOneWidget);
    expect(find.text('Principiante: 1/2'), findsOneWidget);
    expect(find.text('Intermedio: 0/1'), findsOneWidget);
    // Level headings, and the path before free practice inside a level.
    expect(find.text('Principiante'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Video libre'), 100);
    expect(
      tester.getTopLeft(find.text('Rodilla arriba').last).dy,
      lessThan(tester.getTopLeft(find.text('Video libre')).dy),
    );
    await tester.scrollUntilVisible(find.text('Intermedio'), 100);
    expect(find.text('Intermedio'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Bailar «Rodilla arriba»'), -100);
    await tester.runAsync(() async {
      await tester.tap(find.text('Bailar «Rodilla arriba»'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(opened, ['Rodilla arriba']);
  });

  testWidgets('reopened offline, saved routines are still one-tap Bailar', (
    tester,
  ) async {
    final bytes = referenceBytes();
    final metadata = ReferenceMetadata.fromJson(metadataJson(bytes: bytes));
    final api = CatalogApi(
      'http://localhost:8000/api',
      client: MockClient((_) async => throw http.ClientException('offline')),
    );
    addTearDown(api.close);
    final cache = MemoryCache();
    await cache.save('Hip hop', metadata, bytes);
    final videos = MemoryVideos()..saved[1] = [1, 2, 3];
    final opened = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: RoutinesScreen(
          session: CatalogSession(api)..account = account,
          cache: cache,
          videos: videos,
          sessions: MemorySessionStore(),
          openGame: (saved, video) {
            opened.add(saved.name);
            return const Scaffold(body: Text('Juego abierto'));
          },
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Rutinas guardadas en este teléfono'), findsOneWidget);
    expect(find.textContaining('Se muestran las rutinas guardadas'), findsOne);
    // Nothing to download without a server.
    expect(find.byTooltip('Descargar referencia'), findsNothing);
    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('Bailar'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(find.text('Juego abierto'), findsOneWidget);
    expect(opened, ['Hip hop']);
  });

  for (final success in [true, false]) {
    testWidgets('login navigates only after identity succeeds: $success', (
      tester,
    ) async {
      final api = CatalogApi(
        'http://localhost:8000/api',
        client: MockClient((request) async {
          if (!success) return http.Response('{}', 401);
          return http.Response(
            request.url.path.endsWith('login/')
                ? '{"access":"token"}'
                : '{"id":1,"username":"demo"}',
            200,
          );
        }),
      );
      addTearDown(api.close);
      final session = CatalogSession(api);
      final synced = <int?>[];
      final router = GoRouter(
        initialLocation: '/login',
        routes: [
          GoRoute(
            path: '/login',
            builder: (_, _) => LoginScreen(
              session: session,
              syncPending: (session) async => synced.add(session.account?.id),
            ),
          ),
          GoRoute(
            path: '/home',
            builder: (_, _) => const Scaffold(body: Text('Inicio de prueba')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.enterText(find.byType(TextField).first, 'demo');
      await tester.enterText(find.byType(TextField).last, 'password');
      // Cancellation of MockClient's response stream completes on the real
      // event loop, even though successful responses finish in microtasks.
      await tester.runAsync(() async {
        await tester.tap(find.text('Ingresar'));
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pumpAndSettle();
      if (success) {
        expect(find.text('Inicio de prueba'), findsOneWidget);
        expect(session.account?.id, 1);
        // Practices saved offline for this account go up after signing in.
        expect(synced, [1]);
      } else {
        expect(find.textContaining('contraseña incorrectos'), findsOneWidget);
        expect(session.account, isNull);
        expect(synced, isEmpty);
        expect(
          tester
              .widget<TextField>(find.byType(TextField).last)
              .controller!
              .text,
          isEmpty,
        );
        await tester.tap(find.text('Continuar sin cuenta'));
        await tester.pumpAndSettle();
        expect(find.text('Inicio de prueba'), findsOneWidget);
      }
    });
  }

  testWidgets(
    'catalog downloads, shows saved details offline and removes a version',
    (tester) async {
      // Read the shared fixture before entering fake asynchronous widget work.
      final bytes = referenceBytes();
      final metaJson = metadataJson(bytes: bytes);
      var offline = false;
      final api = CatalogApi(
        'http://localhost:8000/api',
        client: MockClient((request) async {
          if (offline) throw http.ClientException('offline');
          if (request.url.path.endsWith('reference/')) {
            return http.Response(jsonEncode(metaJson), 200);
          }
          if (request.url.path.endsWith('download/')) {
            return http.Response.bytes(bytes, 200);
          }
          return http.Response(
            '{"results":[{"id":7,"name":"Rutina demo"}],"next":null}',
            200,
          );
        }),
      );
      addTearDown(api.close);
      final session = CatalogSession(api)..account = account;
      final cache = MemoryCache();
      await tester.pumpWidget(
        MaterialApp(
          home: RoutinesScreen(session: session, cache: cache),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Descargar referencia'));
      await tester.pumpAndSettle();
      expect(find.textContaining('guardada y verificada'), findsOneWidget);
      expect(cache.entries, hasLength(1));

      offline = true;
      await tester.tap(find.byTooltip('Actualizar catálogo'));
      await tester.pumpAndSettle();
      // The catalog already loaded stays listed; only the error is shown.
      expect(find.textContaining('No se pudo conectar'), findsOneWidget);
      expect(find.text('Catálogo del servidor'), findsOneWidget);
      await tester.tap(find.textContaining('guardada en este dispositivo'));
      await tester.pumpAndSettle();
      expect(find.textContaining('3 muestras'), findsOneWidget);
      expect(
        find.textContaining('33 % con medidas utilizables'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cerrar'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Eliminar versión guardada'));
      await tester.pumpAndSettle();
      expect(cache.entries, isEmpty);
      expect(find.textContaining('Todavía no hay referencias'), findsOneWidget);
    },
  );

  testWidgets('guest catalog does not request protected data', (tester) async {
    var calls = 0;
    final api = CatalogApi(
      'http://localhost:8000/api',
      client: MockClient((_) async {
        calls++;
        return http.Response('{}', 401);
      }),
    );
    addTearDown(api.close);
    await tester.pumpWidget(
      MaterialApp(home: RoutinesScreen(session: CatalogSession(api))),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Ingresa con tu cuenta para descargar rutinas.'),
      findsOneWidget,
    );
    expect(calls, 0);
  });
}
