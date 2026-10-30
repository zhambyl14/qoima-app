import 'package:flutter/material.dart';

import '../../core/lang.dart';
import '../../data/models/cart_item_model.dart';
import '../../data/models/order_model.dart';
import '../../data/models/return_policy.dart';
import '../../data/services/return_service.dart';
import '../../theme/qoima_design.dart';

/// Қайтару шарттарының мәтіні: хабарлама парағы, тапсырыс беті, қайтару формасы
/// және дүкен баптауындағы «клиент осылай көреді» — бәрі осы бір виджет.
///
/// Мәтін тапсырыстың СНАПШОТЫНАН құрылады: дүкен шартын кейін өзгертсе де,
/// клиент сатып алған сәттегі шарт көрсетіледі. 0076: тек ақпарат, қайтаруға
/// шақыратын батырма да, «қайтара аласыз» деген сөз де жоқ.
class ReturnPolicyBody extends StatelessWidget {
  final ReturnPolicy policy;

  /// Тапсырыс жолдары. Баптаудағы алдын ала көріністе бос: онда нақты тауар жоқ.
  final List<CartItemModel> items;

  /// Почта ақысы туралы жол тек Казпочта тапсырысында керек.
  final bool kazpost;

  const ReturnPolicyBody(
    this.policy, {
    super.key,
    this.items = const [],
    this.kazpost = false,
  });

  // Орысша «в течение» ілік септігін талап етеді: 21 дня, бірақ 14 дней.
  static String _daysGenitive(int days) =>
      days % 10 == 1 && days % 100 != 11 ? 'дня' : 'дней';

  @override
  Widget build(BuildContext context) {
    final note = policy.note.trim();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (policy.isNoReturns)
        _noReturnsBanner()
      else ...[
        _periodRow(),
        ..._conditions(),
      ],
      if (note.isNotEmpty) ...[
        const SizedBox(height: 10),
        Text(note, style: manrope(13, FontWeight.w500, color: cInk2)),
      ],
      if (!policy.isNoReturns) ..._itemLines(),
      if (kazpost) ...[
        const SizedBox(height: 10),
        Text(
            tr('Стоимость пересылки не возвращается. Если вы отправляете товар обратно почтой, пересылку оплачиваете вы, кроме случаев, когда товар с браком.',
                'Пошта ақысы қайтарылмайды. Тауарды поштамен кері жіберсеңіз, жөнелту ақысын өзіңіз төлейсіз, тек тауарда ақау болған жағдайда төлемейсіз.'),
            style: manrope(12.5, FontWeight.w500, color: cInk2)),
      ],
      // Әрқашан тұрады: «қайтарылмайды» деген жазу ақаулы тауарға да қатысты
      // сияқты көрінбесін. Заңнан артық уәде бермейміз.
      const SizedBox(height: 10),
      Text(
          tr('Если товар с браком, ваши права защищает закон о защите прав потребителей.',
              'Тауарда ақау болса, құқықтарыңызды тұтынушылар құқығын қорғау туралы заң қорғайды.'),
          style: manrope(11.5, FontWeight.w500, color: cInk3)),
    ]);
  }

  Widget _noReturnsBanner() => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cAmberTint,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cAmber.withValues(alpha: 0.45)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.block_rounded, size: 20, color: cRedInk),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
                tr('Этот магазин не принимает возврат',
                    'Бұл дүкен қайтаруды қабылдамайды'),
                style: manrope(14, FontWeight.w800, color: cRedInk)),
          ),
        ]),
      );

  Widget _periodRow() {
    final d = policy.days;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Icon(Icons.event_note_outlined, size: 20, color: cInk2),
      const SizedBox(width: 10),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
              tr('Возврат в течение $d ${_daysGenitive(d)}',
                  'Қайтару $d күн ішінде'),
              style: manrope(14, FontWeight.w800, color: cInk)),
          const SizedBox(height: 2),
          Text(
              tr('Срок считается со дня получения',
                  'Мерзім тауарды алған күннен басталады'),
              style: manrope(12, FontWeight.w500, color: cInk3)),
        ]),
      ),
    ]);
  }

  List<Widget> _conditions() {
    // Белгісіз код (жаңа нұсқадан келген) бос мәтін береді — тізімге кірмейді.
    final labels = policy.conditions
        .map(ReturnPolicy.conditionLabel)
        .where((l) => l.isNotEmpty)
        .toList();
    if (labels.isEmpty) return const [];
    return [
      const SizedBox(height: 10),
      for (final label in labels)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Padding(
              padding: EdgeInsets.only(top: 1),
              child: Icon(Icons.check_rounded, size: 16, color: cInk3),
            ),
            const SizedBox(width: 8),
            Expanded(
              child:
                  Text(label, style: manrope(13, FontWeight.w600, color: cInk)),
            ),
          ]),
        ),
    ];
  }

  /// Тауарға қатысты жолдар. Бір тауардың екі өлшемі бір-ақ рет шығады.
  List<Widget> _itemLines() {
    final blocked = <Widget>[];
    final notes = <Widget>[];
    final seen = <String>{};
    for (final item in items) {
      if (!seen.add(item.productId)) continue;
      final note = (policy.productNotes[item.productId] ?? '').trim();
      if (item.nonReturnable) {
        blocked.add(_blockedLine(item.productName, note));
      } else if (note.isNotEmpty) {
        notes.add(_noteLine(item.productName, note));
      }
    }
    return [...blocked, ...notes];
  }

  Widget _blockedLine(String name, String note) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr('«$name» — возврату не подлежит', '«$name» — қайтарылмайды'),
              style: manrope(13, FontWeight.w700, color: cRedInk)),
          if (note.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(note, style: manrope(12.5, FontWeight.w500, color: cInk2)),
          ],
        ]),
      );

  Widget _noteLine(String name, String note) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('«$name»', style: manrope(13, FontWeight.w700, color: cInk)),
          const SizedBox(height: 2),
          Text(note, style: manrope(12.5, FontWeight.w500, color: cInk2)),
        ]),
      );
}

/// Хабарламаны көрсетеді. Парақ жабылғанша күтеді — кезекті [ReturnNoticeGate]
/// осы күтумен ұстайды. Сыртын басып кездейсоқ жабылмайды.
Future<void> showReturnNoticeSheet(BuildContext context, OrderModel order) =>
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (_) => ReturnNoticeSheet(order: order),
    );

/// Тауар қолға тигенде БІР РЕТ шығатын хабарлама (0082).
///
/// 0076: «Оформить возврат» батырмасы әдейі жоқ және кейін еске салмаймыз.
class ReturnNoticeSheet extends StatefulWidget {
  final OrderModel order;
  const ReturnNoticeSheet({super.key, required this.order});

  @override
  State<ReturnNoticeSheet> createState() => _ReturnNoticeSheetState();
}

class _ReturnNoticeSheetState extends State<ReturnNoticeSheet> {
  bool _closing = false;

  /// Клиентті желіге күттірмейміз: парақ бірден жабылады, ack артта кетеді.
  /// Сәтсіз болса, келесі ашқанда қайта шығады — мәтін қайталануы зиян емес.
  void _close() {
    if (_closing) return;
    _closing = true;
    _ack(widget.order.id);
    Navigator.of(context).pop();
  }

  static Future<void> _ack(String orderId) async {
    try {
      await ReturnService().ackReturnNotice(orderId);
    } catch (_) {
      // Әдейі үнсіз: хабарлама shell-ді ешқашан бұзбауы керек.
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    final number = o.orderNumber > 0
        ? '${tr('Заказ', 'Тапсырыс')} №${o.orderNumber.toString().padLeft(5, '0')}'
        : tr('Заказ', 'Тапсырыс');
    final subtitle = [
      if (o.storeName.trim().isNotEmpty) o.storeName.trim(),
      number,
    ].join(' · ');
    final policy = o.returnPolicy ?? const ReturnPolicy();
    // Android «артқа» батырмасы да «түсінікті» деп саналады: клиент парақты
    // көрді, онда тұрып қалдырудың мәні жоқ.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Container(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        decoration: const BoxDecoration(
          color: cSurface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      tr('Условия возврата этого магазина',
                          'Осы дүкеннің қайтару шарттары'),
                      style: manrope(17, FontWeight.w800, color: cInk)),
                  const SizedBox(height: 4),
                  Text(subtitle,
                      style: manrope(12.5, FontWeight.w600, color: cInk3)),
                  const SizedBox(height: 14),
                  Flexible(
                    child: SingleChildScrollView(
                      child: ReturnPolicyBody(
                        policy,
                        items: o.items,
                        kazpost: o.isKazpost,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  QPrimaryButton(
                    label: tr('Понятно', 'Түсінікті'),
                    onPressed: _close,
                  ),
                ]),
          ),
        ),
      ),
    );
  }
}
