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
    _tabCtrl = TabController(length: 4, vsync: this);
    if (!context.read<AppUser>().isAdmin) {
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
            style: const TextStyle(
                fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
        content: StatefulBuilder(
            builder: (_, setS) => SizedBox(
                  width: 280,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          IconButton(
                              icon: const Icon(Icons.chevron_left,
                                  color: AppTheme.primary),
                              onPressed: () => setS(() =>
                                  temp = DateTime(temp.year - 1, temp.month))),
                          Text('${temp.year}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 17,
                                  color: AppTheme.textPrimary)),
                          IconButton(
                              icon: const Icon(Icons.chevron_right,
                                  color: AppTheme.primary),
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
                                    color: sel
                                        ? AppTheme.primary
                                        : AppTheme.background,
                                    borderRadius: BorderRadius.circular(8)),
                                child: Center(
                                    child: Text(mn[i],
                                        style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: sel
                                                ? Colors.white
                                                : AppTheme.textSecondary)))));
                      },
                    ),
                  ]),
                )),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(context.l10n.cancel,
                  style: const TextStyle(color: AppTheme.textSecondary))),
          ElevatedButton(
              onPressed: () {
                setState(() => _month = temp);
                Navigator.pop(ctx);
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10))),
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
          SliverToBoxAdapter(
            child: Container(
              decoration: const BoxDecoration(
                  gradient: LinearGradient(
                      colors: [Color(0xFF1E3A8A), Color(0xFF2D4FB5)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight)),
              child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(context.l10n.analyticsTitle,
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 26,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: -0.5)),
                                  Text(context.l10n.financialDashboard,
                                      style: const TextStyle(
                                          color: Colors.white60, fontSize: 13)),
                                ]),
                            const Spacer(),
                            GestureDetector(
                              onTap: _pickMonth,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 8),
                                decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                        color: Colors.white
                                            .withValues(alpha: 0.3))),
                                child: Row(children: [
                                  Text(context.monthShort(_month),
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13)),
                                  const SizedBox(width: 4),
                                  const Icon(Icons.keyboard_arrow_down_rounded,
                                      color: Colors.white, size: 18),
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
                            labelStyle: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 13),
                            unselectedLabelStyle: const TextStyle(
                                fontWeight: FontWeight.w500, fontSize: 13),
                            tabs: [
                              Tab(text: context.l10n.generalTab),
                              Tab(text: context.l10n.sellersTab),
                              Tab(text: context.l10n.warehouseTab),
                              const Tab(text: 'Онлайн'),
                            ],
                          ),
                        ]),
                  )),
            ),
          ),
          SliverFillRemaining(
            child: TabBarView(
              controller: _tabCtrl,
              children: [
                _OverviewTab(month: _month, service: _service),
                _SellersTab(month: _month),
                _WarehousesTab(month: _month),
                _OnlineTab(month: _month),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Tab 1: Жалпы шолу ─────────────────────────────────────────────────────────
class _OverviewTab extends StatefulWidget {
  final DateTime month;
  final FirestoreService service;
  const _OverviewTab({required this.month, required this.service});
  @override
  State<_OverviewTab> createState() => _OverviewTabState();
}

class _OverviewTabState extends State<_OverviewTab> {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<OrderModel>>(
      stream: widget.service.watchOnlineOrders(),
      builder: (_, oSnap) {
        return StreamBuilder<List<SaleModel>>(
          // Сервер айды сүзеді — клиент жағында фильтр жоқ
          stream: widget.service.watchSalesForMonth(widget.month),
          builder: (_, sSnap) {
            if (sSnap.connectionState == ConnectionState.waiting) {
              return const Center(
                  child: CircularProgressIndicator(color: AppTheme.primary));
            }

            final mSales = sSnap.data ?? [];
            final pureSales = mSales.where((s) => !s.isOnline).toList();

            final onlineOrders = (oSnap.data ?? [])
                .where((o) =>
                    o.status == OrderModel.statusCompleted &&
                    o.createdAt.month == widget.month.month &&
                    o.createdAt.year == widget.month.year)
                .toList();

            final offlineRevenue =
                pureSales.fold<double>(0, (s, e) => s + e.totalPrice);
            final onlineRevenue =
                onlineOrders.fold<double>(0, (s, o) => s + o.totalWithDelivery);
            final totalRevenue = offlineRevenue + onlineRevenue;

            final offlinePairs =
                pureSales.fold<int>(0, (s, e) => s + e.quantity);
            final onlinePairs = onlineOrders.fold<int>(
                0, (s, o) => s + o.items.fold(0, (a, i) => a + i.qty));
            final totalPairs = offlinePairs + onlinePairs;

            // Өзіндік құн — денормализацияланған purchase_price-тан (Firestore оқусыз)
            final totalCost = mSales.fold<double>(
                0, (s, e) => s + e.purchasePrice * e.quantity);
            final margin = totalRevenue - totalCost;

            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _StatCard(
                    label: 'Жалпы Түсірілке',
                    value: '${_fmt(totalRevenue)} ₸',
                    sub:
                        'Офлайн: ${_fmt(offlineRevenue)} ₸  ·  Онлайн: ${_fmt(onlineRevenue)} ₸',
                    icon: Icons.trending_up_rounded,
                    color: AppTheme.primary,
                  ),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                        child: _StatCard(
                      label: 'Өзіндік құн',
                      value: '${_fmt(totalCost)} ₸',
                      icon: Icons.arrow_downward_rounded,
                      color: AppTheme.danger,
                    )),
                    const SizedBox(width: 10),
                    Expanded(
                        child: _StatCard(
                      label: 'Маржа',
                      value: '${_fmt(margin)} ₸',
                      icon: Icons.account_balance_wallet_outlined,
                      color: margin >= 0 ? AppTheme.success : AppTheme.danger,
                    )),
                  ]),
                  const SizedBox(height: 10),
                  _StatCard(
                    label: 'Сатылған жұп',
                    value: '$totalPairs жұп',
                    sub: 'Офлайн: $offlinePairs  ·  Онлайн: $onlinePairs',
                    icon: Icons.shopping_bag_outlined,
                    color: AppTheme.success,
                  ),
                  const SizedBox(height: 20),
                  const Text('Күндік белсенділік',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary)),
                  const SizedBox(height: 10),
                  _MobileDailyChart(
                    offlineSales: pureSales,
                    onlineOrders: onlineOrders,
                    month: widget.month,
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

}

// ── Tab 2: Сатушылар ──────────────────────────────────────────────────────────
class _SellersTab extends StatelessWidget {
  final DateTime month;
  const _SellersTab({required this.month});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<SaleModel>>(
      stream: FirestoreService().watchSalesForMonth(month),
      builder: (_, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: AppTheme.primary));
        }

        final sales = snap.data ?? [];

        final Map<String, _SellerStat> bySeller = {};
        for (final s in sales) {
          if (s.sellerId.isEmpty || s.isOnline) continue;
          final stat = bySeller.putIfAbsent(s.sellerId,
              () => _SellerStat(id: s.sellerId, name: s.sellerName));
          stat.revenue += s.totalPrice;
          stat.pairs += s.quantity;
          stat.count++;
        }

        final ranked = bySeller.values.toList()
          ..sort((a, b) => b.revenue.compareTo(a.revenue));
        final grandTotal = ranked.fold<double>(0, (a, s) => a + s.revenue);

        if (ranked.isEmpty) {
          return const Center(
              child: Text('Сатылым жоқ',
                  style: TextStyle(color: AppTheme.textSecondary)));
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(children: [
              _KpiChip(
                  label: 'Сатушылар',
                  value: '${ranked.length}',
                  color: AppTheme.primary),
              const SizedBox(width: 8),
              _KpiChip(
                  label: 'Жалпы түсімі',
                  value: '${_fmt(grandTotal)} ₸',
                  color: AppTheme.success),
            ]),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(children: [
                const Text('🥇 Топ-1: ',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFB45309))),
                Text(ranked.first.name,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF92400E))),
              ]),
            ),
            const SizedBox(height: 16),
            ...ranked.asMap().entries.map((e) {
              final rank = e.key + 1;
              final stat = e.value;
              final medal = rank == 1
                  ? '🥇'
                  : rank == 2
                      ? '🥈'
                      : rank == 3
                          ? '🥉'
                          : '#$rank';
              return GestureDetector(
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SellerDrilldownScreen(
                        sellerId: stat.id,
                        sellerName: stat.name,
                        month: month,
                      ),
                    )),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 8,
                          offset: const Offset(0, 2))
                    ],
                  ),
                  child: Row(children: [
                    Text(medal, style: const TextStyle(fontSize: 20)),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(stat.name,
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w700)),
                        Text('${stat.count} сат · ${stat.pairs} жұп',
                            style: const TextStyle(
                                fontSize: 11, color: AppTheme.textSecondary)),
                      ],
                    )),
                    Text('${_fmt(stat.revenue)} ₸',
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.success)),
                    const SizedBox(width: 8),
                    const Icon(Icons.chevron_right_rounded,
                        color: AppTheme.textHint, size: 22),
                  ]),
                ),
              );
            }),
          ],
        );
      },
    );
  }
}

class _SellerStat {
  final String id, name;
  int count = 0, pairs = 0;
  double revenue = 0;
  _SellerStat({required this.id, required this.name});
}

// ── Tab 3: Қоймалар ───────────────────────────────────────────────────────────
class _WarehousesTab extends StatelessWidget {
  final DateTime month;
  const _WarehousesTab({required this.month});

  @override
  Widget build(BuildContext context) {
    final warehouses = context.watch<WarehouseContext>().all;

    // Барлық партиялар + товар атауларын бір рет оқу (N+1 жоқ)
    return FutureBuilder<(Map<String, List<BatchModel>>, Map<String, String>)>(
      future: FirestoreService().getAllBatchesGrouped(),
      builder: (_, batchSnap) {
        final allBatches = batchSnap.data?.$1 ?? {};
        final nameById = batchSnap.data?.$2 ?? {};
        return StreamBuilder<List<SaleModel>>(
          // Сервер айды + офлайн-ды сүзеді
          stream: FirestoreService().watchSalesForMonth(month),
          builder: (_, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(
                  child: CircularProgressIndicator(color: AppTheme.primary));
            }
            final allSales =
                (snap.data ?? []).where((s) => !s.isOnline).toList();

            if (warehouses.isEmpty) {
              return const Center(
                  child: Text('Қойма жоқ',
                      style: TextStyle(color: AppTheme.textSecondary)));
            }

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: warehouses.length,
              itemBuilder: (_, i) {
                final wh = warehouses[i];
                final wSales =
                    allSales.where((s) => s.warehouseId == wh.id).toList();
                final revenue =
                    wSales.fold<double>(0, (s, e) => s + e.totalPrice);
                return _WarehouseAnalyticsCard(
                  warehouse: wh,
                  sales: wSales,
                  revenue: revenue,
                  month: month,
                  allBatches: allBatches,
                  productNameById: nameById,
                );
              },
            );
          },
        );
      },
    );
  }
}

class _WarehouseAnalyticsCard extends StatelessWidget {
  final WarehouseModel warehouse;
  final List<SaleModel> sales;
  final double revenue;
  final DateTime month;
  final Map<String, List<BatchModel>> allBatches;
  final Map<String, String> productNameById;
  const _WarehouseAnalyticsCard({
    required this.warehouse,
    required this.sales,
    required this.revenue,
    required this.month,
    required this.allBatches,
    required this.productNameById,
  });

  @override
  Widget build(BuildContext context) {
    // D1: productName-тен топтастыру (UID емес)
    final Map<String, double> revByName = {};
    final Map<String, int> qtyByName = {};
    for (final s in sales) {
      final name = s.productName.isNotEmpty ? s.productName : s.productId;
      revByName[name] = (revByName[name] ?? 0) + s.totalPrice;
      qtyByName[name] = (qtyByName[name] ?? 0) + s.quantity;
    }
    final top3 = (revByName.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)))
        .take(3)
        .toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 3))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: const BoxDecoration(
              color: AppTheme.primarySoft,
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(children: [
              const Icon(Icons.warehouse_rounded,
                  color: AppTheme.primary, size: 20),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(warehouse.name,
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.primary))),
              Text('${_fmt(revenue)} ₸',
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.primary)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Күндік белсенділік',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textSecondary)),
                const SizedBox(height: 8),
                _MobileDailyChart(
                  offlineSales: sales,
                  onlineOrders: const [],
                  month: month,
                ),
                if (top3.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  const Text('Топ-3 сатылымдар',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textSecondary)),
                  const SizedBox(height: 8),
                  ...top3.asMap().entries.map((e) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(children: [
                          Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              color: AppTheme.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Center(
                                child: Text('${e.key + 1}',
                                    style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        color: AppTheme.primary))),
                          ),
                          const SizedBox(width: 8),
                          Expanded(child: Text(
                            e.value.key.length > 20
                                ? '${e.value.key.substring(0, 20)}...'
                                : e.value.key,
                            style: const TextStyle(
                                fontSize: 12, color: AppTheme.textPrimary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          )),
                          Text('${qtyByName[e.value.key] ?? 0} жұп',
                              style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.success)),
                        ]),
                      )),
                ],
                const SizedBox(height: 14),
                const Text('Жатып қалған тауар (30+ күн)',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textSecondary)),
                const SizedBox(height: 8),
                FutureBuilder<List<_StaleItem>>(
                  future: _loadStale(warehouse.id),
                  builder: (_, snap) {
                    if (!snap.hasData) {
                      return const SizedBox(
                          height: 30,
                          child: Center(
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: AppTheme.primary)));
                    }
                    if (snap.data!.isEmpty) {
                      return const Text('Жатып қалған тауар жоқ 👍',
                          style: TextStyle(
                              fontSize: 12, color: AppTheme.textHint));
                    }
                    return Column(
                      children: snap.data!
                          .map((item) => Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Row(children: [
                                  const Icon(Icons.warning_amber_rounded,
                                      color: AppTheme.warning, size: 16),
                                  const SizedBox(width: 8),
                                  Expanded(
                                      child: Text(item.product.name,
                                          style: const TextStyle(
                                              fontSize: 12,
                                              color: AppTheme.textPrimary),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis)),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppTheme.warningSoft,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text('${item.days} күн',
                                        style: const TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                            color: AppTheme.warning)),
                                  ),
                                ]),
                              ))
                          .toList(),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<List<_StaleItem>> _loadStale(String warehouseId) async {
    final service = FirestoreService();
    final withStock = await service.watchAllProductPairs().first;
    final result = <_StaleItem>[];
    for (final pw in withStock
        .where((pw) => pw.product.status == ProductModel.statusInStock)) {
      try {
        final batches = await service.getBatches(pw.product.id);
        final whBatches =
            batches.where((b) => b.warehouseId == warehouseId).toList();
        if (whBatches.isEmpty) {
          continue;
        }
        final oldest = whBatches
            .reduce((a, b) => a.dateArrived.isBefore(b.dateArrived) ? a : b);
        final days = DateTime.now().difference(oldest.dateArrived).inDays;
        if (days >= 30) {
          result.add(_StaleItem(product: pw.product, days: days));
        }
      } catch (_) {}
    }
    result.sort((a, b) => b.days.compareTo(a.days));
    return result.take(3).toList();
  }
}

class _StaleItem {
  final ProductModel product;
  final int days;
  _StaleItem({required this.product, required this.days});
}

// ── Tab 4: Онлайн ─────────────────────────────────────────────────────────────
class _OnlineTab extends StatelessWidget {
  final DateTime month;
  const _OnlineTab({required this.month});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<OrderModel>>(
      stream: FirestoreService().watchOnlineOrders(),
      builder: (_, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: AppTheme.primary));
        }

        final allOrders = (snap.data ?? [])
            .where((o) =>
                o.createdAt.month == month.month &&
                o.createdAt.year == month.year)
            .toList();

        final completed = allOrders
            .where((o) => o.status == OrderModel.statusCompleted)
            .toList();
        final cancelled = allOrders
            .where((o) => o.status == OrderModel.statusCancelled)
            .length;
        final totalCount = allOrders.length;

        final revenue =
            completed.fold<double>(0, (s, o) => s + o.totalWithDelivery);
        final pairsSold = completed.fold<int>(
            0, (s, o) => s + o.items.fold(0, (a, i) => a + i.qty));

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _StatCard(
              label: 'Түсімі (Онлайн)',
              value: '${_fmt(revenue)} ₸',
              icon: Icons.shopping_cart_rounded,
              color: AppTheme.primary,
            ),
            const SizedBox(height: 10),
            FutureBuilder<double>(
              future: _calcOnlineCost(completed),
              builder: (_, snap) {
                final cost = snap.data ?? 0;
                final margin = revenue - cost;
                return Row(children: [
                  Expanded(
                      child: _StatCard(
                    label: 'Өзіндік құн',
                    value: '${_fmt(cost)} ₸',
                    icon: Icons.arrow_downward_rounded,
                    color: AppTheme.danger,
                  )),
                  const SizedBox(width: 10),
                  Expanded(
                      child: _StatCard(
                    label: 'Маржа',
                    value: '${_fmt(margin)} ₸',
                    icon: Icons.account_balance_wallet_outlined,
                    color: margin >= 0 ? AppTheme.success : AppTheme.danger,
                  )),
                ]);
              },
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                  child: _StatCard(
                label: 'Тапсырыстар',
                value: '$totalCount',
                icon: Icons.receipt_long_outlined,
                color: AppTheme.primary,
              )),
              const SizedBox(width: 10),
              Expanded(
                  child: _StatCard(
                label: 'Бас тарту',
                value: '$cancelled',
                icon: Icons.cancel_outlined,
                color: AppTheme.danger,
              )),
            ]),
            const SizedBox(height: 10),
            _StatCard(
              label: 'Сатылған жұп (онлайн)',
              value: '$pairsSold жұп',
              icon: Icons.shopping_bag_outlined,
              color: AppTheme.success,
            ),
            const SizedBox(height: 20),
            const Text('Күндік белсенділік (онлайн)',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary)),
            const SizedBox(height: 10),
            _MobileDailyChart(
              offlineSales: const [],
              onlineOrders: completed,
              month: month,
            ),
          ],
        );
      },
    );
  }

  Future<double> _calcOnlineCost(List<OrderModel> orders) async {
    double total = 0;
    for (final o in orders) {
      for (final item in o.items) {
        try {
          final batches = await FirestoreService().getBatches(item.productId);
          if (batches.isEmpty) continue;
          final b = batches.firstWhere((b) => b.id == item.batchId,
              orElse: () => batches.first);
          total += b.purchasePrice * item.qty;
        } catch (_) {}
      }
    }
    return total;
  }
}

// ── Shared: Күндік диаграмма (горизонталды скролл) ───────────────────────────
class _MobileDailyChart extends StatefulWidget {
  final List<SaleModel> offlineSales;
  final List<OrderModel> onlineOrders;
  final DateTime month;
  const _MobileDailyChart({
    required this.offlineSales,
    required this.onlineOrders,
    required this.month,
  });
  @override
  State<_MobileDailyChart> createState() => _MobileDailyChartState();
}

class _MobileDailyChartState extends State<_MobileDailyChart> {
  int? _tapped;

  @override
  Widget build(BuildContext context) {
    final daysInMonth =
        DateUtils.getDaysInMonth(widget.month.year, widget.month.month);
    final byDay = List<double>.filled(daysInMonth, 0.0);

    for (final s in widget.offlineSales) {
      if (s.saleDate.month == widget.month.month) {
        byDay[s.saleDate.day - 1] += s.totalPrice;
      }
    }
    for (final o in widget.onlineOrders) {
      if (o.createdAt.month == widget.month.month) {
        byDay[o.createdAt.day - 1] += o.totalWithDelivery;
      }
    }

    final maxVal = byDay.reduce((a, b) => a > b ? a : b);
    final effectiveMax = maxVal < 1 ? 1.0 : maxVal;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 2))
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 24,
            child: _tapped != null
                ? Row(children: [
                    Text(
                      '${_tapped! + 1} ${_monthShort(widget.month.month)}: ',
                      style: const TextStyle(
                          fontSize: 12, color: AppTheme.textSecondary),
                    ),
                    Text(
                      '${_fmtRev(byDay[_tapped!])} ₸',
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.success),
                    ),
                  ])
                : Text(
                    'Жалпы: ${_fmtRev(byDay.fold(0.0, (s, v) => s + v))} ₸',
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.primary),
                  ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: daysInMonth * 16.0,
              child: Column(children: [
                SizedBox(
                  height: 80,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: List.generate(daysInMonth, (i) {
                      final v = byDay[i];
                      final isSel = _tapped == i;
                      return GestureDetector(
                        onTap: () =>
                            setState(() => _tapped = _tapped == i ? null : i),
                        child: Container(
                          width: 14,
                          margin: const EdgeInsets.symmetric(horizontal: 1),
                          height: v > 0 ? (v / effectiveMax) * 76 + 4 : 3,
                          decoration: BoxDecoration(
                            gradient: isSel
                                ? null
                                : const LinearGradient(
                                    colors: [
                                      AppTheme.primaryLight,
                                      AppTheme.primary
                                    ],
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                  ),
                            color: isSel ? AppTheme.success : null,
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(3)),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  height: 16,
                  child: Row(
                    children: List.generate(daysInMonth, (i) {
                      final day = i + 1;
                      final isSel = _tapped == i;
                      final show = isSel ||
                          day == 1 ||
                          day == 10 ||
                          day == 20 ||
                          day == daysInMonth;
                      return SizedBox(
                        width: 16,
                        child: Text(
                          show ? '$day' : '',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 8,
                            color: isSel ? AppTheme.primary : AppTheme.textHint,
                            fontWeight:
                                isSel ? FontWeight.w700 : FontWeight.w400,
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  static String _fmtRev(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(0)}K';
    return v.toStringAsFixed(0);
  }

  static String _monthShort(int m) {
    const names = [
      'қан',
      'ақп',
      'нау',
      'сәу',
      'мам',
      'мау',
      'шіл',
      'там',
      'қыр',
      'қаз',
      'қар',
      'жел'
    ];
    return names[m - 1];
  }
}

// ── Shared: StatCard ──────────────────────────────────────────────────────────
class _StatCard extends StatelessWidget {
  final String label, value;
  final String? sub;
  final IconData icon;
  final Color color;
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.sub,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2))
          ],
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w500)),
              Text(value,
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w800, color: color)),
              if (sub != null)
                Text(sub!,
                    style: const TextStyle(
                        fontSize: 10, color: AppTheme.textHint)),
            ],
          )),
        ]),
      );
}

// ── Shared: KpiChip ───────────────────────────────────────────────────────────
class _KpiChip extends StatelessWidget {
  final String label, value;
  final Color color;
  const _KpiChip(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Expanded(
          child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: TextStyle(
                  fontSize: 10, color: color, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w800, color: color),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ]),
      ));
}

// ── Shared: number formatter ──────────────────────────────────────────────────
String _fmt(double v) {
  if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
  if (v >= 1000) return '${(v / 1000).toStringAsFixed(0)}K';
  return v.toStringAsFixed(0);
}
