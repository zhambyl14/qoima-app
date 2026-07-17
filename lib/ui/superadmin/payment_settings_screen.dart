import 'package:flutter/material.dart';
import '../../core/card_utils.dart';
import '../../core/lang.dart';
import '../../data/services/app_settings_service.dart';
import '../../theme/qoima_design.dart';

/// Модератор: платформаның төлем реквизиттері. Барлық онлайн-заказ төлемдері
/// осы картаға аударылады — клиент checkout кезінде дәл осы нөмірді көреді.
class PaymentSettingsScreen extends StatefulWidget {
  const PaymentSettingsScreen({super.key});

  @override
  State<PaymentSettingsScreen> createState() => _PaymentSettingsScreenState();
}

class _PaymentSettingsScreenState extends State<PaymentSettingsScreen> {
  final _service = AppSettingsService();
  final _numberCtrl = TextEditingController();
  final _holderCtrl = TextEditingController();
  final _bankCtrl = TextEditingController();
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _numberCtrl.dispose();
    _holderCtrl.dispose();
    _bankCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final card = await _service.getPaymentCard();
      if (!mounted) return;
      setState(() {
        _numberCtrl.text = formatCardDisplay(card.number);
        _holderCtrl.text = card.holder;
        _bankCtrl.text = card.bank;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final digits = cardDigitsOnly(_numberCtrl.text);
    if (digits.isNotEmpty && !isCardValid(digits)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(tr('Проверьте номер карты (16 цифр)', 'Карта нөмірін тексеріңіз (16 сан)')),
        backgroundColor: cRed,
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    setState(() => _saving = true);
    try {
      await _service.savePaymentCard(PaymentCardSettings(
        number: digits,
        holder: _holderCtrl.text.trim(),
        bank: _bankCtrl.text.trim(),
      ));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(tr('Реквизиты сохранены ✓', 'Реквизиттер сақталды ✓')),
          backgroundColor: cGreen,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString()),
          backgroundColor: cRed,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cBg,
      body: Column(children: [
        QGradientHeader(
          title: tr('Реквизиты', 'Реквизиттер'),
          subtitle: tr('Карта для онлайн-оплат клиентов', 'Клиенттердің онлайн-төлем картасы'),
          compact: true,
          showBack: true,
        ),
        Expanded(
          child: _loading
              ? const Center(
                  child:
                      CircularProgressIndicator(color: cGreen, strokeWidth: 2))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: cBlueTint,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.info_outline_rounded,
                                color: cBlue, size: 18),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                tr('Этот номер карты видят клиенты при оплате онлайн-заказов. Все переводы поступают сюда, магазины подтверждают оплату по чеку.',
                                    'Бұл карта нөмірін клиенттер онлайн-заказ төлегенде көреді. Барлық аударым осында түседі, дүкендер төлемді чек арқылы растайды.'),
                                style: manrope(12.5, FontWeight.w500,
                                    color: cInk2),
                              ),
                            ),
                          ]),
                    ),
                    const SizedBox(height: 18),
                    _Field(
                      label: tr('Номер карты', 'Карта нөмірі'),
                      child: TextField(
                        controller: _numberCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [CardNumberFormatter()],
                        style: manrope(16, FontWeight.w700, color: cInk,
                            letterSpacing: 1),
                        decoration: _dec('0000 0000 0000 0000'),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _Field(
                      label: tr('Владелец карты', 'Карта иесі'),
                      child: TextField(
                        controller: _holderCtrl,
                        textCapitalization: TextCapitalization.words,
                        style: manrope(14.5, FontWeight.w600, color: cInk),
                        decoration: _dec(tr('Имя Фамилия', 'Аты Тегі')),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _Field(
                      label: tr('Банк', 'Банк'),
                      child: TextField(
                        controller: _bankCtrl,
                        style: manrope(14.5, FontWeight.w600, color: cInk),
                        decoration: _dec(tr('Например: Kaspi Gold', 'Мысалы: Kaspi Gold')),
                      ),
                    ),
                    const SizedBox(height: 24),
                    QPrimaryButton(
                      label: tr('Сохранить', 'Сақтау'),
                      isLoading: _saving,
                      onPressed: _saving ? null : _save,
                    ),
                  ],
                ),
        ),
      ]),
    );
  }

  InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: manrope(14, FontWeight.w500, color: cInk3),
        filled: true,
        fillColor: cSurface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: cLine),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: cLine),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: cGreen, width: 1.5),
        ),
      );
}

class _Field extends StatelessWidget {
  final String label;
  final Widget child;
  const _Field({required this.label, required this.child});

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: manrope(12.5, FontWeight.w700, color: cInk2)),
        const SizedBox(height: 6),
        child,
      ]);
}
