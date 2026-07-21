import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/banks.dart';

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

class AppSettingsService {
  final SupabaseClient _sb = Supabase.instance.client;

  static const _kNumber = 'payment_card_number';
  static const _kHolder = 'payment_card_holder';
  static const _kBank = 'payment_card_bank';
  static const _kKaspi = 'payment_kaspi_link';
  static const _kBankQrs = 'payment_bank_qrs';
  static const _kMode = 'payment_mode';

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
}
