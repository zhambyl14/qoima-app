// Дүкен сторисі (0084): 24 сағаттық фото + қысқа жазу.

DateTime? _dt(dynamic v) {
  if (v is DateTime) return v;
  if (v is String && v.isNotEmpty) return DateTime.tryParse(v)?.toLocal();
  return null;
}

int _int(dynamic v) => (v as num?)?.toInt() ?? 0;

/// `store_stories` жолы (story_create / stories_for_store қайтарады).
class StoryModel {
  final String id;
  final String storeUid; // stores.admin_uid
  final String imageUrl;
  final String caption; // бос болуы мүмкін, ≤ 200 таңба
  final String createdBy; // кім жариялады (иесі не сатушы); '' = белгісіз
  final DateTime createdAt;
  final DateTime expiresAt;

  const StoryModel({
    required this.id,
    required this.storeUid,
    required this.imageUrl,
    this.caption = '',
    this.createdBy = '',
    required this.createdAt,
    required this.expiresAt,
  });

  /// Сервердегі шектермен бірдей (story_create) — UI алдын ала ескертсін.
  static const maxCaption = 200;
  static const maxActivePerStore = 10;
  static const lifetime = Duration(hours: 24);

  /// Сервер мерзімі өткенді өзі жасырады; бұл — экран ұзақ ашық тұрғанда
  /// көрсетуді тоқтату үшін.
  bool isExpiredAt(DateTime now) => !expiresAt.isAfter(now);
  bool get isExpired => isExpiredAt(DateTime.now());

  /// Қалған уақыт (теріс болмайды).
  Duration get remaining {
    final d = expiresAt.difference(DateTime.now());
    return d.isNegative ? Duration.zero : d;
  }

  factory StoryModel.fromMap(Map<String, dynamic> m) {
    final created = _dt(m['created_at']) ?? DateTime.now();
    return StoryModel(
      id: m['id'] as String? ?? '',
      storeUid: m['store_uid'] as String? ?? '',
      imageUrl: m['image_url'] as String? ?? '',
      caption: m['caption'] as String? ?? '',
      createdBy: m['created_by'] as String? ?? '',
      createdAt: created,
      // Мерзімі жоқ жол болмайды (not null), бірақ қорғаныс: әдепкі 24 сағат.
      expiresAt: _dt(m['expires_at']) ?? created.add(lifetime),
    );
  }
}

/// Басты беттегі сторис жолағының бір дөңгелегі — бір дүкен
/// (`stories_for_stores` жолы).
class StoryStoreGroup {
  final String storeUid;
  final String storeName;
  final String logoUrl;
  final int storyCount;
  final DateTime latestAt; // ең жаңа сторис — жолақ осымен сұрыпталады
  final DateTime oldestAt; // ең ескісі — «көрілді» белгісін салыстыруға

  const StoryStoreGroup({
    required this.storeUid,
    required this.storeName,
    this.logoUrl = '',
    required this.storyCount,
    required this.latestAt,
    required this.oldestAt,
  });

  /// [seenUntil] — клиент осы дүкеннің сторисін соңғы рет қай уақытқа дейін
  /// көрді. Одан жаңа сторис болса — дөңгелек «көрілмеген» (жасыл шеңбер).
  bool hasUnseen(DateTime? seenUntil) =>
      seenUntil == null || latestAt.isAfter(seenUntil);

  factory StoryStoreGroup.fromMap(Map<String, dynamic> m) {
    final latest = _dt(m['latest_at']) ?? DateTime.now();
    return StoryStoreGroup(
      storeUid: m['store_uid'] as String? ?? '',
      storeName: m['store_name'] as String? ?? '',
      logoUrl: m['logo_url'] as String? ?? '',
      storyCount: _int(m['story_count']),
      latestAt: latest,
      oldestAt: _dt(m['oldest_at']) ?? latest,
    );
  }
}
