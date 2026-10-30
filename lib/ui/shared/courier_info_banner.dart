import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/lang.dart';
import '../../data/models/order_model.dart';
import '../../theme/qoima_design.dart';

/// Жеткізу тапсырысындағы курьер блогы — дүкен, сатушы және клиент
/// экрандарында БІРДЕЙ көрінеді (үш жерде қайталанбауы үшін бір виджет).
///
/// [forStore] = true болғанда:
///   · беру коды (6 сан) үлкен әрі анық көрсетіледі — курьер келгенде дүкен
///     дәл осы кодты айтады, курьер оны өз аппына енгізеді. Солай курьердің
///     қоймаға НАҚТЫ келгені расталады. Код админде де, САТУШЫДА да көрінеді:
///     тапсырысты іс жүзінде беретін адам — сатушы.
///   · қайтып келе жатқан өлшемді «Қабылдадым» деп белгілеу батырмасы шығады.
class CourierInfoBanner extends StatelessWidget {
  final OrderModel order;
  final bool forStore;
  /// Дүкен айналымдағы өлшемді қабылдады (null болса батырма көрінбейді).
  final Future<void> Function()? onConfirmReturnLeg;

  const CourierInfoBanner({
    super.key,
    required this.order,
    this.forStore = false,
    this.onConfirmReturnLeg,
  });

  @override
  Widget build(BuildContext context) {
    if (!order.isDelivery) return const SizedBox.shrink();
    // Казпочтада курьер ЕШҚАШАН келмейді: «Ищем курьера» жалған үміт болар еді.
    if (order.isKazpost) return const SizedBox.shrink();

    final blocks = <Widget>[];

    // ── 0) Қалада курьерлік қызмет жоқ — дүкен өзі жеткізеді (0055) ─────────
    //  Мұнда курьер ЕШҚАШАН келмейді, сондықтан «Курьер іздеудеміз» деп
    //  жалған үміт бермейміз: дүкен нақты не істеу керегін көреді.
    if (order.storeDeliversItself) {
      blocks.add(_box(
        tone: 'blue',
        icon: Icons.local_shipping_rounded,
        title: forStore
            ? tr('Доставляете вы сами', 'Өзіңіз жеткізесіз')
            : tr('Магазин доставит сам', 'Дүкен өзі жеткізеді'),
        subtitle: forStore
            ? tr('В этом городе курьерской службы нет — свяжитесь с клиентом и согласуйте доставку',
                'Бұл қалада курьерлік қызмет жоқ — клиентпен байланысып, жеткізуді келісіңіз')
            : tr('Магазин свяжется с вами и согласует доставку',
                'Дүкен сізбен байланысып, жеткізуді келіседі'),
      ));
      return _wrap(blocks);
    }

    // ── 1) Курьер күйі ───────────────────────────────────────────────────────
    if (!order.hasCourier) {
      if (order.status == OrderModel.statusConfirmed) {
        blocks.add(_box(
          tone: 'amber',
          icon: Icons.hourglass_top_rounded,
          title: tr('Ищем курьера', 'Курьер іздеудеміз'),
          subtitle: tr('Заказ виден свободным курьерам вашего города',
              'Тапсырыс қалаңыздағы бос курьерлерге көрінеді'),
        ));
      }
    } else {
      final onWay = order.courierStatus == OrderModel.courierPickedUp;
      final delivered = order.courierStatus == OrderModel.courierDelivered;
      blocks.add(_box(
        tone: delivered || onWay ? 'green' : 'blue',
        icon: delivered
            ? Icons.task_alt_rounded
            : (onWay
                ? Icons.delivery_dining_rounded
                : Icons.assignment_ind_rounded),
        title: order.courierName.isEmpty
            ? tr('Курьер', 'Курьер')
            : '${tr('Курьер', 'Курьер')}: ${order.courierName}',
        subtitle: delivered
            ? tr('Заказ доставлен', 'Тапсырыс жеткізілді')
            : onWay
                ? (forStore
                    ? tr('Забрал заказ, везёт клиенту',
                        'Тапсырысты алды, клиентке апара жатыр')
                    : tr('Уже в пути к вам', 'Сізге қарай жолда'))
                : (forStore
                    ? tr('Скоро приедет на склад за заказом',
                        'Жақында тапсырыс үшін қоймаға келеді')
                    : tr('Курьер назначен, скоро заберёт заказ',
                        'Курьер тағайындалды, тапсырысты жақында алады')),
      ));
    }

    // ── 2) Беру коды — дүкенге, курьер әлі алмаған кезде ────────────────────
    if (forStore &&
        order.courierStatus == OrderModel.courierAssigned &&
        order.pickupCode.isNotEmpty) {
      blocks.add(_PickupCodeCard(code: order.pickupCode));
    }

    // ── 3) «Өлшеп көру» — беруге дейін: екі өлшемді де дайындау ─────────────
    if (order.hasFitting) {
      blocks.add(_fittingPrepBlock());
    }

    // ── 4) Айналымдағы өлшем — қайсысы қалды, қайсысы қайтып келеді ─────────
    if (order.hasReturnLeg) {
      blocks.add(_returnLegBlock(context));
    }

    return _wrap(blocks);
  }

  Widget _wrap(List<Widget> blocks) {
    if (blocks.isEmpty) return const SizedBox.shrink();
    return Column(children: [
      for (var i = 0; i < blocks.length; i++) ...[
        if (i > 0) const SizedBox(height: 8),
        blocks[i],
      ],
    ]);
  }

  // ── «Өлшеп көру»: екінші өлшемді де қоймадан беру керек ───────────────────
  Widget _fittingPrepBlock() => Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: cAmberTint,
          borderRadius: BorderRadius.circular(13),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.checkroom_rounded, color: cAmber, size: 17),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      tr('Примерка — нужен запасной размер',
                          'Өлшеп көру — қосалқы өлшем керек'),
                      style: manrope(12, FontWeight.w800, color: cInk)),
                  const SizedBox(height: 2),
                  ...order.items.where((i) => i.hasAltSize).map((i) => Text(
                      '${i.productName}: ${i.size} + ${i.altSize}',
                      style: manrope(11.5, FontWeight.w600, color: cInk2))),
                  const SizedBox(height: 2),
                  Text(
                      forStore
                          ? tr('Один размер останется у клиента, второй курьер вернёт на склад',
                              'Бір өлшем клиентте қалады, екіншісін курьер қоймаға қайтарады')
                          : tr('Курьер привезёт оба — примерите и выберете один',
                              'Курьер екеуін де әкеледі — өлшеп көріп, біреуін таңдайсыз'),
                      style: manrope(11, FontWeight.w600, color: cInk3)),
                ]),
          ),
        ]),
      );

  // ── Қайтып келе жатқан өлшем ──────────────────────────────────────────────
  Widget _returnLegBlock(BuildContext context) {
    final done = order.returnLegDone;
    // Клиентте ҚАЛҒАН өлшемдер — курьер свопынан кейін items-те тұр.
    final kept = order.items.where((i) => i.fittingResolved).toList();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: done ? cGreenTint : cBlueTint,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(done ? Icons.inventory_rounded : Icons.u_turn_left_rounded,
              color: done ? cGreen : cBlue, size: 18),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
                done
                    ? tr('Второй размер вернулся на склад',
                        'Екінші өлшем қоймаға оралды')
                    : tr('Второй размер едет обратно на склад',
                        'Екінші өлшем қоймаға қайтып келе жатыр'),
                style: manrope(12.5, FontWeight.w800, color: cInk)),
          ),
        ]),
        const SizedBox(height: 8),
        // Қайсысы клиентте қалды / қайсысы қайтады — нақты жазылады.
        ...kept.map((i) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(i.productName,
                        style: manrope(11.5, FontWeight.w700, color: cInk2),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    Row(children: [
                      _sizeTag(i.size, kept_: true),
                      const SizedBox(width: 6),
                      _sizeTag(i.returningSize, kept_: false),
                    ]),
                  ]),
            )),
        if (forStore && !done && onConfirmReturnLeg != null) ...[
          const SizedBox(height: 10),
          _ConfirmReturnButton(onConfirm: onConfirmReturnLeg!),
        ],
      ]),
    );
  }

  Widget _sizeTag(String size, {required bool kept_}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: kept_ ? cGreen : cInk3,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(kept_ ? Icons.check_rounded : Icons.u_turn_left_rounded,
              size: 11, color: Colors.white),
          const SizedBox(width: 3),
          Text(
              kept_
                  ? tr('$size — у клиента', '$size — клиентте')
                  : tr('$size — возврат', '$size — қайтады'),
              style: manrope(10.5, FontWeight.w800, color: Colors.white)),
        ]),
      );

  Widget _box({
    required String tone,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final color = switch (tone) {
      'green' => cGreen,
      'amber' => cAmber,
      _ => cBlue,
    };
    final bg = switch (tone) {
      'green' => cGreenTint,
      'amber' => cAmberTint,
      _ => cBlueTint,
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        Icon(icon, color: color, size: 19),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: manrope(13, FontWeight.w800, color: cInk)),
                Text(subtitle,
                    style: manrope(11.5, FontWeight.w600, color: cInk2)),
              ]),
        ),
      ]),
    );
  }
}

// ── Беру коды (6 сан) ─────────────────────────────────────────────────────────
class _PickupCodeCard extends StatelessWidget {
  final String code;
  const _PickupCodeCard({required this.code});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () {
          Clipboard.setData(ClipboardData(text: code));
          HapticFeedback.lightImpact();
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(
              content: Text(tr('Код скопирован', 'Код көшірілді')),
              backgroundColor: cGreen,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 2),
            ));
        },
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: cAmberTint,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cAmber.withValues(alpha: 0.4)),
          ),
          child: Column(children: [
            Text(tr('Назовите курьеру этот код', 'Курьерге осы кодты айтыңыз'),
                style: manrope(11.5, FontWeight.w700, color: cAmber)),
            const SizedBox(height: 5),
            Text(code,
                style: manrope(27, FontWeight.w800,
                    color: cInk, letterSpacing: 7)),
            const SizedBox(height: 3),
            Text(
                tr('Без кода курьер не сможет забрать заказ',
                    'Кодсыз курьер тапсырысты ала алмайды'),
                style: manrope(10.5, FontWeight.w600, color: cInk3)),
          ]),
        ),
      );
}

// ── «Қабылдадым» батырмасы (қайтып келген өлшем) ──────────────────────────────
class _ConfirmReturnButton extends StatefulWidget {
  final Future<void> Function() onConfirm;
  const _ConfirmReturnButton({required this.onConfirm});

  @override
  State<_ConfirmReturnButton> createState() => _ConfirmReturnButtonState();
}

class _ConfirmReturnButtonState extends State<_ConfirmReturnButton> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        height: 42,
        child: ElevatedButton.icon(
          onPressed: _busy
              ? null
              : () async {
                  setState(() => _busy = true);
                  try {
                    await widget.onConfirm();
                  } finally {
                    if (mounted) setState(() => _busy = false);
                  }
                },
          icon: _busy
              ? const SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.inventory_2_rounded, size: 17),
          style: ElevatedButton.styleFrom(
            backgroundColor: cGreen,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
          label: Text(
              tr('Принял размер на склад', 'Өлшемді қоймаға қабылдадым'),
              style: manrope(13, FontWeight.w800, color: Colors.white)),
        ),
      );
}
