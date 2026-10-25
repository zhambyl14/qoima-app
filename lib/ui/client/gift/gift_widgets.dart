import 'package:flutter/material.dart';

import '../../../core/lang.dart';
import '../../../data/models/order_model.dart';
import '../../../theme/qoima_design.dart';

/// «Сыйлау» тапсырысының қысқа белгісі (клиент және дүкен тізімдерінде).
///
/// Алушы әлі өлшем таңдамаған болса — «күтуде», таңдаса — қарапайым белгі.
class GiftBadge extends StatelessWidget {
  final OrderModel order;
  const GiftBadge({super.key, required this.order});

  @override
  Widget build(BuildContext context) {
    if (!order.isGift) return const SizedBox.shrink();
    final waiting = order.isGiftAwaitingRecipient;
    return QPill(
      waiting
          ? tr('Подарок · ждём получателя', 'Сыйлық · алушыны күтеміз')
          : tr('Подарок', 'Сыйлық'),
      tone: waiting ? 'amber' : 'purple',
      icon: Icon(Icons.card_giftcard_rounded,
          size: 12, color: waiting ? cAmberInk : cPurpleInk),
    );
  }
}

/// Дүкен (админ/сатушы) үшін түсіндірме блок.
///
///  • алушы әлі таңдамаған → «өлшем жоқ, беруге болмайды» түсіндірмесі;
///  • таңдаған → кімнен/кімге + тілек (бағасы жасырын болса да дүкен өз
///    тапсырысының бағасын көре береді — ол оның кірісі).
class GiftStoreNote extends StatelessWidget {
  final OrderModel order;
  const GiftStoreNote({super.key, required this.order});

  @override
  Widget build(BuildContext context) {
    if (!order.isGift) return const SizedBox.shrink();
    final waiting = order.isGiftAwaitingRecipient;
    final fg = waiting ? cAmberInk : cPurpleInk;
    final bg = waiting ? cAmberTint : cPurpleTint;
    final giver = order.giftGiverName;
    final recipient = order.giftRecipientName;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(kR14),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.card_giftcard_rounded, size: 18, color: fg),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              waiting
                  ? (order.isGiftExpired
                      ? tr('Подарок: срок получения истёк',
                          'Сыйлық: алу мерзімі өтті')
                      : tr('Подарок: получатель ещё не выбрал размер',
                          'Сыйлық: алушы өлшемді әлі таңдаған жоқ'))
                  : tr('Подарок', 'Сыйлық'),
              style: manrope(13, FontWeight.w800, color: fg),
            ),
          ),
        ]),
        const SizedBox(height: 6),
        if (waiting)
          Text(
            order.isGiftExpired
                ? tr('Получатель не открыл подарок за 30 дней. Покупатель может запросить возврат — отмените заказ после согласования.',
                    'Алушы сыйлықты 30 күн ішінде ашпады. Сатып алушы қайтаруды сұрай алады — келісіп, тапсырысты бас тартыңыз.')
                : tr('Выдача и передача курьеру станут доступны после выбора размера. Товар не зарезервирован — размер определится при получении.',
                    'Өлшем таңдалғанша беру мен курьерге тапсыру қолжетімсіз. Тауар брондалмаған — өлшем алушы таңдағанда анықталады.'),
            style: manrope(12, FontWeight.w500, color: cInk2),
          ),
        if (giver.isNotEmpty || recipient.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(top: waiting ? 6 : 0),
            child: Text(
              [
                if (giver.isNotEmpty) tr('От: $giver', 'Кімнен: $giver'),
                if (recipient.isNotEmpty)
                  tr('Кому: $recipient', 'Кімге: $recipient'),
              ].join('  ·  '),
              style: manrope(12, FontWeight.w700, color: cInk),
            ),
          ),
        if (order.giftMessage.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('«${order.giftMessage.trim()}»',
                style: manrope(12, FontWeight.w600, color: cInk2)),
          ),
      ]),
    );
  }
}
