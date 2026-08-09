import 'package:flutter/material.dart';
import '../../core/kz_cities.dart';
import '../../core/lang.dart';
import '../../data/models/delivery_tariff.dart';
import '../../data/services/app_settings_service.dart';
import '../../theme/qoima_design.dart';
import '../shared/bank_qr_editor.dart';
import '../../core/error_text.dart';

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

  final _waCtrl = TextEditingController();
  final _tgCtrl = TextEditingController();
  final _igCtrl = TextEditingController();

  // ── Жеткізу тарифі (0050) ──────────────────────────────────────────────────
  final _baseCtrl = TextEditingController();
  final _reducedCtrl = TextEditingController();
  final _fromCtrl = TextEditingController();
  final _extraCtrl = TextEditingController();
  final _fittingCtrl = TextEditingController();
  final _fittingMaxCtrl = TextEditingController();
  final _returnFeeCtrl = TextEditingController();

  /// Курьерлік қызмет іске қосылған қалалар (0055). БОС = барлық қалада.
  List<String> _courierCities = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _waCtrl.dispose();
    _tgCtrl.dispose();
    _igCtrl.dispose();
    _baseCtrl.dispose();
    _reducedCtrl.dispose();
    _fromCtrl.dispose();
    _extraCtrl.dispose();
    _fittingCtrl.dispose();
    _fittingMaxCtrl.dispose();
    _returnFeeCtrl.dispose();
    super.dispose();
  }

  /// Бос/қате мән әдепкіге қайтады — тариф ЕШҚАШАН 0-ге түспеуі керек
  /// (тегін жеткізу жол шығынын жаппайды).
  DeliveryTariff get _tariffFromFields {
    const d = DeliveryTariff();
    double num(TextEditingController c, double fallback) {
      final v = double.tryParse(c.text.trim().replaceAll(',', '.'));
      return (v == null || v < 0) ? fallback : v;
    }

    final base = num(_baseCtrl, d.baseFee);
    return DeliveryTariff(
      baseFee: base <= 0 ? d.baseFee : base,
      reducedFee: num(_reducedCtrl, d.reducedFee),
      reducedFrom: num(_fromCtrl, d.reducedFrom),
      extraStorePercent:
          num(_extraCtrl, d.extraStorePercent.toDouble()).clamp(0, 100).round(),
      fittingFee: num(_fittingCtrl, d.fittingFee),
      fittingMaxItems:
          num(_fittingMaxCtrl, d.fittingMaxItems.toDouble()).clamp(1, 5).round(),
      returnFee: num(_returnFeeCtrl, d.returnFee),
      courierCities: _courierCities,
    );
  }

  Future<void> _load() async {
    try {
      final card = await _service.getPaymentCard();
      final mode = await _service.getPaymentMode();
      final contacts = await _service.getContactSettings();
      final tariff = await _service.getDeliveryTariff();
      if (!mounted) return;
      setState(() {
        _bankQrs = Map.of(card.bankQrs);
        _mode = mode;
        _waCtrl.text = contacts.whatsapp;
        _tgCtrl.text = contacts.telegram;
        _igCtrl.text = contacts.instagram;
        _baseCtrl.text = tariff.baseFee.toStringAsFixed(0);
        _reducedCtrl.text = tariff.reducedFee.toStringAsFixed(0);
        _fromCtrl.text = tariff.reducedFrom.toStringAsFixed(0);
        _extraCtrl.text = '${tariff.extraStorePercent}';
        _fittingCtrl.text = tariff.fittingFee.toStringAsFixed(0);
        _fittingMaxCtrl.text = '${tariff.fittingMaxItems}';
        _returnFeeCtrl.text = tariff.returnFee.toStringAsFixed(0);
        _courierCities = List.of(tariff.courierCities);
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
      await _service.saveContactSettings(ContactSettings(
        whatsapp: _waCtrl.text.trim(),
        telegram: _tgCtrl.text.trim().replaceFirst('@', ''),
        instagram: _igCtrl.text.trim().replaceFirst('@', ''),
      ));
      await _service.saveDeliveryTariff(_tariffFromFields);
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
          content: Text(friendlyError(e)),
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
          subtitle: tr('Оплата, контакты, тариф доставки',
              'Төлем, байланыс, жеткізу тарифі'),
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
                    const SizedBox(height: 28),
                    Text(tr('Контакты приложения', 'Қолданба байланысы'),
                        style: manrope(13, FontWeight.w800, color: cInk)),
                    const SizedBox(height: 4),
                    Text(
                        tr('Профиль экранындағы «Байланыс» карточкасында клиенттерге/сатушыларға көрінеді.',
                            'Профиль экранындағы «Байланыс» карточкасында клиенттерге/сатушыларға көрінеді.'),
                        style: manrope(12, FontWeight.w500, color: cInk3)),
                    const SizedBox(height: 12),
                    _ContactField(
                      icon: Icons.chat_rounded,
                      label: 'WhatsApp',
                      hint: '+7 700 000 00 00',
                      controller: _waCtrl,
                    ),
                    const SizedBox(height: 10),
                    _ContactField(
                      icon: Icons.send_rounded,
                      label: 'Telegram',
                      hint: 'username',
                      controller: _tgCtrl,
                    ),
                    const SizedBox(height: 10),
                    _ContactField(
                      icon: Icons.camera_alt_rounded,
                      label: 'Instagram',
                      hint: 'username',
                      controller: _igCtrl,
                    ),
                    const SizedBox(height: 28),
                    // ── Жеткізу тарифі ─────────────────────────────────────
                    Text(tr('Доставка курьером', 'Курьер жеткізуі'),
                        style: manrope(13, FontWeight.w800, color: cInk)),
                    const SizedBox(height: 4),
                    Text(
                        tr('Клиент платит это вместе с заказом — деньги приходят туда же, куда и оплата. Бесплатной доставки нет: она не окупает дорогу и провоцирует отказы.',
                            'Клиент мұны тапсырыспен бірге төлейді — ақша төлеммен бір жерге түседі. Тегін жеткізу жоқ: ол жол шығынын жаппайды әрі бас тартуды көбейтеді.'),
                        style: manrope(12, FontWeight.w500,
                            color: cInk3, height: 1.4)),
                    const SizedBox(height: 12),
                    _NumField(
                      icon: Icons.local_shipping_outlined,
                      label: tr('Базовая', 'Базалық'),
                      suffix: '₸',
                      hint: '690',
                      controller: _baseCtrl,
                      onChanged: () => setState(() {}),
                    ),
                    const SizedBox(height: 10),
                    _NumField(
                      icon: Icons.trending_down_rounded,
                      label: tr('Со скидкой', 'Жеңілдікпен'),
                      suffix: '₸',
                      hint: '390',
                      controller: _reducedCtrl,
                      onChanged: () => setState(() {}),
                    ),
                    const SizedBox(height: 10),
                    _NumField(
                      icon: Icons.attach_money_rounded,
                      label: tr('От суммы', 'Сомадан'),
                      suffix: '₸',
                      hint: '15000',
                      controller: _fromCtrl,
                      onChanged: () => setState(() {}),
                    ),
                    const SizedBox(height: 10),
                    _NumField(
                      icon: Icons.storefront_outlined,
                      label: tr('2-й магазин', '2-ші дүкен'),
                      suffix: '%',
                      hint: '50',
                      controller: _extraCtrl,
                      onChanged: () => setState(() {}),
                    ),
                    const SizedBox(height: 10),
                    _NumField(
                      icon: Icons.checkroom_rounded,
                      label: tr('Примерка', 'Өлшеп көру'),
                      suffix: '₸',
                      hint: '300',
                      controller: _fittingCtrl,
                      onChanged: () => setState(() {}),
                    ),
                    const SizedBox(height: 10),
                    _NumField(
                      icon: Icons.numbers_rounded,
                      label: tr('Примерок макс.', 'Өлшеу макс.'),
                      suffix: tr('шт', 'дана'),
                      hint: '2',
                      controller: _fittingMaxCtrl,
                      onChanged: () => setState(() {}),
                    ),
                    const SizedBox(height: 10),
                    _NumField(
                      icon: Icons.u_turn_left_rounded,
                      label: tr('Возврат курьером', 'Курьермен қайтару'),
                      suffix: '₸',
                      hint: '1500',
                      controller: _returnFeeCtrl,
                      onChanged: () => setState(() {}),
                    ),
                    const SizedBox(height: 16),
                    _CourierCitiesEditor(
                      cities: _courierCities,
                      onChanged: (list) =>
                          setState(() => _courierCities = list),
                    ),
                    const SizedBox(height: 12),
                    _TariffPreview(tariff: _tariffFromFields),
                    const SizedBox(height: 12),
                    const _MoneySplitCard(),
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

/// Курьерлік қызмет ІСКЕ ҚОСЫЛҒАН қалалар (0055, 0057).
///
/// ҚОСУЛЫ қалада жеткізуді де, возврат тасымалын да платформа курьері
/// орындайды: клиент себетте жеткізу ақысын көреді, тапсырыс расталған соң
/// курьерге түседі. ӨШІРУЛІ қалада курьер мүлде көрінбейді — жеткізу ақысы
/// да жоқ, дүкен клиентпен өзі келіседі (өзі апарады не жөнелту қызметімен
/// жібереді), возратты да клиент өзі әкеледі.
///
/// ⚠️ БОС ТІЗІМ = ЕШБІР ҚАЛАДА КУРЬЕР ЖОҚ. 0055-те керісінше болатын («бос =
/// бәрінде қосулы»), содан модератор тізімді толтырғанша клиенттерге жоқ
/// курьердің ақысы көрсетіліп тұратын. Серверде де сол ереже
/// (`courier_city_enabled`, 0057) — екеуі бір ақиқатты айтуы керек.
///
/// НЕГЕ ТІЗІМНЕН ТАҢДАУ: бұрын мұнда қолмен теру өрісі тұрған. Қала атауы
/// дүкеннің `stores.city` мәнімен ӘРІПКЕ ДЕЙІН дәл келуі керек, ал ол әрқашан
/// [kzCities] тізімінен алынады — қолмен терген «Алматы қ.» немесе «Almaty»
/// ешқашан сәйкес келмей, курьер үнсіз өшіп қалатын.
class _CourierCitiesEditor extends StatelessWidget {
  final List<String> cities;
  final ValueChanged<List<String>> onChanged;
  const _CourierCitiesEditor({required this.cities, required this.onChanged});

  bool _has(String city) =>
      cities.any((c) => c.trim().toLowerCase() == city.trim().toLowerCase());

  void _toggle(String city) {
    if (_has(city)) {
      onChanged(cities
          .where((c) => c.trim().toLowerCase() != city.trim().toLowerCase())
          .toList());
    } else {
      onChanged([...cities, city]);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Тізімде жоқ, бірақ бұрын сақталған қалалар да көрінуі керек — әйтпесе
    // модератор оларды өшіре де алмайды.
    final extra = cities
        .where((c) => !kzCities
            .any((k) => k.toLowerCase() == c.trim().toLowerCase()))
        .toList();
    final all = [...kzCities, ...extra];
    final none = cities.isEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: none ? cAmber : cLine),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.map_rounded, size: 17, color: none ? cAmber : cGreen),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
                tr('Города с курьерской службой',
                    'Курьерлік қызмет бар қалалар'),
                style: manrope(13.5, FontWeight.w800, color: cInk)),
          ),
          Text('${cities.length}/${all.length}',
              style: manrope(12, FontWeight.w800, color: cInk3)),
        ]),
        const SizedBox(height: 6),
        Text(
          none
              ? tr('Не выбрано ни одного города — курьеров НЕТ НИГДЕ. Клиенты не видят стоимость доставки, магазины договариваются сами.',
                  'Бірде-бір қала таңдалмаған — курьер ЕШҚАЙДА жоқ. Клиенттер жеткізу ақысын көрмейді, дүкендер өздері келіседі.')
              : tr('Курьеры работают только в отмеченных городах. В остальных магазин доставляет сам, а возврат клиент привозит сам.',
                  'Курьерлер тек белгіленген қалаларда жұмыс істейді. Қалғанында дүкен өзі жеткізеді, қайтарымды клиент өзі әкеледі.'),
          style: manrope(11.5, FontWeight.w600,
              color: none ? cAmber : cInk3, height: 1.35),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: all.map((c) {
            final on = _has(c);
            return GestureDetector(
              onTap: () => _toggle(c),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                padding: const EdgeInsets.fromLTRB(10, 7, 12, 7),
                decoration: BoxDecoration(
                  color: on ? cGreenTint : cBg,
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: on ? cGreen : cLine),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(
                      on
                          ? Icons.check_circle_rounded
                          : Icons.circle_outlined,
                      size: 15,
                      color: on ? cGreen : cInk3),
                  const SizedBox(width: 6),
                  Text(trValue(c),
                      style: manrope(12.5, FontWeight.w700,
                          color: on ? cGreenDeep : cInk2)),
                ]),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: GestureDetector(
              onTap: () => onChanged(List.of(kzCities)),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: cBg, borderRadius: BorderRadius.circular(11)),
                child: Text(tr('Отметить все', 'Барлығын белгілеу'),
                    style: manrope(12, FontWeight.w800, color: cInk2)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: GestureDetector(
              onTap: cities.isEmpty ? null : () => onChanged(const []),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: cBg, borderRadius: BorderRadius.circular(11)),
                child: Text(tr('Снять все', 'Барлығын алу'),
                    style: manrope(12, FontWeight.w800,
                        color: cities.isEmpty ? cInk3 : cRed)),
              ),
            ),
          ),
        ]),
      ]),
    );
  }
}

class _ContactField extends StatelessWidget {
  final IconData icon;
  final String label, hint;
  final TextEditingController controller;
  const _ContactField({
    required this.icon,
    required this.label,
    required this.hint,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: cSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cLine),
        ),
        child: Row(children: [
          Icon(icon, size: 18, color: cInk3),
          const SizedBox(width: 10),
          SizedBox(
            width: 78,
            child: Text(label,
                style: manrope(13, FontWeight.w700, color: cInk)),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              style: manrope(14, FontWeight.w600, color: cInk),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: manrope(13, FontWeight.w500, color: cInk3),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ]),
      );
}

// ── Сан өрісі (тариф) ─────────────────────────────────────────────────────────
class _NumField extends StatelessWidget {
  final IconData icon;
  final String label, suffix, hint;
  final TextEditingController controller;
  final VoidCallback onChanged;
  const _NumField({
    required this.icon,
    required this.label,
    required this.suffix,
    required this.hint,
    required this.controller,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: cSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cLine),
        ),
        child: Row(children: [
          Icon(icon, size: 18, color: cInk3),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label,
                style: manrope(13, FontWeight.w700, color: cInk)),
          ),
          SizedBox(
            width: 88,
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.right,
              onChanged: (_) => onChanged(),
              style: manrope(15, FontWeight.w800, color: cInk),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: manrope(14, FontWeight.w600, color: cInk3),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(width: 5),
          SizedBox(
            width: 34,
            child: Text(suffix,
                style: manrope(12.5, FontWeight.w700, color: cInk3)),
          ),
        ]),
      );
}

/// Тариф қалай жұмыс істейтінін модератор БІРДЕН көреді — сандарды соқыр
/// енгізіп, «неге 1035 ₸ шықты?» деп таңданбауы үшін.
class _TariffPreview extends StatelessWidget {
  final DeliveryTariff tariff;
  const _TariffPreview({required this.tariff});

  @override
  Widget build(BuildContext context) {
    final small = tariff.totalFee(orderTotal: 5000, storeCount: 1);
    final big = tariff.totalFee(
        orderTotal: tariff.reducedFrom + 1000, storeCount: 1);
    final two = tariff.totalFee(orderTotal: 5000, storeCount: 2);
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: cGreenTint,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr('Как получится у клиента', 'Клиентте қалай шығады'),
            style: manrope(12, FontWeight.w800, color: cGreenDeep)),
        const SizedBox(height: 7),
        _line(tr('Заказ 5 000 ₸, 1 магазин', 'Тапсырыс 5 000 ₸, 1 дүкен'), small),
        _line(
            tr('Заказ ${money(tariff.reducedFrom + 1000)}, 1 магазин',
                'Тапсырыс ${money(tariff.reducedFrom + 1000)}, 1 дүкен'),
            big),
        _line(tr('Заказ 5 000 ₸, 2 магазина', 'Тапсырыс 5 000 ₸, 2 дүкен'), two),
        _line(tr('+ примерка', '+ өлшеп көру'), tariff.fittingFee),
      ]),
    );
  }

  Widget _line(String label, double value) => Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Row(children: [
          Expanded(
            child: Text(label,
                style: manrope(11.5, FontWeight.w600, color: cGreenDeep)),
          ),
          Text(money(value),
              style: manrope(12.5, FontWeight.w800, color: cGreenDeep)),
        ]),
      );
}

/// Ақшаның кімге тиесілі екені — модератор бір қарап есіне түсіруі үшін.
/// Бұл жүйедегі ЕҢ жиі шатасатын нәрсе, сондықтан баптау экранында тұрады.
class _MoneySplitCard extends StatelessWidget {
  const _MoneySplitCard();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: cSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cLine),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr('Кому какие деньги', 'Қай ақша кімдікі'),
              style: manrope(12.5, FontWeight.w800, color: cInk)),
          const SizedBox(height: 8),
          _row(Icons.storefront_rounded, 'green',
              tr('Товар', 'Тауар'),
              tr('магазину · переводом', 'дүкенге · аударыммен')),
          _row(Icons.checkroom_rounded, 'green',
              tr('Примерка', 'Өлшеп көру'),
              tr('магазину · переводом', 'дүкенге · аударыммен')),
          _row(Icons.delivery_dining_rounded, 'amber',
              tr('Доставка', 'Жеткізу'),
              tr('курьеру · наличными', 'курьерге · қолма-қол')),
          _row(Icons.u_turn_left_rounded, 'amber',
              tr('Возврат курьером', 'Курьермен қайтару'),
              tr('курьеру · наличными', 'курьерге · қолма-қол')),
          const SizedBox(height: 8),
          Text(
              tr('Клиент делает ДВА платежа: перевод магазину (товар + примерка) и наличные курьеру (доставка). Деньги курьера через кассу магазина НЕ проходят и в его выручку не попадают. Стоимость возврата НЕ вычитается из суммы, которую возвращают клиенту.',
                  'Клиент ЕКІ төлем жасайды: дүкенге аударым (тауар + өлшеп көру) және курьерге қолма-қол (жеткізу). Курьердің ақшасы дүкеннің кассасынан ӨТПЕЙДІ әрі оның түсіміне кірмейді. Қайтару ақысы клиентке қайтарылатын сомадан ШЕГЕРІЛМЕЙДІ.'),
              style: manrope(11, FontWeight.w600, color: cInk3, height: 1.4)),
        ]),
      );

  Widget _row(IconData icon, String tone, String what, String toWhom) {
    final color = switch (tone) {
      'green' => cGreen,
      'amber' => cAmber,
      _ => cBlue,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(what,
              style: manrope(12, FontWeight.w600, color: cInk2)),
        ),
        Text('→ $toWhom',
            style: manrope(12, FontWeight.w800, color: color)),
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

