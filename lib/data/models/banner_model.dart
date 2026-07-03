import 'dart:ui' show Color;

/// Промо-баннер для клиентской главной (Supabase `banners`).
class BannerModel {
  final String id;
  final String title;
  final String subtitle;
  final String badge;
  final String gradientStart; // hex, напр. "#C62828"
  final String gradientEnd;
  final int order;
  final bool active;
  final DateTime? startsAt;
  final DateTime? endsAt;

  const BannerModel({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.gradientStart,
    required this.gradientEnd,
    required this.order,
    required this.active,
    this.startsAt,
    this.endsAt,
  });

  static const String _defStart = '#00713F';
  static const String _defEnd = '#12C97A';

  static Color hexColor(String hex) {
    final h = hex.replaceAll('#', '').trim();
    final full = h.length == 6 ? 'FF$h' : h;
    return Color(int.tryParse(full, radix: 16) ?? 0xFF00A862);
  }

  Color get startColor => hexColor(gradientStart);
  Color get endColor => hexColor(gradientEnd);

  bool isVisibleAt(DateTime now) {
    if (!active) return false;
    if (startsAt != null && now.isBefore(startsAt!)) return false;
    if (endsAt != null && now.isAfter(endsAt!)) return false;
    return true;
  }

  /// Supabase `banners` жолынан (snake_case бағандар).
  factory BannerModel.fromMap(Map<String, dynamic> m) {
    DateTime? dtn(dynamic v) =>
        v is String && v.isNotEmpty ? DateTime.tryParse(v) : null;
    String hx(dynamic raw, String fb) =>
        raw is String && raw.trim().isNotEmpty ? raw.trim() : fb;
    return BannerModel(
      id: m['id'] as String? ?? '',
      title: m['title'] as String? ?? '',
      subtitle: m['subtitle'] as String? ?? '',
      badge: m['badge'] as String? ?? '',
      gradientStart: hx(m['gradient_start'], _defStart),
      gradientEnd: hx(m['gradient_end'], _defEnd),
      order: (m['order'] as num?)?.toInt() ?? 0,
      active: m['active'] as bool? ?? true,
      startsAt: dtn(m['starts_at']),
      endsAt: dtn(m['ends_at']),
    );
  }

  /// Supabase жазу үшін (snake_case).
  Map<String, dynamic> toRow() => {
        'title': title,
        'subtitle': subtitle,
        'badge': badge,
        'gradient_start': gradientStart,
        'gradient_end': gradientEnd,
        'order': order,
        'active': active,
        'starts_at': startsAt?.toIso8601String(),
        'ends_at': endsAt?.toIso8601String(),
      };

  BannerModel copyWith({
    String? id,
    String? title,
    String? subtitle,
    String? badge,
    String? gradientStart,
    String? gradientEnd,
    int? order,
    bool? active,
    DateTime? startsAt,
    DateTime? endsAt,
  }) =>
      BannerModel(
        id: id ?? this.id,
        title: title ?? this.title,
        subtitle: subtitle ?? this.subtitle,
        badge: badge ?? this.badge,
        gradientStart: gradientStart ?? this.gradientStart,
        gradientEnd: gradientEnd ?? this.gradientEnd,
        order: order ?? this.order,
        active: active ?? this.active,
        startsAt: startsAt ?? this.startsAt,
        endsAt: endsAt ?? this.endsAt,
      );
}
