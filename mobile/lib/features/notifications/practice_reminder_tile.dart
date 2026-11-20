import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/notifications/local_notifications.dart';
import '../../core/notifications/reminder_settings.dart';

/// "Recordatorio para practicar": on/off and the hour, for this phone.
class PracticeReminderTile extends StatefulWidget {
  const PracticeReminderTile({this.notifier, this.store, super.key});

  /// Defaults to the phone's notifications.
  final PracticeNotifier? notifier;
  final Future<ReminderSettingsStore> Function()? store;

  @override
  State<PracticeReminderTile> createState() => _PracticeReminderTileState();
}

class _PracticeReminderTileState extends State<PracticeReminderTile> {
  late final PracticeNotifier _notifier =
      widget.notifier ?? LocalNotifications.instance;
  ReminderSettingsStore? _store;
  ReminderSettings _settings = const ReminderSettings();
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      _store = await (widget.store ?? ReminderSettingsStore.open)();
      final settings = await _store!.read();
      if (mounted) setState(() => _settings = settings);
    } catch (_) {
      // Without storage the switch still works for this session.
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _apply(ReminderSettings next) async {
    setState(() => _busy = true);
    try {
      if (next.enabled) {
        if (!await _notifier.requestPermission()) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Activa las notificaciones de SyncDance en los ajustes del '
                  'teléfono para recibir el recordatorio.',
                ),
              ),
            );
          }
          return;
        }
        await _notifier.scheduleDailyReminder(next.time);
      } else {
        await _notifier.cancelDailyReminder();
      }
      await _store?.write(next);
      if (mounted) setState(() => _settings = next);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo guardar el recordatorio.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: _settings.time,
      helpText: 'Hora del recordatorio',
    );
    if (time != null && mounted) {
      await _apply(_settings.copyWith(time: time, enabled: true));
    }
  }

  @override
  Widget build(BuildContext context) {
    final time = _settings.time.format(context);
    return Column(
      children: [
        SwitchListTile(
          secondary: const Icon(Icons.alarm_outlined),
          title: const Text('Recordatorio para practicar'),
          subtitle: Text(
            _settings.enabled
                ? 'Todos los días a las $time'
                : 'Un aviso diario a la hora que elijas',
          ),
          value: _settings.enabled,
          onChanged: _busy
              ? null
              : (enabled) => _apply(_settings.copyWith(enabled: enabled)),
        ),
        if (_settings.enabled)
          ListTile(
            leading: const SizedBox(width: 24),
            title: const Text('Cambiar hora'),
            trailing: Text(time),
            enabled: !_busy,
            onTap: _pickTime,
          ),
      ],
    );
  }
}
