import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/lang.dart';
import '../../data/models/order_model.dart';
import '../../theme/qoima_design.dart';

/// Курьердің тапсырыс карточкасы. Күйіне қарай әрекеттер өзгереді:
///   бос           → [onTake]
///   assigned      → [onPickup] (қойма кодымен) · [onDrop]
///   picked_up     → [onDeliver] (өлшеп көру свопымен) · [onReturn]
///   аяқталған     → әрекетсіз, тарих
class CourierOrderCard extends StatelessWidget {
  final OrderModel order;
  final VoidCallback? onTake;
  final void Function(String code)? onPickup;
  /// [swappedIndexes] — примерка свопы; [feeCollected] — жеткізу ақысын
  /// клиенттен алды ма (ақша курьердікі, есеп ашық болуы үшін сұралады).
  final void Function(List<int> swappedIndexes, bool feeCollected)? onDeliver;
  /// [reason] — бас тарту себебі; [feeCollected] — жол ақысын алды ма.
  final void Function(String reason, bool feeCollected)? onReturn;
  final VoidCallback? onDrop;

  const CourierOrderCard({
    super.key,
    required this.order,
    this.onTake,
    this.onPickup,
    this.onDeliver,
    this.onReturn,
    this.onDrop,
  });

  bool get _isAssigned => order.courierStatus == OrderModel.courierAssigned;
  bool get _isPickedUp => order.courierStatus == OrderModel.courierPickedUp;
  bool get _isDone => order.status != OrderModel.statusConfirmed;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cSurface,
        borderRadius: BorderRadius.circular(18),
        // Қоймаға қайтаруы керек өлшем бар болса — карточка АЙҚЫН ерекшеленеді:
        // курьердің миссиясы әлі бітпеген.
        border: Border.all(
            color: order.returnLegPending
                ? cAmber
                : (_isPickedUp ? cGreen.withValues(alpha: 0.45) : cLine),
            width: order.returnLegPending ? 2 : 1),
        boxShadow: kShadowSm,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Миссия жабылмаған: ең үстінде, елеусіз қалмайтындай ─────────────
        if (order.returnLegPending)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: const BoxDecoration(
              color: cAmber,
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(children: [
              const Icon(Icons.priority_high_rounded,
                  color: Colors.white, size: 17),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                    tr('ОТВЕЗИТЕ РАЗМЕР НА СКЛАД — заказ ещё не закрыт',
                        'ӨЛШЕМДІ ҚОЙМАҒА АПАРЫҢЫЗ — тапсырыс әлі жабылмаған'),
                    style: manrope(11.5, FontWeight.w800, color: Colors.white)),
              ),
            ]),
          ),
        // ── Шапка: нөмір + күй + сома ────────────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
          decoration: BoxDecoration(
            color: _statusColor.withValues(alpha: 0.08),
            borderRadius: order.returnLegPending
                ? BorderRadius.zero
                : const BorderRadius.vertical(top: Radius.circular(18)),
          ),
          child: Row(children: [
            QPill(_statusLabel, tone: _statusTone),
            const SizedBox(width: 8),
            Text('№${order.orderNumber}',
                style: manrope(13, FontWeight.w800, color: cInk2)),
            const Spacer(),
            // ⚠️ ТҮЗЕТУ (0053): бұрын мұнда deliveryFee + fittingFee тұрған —
            // курьер «өлшеп көру» ақысын да өзінікі деп ойлайтын. Ол ақы
            // ДҮКЕНДІКІ (екінші жұп оның қоймасынан шығады). Курьерге тек
            // жеткізу ақысы тиесілі.
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(money(order.deliveryFee),
                  style: manrope(15, FontWeight.w800, color: cGreenDeep)),
              Text(tr('вам от клиента', 'клиенттен сізге'),
                  style: manrope(9.5, FontWeight.w700, color: cInk3)),
            ]),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Қоймадан алу ────────────────────────────────────────────
                _AddressRow(
                  icon: Icons.storefront_rounded,
                  tone: 'amber',
                  title: order.storeName,
                  subtitle: order.warehouseAddress.isEmpty
                      ? tr('Адрес склада не указан', 'Қойма мекенжайы жоқ')
                      : order.warehouseAddress,
                  phone: order.storePhone,
                ),
                const SizedBox(height: 10),
                // ── Клиентке жеткізу ────────────────────────────────────────
                _AddressRow(
                  icon: Icons.person_pin_circle_rounded,
                  tone: 'green',
                  title: order.clientName.isEmpty
                      ? tr('Клиент', 'Клиент')
                      : order.clientName,
                  subtitle: order.address,
                  phone: order.clientPhone,
                ),
                if (order.note.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                        color: cBg, borderRadius: BorderRadius.circular(11)),
                    child: Row(children: [
                      const Icon(Icons.sticky_note_2_outlined,
                          size: 15, color: cInk3),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(order.note,
                            style: manrope(12, FontWeight.w600, color: cInk2)),
                      ),
                    ]),
                  ),
                ],
                const SizedBox(height: 12),
                // ── Тауарлар (курьер нақты нені алатынын көреді) ────────────
                ...order.items.map((i) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(children: [
                        const Icon(Icons.check_box_outline_blank_rounded,
                            size: 15, color: cInk3),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text('${i.productName} · ${i.size}',
                              style: manrope(12.5, FontWeight.w600,
                                  color: cInk),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ),
                        if (i.hasAltSize)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: cAmberTint,
                              borderRadius: BorderRadius.circular(7),
                            ),
                            child: Text(
                                tr('+ ${i.altSize} на примерку',
                                    '+ ${i.altSize} өлшеуге'),
                                style: manrope(10.5, FontWeight.w800,
                                    color: cAmber)),
                          ),
                        Text('  ×${i.qty}',
                            style:
                                manrope(12, FontWeight.w700, color: cInk3)),
                      ]),
                    )),
                if (order.hasFitting) ...[
                  const SizedBox(height: 4),
                  Text(
                      tr('Возьмите оба размера — клиент примерит на месте',
                          'Екі өлшемді де алыңыз — клиент орнында өлшейді'),
                      style: manrope(11.5, FontWeight.w700, color: cAmber)),
                ],
                // Миссия әлі бітпеді: клиент таңдамаған өлшемді қоймаға
                // апару керек. Дүкен «қабылдадым» дегенде ғана жабылады —
                // сондықтан курьерге бұл еске салғыш ретінде тұрады.
                if (order.returnLegPending) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      color: cBlueTint,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.u_turn_left_rounded,
                              color: cBlue, size: 17),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                      tr('Вернуть на склад',
                                          'Қоймаға қайтару керек'),
                                      style: manrope(12, FontWeight.w800,
                                          color: cInk)),
                                  ...order.returnLeg.map((r) => Text(
                                      '${r.productName} · ${r.size} × ${r.qty}',
                                      style: manrope(11.5, FontWeight.w600,
                                          color: cInk2))),
                                  const SizedBox(height: 2),
                                  Text(
                                      tr('Магазин подтвердит приём — тогда миссия закроется',
                                          'Дүкен қабылдағанда миссия жабылады'),
                                      style: manrope(10.5, FontWeight.w600,
                                          color: cInk3)),
                                ]),
                          ),
                        ]),
                  ),
                ],
                if (order.returnLegDone) ...[
                  const SizedBox(height: 10),
                  Row(children: [
                    const Icon(Icons.check_circle_rounded,
                        color: cGreen, size: 16),
                    const SizedBox(width: 7),
                    Text(tr('Возврат сдан на склад', 'Қайтарым қоймаға тапсырылды'),
                        style: manrope(11.5, FontWeight.w700, color: cGreen)),
                  ]),
                ],
                if (!_isDone) ...[
                  const SizedBox(height: 14),
                  _actions(context),
                ],
              ]),
        ),
      ]),
    );
  }

  // ── Әрекет батырмалары ──────────────────────────────────────────────────────
  Widget _actions(BuildContext context) {
    if (onTake != null) {
      return QPrimaryButton(
          label: tr('Взять заказ', 'Тапсырысты алу'),
          onPressed: onTake,
          height: 46);
    }
    if (_isAssigned) {
      return Column(children: [
        QPrimaryButton(
          label: tr('Забрал со склада', 'Қоймадан алдым'),
          onPressed: () => _askPickupCode(context),
          height: 46,
        ),
        if (onDrop != null)
          TextButton(
            onPressed: onDrop,
            child: Text(tr('Отказаться от заказа', 'Тапсырыстан бас тарту'),
                style: manrope(13, FontWeight.w600, color: cInk3)),
          ),
      ]);
    }
    if (_isPickedUp) {
      return Column(children: [
        QPrimaryButton(
          label: tr('Передал клиенту', 'Клиентке бердім'),
          onPressed: () => _handOver(context),
          height: 46,
        ),
        // «Өлшеп көру» тапсырысында бас тарту жолы ЖОҚ: клиент екі өлшемнің
        // біреуін МІНДЕТТІ түрде алады, екіншісі қоймаға қайтады. Сондықтан
        // мұнда тек примеркасыз тапсырыс үшін ғана бас тарту қалады
        // (клиент үйде жоқ / байланысқа шықпады деген нақты жағдайлар).
        if (onReturn != null && !order.hasFitting)
          TextButton(
            onPressed: () => _askReturnReason(context),
            child: Text(tr('Клиент отказался', 'Клиент бас тартты'),
                style: manrope(13, FontWeight.w600, color: cRed)),
          ),
      ]);
    }
    return const SizedBox.shrink();
  }

  /// Қойма кодын сұрау — курьердің дүкенге НАҚТЫ келгенінің дәлелі
  /// (кодты дүкен өз экранынан көрсетеді).
  Future<void> _askPickupCode(BuildContext context) async {
    final ctrl = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(tr('Код со склада', 'Қойма коды'),
            style: manrope(16, FontWeight.w800, color: cInk)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
              tr('Попросите продавца показать 6-значный код заказа и введите его.',
                  'Сатушыдан тапсырыстың 6 сандық кодын көрсетуін сұрап, енгізіңіз.'),
              style: manrope(13, FontWeight.w500, color: cInk2, height: 1.4)),
          const SizedBox(height: 14),
          // Код — ӘРҚАШАН 6 сан (client_service._generatePickupCode).
          // Бұрын hint «QM-XXXX» тұрған да, курьер әріпті код іздейтін.
          TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: TextInputType.number,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: manrope(24, FontWeight.w800, color: cInk, letterSpacing: 6),
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              counterText: '',
              hintText: '000000',
              hintStyle:
                  manrope(24, FontWeight.w700, color: cInk3, letterSpacing: 6),
              filled: true,
              fillColor: cBg,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
            ),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(tr('Отмена', 'Болдырмау'),
                  style: manrope(14, FontWeight.w600, color: cInk2))),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              style: ElevatedButton.styleFrom(
                  backgroundColor: cGreen, foregroundColor: Colors.white),
              child: Text(tr('Подтвердить', 'Растау'))),
        ],
      ),
    );
    ctrl.dispose();
    if (code != null && code.isNotEmpty) onPickup?.call(code);
  }

  /// Клиентке беру. Екі нәрсе бір ағында бекітіледі:
  ///   1) «Өлшеп көру» болса — клиент қай өлшемді алды (38 ме, 39 ба);
  ///   2) жеткізу ақысын клиенттен алды ма — ақша курьердікі, сондықтан оны
  ///      курьердің өзі растайды (есеп ашық болу үшін).
  Future<void> _handOver(BuildContext context) async {
    final fittingIdx = <int>[];
    for (var i = 0; i < order.items.length; i++) {
      if (order.items[i].hasAltSize) fittingIdx.add(i);
    }

    final result = await showModalBottomSheet<_HandOverResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _HandOverSheet(order: order, fittingIdx: fittingIdx),
    );
    if (result != null) {
      onDeliver?.call(result.swaps, result.feeCollected);
    }
  }

  /// Клиент бас тартты. Себебімен қатар жол ақысын алған-алмағаны да
  /// сұралады — тапсырыс жабылады, ал ақшаның есебі ашық қалуы керек.
  Future<void> _askReturnReason(BuildContext context) async {
    final ctrl = TextEditingController();
    // ⚠️ Күй builder-дің СЫРТЫНДА тұруы керек — әйтпесе әр қайта салуда
    // әдепкіге қайтып, курьердің таңдауы жоғалады.
    var feeCollected = true;
    final res = await showDialog<({String reason, bool fee})>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setInner) {
          return AlertDialog(
            backgroundColor: cSurface,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text(tr('Клиент отказался', 'Клиент бас тартты'),
                style: manrope(16, FontWeight.w800, color: cInk)),
            content:
                Column(mainAxisSize: MainAxisSize.min, children: [
              Text(
                  tr('Товар вернётся на склад. Стоимость доставки клиенту не возвращается — вы уже съездили.',
                      'Тауар қоймаға оралады. Жеткізу ақысы клиентке қайтарылмайды — сіз барып қайттыңыз.'),
                  style:
                      manrope(13, FontWeight.w500, color: cInk2, height: 1.4)),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                autofocus: true,
                style: manrope(14, FontWeight.w600, color: cInk),
                decoration: InputDecoration(
                  hintText: tr('Причина (не подошёл размер…)',
                      'Себебі (өлшемі келмеді…)'),
                  hintStyle: manrope(13.5, FontWeight.w500, color: cInk3),
                  filled: true,
                  fillColor: cBg,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none),
                ),
              ),
              if (order.deliveryFee > 0) ...[
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: _FeeChoice(
                      label: tr('Заплатил', 'Төледі'),
                      amount: money(order.deliveryFee),
                      tone: 'green',
                      selected: feeCollected,
                      onTap: () => setInner(() => feeCollected = true),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: _FeeChoice(
                      label: tr('Не заплатил', 'Төлемеді'),
                      amount: tr('долг', 'қарыз'),
                      tone: 'red',
                      selected: !feeCollected,
                      onTap: () => setInner(() => feeCollected = false),
                    ),
                  ),
                ]),
              ],
            ]),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(tr('Отмена', 'Болдырмау'),
                      style: manrope(14, FontWeight.w600, color: cInk2))),
              ElevatedButton(
                  onPressed: () => Navigator.pop(
                      ctx, (reason: ctrl.text.trim(), fee: feeCollected)),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: cRed, foregroundColor: Colors.white),
                  child: Text(tr('Вернуть', 'Қайтару'))),
            ],
          );
      }),
    );
    ctrl.dispose();
    if (res != null) onReturn?.call(res.reason, res.fee);
  }

  Color get _statusColor => _isDone
      ? (order.status == OrderModel.statusCompleted ? cGreen : cRed)
      : (_isPickedUp ? cGreen : cAmber);

  String get _statusTone => _isDone
      ? (order.status == OrderModel.statusCompleted ? 'green' : 'red')
      : (_isPickedUp ? 'green' : 'amber');

  String get _statusLabel {
    if (order.status == OrderModel.statusCompleted) {
      return tr('Доставлен', 'Жеткізілді');
    }
    if (order.status == OrderModel.statusCancelled) {
      return tr('Возврат', 'Қайтарылды');
    }
    if (_isPickedUp) return tr('В пути', 'Жолда');
    if (_isAssigned) return tr('Забрать со склада', 'Қоймадан алу');
    return tr('Свободен', 'Бос');
  }
}

// ── Мекенжай жолы (соғу нүктесі) ──────────────────────────────────────────────
class _AddressRow extends StatelessWidget {
  final IconData icon;
  final String tone, title, subtitle, phone;
  const _AddressRow({
    required this.icon,
    required this.tone,
    required this.title,
    required this.subtitle,
    required this.phone,
  });

  Future<void> _call() async {
    if (phone.isEmpty) return;
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _map() async {
    if (subtitle.isEmpty) return;
    // Геокодтау серверде жоқ — сыртқы картаға мәтіндік іздеу сұранысын береміз.
    final uri = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(subtitle)}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          QIconTile(
            icon: Icon(icon,
                color: tone == 'green' ? cGreen : cAmber, size: 17),
            tone: tone,
            size: 36,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              onTap: _map,
              onLongPress: () {
                Clipboard.setData(ClipboardData(text: subtitle));
                HapticFeedback.lightImpact();
              },
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: manrope(13.5, FontWeight.w800, color: cInk),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    Text(subtitle,
                        style: manrope(12, FontWeight.w600, color: cInk2,
                            height: 1.3)),
                  ]),
            ),
          ),
          if (phone.isNotEmpty)
            GestureDetector(
              onTap: _call,
              child: Container(
                width: 34,
                height: 34,
                margin: const EdgeInsets.only(left: 8),
                decoration: BoxDecoration(
                  color: cGreenTint,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(Icons.call_rounded,
                    color: cGreenDeep, size: 17),
              ),
            ),
        ],
      );
}

// ── Клиентке беру нәтижесі ────────────────────────────────────────────────────
class _HandOverResult {
  final List<int> swaps;
  final bool feeCollected;
  const _HandOverResult(this.swaps, this.feeCollected);
}

/// «Клиентке бердім» парағы: примерка қорытындысы + жеткізу ақысының есебі.
///
/// Екеуі БІР экранда — курьер бір рет ғана растайды да, ақша мен қойма
/// қозғалысы бір транзакцияда тіркеледі.
class _HandOverSheet extends StatefulWidget {
  final OrderModel order;
  final List<int> fittingIdx;
  const _HandOverSheet({required this.order, required this.fittingIdx});

  @override
  State<_HandOverSheet> createState() => _HandOverSheetState();
}

class _HandOverSheetState extends State<_HandOverSheet> {
  /// index → қосалқы өлшем алынды ма (true = своп).
  final Map<int, bool> _tookAlt = {};
  bool _feeCollected = true;

  /// Клиент таңдамаған, қоймаға апарылатын өлшемдер (алдын ала көрсету).
  List<String> get _willReturn {
    final out = <String>[];
    for (final i in widget.fittingIdx) {
      final item = widget.order.items[i];
      final tookAlt = _tookAlt[i] ?? false;
      out.add('${item.productName} · ${tookAlt ? item.size : item.altSize}');
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    final hasFitting = widget.fittingIdx.isNotEmpty;

    return Container(
      constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9),
      decoration: const BoxDecoration(
        color: cSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, MediaQuery.of(context).padding.bottom + 20),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 18),
            decoration: BoxDecoration(
                color: cLine, borderRadius: BorderRadius.circular(2)),
          ),
          Text(tr('Передача клиенту', 'Клиентке беру'),
              style: manrope(17, FontWeight.w800, color: cInk)),
          const SizedBox(height: 14),

          // ── 1) Примерка: клиент қай өлшемді алды ─────────────────────────
          if (hasFitting) ...[
            _sectionLabel(
                tr('1. Какой размер взял клиент?', '1. Клиент қай өлшемді алды?')),
            const SizedBox(height: 8),
            ...widget.fittingIdx.map((i) {
              final item = widget.order.items[i];
              final tookAlt = _tookAlt[i] ?? false;
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cBg,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.productName,
                          style: manrope(13.5, FontWeight.w800, color: cInk),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 9),
                      Row(children: [
                        Expanded(
                          child: _SizeChoice(
                            size: item.size,
                            label: tr('Заказанный', 'Тапсырыс берген'),
                            selected: !tookAlt,
                            onTap: () => setState(() => _tookAlt[i] = false),
                          ),
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: _SizeChoice(
                            size: item.altSize,
                            label: tr('Запасной', 'Қосалқы'),
                            selected: tookAlt,
                            onTap: () => setState(() => _tookAlt[i] = true),
                          ),
                        ),
                      ]),
                    ]),
              );
            }),
            // Екінші өлшемнің тағдыры — БІРДЕН, растауға дейін көрінеді.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: cAmberTint,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cAmber.withValues(alpha: 0.5)),
              ),
              child:
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.u_turn_left_rounded, color: cAmber, size: 17),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                        tr('Второй размер вы обязаны отвезти на склад',
                            'Екінші өлшемді қоймаға апаруыңыз МІНДЕТ'),
                        style: manrope(12, FontWeight.w800, color: cInk)),
                  ),
                ]),
                const SizedBox(height: 4),
                ..._willReturn.map((t) => Text('• $t',
                    style: manrope(11.5, FontWeight.w700, color: cInk2))),
                const SizedBox(height: 3),
                Text(
                    tr('Заказ закроется только когда магазин примет размер',
                        'Тапсырыс дүкен өлшемді қабылдағанда ғана жабылады'),
                    style: manrope(10.5, FontWeight.w600, color: cInk3)),
              ]),
            ),
            const SizedBox(height: 16),
          ],

          // ── 2) Жеткізу ақысы — курьердің өз есебі ────────────────────────
          if (o.deliveryFee > 0) ...[
            _sectionLabel(hasFitting
                ? tr('2. Оплата доставки', '2. Жеткізу ақысы')
                : tr('Оплата доставки', 'Жеткізу ақысы')),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cBg,
                borderRadius: BorderRadius.circular(15),
              ),
              child: Column(children: [
                Row(children: [
                  const Icon(Icons.payments_rounded, color: cGreen, size: 18),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                        tr('Клиент платит вам ${money(o.deliveryFee)} наличными. Товар он уже оплатил магазину переводом.',
                            'Клиент сізге ${money(o.deliveryFee)} қолма-қол төлейді. Тауар ақысын дүкенге аударыммен төлеп қойған.'),
                        style: manrope(12, FontWeight.w600,
                            color: cInk2, height: 1.35)),
                  ),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: _FeeChoice(
                      label: tr('Получил', 'Алдым'),
                      amount: money(o.deliveryFee),
                      selected: _feeCollected,
                      tone: 'green',
                      onTap: () => setState(() => _feeCollected = true),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: _FeeChoice(
                      label: tr('Не получил', 'Алмадым'),
                      amount: tr('долг', 'қарыз'),
                      selected: !_feeCollected,
                      tone: 'red',
                      onTap: () => setState(() => _feeCollected = false),
                    ),
                  ),
                ]),
              ]),
            ),
            const SizedBox(height: 16),
          ],

          QPrimaryButton(
            label: tr('Передал клиенту', 'Клиентке бердім'),
            onPressed: () => Navigator.pop(
                context,
                _HandOverResult(
                    widget.fittingIdx
                        .where((i) => _tookAlt[i] == true)
                        .toList(),
                    _feeCollected)),
            height: 50,
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr('Отмена', 'Болдырмау'),
                style: manrope(14, FontWeight.w600, color: cInk3)),
          ),
        ]),
      ),
    );
  }

  Widget _sectionLabel(String text) => Align(
        alignment: Alignment.centerLeft,
        child: Text(text, style: manrope(13, FontWeight.w800, color: cInk)),
      );
}

/// «Алдым / Алмадым» таңдауы — курьердің ақшасы, есебі ашық болуы керек.
class _FeeChoice extends StatelessWidget {
  final String label, amount, tone;
  final bool selected;
  final VoidCallback onTap;
  const _FeeChoice({
    required this.label,
    required this.amount,
    required this.tone,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = tone == 'green' ? cGreen : cRed;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? color : cSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: selected ? color : cLine, width: selected ? 2 : 1.5),
        ),
        child: Column(children: [
          Text(label,
              style: manrope(13, FontWeight.w800,
                  color: selected ? Colors.white : cInk)),
          Text(amount,
              style: manrope(11, FontWeight.w700,
                  color: selected ? Colors.white70 : cInk3)),
        ]),
      ),
    );
  }
}

class _SizeChoice extends StatelessWidget {
  final String size, label;
  final bool selected;
  final VoidCallback onTap;
  const _SizeChoice({
    required this.size,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: selected ? cGreen : cSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: selected ? cGreen : cLine, width: selected ? 2 : 1.5),
          ),
          child: Column(children: [
            Text(size,
                style: manrope(18, FontWeight.w800,
                    color: selected ? Colors.white : cInk)),
            Text(label,
                style: manrope(10.5, FontWeight.w700,
                    color: selected ? Colors.white70 : cInk3)),
          ]),
        ),
      );
}
