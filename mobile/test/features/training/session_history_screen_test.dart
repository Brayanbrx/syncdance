import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:syncdance_mobile/core/network/catalog_session.dart';
import 'package:syncdance_mobile/features/routines/reference/catalog_api.dart';
import 'package:syncdance_mobile/features/training/presentation/session_history_screen.dart';

import 'master_playback_screen_test.dart' show MemorySessionStore;
import 'routine_progress_test.dart' show practice;
import 'session_store_test.dart' show savedPractice;
import 'session_sync_test.dart' show asServer;

void main() {
  testWidgets('history opens persisted detail offline and confirms deletion', (
    tester,
  ) async {
    final api = CatalogApi(
      'http://localhost/api',
      client: MockClient((_) async => throw StateError('No network')),
    );
    addTearDown(api.close);
    final session = CatalogSession(api)
      ..account = const Account(1, 'demo', 'token');
    final store = MemorySessionStore();
    await store.save(savedPractice());
    await tester.pumpWidget(
      MaterialApp(
        home: SessionHistoryScreen(session: session, store: store),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Cobertura: 40.0 %'), findsOneWidget);
    expect(find.textContaining('Pendiente de enviar'), findsOneWidget);
    expect(find.textContaining('1 pendientes de enviar'), findsOneWidget);
    await tester.tap(find.text('Mi rutina'));
    await tester.pumpAndSettle();
    expect(find.text('Resumen de práctica'), findsOneWidget);
    expect(find.text('leftElbow_extend · 1 avisos'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Eliminar práctica'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(store.records.length, 1);
    await tester.tap(find.byTooltip('Eliminar práctica'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Eliminar'));
    await tester.pumpAndSettle();
    expect(store.records, isEmpty);
    expect(find.text('Todavía no hay prácticas guardadas.'), findsOneWidget);
  });

  testWidgets('history uploads pending practices and retries a rejection', (
    tester,
  ) async {
    var status = 400;
    final api = CatalogApi(
      'http://localhost/api',
      client: MockClient((_) async => http.Response('{}', status)),
    );
    addTearDown(api.close);
    final session = CatalogSession(api)
      ..account = const Account(1, 'demo', 'token');
    final store = MemorySessionStore();
    await store.save(savedPractice());
    // Response stream cancellation completes on the real event loop.
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: SessionHistoryScreen(session: session, store: store),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(find.textContaining('No aceptada por el servidor'), findsOneWidget);
    expect(find.textContaining('no fueron aceptadas'), findsOneWidget);
    await tester.tap(find.text('Mi rutina'));
    await tester.pumpAndSettle();
    expect(find.textContaining('no aceptó el resumen'), findsOneWidget);
    status = 201;
    await tester.runAsync(() async {
      await tester.tap(find.text('Volver a intentar el envío'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(find.textContaining('Sincronizada con el servidor'), findsOneWidget);
    expect(find.textContaining('Nada pendiente'), findsOneWidget);
  });

  testWidgets('history shows best mark and change per routine', (tester) async {
    final api = CatalogApi(
      'http://localhost/api',
      client: MockClient((_) async => throw StateError('No network')),
    );
    addTearDown(api.close);
    final session = CatalogSession(api)
      ..account = const Account(1, 'demo', 'token');
    final store = MemorySessionStore();
    await store.save(practice(60, day: 1));
    await store.save(practice(75, day: 2, perfectMoves: 3));
    await store.save(practice(null, day: 3));
    await tester.pumpWidget(
      MaterialApp(
        home: SessionHistoryScreen(session: session, store: store),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Progreso por rutina'), findsOneWidget);
    expect(
      find.textContaining(
        'Mejor marca: 75 · Última: 75 (+15 respecto a la anterior)',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Últimas: 60 · 75'), findsOneWidget);
    expect(
      find.textContaining('Modo juego: mejor ★★★★☆ · 300 de 400 pts'),
      findsOneWidget,
    );
    expect(find.textContaining('1 prácticas no comparables'), findsOneWidget);
    // Newest first: the practice without evidence, then the best mark.
    await tester.tap(find.text('Rutina 7').at(1));
    await tester.pumpAndSettle();
    expect(find.text('Mejor marca personal en esta rutina'), findsOneWidget);
  });

  testWidgets('an empty history can be recovered from the server', (
    tester,
  ) async {
    final remote = savedPractice();
    final api = CatalogApi(
      'http://localhost/api',
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'results': [asServer(remote)],
            'next': null,
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
    );
    addTearDown(api.close);
    final session = CatalogSession(api)
      ..account = const Account(1, 'demo', 'token');
    final store = MemorySessionStore();
    await tester.pumpWidget(
      MaterialApp(
        home: SessionHistoryScreen(session: session, store: store),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Todavía no hay prácticas guardadas.'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.text('Recuperar mis prácticas del servidor'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(
      find.text('Se recuperaron 1 prácticas del servidor.'),
      findsOneWidget,
    );
    expect(find.text('Mi rutina'), findsOneWidget);
    expect(find.textContaining('Sincronizada con el servidor'), findsOneWidget);
    expect(store.records.keys, [remote.id]);
  });

  testWidgets('guest cannot read a supplied history store', (tester) async {
    final api = CatalogApi('http://localhost/api');
    addTearDown(api.close);
    final store = MemorySessionStore();
    await store.save(savedPractice());
    await tester.pumpWidget(
      MaterialApp(
        home: SessionHistoryScreen(session: CatalogSession(api), store: store),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Ingresa con tu cuenta'), findsOneWidget);
    expect(find.text('Mi rutina'), findsNothing);
  });
}
