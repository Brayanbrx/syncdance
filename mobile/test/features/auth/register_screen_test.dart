import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:syncdance_mobile/core/network/catalog_session.dart';
import 'package:syncdance_mobile/features/auth/register_screen.dart';
import 'package:syncdance_mobile/features/routines/reference/catalog_api.dart';

void main() {
  late List<String> calls;
  late List<Map<String, dynamic>> bodies;

  Future<CatalogSession> mount(
    WidgetTester tester,
    Future<http.Response> Function(http.Request) answer,
  ) async {
    calls = [];
    bodies = [];
    final api = CatalogApi(
      'http://localhost:8000/api',
      client: MockClient((request) {
        calls.add(request.url.path);
        if (request.body.isNotEmpty) bodies.add(jsonDecode(request.body));
        return answer(request);
      }),
    );
    addTearDown(api.close);
    final session = CatalogSession(api);
    final router = GoRouter(
      initialLocation: '/register',
      routes: [
        GoRoute(
          path: '/register',
          builder: (_, _) => RegisterScreen(session: session),
        ),
        GoRoute(
          path: '/home',
          builder: (_, _) => const Scaffold(body: Text('Inicio de prueba')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    return session;
  }

  Future<void> fill(
    WidgetTester tester, {
    String password = 'baile-2026',
    String? repeat,
  }) async {
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'nueva');
    await tester.enterText(fields.at(1), 'nueva@example.com');
    await tester.enterText(fields.at(2), password);
    await tester.enterText(fields.at(3), repeat ?? password);
  }

  Future<void> submit(WidgetTester tester) async {
    // MockClient response streams complete on the real event loop.
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(FilledButton, 'Crear cuenta'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pumpAndSettle();
  }

  testWidgets('local checks need no network', (tester) async {
    await mount(tester, (_) async => http.Response('{}', 500));
    await fill(tester, repeat: 'otra-clave');
    await submit(tester);
    expect(find.text('Las contraseñas no coinciden.'), findsOneWidget);
    await fill(tester, password: 'corta');
    await submit(tester);
    expect(find.text('Usa al menos 8 caracteres.'), findsOneWidget);
    expect(calls, isEmpty);
  });

  testWidgets('server messages appear under each field', (tester) async {
    await mount(
      tester,
      (_) async => http.Response(
        jsonEncode({
          'username': ['Ya existe un usuario con este nombre.'],
          'password': ['Esta contraseña es demasiado común.'],
        }),
        400,
        headers: {'content-type': 'application/json; charset=utf-8'},
      ),
    );
    await fill(tester);
    await submit(tester);
    expect(find.text('Ya existe un usuario con este nombre.'), findsOneWidget);
    expect(find.text('Esta contraseña es demasiado común.'), findsOneWidget);
    expect(find.text('Inicio de prueba'), findsNothing);
  });

  testWidgets('a new account signs in and goes home', (tester) async {
    final session = await mount(tester, (request) async {
      final path = request.url.path;
      if (path.endsWith('register/')) {
        return http.Response('{"id":5,"username":"nueva"}', 201);
      }
      if (path.endsWith('login/')) {
        return http.Response('{"access":"token","refresh":"r"}', 200);
      }
      return http.Response('{"id":5,"username":"nueva"}', 200);
    });
    await fill(tester);
    await submit(tester);
    expect(find.text('Inicio de prueba'), findsOneWidget);
    expect(session.account?.id, 5);
    expect(calls.first, endsWith('auth/register/'));
    expect(bodies.first, {
      'username': 'nueva',
      'email': 'nueva@example.com',
      'password': 'baile-2026',
    });
  });
}
