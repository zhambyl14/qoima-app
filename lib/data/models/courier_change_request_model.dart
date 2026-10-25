import 'user_model.dart';

/// Курьердің өзгертуге болатын деректері (0074 ақ тізімі — SQL
/// `courier_changes_normalize` пен ДӘЛ бірдей болуы керек).
// Телефон бұл тізімде ЖОҚ: нөмір иелігін растау қажет, ол Telegram ағынымен
// (AccountSecurityScreen) не superadmin арқылы өзгереді.
const List<String> kCourierChangeKeys = ['name', 'city'];

/// Курьер профилі: users жолы + телефон (UserModel-де phone өрісі жоқ).
class CourierProfile {
  final UserModel user;
  final String phone;

  const CourierProfile({required this.user, required this.phone});

  String get uid => user.uid;
  String get name => user.name;
  String get city => user.city;
  String get courierStatus => user.courierStatus;
  bool get blocked => user.blocked;

  /// [key] бойынша ағымдағы мән ('name' | 'phone' | 'city').
  String valueOf(String key) => switch (key) {
        'name' => user.name,
        'phone' => phone,
        'city' => user.city,
        _ => '',
      };

  factory CourierProfile.fromMap(Map<String, dynamic> m) => CourierProfile(
        user: UserModel.fromMap(m),
        phone: m['phone'] as String? ?? '',
      );
}

/// `courier_change_requests` жолы (0074).
class CourierChangeRequest {
  final String id;
  final String courierUid;

  /// Сұралған жаңа мәндер (тек ақ тізімдегі кілттер).
  final Map<String, String> changes;

  /// Сұраныс сәтіндегі ескі мәндер (diff үшін).
  final Map<String, String> oldValues;
  final String reason;

  /// 'pending' | 'approved' | 'rejected' | 'cancelled'
  final String status;
  final String reviewedBy;
  final DateTime? reviewedAt;
  final String rejectReason;
  final DateTime createdAt;

  const CourierChangeRequest({
    required this.id,
    required this.courierUid,
    required this.changes,
    required this.oldValues,
    required this.reason,
    required this.status,
    required this.reviewedBy,
    required this.reviewedAt,
    required this.rejectReason,
    required this.createdAt,
  });

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';
  bool get isCancelled => status == 'cancelled';

  static Map<String, String> _strMap(dynamic raw) {
    if (raw is! Map) return const {};
    return {
      for (final e in raw.entries)
        if (e.value != null) e.key.toString(): e.value.toString(),
    };
  }

  static DateTime? _date(dynamic raw) => raw is String && raw.isNotEmpty
      ? DateTime.tryParse(raw)?.toLocal()
      : null;

  factory CourierChangeRequest.fromMap(Map<String, dynamic> m) =>
      CourierChangeRequest(
        id: m['id'] as String? ?? '',
        courierUid: m['courier_uid'] as String? ?? '',
        changes: _strMap(m['changes']),
        oldValues: _strMap(m['old_values']),
        reason: m['reason'] as String? ?? '',
        status: m['status'] as String? ?? 'pending',
        reviewedBy: m['reviewed_by'] as String? ?? '',
        reviewedAt: _date(m['reviewed_at']),
        rejectReason: m['reject_reason'] as String? ?? '',
        createdAt: _date(m['created_at']) ?? DateTime.now(),
      );
}
