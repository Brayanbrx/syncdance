import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:go_router/go_router.dart';

import 'core/network/catalog_session.dart';
import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env.example');
  final restored = await catalogSession.restore();
  runApp(
    SyncDanceApp(
      router: createAppRouter(initialLocation: restored ? '/home' : '/login'),
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
      title: 'SyncDance AI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routerConfig: _router,
    );
  }
}
