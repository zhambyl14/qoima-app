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
  final _kaspiCtrl = TextEditingController();
  String _mode = 'platform'; // 'platform' | 'store'
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
    _kaspiCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final card = await _service.getPaymentCard();
      final mode = await _service.getPaymentMode();
      if (!mounted) return;
      setState(() {
        _numberCtrl.text = formatCardDisplay(card.number);
        _holderCtrl.text = card.holder;
        _bankCtrl.text = card.bank;
        _kaspiCtrl.text = card.kaspiLink;
        _mode = mode;
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
        kaspiLink: _kaspiCtrl.text.trim(),
      ));
      await _service.savePaymentMode(_mode);
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
                    // ── Куда поступают деньги (режим) ─────────────────────────
                    Text(tr('Куда поступают деньги', 'Ақша қайда түседі'),
                        style: manrope(13, FontWeight.w800, color: cInk)),
                    const SizedBox(height: 10),
                    _ModeOption(
                      selected: _mode == 'platform',
                      icon: Icons.account_balance_rounded,
                      title: tr('На карту платформы', 'Платформа картасына'),
                      subtitle: tr(
                          'Все переводы приходят на карту ниже. Вы сами рассчитываетесь с магазинами.',
                          'Барлық аударым төмендегі картаға түседі. Дүкендермен өзіңіз есеп айырысасыз.'),
                      onTap: () => setState(() => _mode = 'platform'),
                    ),
                    const SizedBox(height: 10),
                    _ModeOption(
                      selected: _mode == 'store',
                      icon: Icons.storefront_rounded,
                      title: tr('На карту магазина', 'Дүкен картасына'),
                      subtitle: tr(
                          'Клиент платит напрямую магазину (его реквизиты из заявки). При заказе из нескольких магазинов — каждому отдельно. Если у магазина нет карты — платёж идёт на карту платформы.',
                          'Клиент тікелей дүкенге төлейді (өтінімдегі реквизиті). Бірнеше дүкеннен тапсырыс болса — әрқайсысына бөлек. Дүкенде карта болмаса — платформа картасына түседі.'),
                      onTap: () => setState(() => _mode = 'store'),
                    ),
                    const SizedBox(height: 20),
                    Text(tr('Карта платформы', 'Платформа картасы'),
                        style: manrope(13, FontWeight.w800, color: cInk)),
                    const SizedBox(height: 10),
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
                                _mode == 'store'
                                    ? tr('Резервная карта: используется, когда у магазина не указаны реквизиты.',
                                        'Резервтік карта: дүкеннің реквизиті болмағанда қолданылады.')
                                    : tr('Этот номер карты видят клиенты при оплате онлайн-заказов. Все переводы поступают сюда, магазины подтверждают оплату по чеку.',
                                        'Бұл карта нөмірін клиенттер онлайн-заказ төлегенде көреді. Барлық аударым осында түседі, дүкендер төлемді чек арқылы растайды.'),
                                style: manrope(12.5, FontWeight.w500,
                                    color: cInk2),
                              ),
                            ),
                          ]),
                    ),
                    const SizedBox(height: 18),
                    _Field(
                      label: tr('Ссылка Kaspi QR (основной способ)',
                          'Kaspi QR сілтемесі (негізгі тәсіл)'),
                      child: TextField(
                        controller: _kaspiCtrl,
                        keyboardType: TextInputType.url,
                        style: manrope(14, FontWeight.w600, color: cInk),
                        decoration:
                            _dec('https://pay.kaspi.kz/pay/...'),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _Field(
                      label: tr('Номер карты (запасной)', 'Карта нөмірі (қосымша)'),
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

class _ModeOption extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;
  const _ModeOption({
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected ? cGreenTint : cSurface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: selected ? cGreen : cLine,
                width: selected ? 1.5 : 1),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 22, color: selected ? cGreen : cInk3),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: manrope(14, FontWeight.w700,
                            color: selected ? cGreenDeep : cInk)),
                    const SizedBox(height: 3),
                    Text(subtitle,
                        style: manrope(12, FontWeight.w500, color: cInk2)),
                  ]),
            ),
            const SizedBox(width: 8),
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? cGreen : cSurface,
                border: Border.all(
                    color: selected ? cGreen : cLine, width: 2),
              ),
              child: selected
                  ? const Icon(Icons.check_rounded,
                      size: 13, color: Colors.white)
                  : null,
            ),
          ]),
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
