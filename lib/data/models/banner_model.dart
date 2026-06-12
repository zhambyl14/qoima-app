import 'dart:ui' show Color;
import 'package:cloud_firestore/cloud_firestore.dart';

/// Промо-баннер для клиентской главной (root-коллекция "banners").
/// Документы заводит суперадмин. Цвета градиента хранятся как hex-строки
/// («#C62828» / «C62828»); опциональное окно показа — startsAt/endsAt.
class BannerModel {
  final String id;
  final String title; // "Мега Жеңілдік!"
  final String subtitle; // "Барлық тауарларға 30% дейін"
  final String badge; // "🔥 11.11"
  final String gradientStart; // hex, напр. "#C62828"
  final String gradientEnd; // hex, напр. "#F0384B"
  final int order; // порядок показа (по возрастанию)
  final bool active; // вкл/выкл
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

  // Бренд градиентінің дефолт hex-тары (қате/бос мән болса).
  static const String _defStart = '#00713F';
  static const String _defEnd = '#12C97A';

  /// Hex-строканы Color-ге айналдырады («#RRGGBB» / «RRGGBB»). Қате болса жасыл.
  static Color hexColor(String hex) {
    final h = hex.replaceAll('#', '').trim();
    final full = h.length == 6 ? 'FF$h' : h;
    return Color(int.tryParse(full, radix: 16) ?? 0xFF00A862);
  }

  Color get startColor => hexColor(gradientStart);
  Color get endColor => hexColor(gradientEnd);

  /// Көрсетуге жарай ма (active + уақыт терезесі ішінде).
  bool isVisibleAt(DateTime now) {
    if (!active) return false;
    if (startsAt != null && now.isBefore(startsAt!)) return false;
    if (endsAt != null && now.isAfter(endsAt!)) return false;
    return true;
  }

  factory BannerModel.fromFirestore(DocumentSnapshot doc) {
    final d = (doc.data() as Map<String, dynamic>?) ?? {};
    // Артқа үйлесімділік: ескі құжаттарда gradientStart int болуы мүмкін.
    String hex(dynamic raw, String fallback) {
      if (raw is String && raw.trim().isNotEmpty) return raw.trim();
      if (raw is num) {
        return '#${(raw.toInt() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
      }
      return fallback;
    }

    return BannerModel(
      id: doc.id,
      title: d['title'] as String? ?? '',
      subtitle: d['subtitle'] as String? ?? '',
      badge: d['badge'] as String? ?? '',
      gradientStart: hex(d['gradientStart'], _defStart),
      gradientEnd: hex(d['gradientEnd'], _defEnd),
      order: (d['order'] as num?)?.toInt() ?? 0,
      active: d['active'] as bool? ?? true,
      startsAt: (d['startsAt'] as Timestamp?)?.toDate(),
      endsAt: (d['endsAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() => {
        'title': title,
        'subtitle': subtitle,
        'badge': badge,
        'gradientStart': gradientStart,
        'gradientEnd': gradientEnd,
        'order': order,
        'active': active,
        'startsAt': startsAt != null ? Timestamp.fromDate(startsAt!) : null,
        'endsAt': endsAt != null ? Timestamp.fromDate(endsAt!) : null,
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
