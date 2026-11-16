import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:syncdance_mobile/core/network/catalog_session.dart';
import 'package:syncdance_mobile/features/auth/login_screen.dart';
import 'package:syncdance_mobile/features/routines/reference/catalog_api.dart';

/// UTF-8 body: http.Response(String) would encode it as latin1.
http.Response reply(Object body, int status) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  late List<Map<String, dynamic>> bodies;

  Future<void> mount(
    WidgetTester tester,
    Future<http.Response> Function(http.Request) answer,
  ) async {
    bodies = [];
    final api = CatalogApi(
      'http://localhost:8000/api',
      client: MockClient((request) {
        expect(request.url.path, '/api/auth/password-reset/');
        bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
        return answer(request);
      }),
    );
    addTearDown(api.close);
    final router = GoRouter(
      initialLocation: '/login',
      routes: [
        GoRoute(
          path: '/login',
          builder: (_, _) => LoginScreen(session: CatalogSession(api)),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.tap(find.text('¿Olvidaste tu contraseña?'));
    await tester.pumpAndSettle();
  }

  Future<void> send(WidgetTester tester, String email) async {
    await tester.enterText(
      find.widgetWithText(TextField, 'Correo de tu cuenta'),
      email,
    );
    // MockClient response streams complete on the real event loop.
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(FilledButton, 'Enviar enlace'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pumpAndSettle();
  }

  testWidgets('asks for the link and shows the server answer', (tester) async {
    const detail =
        'Si existe una cuenta con ese correo, te enviamos un enlace para '
        'cambiar la contraseña.';
    await mount(tester, (_) async => reply({'detail': detail}, 202));

    await send(tester, '  ana@example.com ');

    expect(bodies, [
      {'email': 'ana@example.com'},
    ]);
    expect(find.textContaining(detail), findsOneWidget);
    await tester.tap(find.text('Entendido'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('a malformed address never reaches the server', (tester) async {
    await mount(tester, (_) async => reply({}, 500));

    await send(tester, 'ana-sin-arroba');

    expect(bodies, isEmpty);
    expect(find.text('Escribe un correo válido.'), findsOneWidget);
  });

  testWidgets('too many links for one mailbox is explained', (tester) async {
    await mount(tester, (_) async => reply({'detail': 'throttled'}, 429));

    await send(tester, 'ana@example.com');

    expect(
      find.text(
        'Ya se pidieron varios enlaces para este correo. Espera una hora.',
      ),
      findsOneWidget,
    );
    expect(find.widgetWithText(FilledButton, 'Enviar enlace'), findsOneWidget);
  });
}
