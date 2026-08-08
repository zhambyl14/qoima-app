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
  final void Function(List<int> swappedIndexes)? onDeliver;
  final void Function(String reason)? onReturn;
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
        border: Border.all(
            color: _isPickedUp ? cGreen.withValues(alpha: 0.45) : cLine),
        boxShadow: kShadowSm,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Шапка: нөмір + күй + сома ────────────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
          decoration: BoxDecoration(
            color: _statusColor.withValues(alpha: 0.08),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
          ),
          child: Row(children: [
            QPill(_statusLabel, tone: _statusTone),
            const SizedBox(width: 8),
            Text('№${order.orderNumber}',
                style: manrope(13, FontWeight.w800, color: cInk2)),
            const Spacer(),
            Text(money(order.deliveryFee + order.fittingFee),
                style: manrope(15, FontWeight.w800, color: cGreenDeep)),
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
        if (onReturn != null)
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
              tr('Попросите продавца показать код заказа и введите его.',
                  'Сатушыдан тапсырыс кодын көрсетуін сұрап, енгізіңіз.'),
              style: manrope(13, FontWeight.w500, color: cInk2, height: 1.4)),
          const SizedBox(height: 14),
          TextField(
            controller: ctrl,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            style: manrope(17, FontWeight.w800, color: cInk),
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              hintText: 'QM-XXXX',
              hintStyle: manrope(17, FontWeight.w700, color: cInk3),
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

  /// Клиентке беру. «Өлшеп көру» сұралған позициялар болса — қайсысын алғанын
  /// белгілейміз (38 ме, әлде 39 ба). Бағасы бірдей — ақша қозғалмайды.
  Future<void> _handOver(BuildContext context) async {
    final fittingIdx = <int>[];
    for (var i = 0; i < order.items.length; i++) {
      if (order.items[i].hasAltSize) fittingIdx.add(i);
    }
    if (fittingIdx.isEmpty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: cSurface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(tr('Заказ передан клиенту?', 'Тапсырыс клиентке берілді ме?'),
              style: manrope(16, FontWeight.w800, color: cInk)),
          content: Text(
              tr('Заказ будет закрыт, магазин получит продажу.',
                  'Тапсырыс жабылады, дүкен сатылым алады.'),
              style: manrope(13.5, FontWeight.w500, color: cInk2)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(tr('Нет', 'Жоқ'),
                    style: manrope(14, FontWeight.w600, color: cInk2))),
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                    backgroundColor: cGreen, foregroundColor: Colors.white),
                child: Text(tr('Да, передал', 'Иә, бердім'))),
          ],
        ),
      );
      if (ok == true) onDeliver?.call(const []);
      return;
    }

    final swaps = await showModalBottomSheet<List<int>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FittingSheet(order: order, fittingIdx: fittingIdx),
    );
    if (swaps != null) onDeliver?.call(swaps);
  }

  Future<void> _askReturnReason(BuildContext context) async {
    final ctrl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(tr('Клиент отказался', 'Клиент бас тартты'),
            style: manrope(16, FontWeight.w800, color: cInk)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
              tr('Товар вернётся на склад. Стоимость доставки клиенту не возвращается.',
                  'Тауар қоймаға оралады. Жеткізу ақысы клиентке қайтарылмайды.'),
              style: manrope(13, FontWeight.w500, color: cInk2, height: 1.4)),
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
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(tr('Отмена', 'Болдырмау'),
                  style: manrope(14, FontWeight.w600, color: cInk2))),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              style: ElevatedButton.styleFrom(
                  backgroundColor: cRed, foregroundColor: Colors.white),
              child: Text(tr('Вернуть', 'Қайтару'))),
        ],
      ),
    );
    ctrl.dispose();
    if (reason != null) onReturn?.call(reason);
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

// ── «Өлшеп көру» қорытындысы: клиент қай өлшемді алды? ────────────────────────
class _FittingSheet extends StatefulWidget {
  final OrderModel order;
  final List<int> fittingIdx;
  const _FittingSheet({required this.order, required this.fittingIdx});

  @override
  State<_FittingSheet> createState() => _FittingSheetState();
}

class _FittingSheetState extends State<_FittingSheet> {
  /// index → қосалқы өлшем алынды ма (true = своп).
  final Map<int, bool> _tookAlt = {};

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: cSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, MediaQuery.of(context).padding.bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 40,
          height: 4,
          margin: const EdgeInsets.only(bottom: 18),
          decoration:
              BoxDecoration(color: cLine, borderRadius: BorderRadius.circular(2)),
        ),
        Text(tr('Какой размер взял клиент?', 'Клиент қай өлшемді алды?'),
            style: manrope(17, FontWeight.w800, color: cInk)),
        const SizedBox(height: 6),
        Text(
          tr('Второй размер вернётся на склад. Доплаты нет — цена одинаковая.',
              'Екінші өлшем қоймаға оралады. Қосымша төлем жоқ — бағасы бірдей.'),
          textAlign: TextAlign.center,
          style: manrope(12.5, FontWeight.w600, color: cInk2, height: 1.4),
        ),
        const SizedBox(height: 18),
        ...widget.fittingIdx.map((i) {
          final item = widget.order.items[i];
          final tookAlt = _tookAlt[i] ?? false;
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
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
        const SizedBox(height: 4),
        QPrimaryButton(
          label: tr('Передал клиенту', 'Клиентке бердім'),
          onPressed: () => Navigator.pop(
              context,
              widget.fittingIdx.where((i) => _tookAlt[i] == true).toList()),
          height: 50,
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('Отмена', 'Болдырмау'),
              style: manrope(14, FontWeight.w600, color: cInk3)),
        ),
      ]),
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
