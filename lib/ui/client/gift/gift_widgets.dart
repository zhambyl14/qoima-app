import 'package:flutter/material.dart';

import '../../../core/lang.dart';
import '../../../data/models/order_model.dart';
import '../../../theme/qoima_design.dart';
import 'gift_exchange_sheet.dart';

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
///    тапсырысының бағасын көре береді — ол оның кірісі);
///  • қосымша төлем (gift_extra_due) — ІРІ, беру кезінде алынуы тиіс;
///  • «Ауыстыру» батырмасы — дүкеннен алатын сыйлық берілгенге дейін, не
///    алынған сыйлық 14 күн ішінде (gift_store_exchange). [onChanged] —
///    ауыстырудан кейін тізімді жаңарту үшін.
class GiftStoreNote extends StatelessWidget {
  final OrderModel order;
  final VoidCallback? onChanged;
  const GiftStoreNote({super.key, required this.order, this.onChanged});

  static String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

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
                      : order.isGiftSizeReserved
                          ? tr('Подарок: ждём подтверждения получателя',
                              'Сыйлық: алушының растауын күтеміз')
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
                ? tr(
                    'Получатель не открыл подарок за 30 дней. Покупатель может запросить возврат — отмените заказ после согласования.',
                    'Алушы сыйлықты 30 күн ішінде ашпады. Сатып алушы қайтаруды сұрай алады — келісіп, тапсырысты бас тартыңыз.')
                : order.isGiftSizeReserved
                    ? tr(
                        'Размер ${trValue(order.items.first.size)} забронирован отправителем — получатель может подтвердить его или выбрать другой размер/товар. Выдача после подтверждения.',
                        '${trValue(order.items.first.size)} өлшемін сыйлаушы брондады — алушы оны растайды не басқа өлшем/тауар таңдайды. Растағаннан кейін беріледі.')
                    : tr(
                        'Выдача и передача курьеру станут доступны после выбора размера. Товар не зарезервирован — размер определится при получении.',
                        'Өлшем таңдалғанша беру мен курьерге тапсыру қолжетімсіз. Тауар брондалмаған — өлшем алушы таңдағанда анықталады.'),
            style: manrope(12, FontWeight.w500, color: cInk2),
          ),
        // Қосымша төлем — беру кезінде МІНДЕТТІ түрде алынады (ірі көрсетеміз)
        if (order.hasGiftExtraDue)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 6, bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: cRedTint,
              borderRadius: BorderRadius.circular(kR12),
              border: Border.all(color: cRed.withValues(alpha: 0.35)),
            ),
            child: Row(children: [
              const Icon(Icons.payments_rounded, color: cRedInk, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  tr('Доплата ${money(order.giftExtraDue)} при выдаче',
                      'Беру кезінде ${money(order.giftExtraDue)} қосымша төлем'),
                  style: manrope(14, FontWeight.w800, color: cRedInk),
                ),
              ),
            ]),
          ),
        if (order.giftExchangeLog.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              () {
                final l = order.giftExchangeLog.last;
                final from =
                    '${l['from_product'] ?? ''} ${l['from_size'] ?? ''}'.trim();
                final to = '${l['to_product'] ?? ''} ${l['to_size'] ?? ''}'.trim();
                return tr('Обмен: $from → $to', 'Ауыстыру: $from → $to');
              }(),
              style: manrope(12, FontWeight.w700, color: cInk2),
            ),
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
        // Сыйлық = тек ауыстыру (ақша қайтарылмайды): дүкен кассада ауыстырады.
        if (order.canGiftStoreExchange) ...[
          const SizedBox(height: 10),
          if (order.status == OrderModel.statusCompleted)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                tr('Обмен возможен до ${_date(order.returnDeadline)} (возврат денег не предусмотрен)',
                    'Ауыстыру ${_date(order.returnDeadline)} дейін (ақша қайтарылмайды)'),
                style: manrope(12, FontWeight.w600, color: cInk2),
              ),
            ),
          QSoftButton(
            label: tr('Обмен', 'Ауыстыру'),
            height: 42,
            icon: const Icon(Icons.swap_horiz_rounded, color: cGreen, size: 19),
            onPressed: () async {
              final ok = await showGiftStoreExchange(context, order);
              if (ok) onChanged?.call();
            },
          ),
        ],
      ]),
    );
  }
}

/// Дүкенде сыйлықты беру кезінде қосымша төлемнің қалай алынғанын сұрайды
/// ('cash' | 'kaspi'); бас тартса — null. Сома ІРІ көрсетіледі.
Future<String?> askGiftExtraPayment(BuildContext context, double amount) =>
    showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                    color: cLine, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            Text(
                tr('Подарок · доплата ${money(amount)}',
                    'Сыйлық · қосымша төлем ${money(amount)}'),
                textAlign: TextAlign.center,
                style: manrope(17, FontWeight.w800, color: cInk)),
            const SizedBox(height: 4),
            Text(
                tr('Получатель выбрал товар дороже подарка. Как он оплатил разницу?',
                    'Алушы сыйлықтан қымбат тауар таңдады. Айырманы қалай төледі?'),
                textAlign: TextAlign.center,
                style: manrope(13, FontWeight.w500, color: cInk2)),
            const SizedBox(height: 18),
            QPrimaryButton(
              label: tr('Наличными', 'Қолма-қол'),
              icon: const Icon(Icons.payments_outlined,
                  color: Colors.white, size: 19),
              onPressed: () => Navigator.pop(ctx, 'cash'),
            ),
            const SizedBox(height: 10),
            QSoftButton(
              label: 'Kaspi',
              icon: const Icon(Icons.phone_iphone_rounded,
                  color: cGreen, size: 19),
              onPressed: () => Navigator.pop(ctx, 'kaspi'),
            ),
          ]),
        ),
      ),
    );
