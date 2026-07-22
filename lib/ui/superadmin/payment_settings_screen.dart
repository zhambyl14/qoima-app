import 'package:flutter/material.dart';
import '../../core/lang.dart';
import '../../data/services/app_settings_service.dart';
import '../../theme/qoima_design.dart';
import '../shared/bank_qr_editor.dart';

/// Модератор: платформаның төлем реквизиттері. Барлық онлайн-заказ төлемдері
/// осы картаға аударылады — клиент checkout кезінде дәл осы нөмірді көреді.
class PaymentSettingsScreen extends StatefulWidget {
  const PaymentSettingsScreen({super.key});

  @override
  State<PaymentSettingsScreen> createState() => _PaymentSettingsScreenState();
}

class _PaymentSettingsScreenState extends State<PaymentSettingsScreen> {
  final _service = AppSettingsService();
  Map<String, String> _bankQrs = {}; // {bank_id: qr_link}
  String _mode = 'platform'; // 'platform' | 'store'
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final card = await _service.getPaymentCard();
      final mode = await _service.getPaymentMode();
      if (!mounted) return;
      setState(() {
        _bankQrs = Map.of(card.bankQrs);
        _mode = mode;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await _service.savePaymentCard(PaymentCardSettings(bankQrs: _bankQrs));
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
                    Text(
                        _mode == 'store'
                            ? tr('Резервные QR платформы', 'Платформаның резервтік QR-лары')
                            : tr('QR банков платформы', 'Платформаның банк QR-лары'),
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
                                    ? tr('Используются, когда у магазина не указаны QR.',
                                        'Дүкенде QR болмағанда қолданылады.')
                                    : tr('Клиенты видят эти QR при оплате онлайн-заказов и платят любым банком.',
                                        'Клиенттер осы QR-ларды онлайн-заказ төлегенде көріп, кез келген банкпен төлейді.'),
                                style: manrope(12.5, FontWeight.w500,
                                    color: cInk2),
                              ),
                            ),
                          ]),
                    ),
                    const SizedBox(height: 16),
                    BankQrEditor(
                      initial: _bankQrs,
                      onChanged: (m) => _bankQrs = m,
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

