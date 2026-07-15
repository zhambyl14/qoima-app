import '../../core/lang.dart';

/// Контент шағымы (content_reports кестесі).
///
/// Кез келген авторизацияланған қолданушы тауарға / дүкенге / пікірге
/// шағымдана алады (App Store Guideline 1.2 — report mechanism).
/// Қарайтын — superadmin (модератор).
class ReportModel {
  final String id;
  final String reporterUid;
  final String reporterName;
  final String reporterPhone;
  final String targetType; // product|store|review
  final String targetId;
  final String targetName;
  final String adminUid;
  final String storeName;
  final String reason; // канондық кілт (reportReasonLabel аударады)
  final String comment;
  final String status; // new|resolved|dismissed
  final String resolvedBy;
  final String resolutionNote;
  final DateTime? resolvedAt;
  final DateTime createdAt;

  bool get isNew => status == 'new';
  bool get isResolved => status == 'resolved';
  bool get isDismissed => status == 'dismissed';

  const ReportModel({
    required this.id,
    required this.reporterUid,
    required this.reporterName,
    required this.reporterPhone,
    required this.targetType,
    required this.targetId,
    required this.targetName,
    required this.adminUid,
    required this.storeName,
    required this.reason,
    required this.comment,
    required this.status,
    required this.resolvedBy,
    required this.resolutionNote,
    required this.resolvedAt,
    required this.createdAt,
  });

  factory ReportModel.fromMap(Map<String, dynamic> m) {
    DateTime dt(dynamic v) =>
        v is String ? (DateTime.tryParse(v) ?? DateTime.now()) : DateTime.now();
    DateTime? dtn(dynamic v) =>
        v is String && v.isNotEmpty ? DateTime.tryParse(v) : null;
    return ReportModel(
      id: m['id'] as String? ?? '',
      reporterUid: m['reporter_uid'] as String? ?? '',
      reporterName: m['reporter_name'] as String? ?? '',
      reporterPhone: m['reporter_phone'] as String? ?? '',
      targetType: m['target_type'] as String? ?? 'product',
      targetId: m['target_id'] as String? ?? '',
      targetName: m['target_name'] as String? ?? '',
      adminUid: m['admin_uid'] as String? ?? '',
      storeName: m['store_name'] as String? ?? '',
      reason: m['reason'] as String? ?? 'other',
      comment: m['comment'] as String? ?? '',
      status: m['status'] as String? ?? 'new',
      resolvedBy: m['resolved_by'] as String? ?? '',
      resolutionNote: m['resolution_note'] as String? ?? '',
      resolvedAt: dtn(m['resolved_at']),
      createdAt: dt(m['created_at']),
    );
  }
}

/// Шағым себептерінің канондық кілттері (DB-де кілт сақталады, UI аударады).
const List<String> kReportReasons = [
  'misleading', // жалған/қате ақпарат
  'fake', // контрафакт / жалған тауар
  'offensive', // қорлайтын / орынсыз контент
  'fraud', // алаяқтық
  'ip', // авторлық құқық бұзылуы
  'other', // басқа
];

/// Себеп кілті → ағымдағы тілдегі жазба.
String reportReasonLabel(String key) {
  switch (key) {
    case 'misleading':
      return tr('Недостоверная информация', 'Жалған/қате ақпарат');
    case 'fake':
      return tr('Подделка / контрафакт', 'Жасанды тауар / контрафакт');
    case 'offensive':
      return tr('Оскорбительный контент', 'Қорлайтын/орынсыз контент');
    case 'fraud':
      return tr('Мошенничество', 'Алаяқтық');
    case 'ip':
      return tr('Нарушение авторских прав', 'Авторлық құқық бұзылуы');
    default:
      return tr('Другое', 'Басқа');
  }
}

/// Нысан түрі → ағымдағы тілдегі жазба (superadmin экраны).
String reportTargetLabel(String type) {
  switch (type) {
    case 'store':
      return tr('Магазин', 'Дүкен');
    case 'review':
      return tr('Отзыв', 'Пікір');
    default:
      return tr('Товар', 'Тауар');
  }
}
