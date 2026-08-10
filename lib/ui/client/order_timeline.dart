import 'package:flutter/material.dart';
import '../../core/lang.dart';
import '../../data/models/cart_item_model.dart';
import '../../data/models/order_model.dart';
import '../../theme/qoima_design.dart';

/// Клиентке арналған тапсырыс жолы (timeline).
///
/// НЕГЕ КЕРЕК: бұрын клиент тек «Оплачен»/«Выполнен» деген құрғақ статусты
/// көретін. Курьер келді ме, тапсырысты алды ма, жолда ма, примеркадағы
/// қай өлшем өзінде қалды, қайсысы қайтып жатыр — ештеңе түсініксіз еді.
/// Осы виджет әр қадамды нақты сөзбен көрсетеді.
class OrderTimeline extends StatelessWidget {
  final OrderModel order;
  const OrderTimeline({super.key, required this.order});

  @override
  Widget build(BuildContext context) {
    final steps = _steps();
    if (steps.isEmpty) return const SizedBox.shrink();
    // Түсініктеме ТЕК ағымдағы қадамда керек: болашақ қадамдардың астындағы
    // мәтін («Тапсырыс курьерлерге көрінеді») әлі болмаған нәрсені түсіндіріп,
    // тізімді оқылмайтын мәтін қабырғасына айналдырады. Дерек тасушы
    // түсініктемелер (өлшемдер, бас тарту себебі) әрқашан қалады.
    final current = steps.indexWhere((s) => !s.done);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      decoration: BoxDecoration(
        color: cBg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr('Что происходит с заказом', 'Тапсырыспен не болып жатыр'),
            style: manrope(11.5, FontWeight.w800, color: cInk3)),
        const SizedBox(height: 10),
        ...steps.asMap().entries.map((e) => _StepRow(
              step: e.value,
              last: e.key == steps.length - 1,
              showSubtitle: e.value.keepSubtitle || e.key == current,
            )),
      ]),
    );
  }

  List<_Step> _steps() {
    final o = order;
    final cancelled = o.status == OrderModel.statusCancelled;
    final completed = o.status == OrderModel.statusCompleted;
    final paid = o.status == OrderModel.statusConfirmed || completed;

    final steps = <_Step>[
      _Step(
        icon: Icons.receipt_long_rounded,
        title: tr('Заказ оформлен', 'Тапсырыс рәсімделді'),
        done: true,
      ),
      _Step(
        icon: Icons.verified_rounded,
        title: tr('Оплата подтверждена', 'Төлем расталды'),
        subtitle: paid
            ? null
            : tr('Ждём проверки чека продавцом',
                'Сатушының чекті тексеруін күтудеміз'),
        done: paid,
      ),
    ];

    if (!o.isDelivery) {
      steps.add(_Step(
        icon: Icons.storefront_rounded,
        title: tr('Получено в магазине', 'Дүкеннен алынды'),
        done: completed,
      ));
      if (cancelled) {
        steps.add(_Step(
          icon: Icons.cancel_rounded,
          title: tr('Заказ отменён', 'Тапсырыс болдырылмады'),
          done: true,
          tone: 'red',
        ));
      }
      return steps;
    }

    // ── Қалада курьерлік қызмет жоқ: дүкен өзі жеткізеді (0055) ────────────
    //  Курьер қадамдарын көрсету жалған үміт болар еді — ол ешқашан келмейді.
    if (o.storeDeliversItself) {
      steps.add(_Step(
        icon: Icons.local_shipping_rounded,
        title: tr('Магазин доставит сам', 'Дүкен өзі жеткізеді'),
        subtitle: completed
            ? null
            : tr('Магазин свяжется с вами и согласует доставку',
                'Дүкен сізбен байланысып, жеткізуді келіседі'),
        done: completed,
      ));
      steps.add(_Step(
        icon: Icons.check_circle_rounded,
        title: tr('Заказ у вас', 'Тапсырыс сізде'),
        done: completed,
      ));
      if (cancelled) {
        steps.add(_Step(
          icon: Icons.cancel_rounded,
          title: tr('Заказ отменён', 'Тапсырыс болдырылмады'),
          done: true,
          tone: 'red',
        ));
      }
      return steps;
    }

    // ── Жеткізу жолы ────────────────────────────────────────────────────────
    final assigned = o.hasCourier;
    final onWay = o.courierStatus == OrderModel.courierPickedUp ||
        o.courierStatus == OrderModel.courierDelivered;

    steps.add(_Step(
      icon: Icons.assignment_ind_rounded,
      title: assigned
          ? tr('Курьер назначен: ${o.courierName}',
              'Курьер тағайындалды: ${o.courierName}')
          : tr('Ищем курьера', 'Курьер іздеудеміз'),
      subtitle: assigned
          ? null
          : tr('Заказ виден курьерам вашего города',
              'Тапсырыс қалаңыздағы курьерлерге көрінеді'),
      done: assigned,
    ));

    steps.add(_Step(
      icon: Icons.local_shipping_rounded,
      title: tr('Курьер забрал заказ со склада',
          'Курьер тапсырысты қоймадан алды'),
      subtitle: onWay && !completed
          ? tr('Едет к вам', 'Сізге қарай келе жатыр')
          : null,
      done: onWay,
    ));

    // «Өлшеп көру» — БӨЛЕК қадам ЕМЕС: ол жеткізудің қасиеті ғана. Курьер
    // екі өлшемді бір жолы әкеледі, сондықтан жеткізу қадамының өзінде
    // жазылады.
    final fitting = o.hasFitting && !completed
        ? o.items.where((i) => i.hasAltSize).toList()
        : <CartItemModel>[];
    steps.add(_Step(
      icon: Icons.done_all_rounded,
      title: tr('Заказ доставлен', 'Тапсырыс жеткізілді'),
      subtitle: fitting.isEmpty
          ? null
          : fitting
              .map((i) => tr('${i.productName}: привезём ${i.size} и ${i.altSize} — примерите',
                  '${i.productName}: ${i.size} және ${i.altSize} әкелеміз — өлшеп көресіз'))
              .join('\n'),
      done: completed,
      keepSubtitle: true,
    ));

    // ── Примеркадан кейін: қайсысы қалды, қайсысы қайтады — БІР қадам ──────
    if (o.hasReturnLeg) {
      final kept = o.items.where((i) => i.fittingResolved).toList();
      steps.add(_Step(
        icon: Icons.u_turn_left_rounded,
        title: o.returnLegDone
            ? tr('Второй размер вернулся продавцу',
                'Екінші өлшем сатушыға оралды')
            : tr('Второй размер везёт курьер обратно',
                'Екінші өлшемді курьер қайтарып апара жатыр'),
        subtitle: kept
            .map((i) => tr(
                '${i.productName}: ${i.size} у вас · ${i.returningSize} возврат',
                '${i.productName}: ${i.size} сізде · ${i.returningSize} қайтады'))
            .join('\n'),
        done: o.returnLegDone,
        tone: o.returnLegDone ? 'green' : 'blue',
        keepSubtitle: true,
      ));
    }

    if (cancelled) {
      steps.add(_Step(
        icon: Icons.cancel_rounded,
        title: tr('Заказ отменён', 'Тапсырыс болдырылмады'),
        subtitle: o.rejectionReason.isEmpty ? null : o.rejectionReason,
        done: true,
        tone: 'red',
        keepSubtitle: true,
      ));
    }
    return steps;
  }
}

class _Step {
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool done;
  final String tone;

  /// Түсініктеме дерек тасиды (өлшемдер, себеп) — ағымдағы қадам болмаса да
  /// көрсетіледі. Жай «не болатынын» түсіндіретін мәтін үшін false.
  final bool keepSubtitle;

  const _Step({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.done,
    this.tone = 'green',
    this.keepSubtitle = false,
  });
}

class _StepRow extends StatelessWidget {
  final _Step step;
  final bool last;
  final bool showSubtitle;
  const _StepRow({
    required this.step,
    required this.last,
    this.showSubtitle = true,
  });

  @override
  Widget build(BuildContext context) {
    final color = switch (step.tone) {
      'red' => cRed,
      'amber' => cAmber,
      'blue' => cBlue,
      _ => cGreen,
    };
    final active = step.done || step.tone != 'green';
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Column(children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: active ? color : cSurface,
              shape: BoxShape.circle,
              border: Border.all(color: active ? color : cLine, width: 1.5),
            ),
            child: Icon(step.icon,
                size: 13, color: active ? Colors.white : cInk3),
          ),
          if (!last)
            Expanded(
              child: Container(
                width: 2,
                margin: const EdgeInsets.symmetric(vertical: 2),
                color: step.done ? color.withValues(alpha: 0.35) : cLine,
              ),
            ),
        ]),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: last ? 6 : 12, top: 2),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(step.title,
                      style: manrope(12.5, FontWeight.w800,
                          color: active ? cInk : cInk3)),
                  if (showSubtitle &&
                      step.subtitle != null &&
                      step.subtitle!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(step.subtitle!,
                          style: manrope(11.5, FontWeight.w600,
                              color: cInk2, height: 1.35)),
                    ),
                ]),
          ),
        ),
      ]),
    );
  }
}
