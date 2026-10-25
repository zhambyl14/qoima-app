import '../../core/lang.dart';

/// «Той тілек тізімі» (0069) модельдері.
///
/// Тойдың түрі ДБ-да канондық кілтпен сақталады ('birthday', 'wedding' ...);
/// көрсетілім тек [RegistryOccasion.label] арқылы аударылады — кілттің өзі
/// tr()-ден ӨТПЕЙДІ (сүзгі/салыстыру бұзылмауы үшін).
class RegistryOccasion {
  RegistryOccasion._();

  static const List<String> keys = [
    'birthday',
    'wedding',
    'toi',
    'sundet',
    'besik',
    'baby',
    'other',
  ];

  static String emoji(String key) {
    switch (key) {
      case 'birthday':
        return '🎂';
      case 'wedding':
        return '💍';
      case 'toi':
        return '🎉';
      case 'sundet':
        return '👦';
      case 'besik':
        return '👶';
      case 'baby':
        return '🍼';
      default:
        return '✨';
    }
  }

  static String label(String key) {
    switch (key) {
      case 'birthday':
        return tr('День рождения', 'Туған күн');
      case 'wedding':
        return tr('Свадьба', 'Үйлену тойы');
      case 'toi':
        return tr('Той', 'Той');
      case 'sundet':
        return tr('Сундет той', 'Сүндет той');
      case 'besik':
        return tr('Бесик той', 'Бесік той');
      case 'baby':
        return tr('Шилдехана', 'Шілдехана');
      default:
        return tr('Другое', 'Басқа');
    }
  }

  static String withEmoji(String key) => '${emoji(key)} ${label(key)}';
}

DateTime? _date(dynamic v) {
  if (v is DateTime) return v;
  if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
  return null;
}

int _int(dynamic v, [int def = 0]) =>
    v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? def;

double _double(dynamic v) =>
    v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;

/// Той күніне дейін қалған күн: бүгін = 0, өтіп кетсе — теріс. Күн жоқ — null.
int? registryDaysLeft(DateTime? eventDate) {
  if (eventDate == null) return null;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final d = DateTime(eventDate.year, eventDate.month, eventDate.day);
  return d.difference(today).inDays;
}

/// «15 күн қалды» / «Бүгін!» / «Өтті» — карточка мен беттегі чип мәтіні.
String registryCountdownText(DateTime? eventDate) {
  final left = registryDaysLeft(eventDate);
  if (left == null) return '';
  if (left == 0) return tr('Сегодня!', 'Бүгін!');
  if (left == 1) return tr('Завтра', 'Ертең');
  if (left < 0) return tr('Прошло', 'Өтті');
  return tr('Осталось $left дн.', '$left күн қалды');
}

String registryDateText(DateTime? d) {
  if (d == null) return '';
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(d.day)}.${two(d.month)}.${d.year}';
}

/// gift_registries жолы (тізім иесіне ғана көрінеді, RLS).
class GiftRegistry {
  final String id;
  final String ownerUid;
  final String title;
  final String occasion;
  final DateTime? eventDate;
  final String message;
  final String city;
  final String shareToken;
  final bool isActive;
  final DateTime? createdAt;

  const GiftRegistry({
    required this.id,
    required this.ownerUid,
    required this.title,
    required this.occasion,
    this.eventDate,
    this.message = '',
    this.city = '',
    required this.shareToken,
    this.isActive = true,
    this.createdAt,
  });

  factory GiftRegistry.fromMap(Map<String, dynamic> m) => GiftRegistry(
        id: m['id'] as String? ?? '',
        ownerUid: m['owner_uid'] as String? ?? '',
        title: m['title'] as String? ?? '',
        occasion: m['occasion'] as String? ?? 'other',
        eventDate: _date(m['event_date']),
        message: m['message'] as String? ?? '',
        city: m['city'] as String? ?? '',
        shareToken: m['share_token'] as String? ?? '',
        isActive: m['is_active'] as bool? ?? true,
        createdAt: _date(m['created_at']),
      );

  int? get daysLeft => registryDaysLeft(eventDate);
}

/// Иесінің карточкасындағы прогресс (get_my_registries_summary) — тек сандар.
class RegistrySummary {
  final int itemsCount;
  final int qtyTotal;
  final int qtyTaken;

  const RegistrySummary(
      {this.itemsCount = 0, this.qtyTotal = 0, this.qtyTaken = 0});

  factory RegistrySummary.fromMap(Map<String, dynamic> m) => RegistrySummary(
        itemsCount: _int(m['items_count']),
        qtyTotal: _int(m['qty_total']),
        qtyTaken: _int(m['qty_taken']),
      );

  double get progress =>
      qtyTotal <= 0 ? 0 : (qtyTaken / qtyTotal).clamp(0, 1).toDouble();
}

/// Позицияның көрінетін күйі.
enum RegistryItemState { free, reserved, purchased }

/// get_registry_public ішіндегі бір позиция.
class RegistryItem {
  final String id;
  final String productId;
  final String adminUid;
  final String productName;
  final String imageUrl;
  final String size;
  final double price;
  final bool inStock;
  final int qtyWanted;
  final int qtyTaken;
  final int qtyPurchased;
  final int remaining;
  final String note;

  const RegistryItem({
    required this.id,
    required this.productId,
    required this.adminUid,
    required this.productName,
    this.imageUrl = '',
    this.size = '',
    this.price = 0,
    this.inStock = true,
    this.qtyWanted = 1,
    this.qtyTaken = 0,
    this.qtyPurchased = 0,
    this.remaining = 1,
    this.note = '',
  });

  factory RegistryItem.fromMap(Map<String, dynamic> m) => RegistryItem(
        id: m['id'] as String? ?? '',
        productId: m['product_id'] as String? ?? '',
        adminUid: m['admin_uid'] as String? ?? '',
        productName: m['product_name'] as String? ?? '',
        imageUrl: m['image_url'] as String? ?? '',
        size: m['size'] as String? ?? '',
        price: _double(m['price']),
        inStock: m['in_stock'] as bool? ?? true,
        qtyWanted: _int(m['qty_wanted'], 1),
        qtyTaken: _int(m['qty_taken']),
        qtyPurchased: _int(m['qty_purchased']),
        remaining: _int(m['remaining']),
        note: m['note'] as String? ?? '',
      );

  /// Бәрі сатып алынса — «Сатып алынды»; бос дана қалмаса — «Брондалған».
  RegistryItemState get state {
    if (qtyPurchased >= qtyWanted) return RegistryItemState.purchased;
    if (remaining <= 0) return RegistryItemState.reserved;
    return RegistryItemState.free;
  }
}

/// Шақырушының (қонақтың) белсенді броны.
class RegistryClaim {
  final String id;
  final String itemId;
  final int qty;
  final String status; // reserved | purchased
  final DateTime? reservedUntil;
  final bool inOrder;

  const RegistryClaim({
    required this.id,
    required this.itemId,
    required this.qty,
    required this.status,
    this.reservedUntil,
    this.inOrder = false,
  });

  factory RegistryClaim.fromMap(Map<String, dynamic> m) => RegistryClaim(
        id: m['id'] as String? ?? '',
        itemId: m['item_id'] as String? ?? '',
        qty: _int(m['qty'], 1),
        status: m['status'] as String? ?? 'reserved',
        reservedUntil: _date(m['reserved_until']),
        inOrder: m['in_order'] as bool? ?? false,
      );

  bool get isPurchased => status == 'purchased';

  /// Тек тапсырысқа әлі байланбаған бронның ғана бас тартуы бар.
  bool get canRelease => status == 'reserved' && !inOrder;
}

/// get_registry_public(token) жауабы — қонақ көретін тізім.
class PublicRegistry {
  final String id;
  final String title;
  final String occasion;
  final DateTime? eventDate;
  final String message;
  final String ownerName;
  final String city;
  final bool isActive;
  final List<RegistryItem> items;
  final bool isOwner;
  final List<RegistryClaim> myClaims;

  const PublicRegistry({
    required this.id,
    required this.title,
    required this.occasion,
    this.eventDate,
    this.message = '',
    this.ownerName = '',
    this.city = '',
    this.isActive = true,
    this.items = const [],
    this.isOwner = false,
    this.myClaims = const [],
  });

  factory PublicRegistry.fromMap(Map<String, dynamic> m) {
    List<Map<String, dynamic>> list(dynamic v) => v is List
        ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : const [];
    return PublicRegistry(
      id: m['id'] as String? ?? '',
      title: m['title'] as String? ?? '',
      occasion: m['occasion'] as String? ?? 'other',
      eventDate: _date(m['event_date']),
      message: m['message'] as String? ?? '',
      ownerName: m['owner_name'] as String? ?? '',
      city: m['city'] as String? ?? '',
      isActive: m['is_active'] as bool? ?? true,
      items: list(m['items']).map(RegistryItem.fromMap).toList(),
      isOwner: m['is_owner'] as bool? ?? false,
      myClaims: list(m['my_claims']).map(RegistryClaim.fromMap).toList(),
    );
  }

  RegistryClaim? myClaimFor(String itemId) {
    for (final c in myClaims) {
      if (c.itemId == itemId) return c;
    }
    return null;
  }

  int get qtyTotal => items.fold(0, (s, i) => s + i.qtyWanted);
  int get qtyTaken => items.fold(
      0, (s, i) => s + (i.qtyTaken > i.qtyWanted ? i.qtyWanted : i.qtyTaken));
}
