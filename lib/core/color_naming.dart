import 'package:flutter/material.dart';
import 'lang.dart';

/// Таңдалған түске автоматты АТ береді (тонға + жарықтығына қарай): «ашық қызыл»,
/// «қою жасыл», «сұр» т.б. — дүкен иесі түстің атын білмей, HSV палитрадан
/// таңдағанда қолданылады. Ағымдағы тілде (ru/kk) қайтарады.
String describeColorName(Color c) {
  final hsv = HSVColor.fromColor(c);
  final h = hsv.hue; // 0..360
  final s = hsv.saturation; // 0..1
  final v = hsv.value; // 0..1

  // Ахроматтық (қанықтығы төмен) — ақ/қара/сұр.
  if (s < 0.12) {
    if (v < 0.2) return tr('Чёрный', 'Қара');
    if (v > 0.9) return tr('Белый', 'Ақ');
    return v > 0.55 ? tr('Светло-серый', 'Ашық сұр') : tr('Серый', 'Сұр');
  }

  // Негізгі тон (hue бойынша).
  String ru, kk;
  if (h < 15 || h >= 345) {
    ru = 'красный';
    kk = 'қызыл';
  } else if (h < 45) {
    ru = 'оранжевый';
    kk = 'қызғылт сары';
  } else if (h < 66) {
    ru = 'жёлтый';
    kk = 'сары';
  } else if (h < 90) {
    ru = 'салатовый';
    kk = 'ашық жасыл';
  } else if (h < 160) {
    ru = 'зелёный';
    kk = 'жасыл';
  } else if (h < 200) {
    ru = 'бирюзовый';
    kk = 'көгілдір';
  } else if (h < 255) {
    ru = 'синий';
    kk = 'көк';
  } else if (h < 290) {
    ru = 'фиолетовый';
    kk = 'күлгін';
  } else {
    ru = 'розовый';
    kk = 'қызғылт';
  }

  // Жарықтық префиксі.
  if (v < 0.4) return tr('Тёмно-$ru', 'Қою $kk');
  if (v > 0.85 && s < 0.55) return tr('Светло-$ru', 'Ашық $kk');
  // Бірінші әріпті бас әріпке.
  String cap(String x) => x.isEmpty ? x : x[0].toUpperCase() + x.substring(1);
  return tr(cap(ru), cap(kk));
}

/// HEX жол ↔ Color түрлендіргіштер (products.color_hex сақтауы үшін).
String colorToHex(Color c) =>
    '#${((c.a * 255).round() << 24 | (c.r * 255).round() << 16 | (c.g * 255).round() << 8 | (c.b * 255).round()).toRadixString(16).padLeft(8, '0').substring(2)}';

Color? hexToColor(String hex) {
  var h = hex.trim().replaceFirst('#', '');
  if (h.isEmpty) return null;
  if (h.length == 6) h = 'FF$h';
  final v = int.tryParse(h, radix: 16);
  return v == null ? null : Color(v);
}
