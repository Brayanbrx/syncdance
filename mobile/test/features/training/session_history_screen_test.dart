import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:syncdance_mobile/core/network/catalog_session.dart';
import 'package:syncdance_mobile/features/routines/reference/catalog_api.dart';
import 'package:syncdance_mobile/features/training/presentation/session_history_screen.dart';

import 'master_playback_screen_test.dart' show MemorySessionStore;
import 'session_store_test.dart' show savedPractice;

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
