import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_user.dart';
import '../../core/l10n_ext.dart';
import '../../core/warehouse_context.dart';
import '../../data/models/models.dart';
import '../../data/services/firestore_service.dart';
import '../../theme/app_theme.dart';
import 'seller_drilldown_screen.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});
  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen>
    with SingleTickerProviderStateMixin {
  final _service = FirestoreService();
  DateTime _month = DateTime.now();
  late final TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    if (!AppUser.isAdmin) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
    }
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickMonth() async {
    DateTime temp = _month;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(context.l10n.selectMonth,
            style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
        content: StatefulBuilder(builder: (_, setS) => SizedBox(
          width: 280,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              IconButton(icon: const Icon(Icons.chevron_left, color: AppTheme.primary),
                  onPressed: () => setS(() => temp = DateTime(temp.year - 1, temp.month))),
              Text('${temp.year}', style: const TextStyle(fontWeight: FontWeight.w700,
                  fontSize: 17, color: AppTheme.textPrimary)),
              IconButton(icon: const Icon(Icons.chevron_right, color: AppTheme.primary),
                  onPressed: () => setS(() => temp = DateTime(temp.year + 1, temp.month))),
            ]),
            const SizedBox(height: 8),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4, childAspectRatio: 1.4, crossAxisSpacing: 6, mainAxisSpacing: 6),
              itemCount: 12,
              itemBuilder: (_, i) {
                final sel = temp.month == i + 1;
                final mn = context.monthAbbreviations;
                return GestureDetector(
                  onTap: () => setS(() => temp = DateTime(temp.year, i + 1)),
                  child: Container(
                    decoration: BoxDecoration(color: sel ? AppTheme.primary : AppTheme.background,
                        borderRadius: BorderRadius.circular(8)),
                    child: Center(child: Text(mn[i], style: TextStyle(fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: sel ? Colors.white : AppTheme.textSecondary)))));
              },
            ),
          ]),
        )),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
              child: Text(context.l10n.cancel, style: const TextStyle(color: AppTheme.textSecondary))),
          ElevatedButton(
            onPressed: () { setState(() => _month = temp); Navigator.pop(ctx); },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            child: Text(context.l10n.apply)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: CustomScrollView(
        slivers: [
          // Header
          SliverToBoxAdapter(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [Color(0xFF1E3A8A), Color(0xFF2D4FB5)],
                    begin: Alignment.topLeft, end: Alignment.bottomRight)),
              child: SafeArea(bottom: false, child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(context.l10n.analyticsTitle, style: const TextStyle(color: Colors.white, fontSize: 26,
                          fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                      Text(context.l10n.financialDashboard, style: const TextStyle(color: Colors.white60, fontSize: 13)),
                    ]),
                    const Spacer(),
                    GestureDetector(
                      onTap: _pickMonth,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.3))),
                        child: Row(children: [
                          Text(context.monthShort(_month),
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                          const SizedBox(width: 4),
                          const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 18),
                        ]),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  TabBar(
                    controller: _tabCtrl,
                    indicatorColor: Colors.white,
                    indicatorWeight: 3,
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.white60,
                    labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                    unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                    tabs: [
                      Tab(text: context.l10n.generalTab),
                      Tab(text: context.l10n.sellersTab),
                      Tab(text: context.l10n.warehouseTab),
                    ],
                  ),
                ]),
              )),
            ),
          ),

          // Tab content
          SliverFillRemaining(
            child: TabBarView(
              controller: _tabCtrl,
              children: [
                _OverviewTab(month: _month, service: _service),
                _SellersTab(month: _month),
                _WarehousesTab(month: _month),
              ],
            ),
          ),
        ],
      ),
    );
  }

}

// ── _OverviewTab — қазіргі аналитика контенті ─────────────────────────────────
class _OverviewTab extends StatefulWidget {
  final DateTime month;
  final FirestoreService service;
  const _OverviewTab({required this.month, required this.service});
  @override
  State<_OverviewTab> createState() => _OverviewTabState();
}

class _OverviewTabState extends State<_OverviewTab> {
  List<SaleModel> _byMonth(List<SaleModel> all) => all
      .where((s) => s.saleDate.month == widget.month.month &&
                    s.saleDate.year  == widget.month.year)
      .toList();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ProductModel>>(
      stream: widget.service.watchProducts(),
      builder: (_, pSnap) => StreamBuilder<List<SaleModel>>(
        stream: widget.service.watchSalesHistory(),
        builder: (_, sSnap) {
          if (pSnap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
          }
          final products = pSnap.data ?? [];
          final allSales = sSnap.data ?? [];
          final mSales   = _byMonth(allSales);
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
            child: _buildFinancialBlock(mSales, products, allSales),
          );
        },
      ),
    );
  }

  Widget _buildFinancialBlock(
      List<SaleModel> mSales, List<ProductModel> products, List<SaleModel> allSales) {
    // ── Финансовые расчёты ─────────────────────────────────────────────
    final revenue = mSales.fold<double>(0, (s, e) => s + e.totalPrice);

    // Себестоимость = кол-во проданных * purchase_price каждой партии
    // Упрощение: берём из продаж totalPrice / sellingPrice * purchasePrice
    // Для точного расчёта нужны batch данные (асинхронно)

    final monthSoldPairs = mSales.fold<int>(0, (sum, sale) => sum + sale.quantity);
    // Топ по выручке за месяц
    final Map<String, double> revByProd = {};
    final Map<String, int> qtyByProd = {};
    for (final s in mSales) {
      revByProd[s.productId] = (revByProd[s.productId] ?? 0) + s.totalPrice;
      qtyByProd[s.productId] = (qtyByProd[s.productId] ?? 0) + s.quantity;
    }
    final topIds = revByProd.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    // Популярные размеры
    final Map<String, int> sizeMap = {};
    for (final s in mSales) {
      sizeMap[s.selectedSize] = (sizeMap[s.selectedSize] ?? 0) + s.quantity;
    }
    final topSizes = sizeMap.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // ── Метка месяца ────────────────────────────────────────────────
      Text(context.forMonth(widget.month),
          style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary,
              fontWeight: FontWeight.w500)),
      const SizedBox(height: 12),

      // ── 3 финансовые карточки ────────────────────────────────────────
      _FinCard(
        label: context.l10n.monthRevenue,
        value: '${_fmt(revenue)} ₸',
        icon: Icons.trending_up_rounded,
        iconBg: AppTheme.primary.withValues(alpha: 0.1),
        iconColor: AppTheme.primary,
        sub: '${mSales.length} ${context.l10n.salesSuffix}',
      ),
      const SizedBox(height: 10),

      // Расчёт себестоимости через FutureBuilder
      FutureBuilder<double>(
        future: _calcCost(mSales),
        builder: (_, snap) {
          final cost = snap.data ?? 0;
          final profit = revenue - cost;
          return Column(children: [
            Row(children: [
              Expanded(child: _FinCard(
                label: context.l10n.costPrice,
                value: '${_fmt(cost)} ₸',
                icon: Icons.arrow_downward_rounded,
                iconBg: AppTheme.dangerLight,
                iconColor: AppTheme.danger,
                sub: context.l10n.purchasePrice,
              )),
              const SizedBox(width: 10),
              Expanded(child: _FinCard(
                label: context.l10n.netProfit,
                value: '${_fmt(profit)} ₸',
                icon: Icons.account_balance_wallet_outlined,
                iconBg: AppTheme.successLight,
                iconColor: AppTheme.success,
                sub: profit >= 0 ? context.l10n.income : context.l10n.lossLabel,
                highlight: profit >= 0,
              )),
            ]),
          ]);
        },
      ),
      const SizedBox(height: 10),

      Row(children: [
        Expanded(child: _StatMini(label: context.l10n.soldPairsMonth,
            value: '$monthSoldPairs ${context.l10n.pairsUnit}',
            color: AppTheme.warning)),
        const SizedBox(width: 10),
        Expanded(child: FutureBuilder<int>(
          future: widget.service.getArrivedPairsForMonth(widget.month),
          builder: (_, snap) => _StatMini(
            label: context.l10n.arrivedPairsMonth,
            value: '${snap.data ?? 0} ${context.l10n.pairsUnit}',
            color: AppTheme.success)),
        ),
      ]),
      const SizedBox(height: 24),

      // ── Топ продаж ───────────────────────────────────────────────────
      if (topIds.isNotEmpty) ...[
        _SecHeader(title: context.l10n.topSalesTitle, sub: context.forMonth(widget.month)),
        const SizedBox(height: 10),
        ...topIds.take(5).map((e) {
          final prod = products.firstWhere((p) => p.id == e.key,
            orElse: () => ProductModel(id: '', name: context.l10n.productDeletedShort, brand: '',
                type: '', material: '', category: '', color: '', articul: '', status: '', images: []));
          final max = topIds.first.value;
          return _TopRow(product: prod, revenue: e.value,
              qty: qtyByProd[e.key] ?? 0, ratio: e.value / max);
        }),
        const SizedBox(height: 24),
      ],

      // ── Хиты — быстрый оборот ────────────────────────────────────────
      _SecHeader(title: context.l10n.fastSalesTitle, sub: context.l10n.fastSalesSub),
      const SizedBox(height: 10),
      FutureBuilder<List<_FastItem>>(
        future: _fastSales(products, allSales),
        builder: (_, snap) {
          if (!snap.hasData) return const _LoadingCard();
          if (snap.data!.isEmpty) return _EmptyCard(text: context.l10n.noFastSalesData);
          return Column(children: snap.data!.take(3).map((e) => _FastCard(item: e)).toList());
        },
      ),
      const SizedBox(height: 24),

      // ── Залежавшийся товар ────────────────────────────────────────────
      _SecHeader(title: context.l10n.staleProductsTitle, sub: context.l10n.staleProductsSub),
      const SizedBox(height: 10),
      FutureBuilder<List<_StaleItem>>(
        future: _staleProducts(products),
        builder: (_, snap) {
          if (!snap.hasData) return const _LoadingCard();
          if (snap.data!.isEmpty) { return _EmptyCard(
              icon: Icons.check_circle_outline, text: context.l10n.noStaleProductsMsg); }
          return Column(children: snap.data!.take(5).map((e) => _StaleCard(item: e)).toList());
        },
      ),
      const SizedBox(height: 24),

      // ── Популярные размеры ────────────────────────────────────────────
      if (topSizes.isNotEmpty) ...[
        _SecHeader(title: context.l10n.popularSizesTitle, sub: context.forMonth(widget.month)),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: AppTheme.surface,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10, offset: const Offset(0, 2))]),
          child: Column(children: topSizes.take(6).map((e) {
            final ratio = e.value / topSizes.first.value;
            return Padding(padding: const EdgeInsets.only(bottom: 12), child: Row(children: [
              Container(width: 36, height: 36,
                decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8)),
                child: Center(child: Text(e.key,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12,
                      color: AppTheme.primary)))),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('${context.l10n.sizeLabel} ${e.key}', style: const TextStyle(fontSize: 13,
                      fontWeight: FontWeight.w500, color: AppTheme.textPrimary)),
                  Text('${e.value} ${context.l10n.pairsUnit}', style: const TextStyle(fontSize: 12,
                      fontWeight: FontWeight.w700, color: AppTheme.primary)),
                ]),
                const SizedBox(height: 5),
                ClipRRect(borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(value: ratio,
                    backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
                    valueColor: const AlwaysStoppedAnimation(AppTheme.primary),
                    minHeight: 5)),
              ])),
            ]));
          }).toList()),
        ),
      ],
    ]);
  }

  // ── Себестоимость через партии ──────────────────────────────────────────
  Future<double> _calcCost(List<SaleModel> sales) async {
    double total = 0;
    for (final s in sales) {
      try {
        final batches = await widget.service.getBatches(s.productId);
        final batch = batches.firstWhere((b) => b.id == s.batchId,
            orElse: () => batches.isNotEmpty ? batches.first :
                BatchModel(id: '', dateArrived: DateTime.now(),
                    purchasePrice: 0, sellingPrice: 0, sizesQuantity: {}));
        total += batch.purchasePrice * s.quantity;
      } catch (_) {}
    }
    return total;
  }

  Future<List<_FastItem>> _fastSales(
      List<ProductModel> products, List<SaleModel> allSales) async {
    final List<_FastItem> result = [];
    for (final p in products.where((p) => p.status == ProductModel.statusSold)) {
      try {
        final batches = await widget.service.getBatches(p.id);
        if (batches.isEmpty) continue;
        final sales = allSales.where((s) => s.productId == p.id).toList();
        if (sales.isEmpty) continue;
        final first = sales.reduce((a, b) => a.saleDate.isBefore(b.saleDate) ? a : b);
        final batch = batches.last;
        final days = first.saleDate.difference(batch.dateArrived).inDays;
        final margin = batch.sellingPrice > 0
            ? ((batch.sellingPrice - batch.purchasePrice) / batch.purchasePrice * 100)
            : 0.0;
        result.add(_FastItem(product: p, days: days, margin: margin.toDouble(), batch: batch));
      } catch (_) {}
    }
    result.sort((a, b) => a.days.compareTo(b.days));
    return result;
  }

  Future<List<_StaleItem>> _staleProducts(List<ProductModel> products) async {
    final List<_StaleItem> result = [];
    for (final p in products.where((p) => p.status == ProductModel.statusInStock)) {
      try {
        final batches = await widget.service.getBatches(p.id);
        if (batches.isEmpty) continue;
        final oldest = batches.reduce((a, b) =>
            a.dateArrived.isBefore(b.dateArrived) ? a : b);
        final days = DateTime.now().difference(oldest.dateArrived).inDays;
        if (days >= 30) result.add(_StaleItem(product: p, days: days, batch: oldest));
      } catch (_) {}
    }
    result.sort((a, b) => b.days.compareTo(a.days));
    return result;
  }

  static String _fmt(double v) {
    if (v >= 1000000) return '${(v/1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v/1000).toStringAsFixed(0)}K';
    return v.toStringAsFixed(0);
  }
}

// ── _SellersTab — саттушылар рейтингі ─────────────────────────────────────────
class _SellersTab extends StatelessWidget {
  final DateTime month;
  const _SellersTab({required this.month});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<SaleModel>>(
      stream: FirestoreService().watchSalesHistory(),
      builder: (_, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
        }
        final sales = (snap.data ?? []).where((s) =>
            s.saleDate.month == month.month && s.saleDate.year == month.year).toList();

        final Map<String, _SellerStat> bySeller = {};
        for (final s in sales) {
          if (s.sellerId.isEmpty) continue;
          final stat = bySeller.putIfAbsent(
              s.sellerId, () => _SellerStat(id: s.sellerId, name: s.sellerName));
          stat.salesCount++;
          stat.totalRevenue += s.totalPrice;
          stat.totalDiscount += s.discountAmount;
          stat.totalPairs += s.quantity;
        }

        final ranked = bySeller.values.toList()
          ..sort((a, b) => b.totalRevenue.compareTo(a.totalRevenue));
        final grandTotal = ranked.fold<double>(0, (a, s) => a + s.totalRevenue);

        if (ranked.isEmpty) {
          return Center(child: Text(context.l10n.noSalesThisMonthSimple,
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14)));
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _SellerKpiRow(ranked: ranked, grandTotal: grandTotal),
            const SizedBox(height: 16),
            _SectionLabel(context.l10n.ranking),
            const SizedBox(height: 8),
            ...ranked.asMap().entries.map((e) => _SellerStatCard(
              rank: e.key + 1,
              stat: e.value,
              share: grandTotal > 0 ? (e.value.totalRevenue / grandTotal * 100) : 0,
              onTap: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => SellerDrilldownScreen(
                  sellerId: e.value.id,
                  sellerName: e.value.name,
                  month: month,
                ),
              )),
            )),
            const SizedBox(height: 16),
            _SectionLabel(context.l10n.dailyActivity),
            const SizedBox(height: 8),
            _DailyChart(sales: sales, month: month),
          ],
        );
      },
    );
  }
}

// ── _WarehousesTab — қойма бойынша аналитика ──────────────────────────────────
class _WarehousesTab extends StatelessWidget {
  final DateTime month;
  const _WarehousesTab({required this.month});

  @override
  Widget build(BuildContext context) {
    final warehouses = context.watch<WarehouseContext>().all;

    return StreamBuilder<List<SaleModel>>(
      stream: FirestoreService().watchSalesHistory(),
      builder: (_, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
        }
        final sales = (snap.data ?? []).where((s) =>
            s.saleDate.month == month.month && s.saleDate.year == month.year).toList();

        final Map<String, _WhStat> byWh = {};
        for (final s in sales) {
          final id = s.warehouseId.isNotEmpty ? s.warehouseId : 'unknown';
          final stat = byWh.putIfAbsent(id, () => _WhStat(id: id));
          stat.salesCount++;
          stat.revenue += s.totalPrice;
          stat.pairs += s.quantity;
        }

        for (final stat in byWh.values) {
          try {
            stat.name = warehouses.firstWhere((w) => w.id == stat.id).name;
          } catch (_) {
            stat.name = stat.id.length > 12 ? '${stat.id.substring(0, 12)}…' : stat.id;
          }
        }

        final ranked = byWh.values.toList()
          ..sort((a, b) => b.revenue.compareTo(a.revenue));
        final grandTotal = ranked.fold<double>(0, (a, s) => a + s.revenue);

        if (ranked.isEmpty) {
          return Center(child: Text(context.l10n.noSalesThisMonthSimple,
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14)));
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(children: [
              _KpiMini(label: context.l10n.activeWarehouses, value: '${ranked.length}',
                  sub: context.l10n.warehouseSuffix, color: AppTheme.primary),
              const SizedBox(width: 8),
              _KpiMini(label: context.l10n.totalRevenueStat,
                  value: '${(grandTotal / 1000).toStringAsFixed(0)}K',
                  sub: '₸', color: AppTheme.success),
            ]),
            const SizedBox(height: 16),
            _SectionLabel(context.l10n.warehouseRanking),
            const SizedBox(height: 8),

            // Each warehouse: stat card + its own daily chart
            ...ranked.expand((stat) {
              final wSales = sales
                  .where((s) => s.warehouseId == stat.id)
                  .toList();
              return <Widget>[
                _WhStatCard(stat: stat, grandTotal: grandTotal),
                if (wSales.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  _SectionLabel('${stat.name}: күндік белсенділік'),
                  const SizedBox(height: 6),
                  _DailyChart(
                    sales: wSales,
                    month: month,
                    revenueLabel: 'Выручка по складу',
                  ),
                ],
                const SizedBox(height: 12),
              ];
            }),
          ],
        );
      },
    );
  }
}

class _WhStat {
  final String id;
  String name = '';
  int salesCount = 0, pairs = 0;
  double revenue = 0;
  _WhStat({required this.id});
}

class _WhStatCard extends StatelessWidget {
  final _WhStat stat;
  final double grandTotal;
  const _WhStatCard({required this.stat, required this.grandTotal});

  @override
  Widget build(BuildContext context) {
    final share = grandTotal > 0 ? stat.revenue / grandTotal * 100 : 0.0;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.warehouse_rounded, color: AppTheme.primary, size: 18)),
          const SizedBox(width: 10),
          Expanded(child: Text(stat.name,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary),
              maxLines: 1, overflow: TextOverflow.ellipsis)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6)),
            child: Text('${share.toStringAsFixed(0)}%',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                    color: AppTheme.primary))),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          _WhMini(label: context.l10n.revenueSuffix,
              value: '${(stat.revenue / 1000).toStringAsFixed(0)}K ₸',
              color: AppTheme.success),
          const SizedBox(width: 8),
          _WhMini(label: context.l10n.pairsSuffix, value: '${stat.pairs}', color: AppTheme.primary),
          const SizedBox(width: 8),
          _WhMini(label: context.l10n.salesSuffix, value: '${stat.salesCount}', color: AppTheme.warning),
        ]),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: share / 100, minHeight: 5,
            backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
            valueColor: const AlwaysStoppedAnimation(AppTheme.primary),
          ),
        ),
      ]),
    );
  }
}

class _WhMini extends StatelessWidget {
  final String label, value;
  final Color color;
  const _WhMini({required this.label, required this.value, required this.color});
  @override
  Widget build(BuildContext context) => Expanded(child: Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(8)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: color)),
      Text(label, style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary)),
    ]),
  ));
}

// ── _SellerStat data class ─────────────────────────────────────────────────────
class _SellerStat {
  final String id, name;
  int salesCount = 0, totalPairs = 0;
  double totalRevenue = 0, totalDiscount = 0;
  _SellerStat({required this.id, required this.name});
}

// ── _SellerStatCard ────────────────────────────────────────────────────────────
class _SellerStatCard extends StatelessWidget {
  final int rank;
  final _SellerStat stat;
  final double share;
  final VoidCallback onTap;
  const _SellerStatCard({required this.rank, required this.stat,
      required this.share, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final medal = rank == 1 ? '🥇' : rank == 2 ? '🥈' : rank == 3 ? '🥉' : '#$rank';
    final barColor = rank == 1 ? AppTheme.primary
        : rank == 2 ? AppTheme.primaryLight
        : const Color(0xFF93A4D9);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .04),
              blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Row(children: [
          SizedBox(width: 34, child: Text(medal, textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22))),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(stat.name,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
              Text('${(stat.totalRevenue / 1000).toStringAsFixed(0)}K ₸',
                  style: const TextStyle(fontSize: 13,
                      fontWeight: FontWeight.w800, color: AppTheme.success)),
            ]),
            const SizedBox(height: 2),
            Text('${stat.salesCount} сат · ${share.toStringAsFixed(0)}% үлес',
                style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
            const SizedBox(height: 6),
            ClipRRect(borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: share / 100, minHeight: 5,
                backgroundColor: const Color(0xFFF3F4F6),
                valueColor: AlwaysStoppedAnimation(barColor),
              )),
          ])),
          const Icon(Icons.chevron_right_rounded, color: AppTheme.textHint),
        ]),
      ),
    );
  }
}

// ── KPI жолы ──────────────────────────────────────────────────────────────────
class _SellerKpiRow extends StatelessWidget {
  final List<_SellerStat> ranked;
  final double grandTotal;
  const _SellerKpiRow({required this.ranked, required this.grandTotal});

  @override
  Widget build(BuildContext context) => Row(children: [
    _KpiMini(label: 'Белсенді', value: '${ranked.length}',
        sub: 'саттушы', color: AppTheme.primary),
    const SizedBox(width: 8),
    _KpiMini(label: 'Жалпы выручка',
        value: '${(grandTotal / 1000).toStringAsFixed(0)}K',
        sub: '₸', color: AppTheme.success),
    if (ranked.isNotEmpty) ...[
      const SizedBox(width: 8),
      _KpiMini(label: 'Топ саттушы',
          value: ranked.first.name.split(' ').first,
          sub: '${ranked.first.salesCount} сат',
          color: const Color(0xFFB45309)),
    ],
  ]);
}

class _KpiMini extends StatelessWidget {
  final String label, value, sub;
  final Color color;
  const _KpiMini({required this.label, required this.value,
      required this.sub, required this.color});

  @override
  Widget build(BuildContext context) => Expanded(child: Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
      const SizedBox(height: 4),
      Text(value, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: color),
          maxLines: 1, overflow: TextOverflow.ellipsis),
      Text(sub, style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary)),
    ]),
  ));
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
        color: AppTheme.textPrimary));
}

// ── Күндік bar chart (интерактивный, выручка в ₸) ────────────────────────────
// revenueLabel — подпись при тапе: "Выручка" или "Выручка по складу" и т.д.
class _DailyChart extends StatefulWidget {
  final List<SaleModel> sales;
  final DateTime month;
  final String revenueLabel;
  const _DailyChart({
    required this.sales,
    required this.month,
    this.revenueLabel = 'Выручка',
  });
  @override
  State<_DailyChart> createState() => _DailyChartState();
}

class _DailyChartState extends State<_DailyChart> {
  int? _tapped; // 0-based

  @override
  Widget build(BuildContext context) {
    final daysInMonth =
        DateUtils.getDaysInMonth(widget.month.year, widget.month.month);

    // Accumulate revenue per day (not count)
    final byDay = List<double>.filled(daysInMonth, 0.0);
    for (final s in widget.sales) {
      if (s.saleDate.month == widget.month.month &&
          s.saleDate.year == widget.month.year) {
        byDay[s.saleDate.day - 1] += s.totalPrice;
      }
    }
    final maxVal      = byDay.reduce((a, b) => a > b ? a : b);
    final effectiveMax = maxVal < 1 ? 1.0 : maxVal;
    final monthTotal  = byDay.fold(0.0, (s, v) => s + v);

    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Info row: month total by default; selected day on tap ──────
            SizedBox(
              height: 26,
              child: Row(children: [
                if (_tapped != null) ...[
                  Expanded(
                    child: Text(
                      'Дата: ${(_tapped! + 1).toString().padLeft(2, '0')}'
                      '.${widget.month.month.toString().padLeft(2, '0')}'
                      '.${widget.month.year}',
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textSecondary),
                    ),
                  ),
                  Text(
                    '${widget.revenueLabel}: ${_fmtRev(byDay[_tapped!])}',
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.success),
                  ),
                ] else ...[
                  const Text('Барлығы',
                      style: TextStyle(fontSize: 12, color: AppTheme.textHint)),
                  const Spacer(),
                  Text(
                    _fmtRev(monthTotal),
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.primary),
                  ),
                ],
              ]),
            ),
            const SizedBox(height: 6),

            // ── Bars ────────────────────────────────────────────────────────
            SizedBox(
              height: 72,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: List.generate(daysInMonth, (i) {
                  final v     = byDay[i];
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
                            gradient: isSel
                                ? null
                                : const LinearGradient(
                                    colors: [
                                      AppTheme.primaryLight,
                                      AppTheme.primary,
                                    ],
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                  ),
                            color: isSel ? AppTheme.success : null,
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

            // ── X-axis: day 1, mid-month, last day + tapped ─────────────────
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
      ),
    );
  }

  static String _fmtRev(double v) {
    if (v >= 1000000) {
      return '${(v / 1000000).toStringAsFixed(1)}M ₸';
    }
    if (v >= 1000) {
      return '${(v / 1000).toStringAsFixed(0)}K ₸';
    }
    return '${v.toStringAsFixed(0)} ₸';
  }
}

// ─── Data classes ─────────────────────────────────────────────────────────────
class _FastItem { final ProductModel product; final int days; final double margin; final BatchModel batch;
  _FastItem({required this.product, required this.days, required this.margin, required this.batch}); }
class _StaleItem { final ProductModel product; final int days; final BatchModel batch;
  _StaleItem({required this.product, required this.days, required this.batch}); }

// ─── Widgets ──────────────────────────────────────────────────────────────────
class _FinCard extends StatelessWidget {
  final String label, value, sub;
  final IconData icon;
  final Color iconBg, iconColor;
  final bool highlight;
  const _FinCard({required this.label, required this.value, required this.icon,
      required this.iconBg, required this.iconColor, required this.sub, this.highlight = false});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: highlight ? const Color(0xFFE6F4EA) : AppTheme.surface,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 10, offset: const Offset(0, 2))],
      border: highlight ? Border.all(color: AppTheme.success.withValues(alpha: 0.2)) : null,
    ),
    child: Row(children: [
      Container(padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: iconColor, size: 20)),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 11, color: highlight ? const Color(0xFF137333) : AppTheme.textSecondary,
            fontWeight: FontWeight.w500)),
        const SizedBox(height: 3),
        Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800,
            color: highlight ? const Color(0xFF137333) : AppTheme.textPrimary,
            letterSpacing: -0.3)),
        Text(sub, style: TextStyle(fontSize: 10, color: highlight ? const Color(0xFF137333).withValues(alpha: 0.7) : AppTheme.textHint)),
      ])),
    ]),
  );
}

class _StatMini extends StatelessWidget {
  final String label, value;
  final Color color;
  const _StatMini({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color)),
      Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
    ]),
  );
}

class _TopRow extends StatelessWidget {
  final ProductModel product; final double revenue; final int qty; final double ratio;
  const _TopRow({required this.product, required this.revenue, required this.qty, required this.ratio});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))]),
    child: Row(children: [
      ClipRRect(borderRadius: BorderRadius.circular(10),
        child: product.images.isNotEmpty
            ? Image.network(product.images.first, width: 44, height: 44, fit: BoxFit.cover)
            : Container(width: 44, height: 44, color: const Color(0xFFEEF2FF),
                child: const Icon(Icons.inventory_2_outlined, color: AppTheme.primary, size: 20))),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(product.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13,
            color: AppTheme.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 4),
        ClipRRect(borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(value: ratio,
              backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
              valueColor: const AlwaysStoppedAnimation(AppTheme.primary), minHeight: 4)),
      ])),
      const SizedBox(width: 12),
      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text('${(revenue/1000).toStringAsFixed(0)}K ₸',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppTheme.primary)),
        Text('$qty пар', style: const TextStyle(fontSize: 11, color: AppTheme.textHint)),
      ]),
    ]),
  );
}

class _FastCard extends StatelessWidget {
  final _FastItem item;
  const _FastCard({required this.item});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))]),
    child: Row(children: [
      Container(padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: AppTheme.warningLight, borderRadius: BorderRadius.circular(10)),
        child: const Icon(Icons.bolt_rounded, color: AppTheme.warning, size: 20)),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(item.product.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14,
            color: AppTheme.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
        Text('Закуп: ${item.batch.purchasePrice.toStringAsFixed(0)} ₸ → '
            'Продажа: ${item.batch.sellingPrice.toStringAsFixed(0)} ₸',
          style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
      ])),
      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(color: AppTheme.successLight, borderRadius: BorderRadius.circular(6)),
          child: Text('+${item.margin.toStringAsFixed(0)}%',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.success))),
        const SizedBox(height: 3),
        Text(item.days == 0 ? 'в 1й день' : 'за ${item.days} дн.',
            style: const TextStyle(fontSize: 11, color: AppTheme.textHint)),
      ]),
    ]),
  );
}

class _StaleCard extends StatelessWidget {
  final _StaleItem item;
  const _StaleCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final c = item.days > 60 ? AppTheme.danger : item.days > 45 ? AppTheme.warning : AppTheme.textSecondary;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(14),
          border: item.days > 60 ? Border.all(color: AppTheme.danger.withValues(alpha: 0.25)) : null,
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))]),
      child: Row(children: [
        Container(padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: c.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
          child: Icon(Icons.hourglass_bottom_rounded, color: c, size: 20)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(item.product.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14,
              color: AppTheme.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
          Text('Закуп: ${item.batch.purchasePrice.toStringAsFixed(0)} ₸ · '
              'Цена: ${item.batch.sellingPrice.toStringAsFixed(0)} ₸',
            style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
        ])),
        Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(color: c.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
          child: Text('${item.days} дн.', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c))),
      ]),
    );
  }
}

class _SecHeader extends StatelessWidget {
  final String title, sub;
  const _SecHeader({required this.title, required this.sub});
  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
    Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
    const SizedBox(width: 6),
    Text(sub, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
  ]);
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(14)),
    child: const Center(child: CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 2)));
}

class _EmptyCard extends StatelessWidget {
  final String text;
  final IconData icon;
  const _EmptyCard({required this.text, this.icon = Icons.bolt_outlined});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 6, offset: const Offset(0, 2))]),
    child: Row(children: [
      Icon(icon, color: AppTheme.textHint, size: 20),
      const SizedBox(width: 12),
      Text(text, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
    ]));
}

