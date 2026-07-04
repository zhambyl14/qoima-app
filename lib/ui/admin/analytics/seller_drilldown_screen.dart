import 'package:flutter/material.dart';
import '../../../data/models/models.dart';
import '../../../data/services/firestore_service.dart';
import '../../../theme/qoima_design.dart';

import '../../../core/lang.dart';
class SellerDrilldownScreen extends StatelessWidget {
  final String sellerId;
  final String sellerName;
  final DateTime month;

  const SellerDrilldownScreen({
    super.key,
    required this.sellerId,
    required this.sellerName,
    required this.month,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cBg,
      body: StreamBuilder<List<ProductModel>>(
        stream: FirestoreService().watchProducts(),
        builder: (_, pSnap) {
          final nameById = <String, String>{
            for (final p in (pSnap.data ?? [])) p.id: p.name,
          };
          return StreamBuilder<List<SaleModel>>(
            stream: FirestoreService().watchSalesHistory(),
            builder: (_, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(
                    child: CircularProgressIndicator(color: cGreen));
              }
              final all = snap.data ?? [];
              // Айдағы осы сатушының ОФЛАЙН жазбалары (возврат та кіреді) — таза
              // есеп үшін. Онлайн сатылым/возврат 'онлайн' бакетіне жазылады әрі
              // тірі сатушыға тиесілі емес, сондықтан мұнда КІРМЕЙДІ (басты
              // «Продавцы» қойындысы да онлайнды елемейді).
              final entries = all
                  .where((s) =>
                      s.sellerId == sellerId &&
                      !s.isOnline &&
                      s.saleDate.month == month.month &&
                      s.saleDate.year == month.year)
                  .toList()
                ..sort((a, b) => b.saleDate.compareTo(a.saleDate));

              final returns = entries.where((s) => s.isReturn).toList();
              final pureSales = entries.where((s) => !s.isReturn).toList();

              // Таза көрсеткіштер: возврат шегеріледі.
              final totalRevenue =
                  entries.fold<double>(0, (s, e) => s + e.totalPrice);
              final totalPairs = entries.fold<int>(
                  0, (s, e) => s + (e.isReturn ? -e.quantity : e.quantity));
              final netCount = pureSales.length - returns.length;
              final avgCheck =
                  netCount <= 0 ? 0.0 : totalRevenue / netCount;
              final totalDiscount =
                  pureSales.fold<double>(0, (s, e) => s + e.discountAmount);
              final salesWithDiscount =
                  pureSales.where((s) => s.discountAmount > 0).length;

              return CustomScrollView(
                slivers: [
                  _Header(
                      sellerName: sellerName,
                      month: month,
                      onBack: () => Navigator.pop(context)),

                  // KPI row
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      child: Row(
                        children: [
                          _KpiCard(
                              label: tr('Продажи', 'Сатулар'),
                              value: '$netCount',
                              sub: tr('транзакций', 'транзакция'),
                              color: cGreen),
                          const SizedBox(width: 8),
                          _KpiCard(
                              label: tr('Штук', 'Дана'),
                              value: '$totalPairs',
                              sub: tr('шт', 'дана'),
                              color: cGreenBright),
                          const SizedBox(width: 8),
                          _KpiCard(
                              label: tr('Ср. чек', 'Орт. чек'),
                              value: _fmt(avgCheck),
                              sub: '₸',
                              color: cGreen),
                        ],
                      ),
                    ),
                  ),

                  // Revenue card
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: _RevenueCard(
                        totalRevenue: totalRevenue,
                        totalDiscount: totalDiscount,
                      ),
                    ),
                  ),

                  // Daily chart (возврат теріс сома → күндік белсенділік нетпен)
                  if (entries.isNotEmpty) ...[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                        child: Text(tr('Дневная активность', 'Күндік белсенділік'),
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: cInk)),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: _DailyChart(sales: entries, month: month),
                      ),
                    ),
                  ],

                  // Discount stats
                  if (salesWithDiscount > 0)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: _DiscountCard(
                          salesWithDiscount: salesWithDiscount,
                          totalSales: pureSales.length,
                          totalDiscount: totalDiscount,
                        ),
                      ),
                    ),

                  // Recent sales header
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Text(tr('Последние продажи', 'Соңғы сатулар'),
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: cInk)),
                    ),
                  ),

                  // Sales list (возврат жолы да көрсетіледі — қызыл, теріс сома)
                  if (entries.isEmpty)
                    SliverToBoxAdapter(
                      child: Center(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: Text(tr('В этом месяце продаж нет', 'Осы айда сатулар жоқ'),
                              style: TextStyle(
                                  color: cInk2, fontSize: 14)),
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (_, i) => _SaleRow(
                            sale: entries[i],
                            productName: nameById[entries[i].productId] ?? '',
                          ),
                          childCount: entries.length,
                        ),
                      ),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  static String _fmt(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(0)}K';
    return v.toStringAsFixed(0);
  }
}

// ── Header with gradient ───────────────────────────────────────────────────────
class _Header extends StatelessWidget {
  final String sellerName;
  final DateTime month;
  final VoidCallback onBack;
  const _Header(
      {required this.sellerName, required this.month, required this.onBack});

  static const _monthsRu = [
    '', 'Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь',
    'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь',
  ];
  static const _monthsKk = [
    '', 'Қаңтар', 'Ақпан', 'Наурыз', 'Сәуір', 'Мамыр', 'Маусым',
    'Шілде', 'Тамыз', 'Қыркүйек', 'Қазан', 'Қараша', 'Желтоқсан',
  ];

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [cGreen, cGreenBright],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 16, 20),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded,
                      color: Colors.white, size: 20),
                  onPressed: onBack,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(sellerName,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text('${tr(_monthsRu[month.month], _monthsKk[month.month])} ${month.year}',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── KPI card ───────────────────────────────────────────────────────────────────
class _KpiCard extends StatelessWidget {
  final String label, value, sub;
  final Color color;
  const _KpiCard(
      {required this.label,
      required this.value,
      required this.sub,
      required this.color});

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.09),
            borderRadius: BorderRadius.circular(14),
          ),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                style: TextStyle(
                    fontSize: 11, color: color, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(value,
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w800, color: color),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            Text(sub,
                style: const TextStyle(
                    fontSize: 11, color: cInk2)),
          ]),
        ),
      );
}

// ── Revenue summary card ───────────────────────────────────────────────────────
class _RevenueCard extends StatelessWidget {
  final double totalRevenue, totalDiscount;
  const _RevenueCard({required this.totalRevenue, required this.totalDiscount});

  static String _fmt(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(2)}M ₸';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(0)}K ₸';
    return '${v.toStringAsFixed(0)} ₸';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: .04),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: cGreen.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.payments_outlined,
                color: cGreen, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('Общая выручка', 'Жалпы түсім'),
                  style:
                      TextStyle(fontSize: 12, color: cInk2)),
              Text(_fmt(totalRevenue),
                  style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: cGreen)),
            ]),
          ),
          if (totalDiscount > 0)
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(tr('Скидка', 'Жеңілдік'),
                  style:
                      TextStyle(fontSize: 11, color: cInk2)),
              Text('−${_fmt(totalDiscount)}',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: cAmber)),
            ]),
        ],
      ),
    );
  }
}

// ── Discount stats card ────────────────────────────────────────────────────────
class _DiscountCard extends StatelessWidget {
  final int salesWithDiscount, totalSales;
  final double totalDiscount;
  const _DiscountCard(
      {required this.salesWithDiscount,
      required this.totalSales,
      required this.totalDiscount});

  @override
  Widget build(BuildContext context) {
    final pct = totalSales > 0
        ? (salesWithDiscount / totalSales * 100).toStringAsFixed(0)
        : '0';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cAmberTint,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(children: [
        const Icon(Icons.local_offer_outlined,
            color: cAmber, size: 20),
        const SizedBox(width: 10),
        Expanded(
            child: Text(
          tr('Продаж со скидкой: $salesWithDiscount ($pct%) — '
                  'итого ${totalDiscount.toStringAsFixed(0)} ₸',
              'Жеңілдікпен $salesWithDiscount сату ($pct%) — '
                  'барлығы ${totalDiscount.toStringAsFixed(0)} ₸'),
          style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF92400E),
              fontWeight: FontWeight.w500),
        )),
      ]),
    );
  }
}

// ── Daily bar chart ────────────────────────────────────────────────────────────
class _DailyChart extends StatefulWidget {
  final List<SaleModel> sales;
  final DateTime month;
  const _DailyChart({required this.sales, required this.month});
  @override
  State<_DailyChart> createState() => _DailyChartState();
}

class _DailyChartState extends State<_DailyChart> {
  int? _tapped; // 0-based day index

  @override
  Widget build(BuildContext context) {
    final daysInMonth =
        DateUtils.getDaysInMonth(widget.month.year, widget.month.month);
    final byDay = List<double>.filled(daysInMonth, 0.0);
    for (final s in widget.sales) {
      byDay[s.saleDate.day - 1] += s.totalPrice;
    }
    final maxVal = byDay.reduce((a, b) => a > b ? a : b);
    final effectiveMax = maxVal < 1 ? 1.0 : maxVal;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: .04),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Info row: month total by default, selected day on tap
          SizedBox(
            height: 26,
            child: Row(children: [
              if (_tapped != null) ...[
                Text(tr('${_tapped! + 1} день', '${_tapped! + 1} күн'),
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: cInk2)),
                const Spacer(),
                Text(_fmtRevenue(byDay[_tapped!]),
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: cGreen)),
              ] else ...[
                Text(tr('Итого', 'Барлығы'),
                    style: TextStyle(fontSize: 12, color: cInk3)),
                const Spacer(),
                Text(
                  _fmtRevenue(
                      widget.sales.fold(0.0, (s, e) => s + e.totalPrice)),
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: cGreen),
                ),
              ],
            ]),
          ),
          const SizedBox(height: 6),
          // Bars
          SizedBox(
            height: 72,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(daysInMonth, (i) {
                final v = byDay[i];
                final isSel = _tapped == i;
                return Expanded(
                  child: GestureDetector(
                    onTap: () =>
                        setState(() => _tapped = _tapped == i ? null : i),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1),
                      child: Container(
                        height: v > 0 ? (v / effectiveMax) * 66 + 3 : 2,
                        decoration: BoxDecoration(
                          color: isSel
                              ? cGreen
                              : v > 0
                                  ? cGreen
                                  : cLine,
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(2)),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 4),
          // X-axis: show only day 1, mid-month, last day + tapped day
          Row(
            children: List.generate(daysInMonth, (i) {
              final day = i + 1;
              final mid = (daysInMonth / 2).round();
              final isSel = _tapped == i;
              final show =
                  isSel || day == 1 || day == mid || day == daysInMonth;
              return Expanded(
                child: Text(
                  show ? '$day' : '',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 9,
                    color: isSel ? cGreen : cInk3,
                    fontWeight: isSel ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  static String _fmtRevenue(double v) {
    if (v >= 1000000) {
      return '${(v / 1000000).toStringAsFixed(1)}M ₸';
    }
    if (v >= 1000) {
      return '${(v / 1000).toStringAsFixed(0)}K ₸';
    }
    return '${v.toStringAsFixed(0)} ₸';
  }
}

// ── Sale row ───────────────────────────────────────────────────────────────────
class _SaleRow extends StatelessWidget {
  final SaleModel sale;
  final String productName;
  const _SaleRow({required this.sale, this.productName = ''});

  @override
  Widget build(BuildContext context) {
    final isReturn = sale.isReturn;
    final hasDiscount = sale.discountAmount > 0;
    final accent = isReturn ? cRed : cGreen;
    final dateStr = '${sale.saleDate.day.toString().padLeft(2, '0')}.'
        '${sale.saleDate.month.toString().padLeft(2, '0')}.'
        '${sale.saleDate.year}';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: .03),
              blurRadius: 6,
              offset: const Offset(0, 1))
        ],
      ),
      child: Row(children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: Text('${isReturn ? '−' : ''}${sale.quantity}',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: accent)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (productName.isNotEmpty)
              Text(productName,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: cInk),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            Text(
                '${isReturn ? tr('Возврат · ', 'Қайтару · ') : ''}${tr('Р', 'Ө')}. ${sale.selectedSize} · $dateStr',
                style: TextStyle(
                    fontSize: productName.isNotEmpty ? 11 : 13,
                    fontWeight: productName.isNotEmpty
                        ? FontWeight.w400
                        : FontWeight.w600,
                    color: isReturn
                        ? cRed
                        : (productName.isNotEmpty ? cInk3 : cInk))),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('${sale.totalPrice.toStringAsFixed(0)} ₸',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: isReturn ? cRed : cInk)),
          if (hasDiscount)
            Text('−${sale.discountAmount.toStringAsFixed(0)} ₸',
                style: const TextStyle(
                    fontSize: 11,
                    color: cAmber,
                    fontWeight: FontWeight.w500)),
        ]),
      ]),
    );
  }
}

