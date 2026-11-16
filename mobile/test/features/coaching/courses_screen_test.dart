import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:syncdance_mobile/core/network/catalog_session.dart';
import 'package:syncdance_mobile/features/coaching/course.dart';
import 'package:syncdance_mobile/features/coaching/courses_screen.dart';
import 'package:syncdance_mobile/features/routines/reference/catalog_api.dart';

Map<String, Object?> courseJson({
  int id = 3,
  String name = 'Danza 1A',
  int? bestStars,
  bool completed = false,
  bool overdue = false,
  String? dueDate = '2026-11-30',
}) => {
  'id': id,
  'name': name,
  'instructor': 'Profe Rosa',
  'joined_at': '2026-11-01T10:00:00Z',
  'assignments': [
    {
      'id': 9,
      'routine': 7,
      'routine_name': 'Paso básico',
      'routine_available': true,
      'target_stars': 3,
      'due_date': dueDate,
      'instructions': 'Con espejo',
      'best_stars': bestStars,
      'practices': bestStars == null ? 0 : 2,
      'last_practice_at': bestStars == null ? null : '2026-11-10T18:00:00Z',
      'completed': completed,
      'overdue': overdue,
    },
  ],
};

/// UTF-8 like Django: `http.Response(String)` would encode Latin-1.
http.Response reply(Object? body, [int status = 200]) => http.Response.bytes(
  utf8.encode(body is String ? body : jsonEncode(body)),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Object page(List<Object?> results) => {'results': results, 'next': null};

/// MockClient answers with a body complete on the real event loop.
Future<void> tapAndWait(WidgetTester tester, Finder finder) async {
  await tester.runAsync(() async {
    await tester.tap(finder);
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });
  await tester.pumpAndSettle();
}

void main() {
  const account = Account(1, 'ana', 'token');
  courseRoutinesTests();

  test('assignments parse leniently: no evidence stays null', () {
    final course = Course.fromJson(
      courseJson(dueDate: null).cast<String, dynamic>(),
    );
    final task = course.assignments.single;
    expect(task.bestStars, isNull);
    expect(task.dueDate, isNull);
    expect(task.targetStars, 3);
    expect(course.pending, 1);
    final dated = Course.fromJson(
      courseJson(bestStars: 4, completed: true).cast<String, dynamic>(),
    ).assignments.single;
    // A calendar day, never shifted by the time zone.
    expect(dated.dueDate, DateTime(2026, 11, 30));
    expect(dated.bestStars, 4);
    expect(dated.completed, isTrue);
  });

  testWidgets('join with a code, see the goal and dance an assignment', (
    tester,
  ) async {
    var joined = false;
    final requests = <String>[];
    final api = CatalogApi(
      'http://localhost:8000/api',
      client: MockClient((request) async {
        final path = request.url.path;
        requests.add('${request.method} $path');
        if (path.endsWith('courses/join/')) {
          final code = (jsonDecode(request.body) as Map)['code'];
          if (code != 'ABCD2345') {
            return reply({'detail': 'no'}, 404);
          }
          joined = true;
          return reply(courseJson(), 201);
        }
        if (path.endsWith('coaching/courses/')) {
          return reply(page([if (joined) courseJson(bestStars: 2)]));
        }
        if (path.endsWith('coaching/notes/')) {
          return reply(
            page([
              if (joined)
                {
                  'id': 1,
                  'session': '00000000-0000-0000-0000-000000000001',
                  'routine_name': 'Paso básico',
                  'session_started_at': '2026-11-10T18:00:00Z',
                  'author': 'Profe Rosa',
                  'text': 'Sube más los brazos',
                  'created_at': '2026-11-11T09:00:00Z',
                },
            ]),
          );
        }
        return reply('', 404);
      }),
    );
    addTearDown(api.close);
    final session = CatalogSession(api)..account = account;
    var synced = 0;
    final router = GoRouter(
      initialLocation: '/courses',
      routes: [
        GoRoute(
          path: '/courses',
          builder: (_, _) => CoursesScreen(
            session: session,
            syncPractices: () async => synced++,
          ),
        ),
        GoRoute(
          path: '/routines',
          builder: (_, state) => Scaffold(
            body: Text('Bailar ${state.uri.queryParameters['start']}'),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    // Offline practices go up before the progress is read.
    expect(synced, 1);
    expect(find.textContaining('Todavía no estás en ningún curso'), findsOne);
    expect(find.text('Sin observaciones todavía.'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'nope');
    await tapAndWait(tester, find.text('Unirme'));
    expect(
      find.text('Código no válido o el curso ya no acepta alumnos.'),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextField), 'ABCD2345');
    await tapAndWait(tester, find.text('Unirme'));
    expect(find.text('Te uniste a «Danza 1A».'), findsOneWidget);
    expect(find.text('Danza 1A'), findsOneWidget);
    expect(
      find.text('Instructor: Profe Rosa · 1 de 1 tareas por cumplir'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Objetivo: ★★★☆☆ · Tu mejor: ★★☆☆☆\nHasta el 30/11/2026\nCon espejo',
      ),
      findsOneWidget,
    );
    expect(find.text('Sube más los brazos'), findsOneWidget);
    expect(
      find.text('Profe Rosa · Paso básico · práctica del 10/11/2026'),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Bailar «Paso básico»'));
    await tester.pumpAndSettle();
    expect(find.text('Bailar 7'), findsOneWidget);
    expect(requests, contains('POST /api/coaching/courses/join/'));
  });

  testWidgets('leaving a course asks first', (tester) async {
    var enrolled = true;
    final api = CatalogApi(
      'http://localhost:8000/api',
      client: MockClient((request) async {
        final path = request.url.path;
        if (path.endsWith('/leave/')) {
          enrolled = false;
          return reply('', 204);
        }
        if (path.endsWith('coaching/courses/')) {
          return reply(
            page([
              if (enrolled)
                courseJson(bestStars: 4, completed: true, dueDate: null),
            ]),
          );
        }
        return reply(page([]));
      }),
    );
    addTearDown(api.close);
    final session = CatalogSession(api)..account = account;
    await tester.pumpWidget(
      MaterialApp(
        home: CoursesScreen(session: session, syncPractices: () async {}),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Instructor: Profe Rosa · Todas las tareas cumplidas'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.check_circle), findsOneWidget);

    await tester.tap(find.byTooltip('Salir de «Danza 1A»'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(enrolled, isTrue);

    await tester.tap(find.byTooltip('Salir de «Danza 1A»'));
    await tester.pumpAndSettle();
    await tapAndWait(tester, find.text('Salir'));
    expect(enrolled, isFalse);
    expect(find.text('Saliste de «Danza 1A».'), findsOneWidget);
    expect(find.textContaining('Todavía no estás en ningún curso'), findsOne);
  });

  testWidgets('offline, the screen explains instead of failing', (
    tester,
  ) async {
    final api = CatalogApi(
      'http://localhost:8000/api',
      client: MockClient((_) async => throw http.ClientException('offline')),
    );
    addTearDown(api.close);
    final session = CatalogSession(api)..account = account;
    await tester.pumpWidget(
      MaterialApp(
        home: CoursesScreen(session: session, syncPractices: () async {}),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(
        'No se pudo conectar. Comprueba la conexión y vuelve a intentar.',
      ),
      findsOneWidget,
    );
  });
}

void courseRoutinesTests() {
  testWidgets('the course lists its routines once and dances them', (
    tester,
  ) async {
    final json = courseJson()
      ..['routines'] = [
        {'id': 7, 'name': 'Paso básico', 'style': ''}, // already a task
        {'id': 12, 'name': 'Urbano del curso', 'style': 'Urbano'},
      ];
    final api = CatalogApi(
      'http://localhost:8000/api',
      client: MockClient((request) async {
        final path = request.url.path;
        if (path.endsWith('coaching/courses/')) return reply(page([json]));
        if (path.endsWith('coaching/notes/')) return reply(page([]));
        return reply('', 404);
      }),
    );
    addTearDown(api.close);
    final router = GoRouter(
      initialLocation: '/courses',
      routes: [
        GoRoute(
          path: '/courses',
          builder: (_, _) => CoursesScreen(
            session: CatalogSession(api)
              ..account = const Account(1, 'ana', 'token'),
            syncPractices: () async {},
          ),
        ),
        GoRoute(
          path: '/routines',
          builder: (_, state) => Scaffold(
            body: Text('Bailar ${state.uri.queryParameters['start']}'),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Rutinas del curso'), findsOneWidget);
    expect(find.text('Urbano del curso'), findsOneWidget);
    expect(find.text('Paso básico'), findsOneWidget); // only as the task
    await tester.tap(find.byTooltip('Bailar «Urbano del curso»'));
    await tester.pumpAndSettle();
    expect(find.text('Bailar 12'), findsOneWidget);
  });
}
