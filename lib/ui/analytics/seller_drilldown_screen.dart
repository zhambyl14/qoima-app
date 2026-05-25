import 'package:flutter/material.dart';
import '../../data/models/models.dart';
import '../../data/services/firestore_service.dart';
import '../../theme/app_theme.dart';

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
      backgroundColor: AppTheme.background,
      body: StreamBuilder<List<SaleModel>>(
        stream: FirestoreService().watchSalesHistory(),
        builder: (_, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
          }
          final all = snap.data ?? [];
          final sales = all
              .where((s) =>
                  s.sellerId == sellerId &&
                  s.saleDate.month == month.month &&
                  s.saleDate.year == month.year)
              .toList()
            ..sort((a, b) => b.saleDate.compareTo(a.saleDate));

          final totalRevenue = sales.fold<double>(0, (s, e) => s + e.totalPrice);
          final totalPairs   = sales.fold<int>(0, (s, e) => s + e.quantity);
          final avgCheck     = sales.isEmpty ? 0.0 : totalRevenue / sales.length;
          final totalDiscount = sales.fold<double>(0, (s, e) => s + e.discountAmount);
          final salesWithDiscount = sales.where((s) => s.discountAmount > 0).length;

          return CustomScrollView(
            slivers: [
              _Header(sellerName: sellerName, month: month,
                  onBack: () => Navigator.pop(context)),

              // KPI row
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Row(
                    children: [
                      _KpiCard(label: 'Сатулар', value: '${sales.length}',
                          sub: 'транзакция', color: AppTheme.primary),
                      const SizedBox(width: 8),
                      _KpiCard(label: 'Жұптар', value: '$totalPairs',
                          sub: 'дана', color: AppTheme.primaryLight),
                      const SizedBox(width: 8),
                      _KpiCard(label: 'Орт. чек', value: _fmt(avgCheck),
                          sub: '₸', color: AppTheme.success),
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

              // Daily chart
              if (sales.isNotEmpty) ...[
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                    child: Text('Күндік белсенділік',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary)),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _DailyChart(sales: sales, month: month),
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
                      totalSales: sales.length,
                      totalDiscount: totalDiscount,
                    ),
                  ),
                ),

              // Recent sales header
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text('Соңғы сатулар',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary)),
                ),
              ),

              // Sales list
              if (sales.isEmpty)
                const SliverToBoxAdapter(
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text('Осы айда сатулар жоқ',
                          style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (_, i) => _SaleRow(sale: sales[i]),
                      childCount: sales.length,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  static String _fmt(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000)    return '${(v / 1000).toStringAsFixed(0)}K';
    return v.toStringAsFixed(0);
  }
}

// ── Header with gradient ───────────────────────────────────────────────────────
class _Header extends StatelessWidget {
  final String sellerName;
  final DateTime month;
  final VoidCallback onBack;
  const _Header({required this.sellerName, required this.month, required this.onBack});

  static const _months = [
    '', 'Қаңтар', 'Ақпан', 'Наурыз', 'Сәуір', 'Мамыр', 'Маусым',
    'Шілде', 'Тамыз', 'Қыркүйек', 'Қазан', 'Қараша', 'Желтоқсан',
  ];

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AppTheme.primary, AppTheme.primaryLight],
            begin: Alignment.topLeft, end: Alignment.bottomRight,
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
                              fontSize: 20, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text('${_months[month.month]} ${month.year}',
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
  const _KpiCard({required this.label, required this.value,
      required this.sub, required this.color});

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 11, color: color,
            fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800,
            color: color), maxLines: 1, overflow: TextOverflow.ellipsis),
        Text(sub, style: const TextStyle(fontSize: 11,
            color: AppTheme.textSecondary)),
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
    if (v >= 1000)    return '${(v / 1000).toStringAsFixed(0)}K ₸';
    return '${v.toStringAsFixed(0)} ₸';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .04),
            blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Row(
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: AppTheme.success.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.payments_outlined,
                color: AppTheme.success, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Жалпы түсім', style: TextStyle(
                  fontSize: 12, color: AppTheme.textSecondary)),
              Text(_fmt(totalRevenue), style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w800,
                  color: AppTheme.success)),
            ]),
          ),
          if (totalDiscount > 0)
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              const Text('Жеңілдік', style: TextStyle(
                  fontSize: 11, color: AppTheme.textSecondary)),
              Text('−${_fmt(totalDiscount)}', style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600,
                  color: AppTheme.warning)),
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
  const _DiscountCard({required this.salesWithDiscount,
      required this.totalSales, required this.totalDiscount});

  @override
  Widget build(BuildContext context) {
    final pct = totalSales > 0
        ? (salesWithDiscount / totalSales * 100).toStringAsFixed(0)
        : '0';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.warningLight,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(children: [
        const Icon(Icons.local_offer_outlined, color: AppTheme.warning, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(
          'Жеңілдікпен $salesWithDiscount сату ($pct%) — '
          'барлығы ${totalDiscount.toStringAsFixed(0)} ₸',
          style: const TextStyle(fontSize: 13, color: Color(0xFF92400E),
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
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .04),
            blurRadius: 8, offset: const Offset(0, 2))],
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
                Text('${_tapped! + 1} күн',
                    style: const TextStyle(fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textSecondary)),
                const Spacer(),
                Text(_fmtRevenue(byDay[_tapped!]),
                    style: const TextStyle(fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.success)),
              ] else ...[
                const Text('Барлығы',
                    style: TextStyle(fontSize: 12, color: AppTheme.textHint)),
                const Spacer(),
                Text(
                  _fmtRevenue(widget.sales
                      .fold(0.0, (s, e) => s + e.totalPrice)),
                  style: const TextStyle(fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.primary),
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
                final v      = byDay[i];
                final isSel  = _tapped == i;
                return Expanded(
                  child: GestureDetector(
                    onTap: () =>
                        setState(() => _tapped = _tapped == i ? null : i),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1),
                      child: Container(
                        height: v > 0
                            ? (v / effectiveMax) * 66 + 3
                            : 2,
                        decoration: BoxDecoration(
                          color: isSel
                              ? AppTheme.success
                              : v > 0
                                  ? AppTheme.primary
                                  : AppTheme.border,
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
              final day   = i + 1;
              final mid   = (daysInMonth / 2).round();
              final isSel = _tapped == i;
              final show  = isSel || day == 1 || day == mid || day == daysInMonth;
              return Expanded(
                child: Text(
                  show ? '$day' : '',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 9,
                    color: isSel ? AppTheme.primary : AppTheme.textHint,
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
  const _SaleRow({required this.sale});

  @override
  Widget build(BuildContext context) {
    final hasDiscount = sale.discountAmount > 0;
    final dateStr = '${sale.saleDate.day.toString().padLeft(2, '0')}.'
        '${sale.saleDate.month.toString().padLeft(2, '0')}.'
        '${sale.saleDate.year}';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .03),
            blurRadius: 6, offset: const Offset(0, 1))],
      ),
      child: Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: Text('${sale.quantity}',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                    color: AppTheme.primary)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Өл. ${sale.selectedSize}', style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary)),
            Text(dateStr, style: const TextStyle(
                fontSize: 11, color: AppTheme.textHint)),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('${sale.totalPrice.toStringAsFixed(0)} ₸',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary)),
          if (hasDiscount)
            Text('−${sale.discountAmount.toStringAsFixed(0)} ₸',
                style: const TextStyle(fontSize: 11, color: AppTheme.warning,
                    fontWeight: FontWeight.w500)),
        ]),
      ]),
    );
  }
}
