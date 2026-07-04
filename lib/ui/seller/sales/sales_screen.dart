import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/app_user.dart';
import '../../../core/l10n_ext.dart';
import '../../../core/warehouse_context.dart';
import '../../../data/models/models.dart';
import '../../../data/services/firestore_service.dart';
import '../../../theme/qoima_design.dart';
import 'make_sale_screen.dart';
import '../returns/seller_returns_tab.dart';
import '../returns/seller_make_offline_return_screen.dart';

import '../../../core/lang.dart';
class SalesScreen extends StatefulWidget {
  const SalesScreen({super.key});
  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen>
    with SingleTickerProviderStateMixin {
  final _service = FirestoreService();
  DateTime _month = DateTime.now();
  String _sellerPeriod = 'today'; // 'today'|'week'|'month'

  late final TabController _tabCtrl =
      TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  static String _fmtRevenue(double v) {
    final s = v.round().toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  List<SaleModel> _filterMonth(List<SaleModel> all) => all
      .where((s) =>
          s.saleDate.month == _month.month && s.saleDate.year == _month.year)
      .toList();

  List<SaleModel> _filterPeriod(List<SaleModel> all) {
    final now = DateTime.now();
    switch (_sellerPeriod) {
      case 'today':
        return all
            .where((s) =>
                s.saleDate.year == now.year &&
                s.saleDate.month == now.month &&
                s.saleDate.day == now.day)
            .toList();
      case 'week':
        final cutoff = now.subtract(const Duration(days: 7));
        return all.where((s) => s.saleDate.isAfter(cutoff)).toList();
      default:
        return all
            .where((s) =>
                s.saleDate.month == now.month &&
                s.saleDate.year == now.year)
            .toList();
    }
  }

  List<SaleModel> _filterSeller(List<SaleModel> all, AppUser appUser) =>
      appUser.isAdmin
          ? all
          : all.where((s) => s.sellerId == appUser.uid).toList();

  void _showHistorySheet(List<SaleModel> all, List<ProductModel> products,
      List<WarehouseModel> warehouses) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        expand: false,
        builder: (_, ctrl) => _HistorySheet(
          sales: _filterSeller(all, context.read<AppUser>()),
          products: products,
          warehouses: warehouses,
          scrollCtrl: ctrl,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appUser = context.watch<AppUser>();
    final warehouses = context.watch<WarehouseContext>().all;

    return Scaffold(
      backgroundColor: cBg,
      floatingActionButton: AnimatedBuilder(
        animation: _tabCtrl,
        builder: (_, __) {
          if (_tabCtrl.index == 1) {
            return FloatingActionButton.extended(
              onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) =>
                          const SellerMakeOfflineReturnScreen())),
              backgroundColor: cGreen,
              elevation: 0,
              icon: const Icon(Icons.assignment_return_outlined,
                  color: Colors.white, size: 22),
              label: Text(tr('Офлайн возврат', 'Офлайн қайтару'),
                  style:
                      manrope(14.5, FontWeight.w700, color: Colors.white)),
            );
          }
          return FloatingActionButton.extended(
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const MakeSaleScreen())),
            backgroundColor: cGreen,
            elevation: 0,
            icon: const Icon(Icons.add_rounded, color: Colors.white, size: 22),
            label: Text(context.l10n.makeSale,
                style: manrope(14.5, FontWeight.w700, color: Colors.white)),
          );
        },
      ),
      body: StreamBuilder<List<SaleModel>>(
        stream: _service.watchSalesHistory(),
        builder: (_, salesSnap) {
          if (salesSnap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.error_outline_rounded,
                      color: cRed, size: 40),
                  const SizedBox(height: 12),
                  Text(salesSnap.error.toString(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: cInk2, fontSize: 13)),
                ]),
              ),
            );
          }
          final allSales = salesSnap.data ?? [];
          return StreamBuilder<List<ProductModel>>(
            stream: _service.watchProducts(),
            builder: (_, prodSnap) {
              final products = prodSnap.data ?? [];
              final sellerSales = _filterSeller(allSales, appUser);
              final monthSales = appUser.isAdmin
                  ? _filterMonth(sellerSales)
                  : _filterPeriod(sellerSales);
              final total =
                  monthSales.fold<double>(0, (s, e) => s + e.totalPrice);
              final now = DateTime.now();
              final today = DateTime(now.year, now.month, now.day);
              final todayRevenue = sellerSales
                  .where((s) {
                    final d = s.saleDate;
                    return d.year == today.year &&
                        d.month == today.month &&
                        d.day == today.day;
                  })
                  .fold<double>(0, (a, b) => a + b.totalPrice);

              return Column(children: [
                // ── Header ──────────────────────────────────────────
                Container(
                  decoration: const BoxDecoration(gradient: kGrad),
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Expanded(
                              child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                        appUser.isAdmin
                                            ? context.l10n.salesTitle
                                            : tr('Мои продажи', 'Менің сатылымдарым'),
                                        style: manrope(23, FontWeight.w800,
                                            color: Colors.white,
                                            letterSpacing: -0.5)),
                                    Text(
                                      appUser.isAdmin
                                          ? context.l10n.overviewSub
                                          : tr('Сегодня · ${monthSales.where((s) { final n = DateTime.now(); return !s.isReturn && s.saleDate.year == n.year && s.saleDate.month == n.month && s.saleDate.day == n.day; }).length} продаж', 'Бүгін · ${monthSales.where((s) { final n = DateTime.now(); return !s.isReturn && s.saleDate.year == n.year && s.saleDate.month == n.month && s.saleDate.day == n.day; }).length} сатылым'),
                                      style: manrope(13, FontWeight.w500,
                                          color: Colors.white
                                              .withValues(alpha: 0.78)),
                                    ),
                                  ]),
                            ),
                            GestureDetector(
                              onTap: () => _showHistorySheet(
                                  allSales, products, warehouses),
                              child: Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color:
                                      Colors.white.withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(Icons.history_rounded,
                                    color: Colors.white, size: 20),
                              ),
                            ),
                          ]),
                          // Revenue card
                          const SizedBox(height: 14),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    appUser.isAdmin
                                        ? tr('Выручка за сегодня', 'Бүгінгі түсім')
                                        : _sellerPeriod == 'today'
                                            ? tr('Выручка за сегодня', 'Бүгінгі түсім')
                                            : _sellerPeriod == 'week'
                                                ? tr('Выручка за неделю', 'Апталық түсім')
                                                : tr('Выручка за месяц', 'Айлық түсім'),
                                    style: manrope(12.5, FontWeight.w600,
                                        color: Colors.white
                                            .withValues(alpha: 0.8)),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    appUser.isAdmin
                                        ? '${_fmtRevenue(todayRevenue)} ₸'
                                        : '${_fmtRevenue(total)} ₸',
                                    style: manrope(30, FontWeight.w800,
                                        color: Colors.white,
                                        letterSpacing: -0.8),
                                  ),
                                ]),
                          ),
                          // Period chips — seller only
                          if (!appUser.isAdmin) ...[
                            const SizedBox(height: 10),
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(children: [
                                _PeriodChip(
                                  label: tr('Сегодня', 'Бүгін'),
                                  value: 'today',
                                  current: _sellerPeriod,
                                  onTap: (v) =>
                                      setState(() => _sellerPeriod = v),
                                ),
                                const SizedBox(width: 8),
                                _PeriodChip(
                                  label: tr('Неделя', 'Апта'),
                                  value: 'week',
                                  current: _sellerPeriod,
                                  onTap: (v) =>
                                      setState(() => _sellerPeriod = v),
                                ),
                                const SizedBox(width: 8),
                                _PeriodChip(
                                  label: tr('Месяц', 'Ай'),
                                  value: 'month',
                                  current: _sellerPeriod,
                                  onTap: (v) =>
                                      setState(() => _sellerPeriod = v),
                                ),
                              ]),
                            ),
                          ],
                          const SizedBox(height: 10),
                          // Tab bar
                          TabBar(
                            controller: _tabCtrl,
                            isScrollable: false,
                            indicatorColor: Colors.white,
                            labelStyle: manrope(13.5, FontWeight.w700,
                                color: Colors.white),
                            unselectedLabelStyle: manrope(13.5,
                                FontWeight.w500,
                                color:
                                    Colors.white.withValues(alpha: 0.65)),
                            labelColor: Colors.white,
                            unselectedLabelColor:
                                Colors.white.withValues(alpha: 0.65),
                            tabs: [
                              Tab(text: context.l10n.salesTitle),
                              Tab(text: context.l10n.returnsTitle),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // ── Body ────────────────────────────────────────────
                Expanded(
                  child: TabBarView(
                    controller: _tabCtrl,
                    children: [
                      // Tab 0: Sales
                      RefreshIndicator(
                        color: cGreen,
                        onRefresh: () async {
                          await _service.refreshSalesHistory();
                          await _service.refreshProducts();
                        },
                        child: SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          child: _SalesBody(
                            sales: monthSales,
                            total: total,
                            month: _month,
                            showRevenue: appUser.isAdmin,
                            products: products,
                            warehouses: warehouses,
                            onMonthTap: _pickMonth,
                          ),
                        ),
                      ),
                      // Tab 1: Returns
                      const SellerReturnsTab(),
                    ],
                  ),
                ),
              ]);
            },
          );
        },
      ),
    );
  }

  Future<void> _pickMonth() async {
    DateTime temp = _month;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(context.l10n.selectMonth,
            style: manrope(17, FontWeight.w700, color: cInk)),
        content: StatefulBuilder(
            builder: (_, setS) => SizedBox(
                  width: 280,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          IconButton(
                              icon: const Icon(Icons.chevron_left,
                                  color: cGreen),
                              onPressed: () => setS(() =>
                                  temp = DateTime(temp.year - 1, temp.month))),
                          Text('${temp.year}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 17,
                                  color: cInk)),
                          IconButton(
                              icon: const Icon(Icons.chevron_right,
                                  color: cGreen),
                              onPressed: () => setS(() =>
                                  temp = DateTime(temp.year + 1, temp.month))),
                        ]),
                    const SizedBox(height: 8),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 4,
                              childAspectRatio: 1.4,
                              crossAxisSpacing: 6,
                              mainAxisSpacing: 6),
                      itemCount: 12,
                      itemBuilder: (_, i) {
                        final sel = temp.month == i + 1;
                        final mn = context.monthAbbreviations;
                        return GestureDetector(
                            onTap: () =>
                                setS(() => temp = DateTime(temp.year, i + 1)),
                            child: Container(
                                decoration: BoxDecoration(
                                    color: sel ? cGreen : cBg,
                                    borderRadius: BorderRadius.circular(8)),
                                child: Center(
                                    child: Text(mn[i],
                                        style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: sel
                                                ? Colors.white
                                                : cInk2)))));
                      },
                    ),
                  ]),
                )),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(context.l10n.cancel,
                  style: manrope(14, FontWeight.w600, color: cInk2))),
          ElevatedButton(
              onPressed: () {
                setState(() => _month = temp);
                Navigator.pop(ctx);
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: cGreen,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12))),
              child: Text(context.l10n.apply,
                  style: manrope(14, FontWeight.w700, color: Colors.white))),
        ],
      ),
    );
  }
}

// ── Body ──────────────────────────────────────────────────────────────────────
class _SalesBody extends StatelessWidget {
  final List<SaleModel> sales;
  final List<ProductModel> products;
  final List<WarehouseModel> warehouses;
  final double total;
  final DateTime month;
  final bool showRevenue;
  final VoidCallback onMonthTap;

  const _SalesBody({
    required this.sales,
    required this.products,
    required this.warehouses,
    required this.total,
    required this.month,
    required this.showRevenue,
    required this.onMonthTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Row(children: [
          GestureDetector(
            onTap: onMonthTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                  color: cGreenTint,
                  borderRadius: BorderRadius.circular(20)),
              child: Row(children: [
                const Icon(Icons.calendar_today_outlined,
                    size: 14, color: cGreen),
                const SizedBox(width: 6),
                Text(_fmtShort(month, context),
                    style: manrope(13, FontWeight.w600, color: cGreen)),
                const SizedBox(width: 4),
                const Icon(Icons.keyboard_arrow_down_rounded,
                    color: cGreen, size: 16),
              ]),
            ),
          ),
          const Spacer(),
          if (showRevenue)
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('${_fmtNum(total)} ₸',
                  style: manrope(20, FontWeight.w800, color: cInk)),
              Text(
                  '${sales.where((s) => !s.isReturn).length} ${context.l10n.salesSuffix}',
                  style: manrope(12, FontWeight.w500, color: cInk3)),
            ])
          else
            Text(
                tr('Сегодня: ${sales.where((s) => !s.isReturn && _isToday(s.saleDate)).length} прод.', 'Бүгін: ${sales.where((s) => !s.isReturn && _isToday(s.saleDate)).length} сат.'),
                style: manrope(13, FontWeight.w600, color: cInk2)),
        ]),
      ),

      if (sales.isEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 60, bottom: 40),
          child: Column(children: [
            Icon(Icons.receipt_long_outlined,
                size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(context.l10n.noSalesThisMonth,
                style: const TextStyle(
                    fontSize: 16,
                    color: cInk2,
                    fontWeight: FontWeight.w500)),
          ]),
        )
      else
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(context.l10n.operations,
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: cInk)),
            const SizedBox(height: 10),
            ..._buildGroupedSales(context, sales, products, warehouses),
          ]),
        ),
    ]);
  }

  static List<Widget> _buildGroupedSales(
    BuildContext context,
    List<SaleModel> sales,
    List<ProductModel> products,
    List<WarehouseModel> warehouses,
  ) {
    final map = <DateTime, List<SaleModel>>{};
    for (final s in sales) {
      final day = DateTime(s.saleDate.year, s.saleDate.month, s.saleDate.day);
      (map[day] ??= []).add(s);
    }
    final days = map.keys.toList()..sort((a, b) => b.compareTo(a));

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    final result = <Widget>[];
    for (final day in days) {
      final daySales = map[day]!;
      final dayTotal = daySales.fold<double>(0, (sum, s) => sum + s.totalPrice);

      final String label;
      if (day == today) {
        label = tr('Сегодня', 'Бүгін');
      } else if (day == yesterday) {
        label = tr('Вчера', 'Кеше');
      } else {
        label = '${day.day.toString().padLeft(2, '0')}'
            '.${day.month.toString().padLeft(2, '0')}'
            '.${day.year}';
      }

      result.add(Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
                color: cGreenTint,
                borderRadius: BorderRadius.circular(20)),
            child: Text(label,
                style: manrope(12, FontWeight.w700, color: cGreenDeep)),
          ),
          const Spacer(),
          Text('${dayTotal.toStringAsFixed(0)} ₸',
              style: manrope(13, FontWeight.w700, color: cGreen)),
        ]),
      ));

      for (final s in daySales) {
        final prod = products.firstWhere((p) => p.id == s.productId,
            orElse: () => ProductModel(
                id: '',
                name: context.l10n.productDeleted,
                brand: '',
                type: '',
                material: '',
                category: '',
                color: '',
                articul: '',
                status: '',
                images: []));
        String whName = '';
        if (s.warehouseId.isNotEmpty) {
          try {
            whName = warehouses.firstWhere((w) => w.id == s.warehouseId).name;
          } catch (_) {}
        }
        result.add(_SaleCard(sale: s, product: prod, warehouseName: whName));
      }
    }
    return result;
  }

  static bool _isToday(DateTime d) {
    final now = DateTime.now();
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }

  static String _fmtNum(double v) {
    if (v < 0) return '-${_fmtNum(-v)}';
    final s = v.round().toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  String _fmtShort(DateTime d, BuildContext ctx) => ctx.monthShort(d);
}

// ── Sale Card ─────────────────────────────────────────────────────────────────
class _SaleCard extends StatelessWidget {
  final SaleModel sale;
  final ProductModel product;
  final String warehouseName;
  const _SaleCard(
      {required this.sale, required this.product, this.warehouseName = ''});

  @override
  Widget build(BuildContext context) {
    final d = sale.saleDate;
    final dateStr =
        '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
    final timeStr =
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    return GestureDetector(
      onTap: () => _showDetail(context, dateStr, timeStr),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
            color: cSurface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: cLine),
            boxShadow: kShadowSm),
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Row(children: [
            QIconTile(
              icon: sale.isReturn
                  ? const Icon(Icons.assignment_return_rounded,
                      color: cRed, size: 19)
                  : product.images.isNotEmpty
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.network(product.images.first,
                              width: 40, height: 40, fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Icon(
                                  Icons.check_rounded, color: cGreen, size: 19)))
                      : const Icon(Icons.check_rounded, color: cGreen, size: 19),
              tone: sale.isReturn ? 'red' : 'green',
              size: 40,
            ),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(product.name,
                      style: manrope(13.5, FontWeight.w700, color: cInk),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(
                      sale.isReturn
                          ? tr('Возврат · $timeStr', 'Қайтару · $timeStr')
                          : '${sale.receiptNumber.isNotEmpty ? '${sale.receiptNumber}  ·  ' : ''}${tr('Р', 'Ө')}: ${sale.sizesSold.entries.where((e) => e.value > 0).map((e) => e.key).join(', ')}  ·  $timeStr',
                      style: manrope(12, FontWeight.w500,
                          color: sale.isReturn ? cRed : cInk3),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  if (warehouseName.isNotEmpty) ...[
                    const SizedBox(height: 1),
                    Text(warehouseName,
                        style: manrope(11, FontWeight.w500, color: cInk3)),
                  ],
                ])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              if (sale.hasDiscount)
                Text('${sale.basePrice.toStringAsFixed(0)} ₸',
                    style: manrope(11, FontWeight.w500, color: cInk3)
                        .copyWith(decoration: TextDecoration.lineThrough)),
              Text('${sale.totalPrice.toStringAsFixed(0)} ₸',
                  style: manrope(14.5, FontWeight.w800,
                      color: (sale.hasDiscount || sale.isReturn) ? cRed : cInk)),
              if (sale.hasDiscount)
                Text('-${sale.effectiveDiscountPercent.toStringAsFixed(0)}%',
                    style: manrope(11, FontWeight.w700, color: cAmber)),
              const SizedBox(height: 2),
              _PaymentBadge(method: _resolveMethod(sale)),
            ]),
          ]),
        ),
      ),
    );
  }

  void _showDetail(BuildContext context, String dateStr, String timeStr) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                  child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              Row(children: [
                ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: product.images.isNotEmpty
                        ? Image.network(product.images.first,
                            width: 56,
                            height: 56,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _detailIcon())
                        : _detailIcon()),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(product.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                              color: cInk)),
                      Text('${product.brand} · ${trValue(product.type)}',
                          style: const TextStyle(
                              color: cInk2, fontSize: 12)),
                    ])),
              ]),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 10),
              if (sale.receiptNumber.isNotEmpty)
                _InfoRow(label: tr('Номер чека', 'Чек нөмірі'), value: sale.receiptNumber),
              _InfoRow(label: tr('Дата продажи', 'Сату күні'), value: '$dateStr · $timeStr'),
              _InfoRow(
                label: tr('Продавец', 'Сатушы'),
                value: sale.isOnline ? 'Онлайн 🛒' : sale.sellerName,
              ),
              _InfoRow(
                label: tr('Тип оплаты', 'Төлем түрі'),
                value: _paymentLabel(_resolveMethod(sale)),
              ),
              if (sale.isOnline && sale.depositPaymentMethod.isNotEmpty)
                _InfoRow(
                  label: 'Депозит (10%)',
                  value: _paymentLabel(sale.depositPaymentMethod),
                ),
              if (sale.isOnline && sale.deliveredByName.isNotEmpty)
                _InfoRow(label: tr('Выдал заказ', 'Тапсырды берген'), value: sale.deliveredByName),
              if (warehouseName.isNotEmpty)
                _InfoRow(label: tr('Склад', 'Қойма'), value: warehouseName),
              if (sale.hasDiscount) ...[
                _InfoRow(
                    label: tr('Базовая цена', 'Базалық баға'),
                    value: '${sale.basePrice.toStringAsFixed(0)} ₸'),
                _InfoRow(
                    label: tr('Скидка', 'Жеңілдік'),
                    value:
                        '-${sale.effectiveDiscountPercent.toStringAsFixed(0)}% '
                        '(−${(sale.basePrice - sale.totalPrice).toStringAsFixed(0)} ₸)'),
              ],
              const SizedBox(height: 10),
              Text(tr('Проданные размеры:', 'Сатылған өлшемдер:'),
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: cInk)),
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
                            color: cGreenTint,
                            borderRadius: BorderRadius.circular(8)),
                        child: Text(tr('Р.${e.key} × ${e.value} шт.', 'Ө.${e.key} × ${e.value} дана'),
                            style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: cGreen,
                                fontSize: 13))))
                    .toList(),
              ),
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 8),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(tr('Итого:', 'Барлығы:'),
                    style: TextStyle(fontSize: 15, color: cInk2)),
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  if (sale.hasDiscount) ...[
                    Text('${sale.basePrice.toStringAsFixed(0)} ₸',
                        style: manrope(13, FontWeight.w500, color: cInk3)
                            .copyWith(decoration: TextDecoration.lineThrough)),
                    const SizedBox(width: 8),
                  ],
                  Text('${sale.totalPrice.toStringAsFixed(0)} ₸',
                      style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: cGreen)),
                ]),
              ]),
            ]),
      ),
    );
  }

  Widget _detailIcon() => Container(
      width: 56,
      height: 56,
      color: cGreenTint,
      child: const Icon(Icons.inventory_2_outlined, color: cGreen));
}

// ── History Sheet ─────────────────────────────────────────────────────────────
class _HistorySheet extends StatelessWidget {
  final List<SaleModel> sales;
  final List<ProductModel> products;
  final List<WarehouseModel> warehouses;
  final ScrollController scrollCtrl;
  const _HistorySheet(
      {required this.sales,
      required this.products,
      required this.warehouses,
      required this.scrollCtrl});

  @override
  Widget build(BuildContext context) {
    final map = <DateTime, List<SaleModel>>{};
    for (final s in sales) {
      final day = DateTime(s.saleDate.year, s.saleDate.month, s.saleDate.day);
      (map[day] ??= []).add(s);
    }
    final days = map.keys.toList()..sort((a, b) => b.compareTo(a));
    final dayTotals = <DateTime, double>{
      for (final d in days)
        d: map[d]!.fold(0.0, (sum, s) => sum + s.totalPrice),
    };

    final items = <Object>[];
    for (final day in days) {
      items.add(day);
      items.addAll(map[day]!);
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
        child: Column(children: [
          Center(
              child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 12),
          Row(children: [
            Text(tr('История операций', 'Операциялар тарихы'),
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: cInk)),
            const Spacer(),
            Text(tr('${sales.length} записей', '${sales.length} жазба'),
                style: const TextStyle(color: cInk3, fontSize: 13)),
          ]),
          const SizedBox(height: 12),
          const Divider(height: 1),
        ]),
      ),
      Expanded(
        child: sales.isEmpty
            ? Center(
                child: Text(tr('Продаж нет', 'Сатылым жоқ'),
                    style: TextStyle(color: cInk2)))
            : ListView.builder(
                controller: scrollCtrl,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                itemCount: items.length,
                itemBuilder: (_, i) {
                  final item = items[i];

                  if (item is DateTime) {
                    final total = dayTotals[item] ?? 0.0;
                    final String label;
                    if (item == today) {
                      label = tr('Сегодня', 'Бүгін');
                    } else if (item == yesterday) {
                      label = tr('Вчера', 'Кеше');
                    } else {
                      label = '${item.day.toString().padLeft(2, '0')}'
                          '.${item.month.toString().padLeft(2, '0')}'
                          '.${item.year}';
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 4),
                      child: Row(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                              color: cGreenTint,
                              borderRadius: BorderRadius.circular(20)),
                          child: Text(label,
                              style: manrope(12, FontWeight.w700,
                                  color: cGreenDeep)),
                        ),
                        const Spacer(),
                        Text('${total.toStringAsFixed(0)} ₸',
                            style:
                                manrope(13, FontWeight.w700, color: cGreen)),
                      ]),
                    );
                  }

                  final s = item as SaleModel;
                  final prod = products.firstWhere((p) => p.id == s.productId,
                      orElse: () => ProductModel(
                          id: '',
                          name: tr('Удалён', 'Жойылды'),
                          brand: '',
                          type: '',
                          material: '',
                          category: '',
                          color: '',
                          articul: '',
                          status: '',
                          images: []));
                  String whName = '';
                  if (s.warehouseId.isNotEmpty) {
                    try {
                      whName = warehouses
                          .firstWhere((w) => w.id == s.warehouseId)
                          .name;
                    } catch (_) {}
                  }
                  return _SaleCard(
                      sale: s, product: prod, warehouseName: whName);
                },
              ),
      ),
    ]);
  }
}

class _InfoRow extends StatelessWidget {
  final String label, value;
  const _InfoRow({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          Text(label, style: manrope(13, FontWeight.w500, color: cInk2)),
          const Spacer(),
          Text(value, style: manrope(13, FontWeight.w700, color: cInk)),
        ]),
      );
}

class _PeriodChip extends StatelessWidget {
  final String label, value, current;
  final void Function(String) onTap;
  const _PeriodChip(
      {required this.label,
      required this.value,
      required this.current,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final active = value == current;
    return GestureDetector(
      onTap: () => onTap(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: active
              ? Colors.white
              : Colors.white.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Text(
          label,
          style: manrope(
            12.5,
            FontWeight.w700,
            color: active ? cInk : Colors.white.withValues(alpha: 0.9),
          ),
        ),
      ),
    );
  }
}

// ── Payment helpers ───────────────────────────────────────────────────────────

String _resolveMethod(SaleModel sale) {
  if (!sale.isOnline) {
    return sale.paymentMethod.isEmpty ? 'cash' : sale.paymentMethod;
  }
  return sale.paymentMethod.isEmpty ? 'online' : sale.paymentMethod;
}

String _normMethod(String m) {
  final s = m.toLowerCase();
  if (s.contains('kaspi')) return 'kaspi';
  if (s.contains('halyk')) return 'halyk';
  if (s == 'cash' || s.contains('налич')) return 'cash';
  if (s == 'online') return 'online';
  return s;
}

String _paymentLabel(String method) {
  switch (_normMethod(method)) {
    case 'kaspi':  return '📱 Kaspi';
    case 'halyk':  return '📱 Halyk Bank';
    case 'online': return '🛒 Онлайн';
    default:       return tr('💵 Наличный', '💵 Қолма-қол');
  }
}

Color _paymentColor(String method) {
  switch (_normMethod(method)) {
    case 'kaspi':  return const Color(0xFFEB3333);
    case 'halyk':  return const Color(0xFF00A550);
    case 'online': return const Color(0xFF3B82F6);
    default:       return cInk3;
  }
}

class _PaymentBadge extends StatelessWidget {
  final String method;
  const _PaymentBadge({required this.method});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: _paymentColor(method).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        _paymentLabel(method),
        style: manrope(10, FontWeight.w700, color: _paymentColor(method)),
      ),
    );
  }
}
