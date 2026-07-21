import 'package:supabase_flutter/supabase_flutter.dart';

/// Платформа реквизиттері (модератордың төлем картасы).
/// Барлық онлайн-төлемдер осы картаға түседі — клиент checkout кезінде көреді,
/// модератор (superadmin) «Реквизиты» экранында өзгертеді.
class PaymentCardSettings {
  final String number;
  final String holder;
  final String bank;
  // Kaspi QR сілтемесі — негізгі төлем тәсілі (карта — қосымша).
  final String kaspiLink;
  const PaymentCardSettings({
    this.number = '',
    this.holder = '',
    this.bank = '',
    this.kaspiLink = '',
  });

  // Карта нөмірі НЕМЕСЕ Kaspi сілтемесі болса — реквизит бар.
  bool get isConfigured =>
      number.trim().isNotEmpty || kaspiLink.trim().isNotEmpty;
  bool get hasKaspi => kaspiLink.trim().isNotEmpty;
}

class AppSettingsService {
  final SupabaseClient _sb = Supabase.instance.client;

  static const _kNumber = 'payment_card_number';
  static const _kHolder = 'payment_card_holder';
  static const _kBank = 'payment_card_bank';
  static const _kKaspi = 'payment_kaspi_link';
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
        .inFilter('key', [_kNumber, _kHolder, _kBank, _kKaspi]);
    final map = {
      for (final r in rows) r['key'] as String: (r['value'] as String? ?? '')
    };
    return PaymentCardSettings(
      number: map[_kNumber] ?? '',
      holder: map[_kHolder] ?? '',
      bank: map[_kBank] ?? '',
      kaspiLink: map[_kKaspi] ?? '',
    );
  }

  /// Тек superadmin (RLS: app_settings_write).
  Future<void> savePaymentCard(PaymentCardSettings card) async {
    final now = DateTime.now().toIso8601String();
    await _sb.from('app_settings').upsert([
      {'key': _kNumber, 'value': card.number.trim(), 'updated_at': now},
      {'key': _kHolder, 'value': card.holder.trim(), 'updated_at': now},
      {'key': _kBank, 'value': card.bank.trim(), 'updated_at': now},
      {'key': _kKaspi, 'value': card.kaspiLink.trim(), 'updated_at': now},
    ]);
  }
}
