import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/catalog_session.dart';
import '../../core/notifications/push_messaging.dart';
import '../routines/reference/motion_reference.dart';
import 'app_notification.dart';

String _when(DateTime? time, DateTime now) {
  if (time == null) return '';
  final elapsed = now.difference(time);
  if (elapsed.inMinutes < 1) return 'Ahora';
  if (elapsed.inMinutes < 60) return 'Hace ${elapsed.inMinutes} min';
  if (elapsed.inHours < 24) return 'Hace ${elapsed.inHours} h';
  if (elapsed.inDays < 7) {
    return elapsed.inDays == 1 ? 'Ayer' : 'Hace ${elapsed.inDays} días';
  }
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(time.day)}/${two(time.month)}/${time.year}';
}

IconData _icon(String kind) => switch (kind) {
  'ASSIGNMENT_NEW' || 'ASSIGNMENT_DUE' => Icons.assignment_outlined,
  'ASSIGNMENT_DONE' => Icons.emoji_events_outlined,
  'SESSION_NOTE' => Icons.chat_bubble_outline,
  'CATALOG_NEW' || 'CATALOG_REVIEW' => Icons.library_music_outlined,
  'APP_RELEASE' => Icons.system_update_outlined,
  'REFERENCE_READY' => Icons.check_circle_outline,
  'REFERENCE_FAILED' || 'APP_ERROR' => Icons.error_outline,
  _ => Icons.notifications_none,
};

/// The account's inbox: everything the server told this person, also when
/// push is off or the phone was offline. Opening it marks all as read.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({this.session, this.now, super.key});
  final CatalogSession? session;
  final DateTime Function()? now;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late final CatalogSession _session = widget.session ?? catalogSession;
  List<AppNotification>? _items;
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    if (_session.account != null) unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final inbox = await _session.authorized(_session.api.notifications);
      if (!mounted) return;
      setState(() => _items = inbox.items);
      if (inbox.unread > 0) {
        await _session.authorized(_session.api.markNotificationsRead);
        PushMessaging.instance.changes.value++;
      }
    } on ReferenceException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'No se pudieron cargar tus notificaciones.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _open(AppNotification item) {
    final route = item.route;
    if (route == null || route == '/notifications') return;
    if (route == '/home') {
      context.go('/home');
    } else {
      context.push(route);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final theme = Theme.of(context);
    final now = (widget.now ?? DateTime.now)();
    Widget body;
    if (_session.account == null) {
      body = const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Ingresa con tu cuenta para recibir avisos de tus cursos.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    } else if (items == null) {
      body = Center(
        child: _loading
            ? const CircularProgressIndicator()
            : Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error ?? '', textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _load,
                      child: const Text('Reintentar'),
                    ),
                  ],
                ),
              ),
      );
    } else if (items.isEmpty) {
      body = ListView(
        children: const [
          SizedBox(height: 120),
          Icon(Icons.notifications_none, size: 56),
          SizedBox(height: 12),
          Text(
            'Todavía no tienes notificaciones.\nAquí verás tus tareas, las '
            'observaciones de tu instructor y las novedades.',
            textAlign: TextAlign.center,
          ),
        ],
      );
    } else {
      body = ListView.separated(
        itemCount: items.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final item = items[index];
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: item.read
                  ? theme.colorScheme.surfaceContainerHighest
                  : theme.colorScheme.primaryContainer,
              child: Icon(_icon(item.kind)),
            ),
            title: Text(
              item.title,
              style: item.read
                  ? null
                  : const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              [
                item.body,
                _when(item.createdAt, now),
              ].where((s) => s.isNotEmpty).join('\n'),
            ),
            isThreeLine: item.body.isNotEmpty,
            trailing: item.route == null || item.route == '/notifications'
                ? null
                : const Icon(Icons.chevron_right),
            onTap: () => _open(item),
          );
        },
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Notificaciones')),
      body: RefreshIndicator(
        onRefresh: _session.account == null ? () async {} : _load,
        child: body,
      ),
    );
  }
}

/// App-bar bell with the unread count. Offline or signed out it shows the
/// plain bell: a missing count is never shown as zero news.
class NotificationBell extends StatefulWidget {
  const NotificationBell({this.session, super.key});
  final CatalogSession? session;

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  late final CatalogSession _session = widget.session ?? catalogSession;
  int? _unread;

  @override
  void initState() {
    super.initState();
    PushMessaging.instance.changes.addListener(_refresh);
    _refresh();
  }

  @override
  void dispose() {
    PushMessaging.instance.changes.removeListener(_refresh);
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_session.account == null) return;
    try {
      final inbox = await _session.authorized(_session.api.notifications);
      if (mounted) setState(() => _unread = inbox.unread);
    } catch (_) {
      if (mounted) setState(() => _unread = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final unread = _unread ?? 0;
    return IconButton(
      tooltip: unread > 0
          ? 'Notificaciones: $unread sin leer'
          : 'Notificaciones',
      onPressed: () async {
        await context.push('/notifications');
        unawaited(_refresh());
      },
      icon: Badge(
        isLabelVisible: unread > 0,
        label: Text(unread > 99 ? '99+' : '$unread'),
        child: const Icon(Icons.notifications_outlined),
      ),
    );
  }
}
