import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/banks.dart';
import '../models/delivery_tariff.dart';

/// Платформа реквизиттері (модератордың банк QR сілтемелері).
/// Клиент checkout кезінде осы QR-ларды кәдімгі QR-код ретінде көреді;
/// модератор (superadmin) «Реквизиты» экранында өзгертеді.
class PaymentCardSettings {
  final String number; // ЕСКІ — енді қолданылмайды
  final String holder;
  final String bank;
  final String kaspiLink; // ЕСКІ — bank_qrs.kaspi-ге көшеді
  // Банк QR сілтемелері {bank_id: qr_link}.
  final Map<String, String> bankQrs;
  const PaymentCardSettings({
    this.number = '',
    this.holder = '',
    this.bank = '',
    this.kaspiLink = '',
    this.bankQrs = const {},
  });

  bool get isConfigured => bankQrs.isNotEmpty;
}

/// Профильдегі «Байланыс» карточкасының мәндері — superadmin «Реквизиты»
/// экранында өзгертеді (app_settings кестесі, payment реквизиттерімен бірдей
/// конвенция: оқу — кез келген авторизацияланған, жазу — тек superadmin).
class ContactSettings {
  final String whatsapp; // тек телефон нөмірі (wa.me сілтемесі үшін)
  final String telegram; // username, @ таңбасынсыз
  final String instagram; // username, @ таңбасынсыз
  const ContactSettings({
    this.whatsapp = '',
    this.telegram = '',
    this.instagram = '',
  });
}

class AppSettingsService {
  final SupabaseClient _sb = Supabase.instance.client;

  static const _kNumber = 'payment_card_number';
  static const _kHolder = 'payment_card_holder';
  static const _kBank = 'payment_card_bank';
  static const _kKaspi = 'payment_kaspi_link';
  static const _kBankQrs = 'payment_bank_qrs';
  static const _kMode = 'payment_mode';
  static const _kWhatsapp = 'contact_whatsapp';
  static const _kTelegram = 'contact_telegram';
  static const _kInstagram = 'contact_instagram';

  /// Төлем режимі: 'platform' — бәрі модератор картасына (әдепкі);
  /// 'store' — әр тапсырыс сол дүкеннің картасына (толтырмаса — fallback
  /// модератор картасы). Superadmin «Реквизиты» экранында ауыстырады.
  Future<String> getPaymentMode() async {
    final row = await _sb
        .from('app_settings')
        .select('value')
        .eq('key', _kMode)
        .maybeSingle();
    final v = (row?['value'] as String?)?.trim() ?? '';
    return v == 'store' ? 'store' : 'platform';
  }

  /// Тек superadmin (RLS: app_settings_write).
  Future<void> savePaymentMode(String mode) async {
    await _sb.from('app_settings').upsert({
      'key': _kMode,
      'value': mode == 'store' ? 'store' : 'platform',
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  Future<PaymentCardSettings> getPaymentCard() async {
    final rows = await _sb
        .from('app_settings')
        .select('key,value')
        .inFilter('key', [_kNumber, _kHolder, _kBank, _kKaspi, _kBankQrs]);
    final map = {
      for (final r in rows) r['key'] as String: (r['value'] as String? ?? '')
    };
    dynamic rawQrs;
    try {
      final s = map[_kBankQrs] ?? '';
      if (s.isNotEmpty) rawQrs = jsonDecode(s);
    } catch (_) {}
    return PaymentCardSettings(
      number: map[_kNumber] ?? '',
      holder: map[_kHolder] ?? '',
      bank: map[_kBank] ?? '',
      kaspiLink: map[_kKaspi] ?? '',
      bankQrs: parseBankQrs(rawQrs, map[_kKaspi] ?? ''),
    );
  }

  /// Тек superadmin (RLS: app_settings_write).
  Future<void> savePaymentCard(PaymentCardSettings card) async {
    final now = DateTime.now().toIso8601String();
    await _sb.from('app_settings').upsert([
      {'key': _kBankQrs, 'value': jsonEncode(card.bankQrs), 'updated_at': now},
    ]);
  }

  Future<ContactSettings> getContactSettings() async {
    final rows = await _sb
        .from('app_settings')
        .select('key,value')
        .inFilter('key', [_kWhatsapp, _kTelegram, _kInstagram]);
    final map = {
      for (final r in rows) r['key'] as String: (r['value'] as String? ?? '')
    };
    return ContactSettings(
      whatsapp: map[_kWhatsapp] ?? '',
      telegram: map[_kTelegram] ?? '',
      instagram: map[_kInstagram] ?? '',
    );
  }

  /// Тек superadmin (RLS: app_settings_write).
  Future<void> saveContactSettings(ContactSettings c) async {
    final now = DateTime.now().toIso8601String();
    await _sb.from('app_settings').upsert([
      {'key': _kWhatsapp, 'value': c.whatsapp, 'updated_at': now},
      {'key': _kTelegram, 'value': c.telegram, 'updated_at': now},
      {'key': _kInstagram, 'value': c.instagram, 'updated_at': now},
    ]);
  }

  // ── Жеткізу тарифі (0050) ──────────────────────────────────────────────────

  /// Тарифті `delivery_tariff()` RPC арқылы оқимыз — app_settings-тің SELECT
  /// саясаты `to authenticated`, ал себетті ҚОНАҚ та ашады. Қате болса
  /// әдепкі тариф қайтады (себет ешқашан ақысыз күйде қалмайды).
  Future<DeliveryTariff> getDeliveryTariff() async {
    try {
      final res = await _sb.rpc('delivery_tariff');
      if (res is Map) {
        return DeliveryTariff.fromMap(
            res.map((k, v) => MapEntry(k.toString(), v?.toString() ?? '')));
      }
    } catch (_) {}
    return const DeliveryTariff();
  }

  /// Тек superadmin (RLS: app_settings_write).
  Future<void> saveDeliveryTariff(DeliveryTariff t) async {
    final now = DateTime.now().toIso8601String();
    await _sb.from('app_settings').upsert([
      for (final e in t.toMap().entries)
        {'key': e.key, 'value': e.value, 'updated_at': now},
    ]);
  }
}
