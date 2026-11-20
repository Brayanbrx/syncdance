import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../../features/notifications/app_notification.dart';
import '../network/catalog_session.dart';
import '../update/app_update.dart';
import 'local_notifications.dart';

/// Push messages from the server (Firebase Cloud Messaging).
///
/// The phone's token is registered for the account signed in on it and
/// removed on sign-out. Without Firebase (a build without
/// google-services.json, tests) every method does nothing: the inbox and the
/// local reminders still work.
class PushMessaging {
  PushMessaging._();
  static final instance = PushMessaging._();

  bool _enabled = false;
  String? _token;
  CatalogSession? _session;

  /// Opens a message's screen; set by main once the router exists.
  void Function(String route)? onOpen;

  /// Unread notifications may have changed (a message arrived).
  final changes = ValueNotifier<int>(0);

  Future<void> init(CatalogSession session) async {
    _session = session;
    try {
      await Firebase.initializeApp();
      _enabled = true;
    } catch (error) {
      debugPrint('Push disabled: $error');
      return;
    }
    final messaging = FirebaseMessaging.instance;
    FirebaseMessaging.onMessage.listen(_foreground);
    FirebaseMessaging.onMessageOpenedApp.listen(_opened);
    // Classic registration tokens: the server sends with firebase-admin's
    // token API, not the newer installation-ID targets of register().
    // ignore: deprecated_member_use
    messaging.onTokenRefresh.listen((token) {
      _token = token;
      unawaited(_register());
    });
    session.onSignedIn = (_) => signedIn();
    session.onSigningOut = signingOut;
    if (session.account != null) unawaited(signedIn());
  }

  /// The message that opened the app from the background or closed, once.
  Future<String?> takeLaunchRoute() async {
    if (!_enabled) return null;
    try {
      final message = await FirebaseMessaging.instance.getInitialMessage();
      return safeRoute(message?.data['route']);
    } catch (_) {
      return null;
    }
  }

  /// After sign-in (or a restored session): ask once for permission and
  /// register this phone for the account.
  Future<void> signedIn() async {
    if (!_enabled) return;
    try {
      await FirebaseMessaging.instance.requestPermission();
      // ignore: deprecated_member_use
      _token ??= await FirebaseMessaging.instance.getToken();
      await _register();
    } catch (error) {
      debugPrint('Push token not registered: $error');
    }
  }

  Future<void> _register() async {
    final session = _session, token = _token;
    if (session == null || token == null || session.account == null) return;
    final version = await InstalledVersion.read();
    await session.authorized(
      (account) => session.api.registerPushDevice(
        account,
        token: token,
        platform: defaultTargetPlatform == TargetPlatform.iOS
            ? 'IOS'
            : 'ANDROID',
        appVersion: version?.name ?? '',
      ),
    );
  }

  /// Before the session is cleared: this phone stops receiving the
  /// account's messages. Offline, the server forgets the token later (FCM
  /// reports it when the next account registers it).
  Future<void> signingOut(CatalogSession session) async {
    final token = _token;
    if (!_enabled || token == null) return;
    try {
      await session
          .authorized((account) => session.api.removePushDevice(account, token))
          .timeout(const Duration(seconds: 4));
    } catch (_) {
      // Never blocks signing out.
    }
  }

  void _foreground(RemoteMessage message) {
    final notification = message.notification;
    changes.value++;
    if (notification == null) return;
    unawaited(
      LocalNotifications.instance.showMessage(
        id:
            int.tryParse('${message.data['notification_id']}') ??
            message.hashCode,
        title: notification.title ?? 'SyncDance',
        body: notification.body ?? '',
        route: safeRoute(message.data['route']),
      ),
    );
  }

  void _opened(RemoteMessage message) {
    changes.value++;
    final route = safeRoute(message.data['route']);
    if (route != null) onOpen?.call(route);
  }
}
