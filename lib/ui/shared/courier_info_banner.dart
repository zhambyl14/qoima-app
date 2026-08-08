import 'package:flutter/material.dart';
import '../../core/lang.dart';
import '../../data/models/order_model.dart';
import '../../theme/qoima_design.dart';

/// Жеткізу тапсырысындағы курьер туралы блок — дүкен, сатушы және клиент
/// экрандарында БІРДЕЙ көрінеді (үш жерде қайталанбауы үшін бір виджет).
///
/// [forStore] = true болғанда қойма коды үлкен әрі анық көрсетіледі: курьер
/// келгенде сатушы дәл осы кодты айтады, курьер оны өз аппына енгізеді —
/// солай оның қоймаға НАҚТЫ келгені расталады.
class CourierInfoBanner extends StatelessWidget {
  final OrderModel order;
  final bool forStore;
  const CourierInfoBanner({
    super.key,
    required this.order,
    this.forStore = false,
  });

  @override
  Widget build(BuildContext context) {
    if (!order.isDelivery) return const SizedBox.shrink();

    // Курьер әлі алмаған — дүкенге «күтіңіз» деп түсіндіреміз.
    if (!order.hasCourier) {
      if (order.status != OrderModel.statusConfirmed) {
        return const SizedBox.shrink();
      }
      return _box(
        tone: 'amber',
        icon: Icons.hourglass_top_rounded,
        title: tr('Ищем курьера', 'Курьер іздеудеміз'),
        subtitle: tr('Заказ виден свободным курьерам вашего города',
            'Тапсырыс қалаңыздағы бос курьерлерге көрінеді'),
      );
    }

    final onWay = order.courierStatus == OrderModel.courierPickedUp;
    final delivered = order.courierStatus == OrderModel.courierDelivered;

    return Column(children: [
      _box(
        tone: delivered ? 'green' : (onWay ? 'green' : 'blue'),
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
      ),
      // Қойма коды — тек дүкенге әрі курьер әлі алмаған кезде керек.
      if (forStore &&
          order.courierStatus == OrderModel.courierAssigned &&
          order.pickupCode.isNotEmpty) ...[
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: cAmberTint,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(children: [
            Text(tr('Назовите курьеру этот код', 'Курьерге осы кодты айтыңыз'),
                style: manrope(11.5, FontWeight.w700, color: cAmber)),
            const SizedBox(height: 4),
            Text(order.pickupCode,
                style: manrope(22, FontWeight.w800,
                    color: cInk, letterSpacing: 2)),
          ]),
        ),
      ],
      // «Өлшеп көру» — дүкен қосымша өлшемді де дайындауы керек.
      if (order.hasFitting) ...[
        const SizedBox(height: 8),
        Container(
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
                    Text(tr('Примерка — нужен запасной размер',
                        'Өлшеп көру — қосалқы өлшем керек'),
                        style: manrope(12, FontWeight.w800, color: cInk)),
                    const SizedBox(height: 2),
                    ...order.items.where((i) => i.hasAltSize).map((i) => Text(
                        '${i.productName}: ${i.size} + ${i.altSize}',
                        style: manrope(11.5, FontWeight.w600, color: cInk2))),
                    const SizedBox(height: 2),
                    Text(
                        forStore
                            ? tr('Второй размер вернётся на склад, если не подойдёт',
                                'Келмесе, екінші өлшем қоймаға оралады')
                            : tr('Курьер привезёт оба — примерите на месте',
                                'Курьер екеуін де әкеледі — орнында өлшейсіз'),
                        style: manrope(11, FontWeight.w600, color: cInk3)),
                  ]),
            ),
          ]),
        ),
      ],
    ]);
  }

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
                Text(title,
                    style: manrope(13, FontWeight.w800, color: cInk)),
                Text(subtitle,
                    style: manrope(11.5, FontWeight.w600, color: cInk2)),
              ]),
        ),
      ]),
    );
  }
}
