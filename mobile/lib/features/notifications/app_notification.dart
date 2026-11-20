import '../routines/reference/motion_reference.dart' show object, positiveInt;

/// Screens a notification may open. Anything else in a message (an older or
/// a tampered server) is ignored instead of navigating somewhere unknown.
const notificationRoutes = {
  '/home',
  '/routines',
  '/singing',
  '/courses',
  '/training/history',
  '/notifications',
};

String? safeRoute(Object? value) =>
    value is String && notificationRoutes.contains(value) ? value : null;

/// One entry of the inbox (`GET notifications/`).
class AppNotification {
  const AppNotification({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.read,
    this.route,
    this.createdAt,
  });

  final int id;
  final String kind, title, body;
  final String? route;
  final bool read;
  final DateTime? createdAt;

  factory AppNotification.fromJson(Map<String, dynamic> json) =>
      AppNotification(
        id: positiveInt(json['id']),
        kind: json['kind'] is String ? json['kind'] as String : '',
        title: json['title'] is String ? json['title'] as String : '',
        body: json['body'] is String ? json['body'] as String : '',
        route: safeRoute(json['route']),
        read: json['read'] == true,
        createdAt: json['created_at'] is String
            ? DateTime.tryParse(json['created_at'] as String)?.toLocal()
            : null,
      );

  AppNotification markedRead() => AppNotification(
    id: id,
    kind: kind,
    title: title,
    body: body,
    route: route,
    read: true,
    createdAt: createdAt,
  );
}

/// The first page of the inbox and how many are still unread.
class NotificationInbox {
  const NotificationInbox(this.items, this.unread);
  final List<AppNotification> items;
  final int unread;

  factory NotificationInbox.fromJson(Map<String, dynamic> json) {
    final results = json['results'];
    final unread = json['unread'];
    return NotificationInbox([
      if (results is List)
        for (final raw in results) AppNotification.fromJson(object(raw)),
    ], unread is int && unread >= 0 ? unread : 0);
  }
}
