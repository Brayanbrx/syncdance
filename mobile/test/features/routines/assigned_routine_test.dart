import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:syncdance_mobile/core/network/catalog_session.dart';
import 'package:syncdance_mobile/features/routines/reference/catalog_api.dart';
import 'package:syncdance_mobile/features/routines/routines_screen.dart';

import '../training/master_playback_screen_test.dart' show MemorySessionStore;
import 'catalog_screens_test.dart' show MemoryCache, MemoryVideos;
import 'reference_test_samples.dart';

void main() {
  const account = Account(1, 'demo', 'token');

  CatalogApi api({required bool hasRoutine}) {
    final bytes = referenceBytes();
    final metaJson = metadataJson(bytes: bytes);
    return CatalogApi(
      'http://localhost:8000/api',
      client: MockClient((request) async {
        final path = request.url.path;
        if (path.endsWith('reference/')) {
          return http.Response(jsonEncode(metaJson), 200);
        }
        if (path.endsWith('download/')) return http.Response.bytes(bytes, 200);
        if (path.endsWith('video/')) return http.Response.bytes([1, 2, 3], 200);
        return http.Response(
          jsonEncode({
            'results': [
              if (hasRoutine)
                {'id': 7, 'name': 'Hip hop', 'difficulty': 'BEGINNER'},
            ],
            'next': null,
          }),
          200,
        );
      }),
    );
  }

  Future<List<String>> open(WidgetTester tester, CatalogApi api) async {
    addTearDown(api.close);
    final opened = <String>[];
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: RoutinesScreen(
            session: CatalogSession(api)..account = account,
            cache: MemoryCache(),
            videos: MemoryVideos(),
            sessions: MemorySessionStore(),
            startRoutineId: 7,
            openGame: (saved, video) {
              opened.add(saved.name);
              return const Scaffold(body: Text('Juego abierto'));
            },
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    return opened;
  }

  testWidgets('an assignment opens its routine straight into the game', (
    tester,
  ) async {
    final opened = await open(tester, api(hasRoutine: true));
    expect(opened, ['Hip hop']);
    expect(find.text('Juego abierto'), findsOneWidget);
  });

  testWidgets('a routine missing from the catalog is explained', (
    tester,
  ) async {
    final opened = await open(tester, api(hasRoutine: false));
    expect(opened, isEmpty);
    expect(
      find.text('La rutina asignada no está disponible en el catálogo.'),
      findsOneWidget,
    );
  });
}
