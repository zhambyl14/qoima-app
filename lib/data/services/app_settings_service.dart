import 'package:supabase_flutter/supabase_flutter.dart';

/// Платформа реквизиттері (модератордың төлем картасы).
/// Барлық онлайн-төлемдер осы картаға түседі — клиент checkout кезінде көреді,
/// модератор (superadmin) «Реквизиты» экранында өзгертеді.
class PaymentCardSettings {
  final String number;
  final String holder;
  final String bank;
  const PaymentCardSettings({
    this.number = '',
    this.holder = '',
    this.bank = '',
  });

  bool get isConfigured => number.trim().isNotEmpty;
}

class AppSettingsService {
  final SupabaseClient _sb = Supabase.instance.client;

  static const _kNumber = 'payment_card_number';
  static const _kHolder = 'payment_card_holder';
  static const _kBank = 'payment_card_bank';

  Future<PaymentCardSettings> getPaymentCard() async {
    final rows = await _sb
        .from('app_settings')
        .select('key,value')
        .inFilter('key', [_kNumber, _kHolder, _kBank]);
    final map = {
      for (final r in rows) r['key'] as String: (r['value'] as String? ?? '')
    };
    return PaymentCardSettings(
      number: map[_kNumber] ?? '',
      holder: map[_kHolder] ?? '',
      bank: map[_kBank] ?? '',
    );
  }

  /// Тек superadmin (RLS: app_settings_write).
  Future<void> savePaymentCard(PaymentCardSettings card) async {
    final now = DateTime.now().toIso8601String();
    await _sb.from('app_settings').upsert([
      {'key': _kNumber, 'value': card.number.trim(), 'updated_at': now},
      {'key': _kHolder, 'value': card.holder.trim(), 'updated_at': now},
      {'key': _kBank, 'value': card.bank.trim(), 'updated_at': now},
    ]);
  }
}
