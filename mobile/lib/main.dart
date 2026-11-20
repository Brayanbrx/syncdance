import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:go_router/go_router.dart';

import 'core/config/api_config.dart';
import 'core/errors/error_reporter.dart';
import 'core/network/catalog_session.dart';
import 'core/notifications/local_notifications.dart';
import 'core/notifications/push_messaging.dart';
import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/training/history/session_sync.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env.example');
  final problem = ApiConfig.releaseProblem();
  if (problem != null) {
    runApp(MisconfiguredApp(problem));
    return;
  }
  // Outside Google Play nobody else tells us the app failed on a phone.
  if (kReleaseMode) ErrorReporter().install();
  final restored = await catalogSession.restore();
  // Reminders and the "practices not sent" notice work without Firebase.
  await LocalNotifications.instance.init();
  SessionSync.onReport = (report) => unawaited(
    LocalNotifications.instance.pendingPracticesChanged(report.pending),
  );
  await PushMessaging.instance.init(catalogSession);
  // Results saved offline go up on the next launch, before any practice.
  if (restored) {
    unawaited(
      SessionSync.forSession(
        catalogSession,
      ).then((_) {}, onError: (Object _) {}),
    );
  }
  final router = createAppRouter(
    initialLocation: restored ? '/home' : '/login',
  );
  // A tapped notification opens its screen; signed out, the login stays.
  void open(String route) {
    if (catalogSession.account == null) return;
    if (route == '/home') {
      router.go(route);
    } else {
      unawaited(router.push(route));
    }
  }

  LocalNotifications.instance.onOpen = open;
  PushMessaging.instance.onOpen = open;
  final launch =
      LocalNotifications.instance.takeLaunchRoute() ??
      await PushMessaging.instance.takeLaunchRoute();
  runApp(SyncDanceApp(router: router));
  if (launch != null) {
    WidgetsBinding.instance.addPostFrameCallback((_) => open(launch));
  }
}

/// A release APK built without an HTTPS server: say so instead of failing
/// every request (see mobile/android/README.md).
class MisconfiguredApp extends StatelessWidget {
  const MisconfiguredApp(this.message, {super.key});
  final String message;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'SyncDance',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    darkTheme: AppTheme.dark,
    home: Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(message, textAlign: TextAlign.center),
        ),
      ),
    ),
  );
}

class SyncDanceApp extends StatefulWidget {
  const SyncDanceApp({this.router, super.key});
  final GoRouter? router;

  @override
  State<SyncDanceApp> createState() => _SyncDanceAppState();
}

class _SyncDanceAppState extends State<SyncDanceApp> {
  late final GoRouter _router = widget.router ?? createAppRouter();

  @override
  void dispose() {
    if (widget.router == null) _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'SyncDance',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      routerConfig: _router,
    );
  }
}
