import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

/// The daily practice reminder the learner chose. Kept on this phone only:
/// it is about this phone's notifications, not the account.
class ReminderSettings {
  const ReminderSettings({this.enabled = false, this.time = defaultTime});

  static const defaultTime = TimeOfDay(hour: 18, minute: 0);

  final bool enabled;
  final TimeOfDay time;

  ReminderSettings copyWith({bool? enabled, TimeOfDay? time}) =>
      ReminderSettings(
        enabled: enabled ?? this.enabled,
        time: time ?? this.time,
      );

  Map<String, Object> toJson() => {
    'version': 1,
    'enabled': enabled,
    'hour': time.hour,
    'minute': time.minute,
  };

  /// Anything unreadable means the default: reminders off.
  factory ReminderSettings.fromJson(Object? json) {
    if (json is! Map) return const ReminderSettings();
    final hour = json['hour'], minute = json['minute'];
    final valid =
        hour is int &&
        minute is int &&
        hour >= 0 &&
        hour < 24 &&
        minute >= 0 &&
        minute < 60;
    return ReminderSettings(
      enabled: json['enabled'] == true,
      time: valid ? TimeOfDay(hour: hour, minute: minute) : defaultTime,
    );
  }
}

/// Reads and writes [ReminderSettings] as a small JSON file.
class ReminderSettingsStore {
  ReminderSettingsStore(this.file);
  final File file;

  static Future<ReminderSettingsStore> open() async => ReminderSettingsStore(
    File(
      '${(await getApplicationSupportDirectory()).path}/practice_reminder.json',
    ),
  );

  Future<ReminderSettings> read() async {
    try {
      if (!await file.exists()) return const ReminderSettings();
      return ReminderSettings.fromJson(jsonDecode(await file.readAsString()));
    } catch (_) {
      return const ReminderSettings();
    }
  }

  Future<void> write(ReminderSettings settings) async {
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(settings.toJson()), flush: true);
    await temp.rename(file.path);
  }
}
