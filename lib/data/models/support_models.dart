/// Қолдау чаты (0072): пайдаланушы ↔ платформа модераторы (superadmin).
///
/// Әр пайдаланушыға бір ғана тред. Жазу тек RPC арқылы (support_send /
/// support_reply), сондықтан бұл модельдерде toMap жоқ — клиент жолды
/// тікелей жазбайды.
class SupportThread {
  static const statusOpen = 'open';
  static const statusClosed = 'closed';

  static const roleClient = 'client';
  static const roleAdmin = 'admin';
  static const roleSeller = 'seller';
  static const roleCourier = 'courier';

  final String id;
  final String userUid;
  final String userRole; // client|admin|seller|courier
  final String userName;
  final String userPhone;
  final String storeName;
  final String status; // open|closed
  final DateTime? lastMessageAt;
  final String lastMessagePreview;
  final int unreadForStaff;
  final int unreadForUser;
  final DateTime createdAt;

  const SupportThread({
    required this.id,
    required this.userUid,
    required this.userRole,
    this.userName = '',
    this.userPhone = '',
    this.storeName = '',
    this.status = statusOpen,
    this.lastMessageAt,
    this.lastMessagePreview = '',
    this.unreadForStaff = 0,
    this.unreadForUser = 0,
    required this.createdAt,
  });

  bool get isOpen => status != statusClosed;

  /// Дүкен жағы (иесі не сатушысы) — сүзгіде «Дүкен» чипі осыны қолданады.
  bool get isStoreSide => userRole == roleAdmin || userRole == roleSeller;

  factory SupportThread.fromMap(Map<String, dynamic> m) => SupportThread(
        id: m['id']?.toString() ?? '',
        userUid: m['user_uid']?.toString() ?? '',
        userRole: m['user_role']?.toString() ?? roleClient,
        userName: m['user_name']?.toString() ?? '',
        userPhone: m['user_phone']?.toString() ?? '',
        storeName: m['store_name']?.toString() ?? '',
        status: m['status']?.toString() ?? statusOpen,
        lastMessageAt: _date(m['last_message_at']),
        lastMessagePreview: m['last_message_preview']?.toString() ?? '',
        unreadForStaff: _int(m['unread_for_staff']),
        unreadForUser: _int(m['unread_for_user']),
        createdAt: _date(m['created_at']) ?? DateTime.now(),
      );
}

class SupportMessage {
  final int id;
  final String threadId;
  final String senderUid;
  final bool isStaff;
  final String body;
  final String imageUrl;
  final DateTime createdAt;

  const SupportMessage({
    required this.id,
    required this.threadId,
    this.senderUid = '',
    required this.isStaff,
    this.body = '',
    this.imageUrl = '',
    required this.createdAt,
  });

  bool get hasImage => imageUrl.isNotEmpty;

  factory SupportMessage.fromMap(Map<String, dynamic> m) => SupportMessage(
        id: _int(m['id']),
        threadId: m['thread_id']?.toString() ?? '',
        senderUid: m['sender_uid']?.toString() ?? '',
        isStaff: m['is_staff'] == true,
        body: m['body']?.toString() ?? '',
        imageUrl: m['image_url']?.toString() ?? '',
        createdAt: _date(m['created_at']) ?? DateTime.now(),
      );
}

int _int(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v?.toString() ?? '') ?? 0;
}

DateTime? _date(dynamic v) {
  if (v == null) return null;
  return DateTime.tryParse(v.toString())?.toLocal();
}
