import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/app_user.dart';
import '../../../core/l10n_ext.dart';
import '../../../core/warehouse_context.dart';
import '../../../data/models/models.dart';
import '../../../data/services/firestore_service.dart';
import '../../../theme/qoima_design.dart';
import 'seller_drilldown_screen.dart';

import '../../../core/lang.dart';
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
                fontWeight: FontWeight.w700, color: cInk)),
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
                                    color: sel
                                        ? cGreen
                                        : cBg,
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
                  style: const TextStyle(color: cInk2))),
          ElevatedButton(
              onPressed: () {
                setState(() => _month = temp);
                Navigator.pop(ctx);
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: cGreen,
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
      backgroundColor: cBg,
      body: RefreshIndicator(
        color: cGreen,
        onRefresh: () async {
          await _service.refreshProducts();
          await _service.refreshSalesHistory();
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
          SliverToBoxAdapter(
            child: Container(
              decoration: const BoxDecoration(gradient: kGrad),
              child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 6, 20, 16),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Title + calendar btn
                          Row(children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(context.l10n.analyticsTitle,
                                      style: manrope(23, FontWeight.w800,
                                          color: Colors.white,
                                          letterSpacing: -0.5)),
                                  Text(context.monthShort(_month),
                                      style: manrope(13, FontWeight.w500,
                                          color: Colors.white
                                              .withValues(alpha: 0.78))),
                                ],
                              ),
                            ),
                            GestureDetector(
                              onTap: _pickMonth,
                              child: QHeaderBtn(
                                  Icons.calendar_today_outlined),
                            ),
                          ]),
                          const SizedBox(height: 14),
                          // Pill-style tab switcher
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(13),
                            ),
                            child: AnimatedBuilder(
                              animation: _tabCtrl,
                              builder: (_, __) => Row(
                                children: [
                                  context.l10n.generalTab,
                                  context.l10n.sellersTab,
                                  context.l10n.warehouseTab,
                                  'Онлайн',
                                ].asMap().entries.map((e) {
                                  final active =
                                      _tabCtrl.index == e.key;
                                  return Expanded(
                                    child: GestureDetector(
                                      onTap: () => _tabCtrl.animateTo(
                                          e.key),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 8),
                                        decoration: BoxDecoration(
                                          color: active
                                              ? Colors.white
                                              : Colors.transparent,
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        child: Text(
                                          e.value,
                                          textAlign: TextAlign.center,
                                          style: manrope(
                                            12.5,
                                            FontWeight.w700,
                                            color: active
                                                ? cGreenDeep
                                                : Colors.white.withValues(
                                                    alpha: 0.85),
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
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
            if (sSnap.connectionState == ConnectionState.waiting &&
                sSnap.data == null) {
              return const Center(
                  child: CircularProgressIndicator(color: cGreen));
            }
            if (sSnap.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.error_outline_rounded,
                        color: cRed, size: 40),
                    const SizedBox(height: 12),
                    Text(tr('Ошибка загрузки данных', 'Деректерді жүктеу қатесі'),
                        style: manrope(15, FontWeight.w700, color: cInk)),
                    const SizedBox(height: 6),
                    Text(sSnap.error.toString(),
                        textAlign: TextAlign.center,
                        style: manrope(12, FontWeight.w500, color: cInk2)),
                  ]),
                ),
              );
            }

            final mSales = sSnap.data ?? [];
            // pureSales — барлық офлайн жазбалар (қайтарулар да кіреді,
            // теріс total_price → таза түсім автоматты балансталады).
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

            // Таза сан: қайтарылған дана шегеріледі (isReturn → -quantity).
            final offlinePairs = pureSales.fold<int>(
                0, (acc, e) => acc + (e.isReturn ? -e.quantity : e.quantity));
            final onlinePairs = onlineOrders.fold<int>(
                0, (s, o) => s + o.items.fold(0, (a, i) => a + i.qty));
            final totalPairs = offlinePairs + onlinePairs;

            // Өзіндік құн — қайтарылған тауардың шығыны шегеріледі.
            final totalCost = mSales.fold<double>(
                0, (acc, e) => acc + (e.isReturn
                    ? -(e.purchasePrice * e.quantity)
                    :   e.purchasePrice * e.quantity));
            final margin = totalRevenue - totalCost;

            if (mSales.isEmpty && onlineOrders.isEmpty) {
              return Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.bar_chart_rounded,
                      size: 56, color: cInk3.withValues(alpha: 0.4)),
                  const SizedBox(height: 12),
                  Text(tr('В этом месяце продаж нет', 'Бұл айда сатылым жоқ'),
                      style: manrope(16, FontWeight.w700, color: cInk2)),
                ]),
              );
            }

            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Карточка общей выручки (34px) ─────────────────────
                  QCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tr('Общая выручка', 'Жалпы түсім'),
                            style: manrope(13, FontWeight.w600, color: cInk3)),
                        const SizedBox(height: 2),
                        Text('${_fmt(totalRevenue)} ₸',
                            style: manrope(34, FontWeight.w800, color: cInk,
                                letterSpacing: -1)),
                        const SizedBox(height: 6),
                        Row(children: [
                          RichText(
                              text: TextSpan(children: [
                            TextSpan(
                                text: 'Офлайн: ',
                                style: manrope(12.5, FontWeight.w600,
                                    color: cInk2)),
                            TextSpan(
                                text: '${_fmt(offlineRevenue)} ₸',
                                style: manrope(12.5, FontWeight.w700,
                                    color: cInk)),
                          ])),
                          const SizedBox(width: 14),
                          RichText(
                              text: TextSpan(children: [
                            TextSpan(
                                text: 'Онлайн: ',
                                style: manrope(12.5, FontWeight.w600,
                                    color: cInk2)),
                            TextSpan(
                                text: '${_fmt(onlineRevenue)} ₸',
                                style: manrope(12.5, FontWeight.w700,
                                    color: cInk)),
                          ])),
                        ]),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // ── Себестоимость / Маржа ─────────────────────────────
                  Row(children: [
                    Expanded(
                      child: QCard(
                        padding: const EdgeInsets.all(15),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              const Icon(Icons.arrow_downward_rounded,
                                  size: 16, color: cRed),
                              const SizedBox(width: 6),
                              Text(tr('Себестоимость', 'Өзіндік құн'),
                                  style: manrope(12, FontWeight.w600,
                                      color: cInk3)),
                            ]),
                            const SizedBox(height: 6),
                            Text('${_fmt(totalCost)} ₸',
                                style: manrope(20, FontWeight.w800,
                                    color: cInk)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: QCard(
                        padding: const EdgeInsets.all(15),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Icon(Icons.trending_up_rounded,
                                  size: 16,
                                  color: margin >= 0 ? cGreen : cRed),
                              const SizedBox(width: 6),
                              Text('Маржа',
                                  style: manrope(12, FontWeight.w600,
                                      color: cInk3)),
                            ]),
                            const SizedBox(height: 6),
                            Text('${_fmt(margin)} ₸',
                                style: manrope(20, FontWeight.w800,
                                    color: margin >= 0 ? cGreen : cRed)),
                          ],
                        ),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  // ── Продажи по дням ───────────────────────────────────
                  QCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(tr('Продажи по дням', 'Күндер бойынша сатылым'),
                                style: manrope(14, FontWeight.w700,
                                    color: cInk)),
                            QPill(tr('$totalPairs шт', '$totalPairs дана'),
                                tone: 'green',
                                icon: const Icon(Icons.trending_up_rounded,
                                    size: 11,
                                    color: Color(0xFF00713F))),
                          ],
                        ),
                        const SizedBox(height: 4),
                        _MobileDailyChart(
                          offlineSales: pureSales,
                          onlineOrders: onlineOrders,
                          month: widget.month,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // ── Топ продаж ────────────────────────────────────────
                  ...() {
                    final top =
                        _buildTopSalesWidgets(pureSales, onlineOrders);
                    if (top.isEmpty) return <Widget>[];
                    return [QSecLabel(tr('Топ продаж', 'Топ сатылым')), ...top];
                  }(),
                ],
              ),
            );
          },
        );
      },
    );
  }

  static List<Widget> _buildTopSalesWidgets(
      List<SaleModel> offlineSales, List<OrderModel> completedOrders) {
    final Map<String, ({double revenue, int qty})> by = {};

    for (final s in offlineSales) {
      final n = s.productName.isNotEmpty ? s.productName : s.productId;
      final e = by[n];
      // Қайтару: revenue теріс (total_price < 0), qty шегеріледі.
      by[n] = (
        revenue: (e?.revenue ?? 0) + s.totalPrice,
        qty: (e?.qty ?? 0) + (s.isReturn ? -s.quantity : s.quantity),
      );
    }
    for (final o in completedOrders) {
      for (final it in o.items) {
        final n = it.productName.isNotEmpty ? it.productName : '—';
        final e = by[n];
        by[n] = (revenue: (e?.revenue ?? 0) + it.subtotal,
                 qty: (e?.qty ?? 0) + it.qty);
      }
    }

    final top3 = (by.entries
          .where((e) => e.value.revenue > 0 && e.value.qty > 0)
          .toList()
          ..sort((a, b) => b.value.revenue.compareTo(a.value.revenue)))
        .take(3)
        .toList();

    return top3.asMap().entries.map((e) {
      final rank = e.key;
      final entry = e.value;
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: QCard(
          padding: const EdgeInsets.all(13),
          child: Row(children: [
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                color: rank == 0 ? cGreen : cLine2,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Center(
                child: Text('${rank + 1}',
                    style: manrope(14, FontWeight.w800,
                        color: rank == 0 ? Colors.white : cInk2)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.key,
                      style: manrope(13.5, FontWeight.w700, color: cInk),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(tr('${entry.value.qty} шт. продано', '${entry.value.qty} дана сатылды'),
                      style: manrope(11.5, FontWeight.w500, color: cInk3)),
                ],
              ),
            ),
            Text('${_fmt(entry.value.revenue)} ₸',
                style: manrope(14, FontWeight.w800, color: cInk)),
          ]),
        ),
      );
    }).toList();
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
              child: CircularProgressIndicator(color: cGreen));
        }

        final sales = snap.data ?? [];

        final Map<String, _SellerStat> bySeller = {};
        for (final s in sales) {
          if (s.sellerId.isEmpty || s.isOnline) continue;
          // ТӘРТІПТЕН ТӘУЕЛСІЗ: сатушы есебі әрқашан алдымен жасалады, сосын
          // дельта қосылады. Бұрын возврат жазбасы (жаңарақ → тізімде бұрын
          // тұрады) сатылымнан бұрын өңделсе stat==null болып, шегерілмей
          // қалатын → возврат жасалса да «1 сат · 1 шт» болып көрінетін.
          final stat = bySeller.putIfAbsent(s.sellerId,
              () => _SellerStat(id: s.sellerId, name: s.sellerName));
          if (stat.name.isEmpty && s.sellerName.isNotEmpty) {
            stat.name = s.sellerName;
          }
          if (s.isReturn) {
            // Қайтару: revenue теріс (total_price < 0) → шегереді; дана мен
            // сатылым саны да кері есептеледі.
            stat.revenue += s.totalPrice;
            stat.pairs -= s.quantity;
            if (stat.count > 0) stat.count--;
          } else {
            stat.revenue += s.totalPrice;
            stat.pairs += s.quantity;
            stat.count++;
          }
        }

        // Толық қайтарылған (нөлге түскен) сатушы тізімнен алынады.
        final ranked = bySeller.values
            .where((s) => s.count > 0 || s.revenue > 0.01)
            .toList()
          ..sort((a, b) => b.revenue.compareTo(a.revenue));
        final grandTotal = ranked.fold<double>(0, (a, s) => a + s.revenue);

        if (ranked.isEmpty) {
          return Center(
              child: Text(tr('Продаж нет', 'Сатылым жоқ'),
                  style: TextStyle(color: cInk2)));
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(children: [
              _KpiChip(
                  label: tr('Продавцы', 'Сатушылар'),
                  value: '${ranked.length}',
                  color: cGreen),
              const SizedBox(width: 8),
              _KpiChip(
                  label: tr('Общая выручка', 'Жалпы түсімі'),
                  value: '${_fmt(grandTotal)} ₸',
                  color: cGreen),
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
                        Text(tr('${stat.count} прод · ${stat.pairs} шт', '${stat.count} сат · ${stat.pairs} дана'),
                            style: const TextStyle(
                                fontSize: 11, color: cInk2)),
                      ],
                    )),
                    Text('${_fmt(stat.revenue)} ₸',
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: cGreen)),
                    const SizedBox(width: 8),
                    const Icon(Icons.chevron_right_rounded,
                        color: cInk3, size: 22),
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
  final String id;
  String name;
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
                  child: CircularProgressIndicator(color: cGreen));
            }
            final allSales =
                (snap.data ?? []).where((s) => !s.isOnline).toList();

            if (warehouses.isEmpty) {
              return Center(
                  child: Text(tr('Нет склада', 'Қойма жоқ'),
                      style: TextStyle(color: cInk2)));
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
      // Қайтару: total_price теріс, qty шегеріледі — таза сан балансталады.
      revByName[name] = (revByName[name] ?? 0) + s.totalPrice;
      qtyByName[name] =
          (qtyByName[name] ?? 0) + (s.isReturn ? -s.quantity : s.quantity);
    }
    final top3 = (revByName.entries
          .where((e) => e.value > 0 && (qtyByName[e.key] ?? 0) > 0)
          .toList()
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
              color: cGreenTint,
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(children: [
              const Icon(Icons.warehouse_rounded,
                  color: cGreen, size: 20),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(warehouse.name,
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: cGreen))),
              Text('${_fmt(revenue)} ₸',
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: cGreen)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('Дневная активность', 'Күндік белсенділік'),
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: cInk2)),
                const SizedBox(height: 8),
                _MobileDailyChart(
                  offlineSales: sales,
                  onlineOrders: const [],
                  month: month,
                ),
                if (top3.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(tr('Топ-3 продаж', 'Топ-3 сатылымдар'),
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: cInk2)),
                  const SizedBox(height: 8),
                  ...top3.asMap().entries.map((e) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(children: [
                          Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              color: cGreen.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Center(
                                child: Text('${e.key + 1}',
                                    style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        color: cGreen))),
                          ),
                          const SizedBox(width: 8),
                          Expanded(child: Text(
                            e.value.key.length > 20
                                ? '${e.value.key.substring(0, 20)}...'
                                : e.value.key,
                            style: const TextStyle(
                                fontSize: 12, color: cInk),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          )),
                          Text(tr('${qtyByName[e.value.key] ?? 0} шт', '${qtyByName[e.value.key] ?? 0} дана'),
                              style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: cGreen)),
                        ]),
                      )),
                ],
                const SizedBox(height: 14),
                Text(tr('Залежавшийся товар (30+ дней)', 'Жатып қалған тауар (30+ күн)'),
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: cInk2)),
                const SizedBox(height: 8),
                FutureBuilder<List<_StaleItem>>(
                  future: _loadStale(warehouse.id),
                  builder: (_, snap) {
                    if (!snap.hasData) {
                      return const SizedBox(
                          height: 30,
                          child: Center(
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: cGreen)));
                    }
                    if (snap.data!.isEmpty) {
                      return Text(tr('Залежавшихся товаров нет 👍', 'Жатып қалған тауар жоқ 👍'),
                          style: TextStyle(
                              fontSize: 12, color: cInk3));
                    }
                    return Column(
                      children: snap.data!
                          .map((item) => Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Row(children: [
                                  const Icon(Icons.warning_amber_rounded,
                                      color: cAmber, size: 16),
                                  const SizedBox(width: 8),
                                  Expanded(
                                      child: Text(item.product.name,
                                          style: const TextStyle(
                                              fontSize: 12,
                                              color: cInk),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis)),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: cAmberTint,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(tr('${item.days} дней', '${item.days} күн'),
                                        style: const TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                            color: cAmber)),
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
    // Онлайн өзіндік құнды sales_history-дегі purchase_price-тан есепте (N+1 жоқ)
    return StreamBuilder<List<SaleModel>>(
      stream: FirestoreService().watchSalesForMonth(month),
      builder: (_, sSnap) {
        // Возврат жазбасы (isReturn) себестоимостьты кері шегереді → балансталады.
        final onlineCost = (sSnap.data ?? [])
            .where((s) => s.isOnline)
            .fold<double>(
                0,
                (a, s) => a +
                    (s.isReturn
                        ? -(s.purchasePrice * s.quantity)
                        : s.purchasePrice * s.quantity));

        return StreamBuilder<List<OrderModel>>(
          stream: FirestoreService().watchOnlineOrders(),
          builder: (_, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(
                  child: CircularProgressIndicator(color: cGreen));
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
            final returned = allOrders
                .where((o) => o.status == OrderModel.statusReturned)
                .length;
            final totalCount = allOrders.length;

            final revenue =
                completed.fold<double>(0, (s, o) => s + o.totalWithDelivery);
            final pairsSold = completed.fold<int>(
                0, (s, o) => s + o.items.fold(0, (a, i) => a + i.qty));
            final margin = revenue - onlineCost;

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _StatCard(
                  label: tr('Выручка (Онлайн)', 'Түсімі (Онлайн)'),
                  value: '${_fmt(revenue)} ₸',
                  icon: Icons.shopping_cart_rounded,
                  color: cGreen,
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                      child: _StatCard(
                    label: tr('Себестоимость', 'Өзіндік құн'),
                    value: '${_fmt(onlineCost)} ₸',
                    icon: Icons.arrow_downward_rounded,
                    color: cRed,
                  )),
                  const SizedBox(width: 10),
                  Expanded(
                      child: _StatCard(
                    label: 'Маржа',
                    value: '${_fmt(margin)} ₸',
                    icon: Icons.account_balance_wallet_outlined,
                    color: margin >= 0 ? cGreen : cRed,
                  )),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                      child: _StatCard(
                    label: tr('Заказы', 'Тапсырыстар'),
                    value: '$totalCount',
                    icon: Icons.receipt_long_outlined,
                    color: cGreen,
                  )),
                  const SizedBox(width: 10),
                  Expanded(
                      child: _StatCard(
                    label: tr('Отмены', 'Бас тарту'),
                    value: '$cancelled',
                    icon: Icons.cancel_outlined,
                    color: cRed,
                  )),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                      child: _StatCard(
                    label: tr('Продано (онлайн)', 'Сатылған (онлайн)'),
                    value: tr('$pairsSold шт', '$pairsSold дана'),
                    icon: Icons.shopping_bag_outlined,
                    color: cGreen,
                  )),
                  const SizedBox(width: 10),
                  Expanded(
                      child: _StatCard(
                    label: tr('Возвраты', 'Қайтару'),
                    value: '$returned',
                    icon: Icons.assignment_return_outlined,
                    color: cRed,
                  )),
                ]),
                const SizedBox(height: 20),
                Text(tr('Дневная активность (онлайн)', 'Күндік белсенділік (онлайн)'),
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: cInk)),
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
      },
    );
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

    const double barW = 18;
    const double barGap = 4;
    const double cellW = barW + barGap;
    const double chartH = 90;

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
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tooltip / total row
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 160),
            child: _tapped != null
                ? Row(
                    key: ValueKey(_tapped),
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(
                          color: cGreenTint,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Text(
                            '${_tapped! + 1} ${_monthShort(widget.month.month)} · ',
                            style: manrope(12, FontWeight.w500, color: cGreenDeep),
                          ),
                          Text(
                            '${_fmtRev(byDay[_tapped!])} ₸',
                            style: manrope(13, FontWeight.w800, color: cGreenDeep),
                          ),
                        ]),
                      ),
                    ],
                  )
                : Row(
                    key: const ValueKey('total'),
                    children: [
                      Text(
                        tr('Итого: ', 'Жалпы: '),
                        style: manrope(12.5, FontWeight.w500, color: cInk3),
                      ),
                      Text(
                        '${_fmtRev(byDay.fold(0.0, (s, v) => s + v))} ₸',
                        style: manrope(13, FontWeight.w700, color: cGreen),
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: daysInMonth * cellW,
              child: Column(children: [
                // Bar chart
                SizedBox(
                  height: chartH,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: List.generate(daysInMonth, (i) {
                      final v = byDay[i];
                      final isSel = _tapped == i;
                      final barH = v > 0
                          ? (v / effectiveMax) * (chartH - 6) + 6
                          : 3.0;
                      return GestureDetector(
                        onTap: () => setState(
                            () => _tapped = _tapped == i ? null : i),
                        child: SizedBox(
                          width: cellW,
                          height: chartH,
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              width: barW,
                              height: isSel ? barH + 4 : barH,
                              decoration: BoxDecoration(
                                gradient: isSel
                                    ? null
                                    : LinearGradient(
                                        colors: [
                                          cGreenBright.withValues(alpha: 0.7),
                                          cGreen.withValues(alpha: 0.55),
                                        ],
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                      ),
                                color: isSel ? cGreenDeep : null,
                                borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(5)),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
                // Day labels
                const SizedBox(height: 4),
                SizedBox(
                  height: 14,
                  child: Row(
                    children: List.generate(daysInMonth, (i) {
                      final day = i + 1;
                      final isSel = _tapped == i;
                      final show = isSel ||
                          day == 1 ||
                          day == 5 ||
                          day == 10 ||
                          day == 15 ||
                          day == 20 ||
                          day == 25 ||
                          day == daysInMonth;
                      return SizedBox(
                        width: cellW,
                        child: Text(
                          show ? '$day' : '',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 8.5,
                            color: isSel ? cGreenDeep : cInk3,
                            fontWeight:
                                isSel ? FontWeight.w800 : FontWeight.w400,
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
    if (v < 0) return '-${_fmtRev(-v)}';
    final s = v.round().toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  static String _monthShort(int m) {
    const ru = ['янв', 'фев', 'мар', 'апр', 'май', 'июн',
        'июл', 'авг', 'сен', 'окт', 'ноя', 'дек'];
    const kk = ['қан', 'ақп', 'нау', 'сәу', 'мам', 'мау',
        'шіл', 'там', 'қыр', 'қаз', 'қар', 'жел'];
    return tr(ru[m - 1], kk[m - 1]);
  }
}

// ── Shared: StatCard ──────────────────────────────────────────────────────────
class _StatCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: cSurface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: cLine),
          boxShadow: kShadowSm,
        ),
        child: Row(children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: color, size: 19),
          ),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: manrope(12, FontWeight.w600, color: cInk3)),
              Text(value,
                  style: manrope(20, FontWeight.w800, color: color)),
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

// ── Shared: number formatter — мыңдықты бос орынмен бөледі, қысқартпайды ──────
String _fmt(double v) {
  if (v < 0) return '-${_fmt(-v)}';
  final s = v.round().toString();
  final buf = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
    buf.write(s[i]);
  }
  return buf.toString();
}

