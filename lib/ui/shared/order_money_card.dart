import 'package:flutter/material.dart';
import '../../core/lang.dart';
import '../../data/models/order_model.dart';
import '../../theme/qoima_design.dart';

/// Тапсырыс ақшасының ТОЛЫҚ жіктелуі — клиент, дүкен, сатушы және курьер
/// БІР ЖӘНЕ СОЛ санды көреді. Жасырын бап жоқ: әр жол кімге тиесілі екені
/// жазылады.
///
/// АҚША ЕРЕЖЕСІ (0053):
///   тауар (− промо) + «өлшеп көру» → ДҮКЕН  (алдын ала аударым + чек)
///   жеткізу                        → КУРЬЕР (алғанда, тікелей)
///
/// [audience] — кімге көрсетіліп тұр: 'client' | 'store' | 'courier'.
/// Тек екпін өзгереді, САНДАР бәріне бірдей.
class OrderMoneyCard extends StatelessWidget {
  final OrderModel order;
  final String audience;

  const OrderMoneyCard({
    super.key,
    required this.order,
    this.audience = 'store',
  });

  bool get _isStore => audience == 'store';
  bool get _isCourier => audience == 'courier';

  @override
  Widget build(BuildContext context) {
    final o = order;
    final isRes = o.isSmartReservation;
    final rows = <Widget>[];

    // ── 1) Тауар ─────────────────────────────────────────────────────────────
    rows.add(_row(tr('Товары', 'Тауарлар'), money(o.total)));
    if (o.promoDiscount > 0) {
      rows.add(_row(
          o.promoCode.isEmpty
              ? tr('Промокод', 'Промокод')
              : tr('Промокод ${o.promoCode}', 'Промокод ${o.promoCode}'),
          '−${money(o.promoDiscount)}',
          color: cGreen));
    }
    if (o.fittingFee > 0) {
      rows.add(_row(tr('Примерка (услуга магазина)', 'Өлшеп көру (дүкен қызметі)'),
          money(o.fittingFee)));
    }

    // ── 2) Дүкенге тиесілі ───────────────────────────────────────────────────
    rows.add(const SizedBox(height: 6));
    rows.add(_bucket(
      icon: Icons.storefront_rounded,
      tone: 'green',
      title: isRes
          ? tr('Магазину — депозит', 'Дүкенге — депозит')
          : tr('Магазину — переводом', 'Дүкенге — аударыммен'),
      amount: isRes ? o.depositAmount : o.storeAmount,
      note: isRes
          ? tr('Доплата в магазине: ${money(o.remainingAmount)}',
              'Дүкенде доплата: ${money(o.remainingAmount)}')
          : (o.paymentBank.isEmpty ? '' : o.paymentBank),
      strong: _isStore,
    ));

    // ── 3) Курьерге тиесілі ──────────────────────────────────────────────────
    if (o.courierAmount > 0) {
      rows.add(const SizedBox(height: 6));
      rows.add(_bucket(
        icon: Icons.delivery_dining_rounded,
        tone: 'amber',
        title: tr('Курьеру — при получении', 'Курьерге — алғанда'),
        amount: o.courierAmount,
        note: o.deliveryFeeCollected
            ? tr('Получено курьером', 'Курьер алды')
            : (_isStore
                ? tr('Клиент платит курьеру напрямую — в вашу кассу не идёт',
                    'Клиент курьерге тікелей төлейді — сіздің кассаға түспейді')
                : tr('Наличными курьеру', 'Курьерге қолма-қол')),
        strong: _isCourier,
        done: o.deliveryFeeCollected,
      ));
    }

    // ── 4) Клиенттің жалпы шығыны ────────────────────────────────────────────
    if (o.courierAmount > 0) {
      rows.add(const SizedBox(height: 8));
      rows.add(_row(
          tr('Всего расходов клиента', 'Клиенттің жалпы шығыны'),
          money(isRes ? o.depositAmount + o.courierAmount : o.clientTotal),
          color: cInk3));
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
      decoration: BoxDecoration(
        color: cBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cLine),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.receipt_long_rounded, size: 15, color: cInk3),
          const SizedBox(width: 7),
          Text(tr('Расчёт', 'Есеп-қисап'),
              style: manrope(11.5, FontWeight.w800, color: cInk3)),
        ]),
        const SizedBox(height: 8),
        ...rows,
      ]),
    );
  }

  Widget _row(String label, String value, {Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Flexible(
            child: Text(label,
                style: manrope(12, FontWeight.w600, color: cInk2),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 8),
          Text(value,
              style: manrope(12.5, FontWeight.w700, color: color ?? cInk)),
        ]),
      );

  /// Ақша «шелегі» — кімге тиесілі екені айқын көрінетін блок.
  Widget _bucket({
    required IconData icon,
    required String tone,
    required String title,
    required double amount,
    required String note,
    required bool strong,
    bool done = false,
  }) {
    final color = tone == 'green' ? cGreen : cAmber;
    final bg = tone == 'green' ? cGreenTint : cAmberTint;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(11),
        border: strong ? Border.all(color: color.withValues(alpha: 0.5)) : null,
      ),
      child: Row(children: [
        Icon(done ? Icons.check_circle_rounded : icon, size: 17, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: manrope(12, FontWeight.w800, color: cInk)),
            if (note.isNotEmpty)
              Text(note,
                  style: manrope(10.5, FontWeight.w600, color: cInk3),
                  maxLines: 2),
          ]),
        ),
        const SizedBox(width: 8),
        Text(money(amount),
            style: manrope(strong ? 16 : 14, FontWeight.w800, color: color)),
      ]),
    );
  }
}
