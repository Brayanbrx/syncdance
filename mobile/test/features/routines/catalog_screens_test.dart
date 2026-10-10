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
import 'package:syncdance_mobile/features/routines/reference/motion_reference.dart';
import 'package:syncdance_mobile/features/routines/reference/reference_cache.dart';
import 'package:syncdance_mobile/features/routines/routines_screen.dart';

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

void main() {
  const account = Account(1, 'demo', 'token');

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
      final router = GoRouter(
        initialLocation: '/login',
        routes: [
          GoRoute(
            path: '/login',
            builder: (_, _) => LoginScreen(session: session),
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
      } else {
        expect(find.textContaining('contraseña incorrectos'), findsOneWidget);
        expect(session.account, isNull);
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
      expect(
        find.textContaining('Puedes consultar las versiones guardadas'),
        findsOneWidget,
      );
      await tester.tap(find.text('Rutina demo').first);
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
