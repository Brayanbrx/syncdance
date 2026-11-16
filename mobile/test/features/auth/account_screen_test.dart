import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:syncdance_mobile/core/network/catalog_session.dart';
import 'package:syncdance_mobile/features/auth/account_data.dart';
import 'package:syncdance_mobile/features/auth/account_screen.dart';
import 'package:syncdance_mobile/features/routines/reference/catalog_api.dart';

void main() {
  late List<String> calls;
  late List<String> erased;
  late CatalogSession session;

  Future<void> mount(WidgetTester tester, http.Response answer) async {
    calls = [];
    erased = [];
    final api = CatalogApi(
      'http://localhost:8000/api',
      client: MockClient((request) async {
        calls.add('${request.url.path} ${request.body}');
        return answer;
      }),
    );
    addTearDown(api.close);
    session = CatalogSession(api)..account = const Account(7, 'ana', 'token');
    final router = GoRouter(
      initialLocation: '/account',
      routes: [
        GoRoute(
          path: '/account',
          builder: (_, _) => AccountScreen(
            session: session,
            eraseLocal: (scope) async => erased.add(scope),
          ),
        ),
        GoRoute(
          path: '/login',
          builder: (_, _) => const Scaffold(body: Text('Ingreso de prueba')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  }

  Future<void> deleteWith(WidgetTester tester, String password) async {
    await tester.tap(find.text('Borrar mi cuenta'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Tu contraseña'),
      password,
    );
    // MockClient response streams complete on the real event loop.
    await tester.runAsync(() async {
      await tester.tap(find.text('Borrar para siempre'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pumpAndSettle();
  }

  testWidgets('deletes the account here and on the server', (tester) async {
    await mount(tester, http.Response('', 204));
    final scope = session.cacheScope;

    await deleteWith(tester, 'mi-clave-123');

    expect(calls, ['/api/auth/me/delete/ {"password":"mi-clave-123"}']);
    expect(erased, [scope]);
    expect(session.account, isNull);
    expect(find.text('Ingreso de prueba'), findsOneWidget);
    expect(find.text('Tu cuenta se borró.'), findsOneWidget);
  });

  testWidgets('a wrong password keeps everything', (tester) async {
    await mount(
      tester,
      http.Response(
        jsonEncode({
          'password': ['incorrecta'],
        }),
        400,
      ),
    );

    await deleteWith(tester, 'otra');

    expect(find.text('La contraseña no es correcta.'), findsOneWidget);
    expect(erased, isEmpty);
    expect(session.account, isNotNull);
  });

  testWidgets('an instructor with courses learns what to do', (tester) async {
    await mount(tester, http.Response('{"detail": "cursos"}', 409));

    await deleteWith(tester, 'mi-clave-123');

    expect(
      find.textContaining('Pide a un administrador que los transfiera'),
      findsOneWidget,
    );
    expect(erased, isEmpty);
  });

  testWidgets('signing out keeps the practices on the phone', (tester) async {
    await mount(tester, http.Response('', 500));

    await tester.tap(find.text('Cerrar sesión'));
    await tester.pumpAndSettle();

    expect(session.account, isNull);
    expect(erased, isEmpty);
    expect(calls, isEmpty);
    expect(find.text('Ingreso de prueba'), findsOneWidget);
  });

  test('erasing one account leaves the others untouched', () async {
    final root = await Directory.systemTemp.createTemp('account-data-');
    addTearDown(() => root.delete(recursive: true));
    final data = AccountData(root);
    const mine = 'http://server/api|7', theirs = 'http://server/api|8';
    for (final folder in [...data.foldersOf(mine), ...data.foldersOf(theirs)]) {
      await File('${folder.path}/videos/x.video').create(recursive: true);
    }

    await data.erase(mine);
    await data.erase(mine); // already gone: no error

    for (final folder in data.foldersOf(mine)) {
      expect(folder.existsSync(), isFalse);
    }
    for (final folder in data.foldersOf(theirs)) {
      expect(folder.existsSync(), isTrue);
    }
  });
}
