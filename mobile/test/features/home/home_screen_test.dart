import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:syncdance_mobile/features/home/home_screen.dart';

void main() {
  testWidgets('Bailar and Cantar are the two main paths, above the tools', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
        GoRoute(
          path: '/routines',
          builder: (_, _) => const Scaffold(body: Text('Catálogo')),
        ),
        GoRoute(
          path: '/singing',
          builder: (_, _) => const Scaffold(body: Text('Ejercicios de canto')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    final tools = tester.getTopLeft(find.text('Herramientas')).dy;
    final dance = tester.getTopLeft(find.text('Bailar')).dy;
    final sing = tester.getTopLeft(find.text('Cantar')).dy;
    expect(dance, lessThan(sing));
    expect(sing, lessThan(tools));

    await tester.tap(find.text('Bailar'));
    await tester.pumpAndSettle();
    expect(find.text('Catálogo'), findsOneWidget);
    router.go('/home');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cantar'));
    await tester.pumpAndSettle();
    expect(find.text('Ejercicios de canto'), findsOneWidget);
  });
}
