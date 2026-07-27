import 'package:flutter/material.dart';
import '../../../data/models/sale_model.dart';
import '../../../theme/qoima_design.dart';

import '../../../core/lang.dart';

/// Push deep-link арқылы ашылатын жалғыз сатылымның детайы (тізімсіз).
/// Мазмұны SalesScreen-дегі _SaleCard._showDetail() bottom-sheet-імен
/// мағыналас — бірақ бөлек толық экран (өз артқа батырмасымен).
class SaleDetailScreen extends StatelessWidget {
  final SaleModel sale;
  const SaleDetailScreen({super.key, required this.sale});

  @override
  Widget build(BuildContext context) {
    final d = sale.saleDate;
    final dateStr =
        '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
    final timeStr =
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

    return Scaffold(
      backgroundColor: cBg,
      body: Column(children: [
        QGradientHeader(
          title: sale.isReturn
              ? tr('Возврат', 'Қайтару')
              : sale.isWriteOff
                  ? tr('Списание', 'Списание')
                  : tr('Продажа', 'Сатылым'),
          subtitle: sale.productName,
          compact: true,
          showBack: true,
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              QCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (sale.isWriteOff)
                        _InfoRow(
                            label: tr('Операция', 'Әрекет'),
                            value: tr(
                                'Списание (недостача)', 'Списание (жетіспеушілік)')),
                      if (sale.receiptNumber.isNotEmpty)
                        _InfoRow(
                            label: tr('Номер чека', 'Чек нөмірі'),
                            value: sale.receiptNumber),
                      _InfoRow(
                          label: sale.isWriteOff
                              ? tr('Дата списания', 'Списание күні')
                              : tr('Дата продажи', 'Сату күні'),
                          value: '$dateStr · $timeStr'),
                      _InfoRow(
                        label: sale.isWriteOff
                            ? tr('Оформил', 'Рәсімдеген')
                            : tr('Продавец', 'Сатушы'),
                        value: sale.isOnline ? 'Онлайн 🛒' : sale.sellerName,
                      ),
                      if (!sale.isWriteOff)
                        _InfoRow(
                          label: tr('Тип оплаты', 'Төлем түрі'),
                          value: sale.paymentMethod.isEmpty
                              ? '—'
                              : sale.paymentMethod,
                        ),
                      if (sale.isOnline && sale.deliveredByName.isNotEmpty)
                        _InfoRow(
                            label: tr('Выдал заказ', 'Тапсырды берген'),
                            value: sale.deliveredByName),
                      if (sale.hasDiscount) ...[
                        _InfoRow(
                            label: tr('Базовая цена', 'Базалық баға'),
                            value: '${sale.basePrice.toStringAsFixed(0)} ₸'),
                        _InfoRow(
                            label: tr('Скидка', 'Жеңілдік'),
                            value:
                                '-${sale.effectiveDiscountPercent.toStringAsFixed(0)}%'),
                      ],
                      const SizedBox(height: 8),
                      Text(
                          sale.isWriteOff
                              ? tr('Списанные размеры:', 'Списание өлшемдері:')
                              : tr('Проданные размеры:', 'Сатылған өлшемдер:'),
                          style: manrope(13, FontWeight.w600, color: cInk)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: sale.sizesSold.entries
                            .where((e) => e.value > 0)
                            .map((e) => Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                    color:
                                        sale.isWriteOff ? cRedTint : cGreenTint,
                                    borderRadius: BorderRadius.circular(8)),
                                child: Text(
                                    tr('Р.${e.key} × ${e.value} шт.',
                                        'Ө.${e.key} × ${e.value} дана'),
                                    style: manrope(13, FontWeight.w600,
                                        color: sale.isWriteOff
                                            ? cRed
                                            : cGreenDeep))))
                            .toList(),
                      ),
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 8),
                      Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                                sale.isWriteOff
                                    ? tr('Списано:', 'Списание:')
                                    : tr('Итого:', 'Барлығы:'),
                                style: manrope(15, FontWeight.w500,
                                    color: cInk2)),
                            Text('${sale.totalPrice.toStringAsFixed(0)} ₸',
                                style: manrope(22, FontWeight.w800,
                                    color: sale.isWriteOff ? cRed : cGreen)),
                          ]),
                    ]),
              ),
            ],
          ),
        ),
      ]),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label, value;
  const _InfoRow({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          Text(label, style: manrope(13, FontWeight.w500, color: cInk2)),
          const Spacer(),
          Text(value, style: manrope(13, FontWeight.w700, color: cInk)),
        ]),
      );
}
