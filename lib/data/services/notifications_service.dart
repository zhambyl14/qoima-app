import 'package:supabase_flutter/supabase_flutter.dart';

/// Іштегі хабарлама жазбасы — `notifications` кестесі (0033 миграция).
/// `data` пішіні push payload-мен ДӘЛ бірдей ({type, ...}) — тапталғанда
/// lib/core/push_navigation.dart-тағы handlePushOpen(data) қайта пайдаланылады.
class NotificationModel {
  final String id;
  final String title;
  final String body;
  final Map<String, dynamic> data;
  final DateTime? readAt;
  final DateTime createdAt;

  const NotificationModel({
    required this.id,
    required this.title,
    required this.body,
    required this.data,
    required this.readAt,
    required this.createdAt,
  });

  bool get isUnread => readAt == null;

  factory NotificationModel.fromMap(Map<String, dynamic> m) =>
      NotificationModel(
        id: m['id'] as String? ?? '',
        title: m['title'] as String? ?? '',
        body: m['body'] as String? ?? '',
        data: Map<String, dynamic>.from(m['data'] as Map? ?? {}),
        readAt:
            m['read_at'] != null ? DateTime.tryParse(m['read_at'] as String) : null,
        createdAt: DateTime.tryParse(m['created_at'] as String? ?? '') ??
            DateTime.now(),
      );
}

/// Іштегі хабарламалар тарихы (0033). notify_push() (сервер жағы) әр
/// оқиғаны осында да жазады — бұл сервис тек оқу/белгілеу үшін.
class NotificationsService {
  final SupabaseClient _sb = Supabase.instance.client;

  String get _uid => _sb.auth.currentUser?.id ?? '';

  Stream<List<NotificationModel>> watchNotifications() => _uid.isEmpty
      ? const Stream.empty()
      : _sb
          .from('notifications')
          .stream(primaryKey: ['id'])
          .eq('uid', _uid)
          .order('created_at', ascending: false)
          .map((rows) => rows.map(NotificationModel.fromMap).toList());

  Stream<int> watchUnreadCount() =>
      watchNotifications().map((list) => list.where((n) => n.isUnread).length);

  Future<void> markRead(String id) => _sb
      .from('notifications')
      .update({'read_at': DateTime.now().toIso8601String()}).eq('id', id);

  Future<void> markAllRead() => _sb
      .from('notifications')
      .update({'read_at': DateTime.now().toIso8601String()})
      .eq('uid', _uid)
      .filter('read_at', 'is', null);
}
