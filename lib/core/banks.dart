import 'package:flutter/material.dart' show Color;

/// Қазақстан банктері — дүкен иесі әрқайсысының QR сілтемесін қоса алады.
/// Клиент төлемде осы QR-ды кәдімгі QR-код ретінде көреді (единый QR — кез
/// келген банк қосымшасы сканерлей алады).
class BankDef {
  final String id;
  final String name;
  const BankDef(this.id, this.name);
}

const List<BankDef> kBanks = [
  BankDef('kaspi', 'Kaspi'),
  BankDef('halyk', 'Halyk'),
  BankDef('freedom', 'Freedom'),
  BankDef('forte', 'ForteBank'),
  BankDef('bcc', 'БЦК'),
  BankDef('eurasian', 'Евразийский'),
  BankDef('bereke', 'Bereke'),
  BankDef('alatau', 'Alatau City'),
  BankDef('home', 'Home Credit'),
];

String bankName(String id) =>
    kBanks.firstWhere((b) => b.id == id, orElse: () => BankDef(id, id)).name;

/// Банктің бренд түсі — клиентке көрсетілетін шағын белгі (badge) үшін.
Color bankColor(String id) => switch (id) {
      'kaspi' => const Color(0xFFE30611),
      'halyk' => const Color(0xFF046A38),
      'freedom' => const Color(0xFF00A651),
      'forte' => const Color(0xFFF7941D),
      'bcc' => const Color(0xFF0033A0),
      'eurasian' => const Color(0xFF005BAA),
      'bereke' => const Color(0xFF6E2585),
      'alatau' => const Color(0xFF1B998B),
      'home' => const Color(0xFFDA291C),
      _ => const Color(0xFF64748B),
    };

/// Supabase `bank_qrs` (jsonb) → `Map<String,String>`. Ескі [kaspiFallback]
/// (kaspi_link) болса, картада kaspi жоқ кезде оны қосады (back-compat).
Map<String, String> parseBankQrs(dynamic raw, [String kaspiFallback = '']) {
  final out = <String, String>{};
  if (raw is Map) {
    raw.forEach((k, v) {
      final link = (v?.toString() ?? '').trim();
      if (link.isNotEmpty) out[k.toString()] = link;
    });
  }
  if ((out['kaspi'] ?? '').isEmpty && kaspiFallback.trim().isNotEmpty) {
    out['kaspi'] = kaspiFallback.trim();
  }
  return out;
}

/// QR картасынан бос емес жазбаларды банк реті бойынша қайтарады.
List<MapEntry<String, String>> orderedBankQrs(Map<String, String> qrs) {
  final out = <MapEntry<String, String>>[];
  for (final b in kBanks) {
    final link = qrs[b.id]?.trim() ?? '';
    if (link.isNotEmpty) out.add(MapEntry(b.id, link));
  }
  // Тізімде жоқ (белгісіз) банктер болса — соңына қосамыз.
  for (final e in qrs.entries) {
    if (kBanks.every((b) => b.id != e.key) && e.value.trim().isNotEmpty) {
      out.add(MapEntry(e.key, e.value.trim()));
    }
  }
  return out;
}
