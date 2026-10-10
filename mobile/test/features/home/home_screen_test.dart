import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:syncdance_mobile/features/home/home_screen.dart';

void main() {
  testWidgets('Bailar is the main path and opens the catalog', (tester) async {
    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
        GoRoute(
          path: '/routines',
          builder: (_, _) => const Scaffold(body: Text('Catálogo')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    // First item on the screen, above the tools.
    expect(
      tester.getTopLeft(find.text('Bailar')).dy,
      lessThan(tester.getTopLeft(find.text('Herramientas')).dy),
    );
    await tester.tap(find.text('Bailar'));
    await tester.pumpAndSettle();
    expect(find.text('Catálogo'), findsOneWidget);
  });
}
