import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:syncdance_mobile/core/network/catalog_session.dart';
import 'package:syncdance_mobile/core/notifications/local_notifications.dart';
import 'package:syncdance_mobile/core/notifications/reminder_settings.dart';
import 'package:syncdance_mobile/features/notifications/app_notification.dart';
import 'package:syncdance_mobile/features/notifications/notifications_screen.dart';
import 'package:syncdance_mobile/features/notifications/practice_reminder_tile.dart';
import 'package:syncdance_mobile/features/routines/reference/catalog_api.dart';

/// Records what the app asked of the phone's notifications.
class FakeNotifier implements PracticeNotifier {
  bool allow = true;
  TimeOfDay? daily;
  final pending = <int>[];

  @override
  Future<bool> requestPermission() async => allow;

  @override
  Future<void> scheduleDailyReminder(TimeOfDay time) async => daily = time;

  @override
  Future<void> cancelDailyReminder() async => daily = null;

  @override
  Future<void> pendingPracticesChanged(int count) async => pending.add(count);
}

Map<String, dynamic> item(int id, {bool read = false, String? route}) => {
  'id': id,
  'kind': 'ASSIGNMENT_NEW',
  'title': 'Nueva tarea en Danza 1A',
  'body': 'Paso básico: meta ★★★',
  'route': route,
  'created_at': '2026-11-19T10:00:00Z',
  'read': read,
};

void main() {
  group('inbox format', () {
    test('only known screens are opened', () {
      expect(safeRoute('/courses'), '/courses');
      expect(safeRoute('/admin'), isNull);
      expect(safeRoute('https://example.com'), isNull);
      expect(safeRoute(3), isNull);
    });

    test('a server inbox is read defensively', () {
      final inbox = NotificationInbox.fromJson({
        'results': [
          item(1, route: '/courses'),
          item(2, read: true, route: '/elsewhere'),
        ],
        'unread': 1,
      });
      expect(inbox.unread, 1);
      expect(inbox.items.map((n) => n.route), ['/courses', null]);
      expect(inbox.items.last.read, isTrue);
      expect(NotificationInbox.fromJson({'unread': -3}).unread, 0);
    });
  });

  group('reminder settings', () {
    test('saved settings come back and broken files mean off', () async {
      final dir = await Directory.systemTemp.createTemp('reminder');
      addTearDown(() => dir.delete(recursive: true));
      final store = ReminderSettingsStore(File('${dir.path}/r.json'));
      expect((await store.read()).enabled, isFalse);
      await store.write(
        const ReminderSettings(
          enabled: true,
          time: TimeOfDay(hour: 7, minute: 30),
        ),
      );
      final read = await store.read();
      expect(
        (read.enabled, read.time),
        (true, const TimeOfDay(hour: 7, minute: 30)),
      );
      await store.file.writeAsString('{"enabled": true, "hour": 99}');
      expect((await store.read()).time, ReminderSettings.defaultTime);
      await store.file.writeAsString('not json');
      expect((await store.read()).enabled, isFalse);
    });
  });

  group('practice reminder switch', () {
    late Directory dir;
    setUp(() async => dir = await Directory.systemTemp.createTemp('tile'));
    tearDown(() => dir.delete(recursive: true));

    Future<FakeNotifier> pump(WidgetTester tester, {bool allow = true}) async {
      final notifier = FakeNotifier()..allow = allow;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PracticeReminderTile(
              notifier: notifier,
              store: () async =>
                  ReminderSettingsStore(File('${dir.path}/r.json')),
            ),
          ),
        ),
      );
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      return notifier;
    }

    testWidgets('turning it on schedules every day at 18:00, off cancels', (
      tester,
    ) async {
      final notifier = await pump(tester);
      await tester.runAsync(() async {
        await tester.tap(find.byType(Switch));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(notifier.daily, ReminderSettings.defaultTime);
      expect(find.textContaining('Todos los días a las'), findsOneWidget);
      expect(find.text('Cambiar hora'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.byType(Switch));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(notifier.daily, isNull);
      expect(find.text('Cambiar hora'), findsNothing);
    });

    testWidgets('a refused permission leaves it off and explains', (
      tester,
    ) async {
      final notifier = await pump(tester, allow: false);
      await tester.runAsync(() async {
        await tester.tap(find.byType(Switch));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(notifier.daily, isNull);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
      expect(find.textContaining('ajustes del teléfono'), findsOneWidget);
    });
  });

  test(
    'the push hooks run after sign-in and before the session clears',
    () async {
      final events = <String>[];
      final api = CatalogApi(
        'http://localhost/api',
        client: MockClient((request) async {
          final path = request.url.path;
          if (path.endsWith('auth/login/')) {
            return http.Response('{"access":"a","refresh":"r"}', 200);
          }
          if (path.endsWith('auth/me/')) {
            return http.Response('{"id":5,"username":"ana"}', 200);
          }
          return http.Response('{}', 200);
        }),
      );
      addTearDown(api.close);
      final session = CatalogSession(api)
        ..onSignedIn = ((s) async => events.add('in ${s.account?.username}'))
        ..onSigningOut = ((s) async {
          events.add('out ${s.account?.username}');
          throw StateError('offline'); // never blocks signing out
        });
      await session.signIn('ana', 'secreta');
      await Future<void>.delayed(Duration.zero);
      await session.signOut();
      expect(events, ['in ana', 'out ana']);
      expect(session.account, isNull);
    },
  );

  group('inbox screen', () {
    CatalogSession session(MockClient client) {
      final api = CatalogApi('http://localhost/api', client: client);
      addTearDown(api.close);
      return CatalogSession(api)..account = const Account(1, 'ana', 'token');
    }

    testWidgets('lists the notifications, marks them read and opens one', (
      tester,
    ) async {
      var reads = 0;
      final current = session(
        MockClient((request) async {
          if (request.url.path.endsWith('notifications/read/')) {
            reads++;
            return http.Response('{"updated":1}', 200);
          }
          return http.Response(
            jsonEncode({
              'results': [item(1, route: '/courses'), item(2, read: true)],
              'unread': 1,
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      final router = GoRouter(
        initialLocation: '/notifications',
        routes: [
          GoRoute(
            path: '/notifications',
            builder: (_, _) => NotificationsScreen(
              session: current,
              now: () => DateTime.utc(2026, 11, 19, 12),
            ),
          ),
          GoRoute(
            path: '/courses',
            builder: (_, _) => const Scaffold(body: Text('Mis cursos')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.runAsync(() async {
        await tester.pumpWidget(MaterialApp.router(routerConfig: router));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(find.text('Nueva tarea en Danza 1A'), findsNWidgets(2));
      expect(find.textContaining('Hace 2 h'), findsNWidgets(2));
      expect(reads, 1);
      await tester.tap(find.text('Nueva tarea en Danza 1A').first);
      await tester.pumpAndSettle();
      expect(find.text('Mis cursos'), findsOneWidget);
    });

    testWidgets('offline it offers a retry', (tester) async {
      final current = session(
        MockClient((_) async => throw http.ClientException('offline')),
      );
      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(home: NotificationsScreen(session: current)),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(find.text('Reintentar'), findsOneWidget);
    });
  });
}
