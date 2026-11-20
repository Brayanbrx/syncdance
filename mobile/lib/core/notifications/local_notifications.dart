import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../../features/notifications/app_notification.dart';

/// What the rest of the app asks of the phone's notifications. Screens and
/// the sync queue depend on this, so tests use a fake.
abstract interface class PracticeNotifier {
  /// Asks for permission (Android 13+); false when the person refuses.
  Future<bool> requestPermission();

  /// Every day at [time]; replaces the previous reminder.
  Future<void> scheduleDailyReminder(TimeOfDay time);

  Future<void> cancelDailyReminder();

  /// Practices the sync queue could not upload: a reminder later on, or
  /// none when [count] is zero.
  Future<void> pendingPracticesChanged(int count);
}

/// The phone's notifications through flutter_local_notifications: the
/// practice reminders, and the push messages that arrive while the app is
/// open (Android does not show those by itself).
class LocalNotifications implements PracticeNotifier {
  LocalNotifications._();
  static final instance = LocalNotifications._();

  static const generalChannel = AndroidNotificationChannel(
    'syncdance_general',
    'Avisos de SyncDance',
    description: 'Tareas, observaciones de tu instructor y novedades.',
    importance: Importance.high,
  );
  static const reminderChannel = AndroidNotificationChannel(
    'syncdance_reminders',
    'Recordatorios de práctica',
    description: 'El recordatorio diario y las prácticas sin enviar.',
  );

  static const _dailyId = 1;
  static const _pendingId = 2;

  /// How long after a failed upload the pending-practices notice appears.
  static const pendingDelay = Duration(hours: 3);

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  /// Opens a notification's screen; set by main once the router exists.
  void Function(String route)? onOpen;
  String? _launchRoute;

  bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  Future<void> init() async {
    if (_ready || !_supported) return;
    try {
      tz_data.initializeTimeZones();
      try {
        final local = await FlutterTimezone.getLocalTimezone();
        tz.setLocalLocation(tz.getLocation(local.identifier));
      } catch (_) {
        // Unknown zone: reminders follow UTC instead of failing.
      }
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
        onDidReceiveNotificationResponse: (response) => _open(response.payload),
      );
      await _android?.createNotificationChannel(generalChannel);
      await _android?.createNotificationChannel(reminderChannel);
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp == true) {
        _launchRoute = safeRoute(launch!.notificationResponse?.payload);
      }
      _ready = true;
    } catch (error) {
      debugPrint('Local notifications unavailable: $error');
    }
  }

  /// The screen of the notification that opened the app, once.
  String? takeLaunchRoute() {
    final route = _launchRoute;
    _launchRoute = null;
    return route;
  }

  void _open(String? payload) {
    final route = safeRoute(payload);
    if (route != null) onOpen?.call(route);
  }

  @override
  Future<bool> requestPermission() async {
    if (!_ready) return false;
    try {
      return await _android?.requestNotificationsPermission() ?? true;
    } catch (_) {
      return false;
    }
  }

  /// A push message received while the app is in front.
  Future<void> showMessage({
    required int id,
    required String title,
    required String body,
    String? route,
  }) async {
    if (!_ready) return;
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      payload: route,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          generalChannel.id,
          generalChannel.name,
          channelDescription: generalChannel.description,
          importance: Importance.high,
          priority: Priority.high,
          styleInformation: BigTextStyleInformation(body),
        ),
      ),
    );
  }

  NotificationDetails get _reminderDetails => NotificationDetails(
    android: AndroidNotificationDetails(
      reminderChannel.id,
      reminderChannel.name,
      channelDescription: reminderChannel.description,
    ),
  );

  @override
  Future<void> scheduleDailyReminder(TimeOfDay time) async {
    if (!_ready) return;
    final now = tz.TZDateTime.now(tz.local);
    var first = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      time.hour,
      time.minute,
    );
    if (!first.isAfter(now)) first = first.add(const Duration(days: 1));
    await _plugin.cancel(id: _dailyId);
    await _plugin.zonedSchedule(
      id: _dailyId,
      title: '¿Bailamos hoy?',
      body: 'Unos minutos de práctica mantienen tu ritmo. Elige una rutina.',
      payload: '/routines',
      scheduledDate: first,
      notificationDetails: _reminderDetails,
      // Inexact: no special alarm permission, and a few minutes late is fine.
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  @override
  Future<void> cancelDailyReminder() async {
    if (_ready) await _plugin.cancel(id: _dailyId);
  }

  @override
  Future<void> pendingPracticesChanged(int count) async {
    if (!_ready) return;
    await _plugin.cancel(id: _pendingId);
    if (count <= 0) return;
    await _plugin.zonedSchedule(
      id: _pendingId,
      title: count == 1
          ? 'Tienes 1 práctica sin enviar'
          : 'Tienes $count prácticas sin enviar',
      body:
          'Abre SyncDance con conexión a internet para que lleguen a tu '
          'historial y a tu instructor.',
      payload: '/training/history',
      scheduledDate: tz.TZDateTime.now(tz.local).add(pendingDelay),
      notificationDetails: _reminderDetails,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }
}
