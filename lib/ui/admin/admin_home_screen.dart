import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_user.dart';
import '../../data/models/models.dart';
import '../../data/services/firestore_service.dart';
import '../../data/services/return_service.dart';
import '../../theme/qoima_design.dart';
import 'settings/sellers_screen.dart';
import 'settings/warehouses_screen.dart';
import 'online_orders_screen.dart';
import 'returns/admin_returns_screen.dart';

import '../../core/lang.dart';
class AdminHomeScreen extends StatefulWidget {
  const AdminHomeScreen({super.key});

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  final _service = FirestoreService();

  late final Stream<StoreModel?> _storeStream = _service.watchStore();
  late final Stream<List<Map<String, dynamic>>> _pendingStream =
      _service.watchPendingRequests();
  late final Stream<List<Map<String, dynamic>>> _sellersStream =
      _service.watchActiveSellers();
  late final Stream<List<SaleModel>> _salesStream =
      _service.watchSalesForMonth(DateTime.now());
  late final Stream<int> _onlineCountStream =
      _service.watchActiveOnlineCount();
  late final Stream<List<WarehouseModel>> _warehousesStream =
      _service.watchWarehouses();
  late final Stream<List<ReturnModel>> _returnsStream =
      ReturnService().watchAllReturns(AppUser.current.uid);

  late Future<int> _stockFuture;

  @override
  void initState() {
    super.initState();
    _stockFuture = _countStock();
  }

  Future<int> _countStock() async {
    try {
      final (batchesMap, _) = await _service.getAllBatchesGrouped();
      int total = 0;
      for (final batches in batchesMap.values) {
        for (final b in batches) {
          total += b.totalAvailable;
        }
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  Future<void> _onRefresh() async {
    await Future.wait([
      _service.refreshOnlineOrders(),
      _service.refreshProducts(),
      _service.refreshWarehouses(),
    ]);
    if (mounted) setState(() => _stockFuture = _countStock());
  }

  @override
  Widget build(BuildContext context) {
    final appUser = context.watch<AppUser>();
    final name = appUser.name.isNotEmpty ? appUser.name : tr('Добрый день', 'Қайырлы күн');

    return Scaffold(
      backgroundColor: cBg,
      body: Column(children: [
        // ── Header ───────────────────────────────────────────────────
        Container(
          decoration: const BoxDecoration(gradient: kGrad),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                      child: StreamBuilder<StoreModel?>(
                        stream: _storeStream,
                        builder: (_, s) {
                          final storeName = s.data?.storeName ?? '';
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name,
                                  style: manrope(23, FontWeight.w800,
                                      color: Colors.white, letterSpacing: -0.5)),
                              if (storeName.isNotEmpty)
                                Text(tr('Магазин «$storeName»', '«$storeName» дүкені'),
                                    style: manrope(13, FontWeight.w500,
                                        color: Colors.white.withValues(alpha: 0.78))),
                            ],
                          );
                        },
                      ),
                    ),
                    StreamBuilder<List<Map<String, dynamic>>>(
                      stream: _pendingStream,
                      builder: (_, snap) {
                        final count = snap.data?.length ?? 0;
                        return GestureDetector(
                          onTap: () => Navigator.push(context,
                              MaterialPageRoute(
                                  builder: (_) => const SellersScreen())),
                          child: QHeaderBtn(
                            Icons.notifications_outlined,
                            badge: count,
                          ),
                        );
                      },
                    ),
                  ]),
                ],
              ),
            ),
          ),
        ),

        // ── Body ─────────────────────────────────────────────────────
        Expanded(
          child: RefreshIndicator(
            color: cGreen,
            onRefresh: _onRefresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 32),
              children: [
                // Metric cards row
                Row(children: [
                  Expanded(
                    child: StreamBuilder<List<SaleModel>>(
                      stream: _salesStream,
                      builder: (_, s) {
                        final total = (s.data ?? [])
                            .fold<double>(0, (a, b) => a + b.totalPrice);
                        return QCard(
                          padding: const EdgeInsets.all(15),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              QIconTile(
                                icon: const Icon(Icons.account_balance_wallet_outlined,
                                    color: cGreen, size: 19),
                                tone: 'green',
                                size: 38,
                              ),
                              const SizedBox(height: 9),
                              Text(money(total),
                                  style: manrope(20, FontWeight.w800,
                                      color: cInk, letterSpacing: -0.5)),
                              const SizedBox(height: 2),
                              Text(tr('Выручка за месяц', 'Айлық түсім'),
                                  style: manrope(12, FontWeight.w600,
                                      color: cInk3)),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FutureBuilder<int>(
                      future: _stockFuture,
                      builder: (_, snap) {
                        final total = snap.data ?? 0;
                        return QCard(
                          padding: const EdgeInsets.all(15),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              QIconTile(
                                icon: const Icon(Icons.inventory_2_outlined,
                                    color: cGreen, size: 19),
                                tone: 'green',
                                size: 38,
                              ),
                              const SizedBox(height: 9),
                              Text('$total',
                                  style: manrope(22, FontWeight.w800,
                                      color: cInk, letterSpacing: -0.5)),
                              const SizedBox(height: 2),
                              Text(tr('Товаров на складах', 'Қойма тауарлары'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: manrope(12, FontWeight.w600,
                                      color: cInk3)),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ]),

                const SizedBox(height: 12),

                // Online orders block
                StreamBuilder<int>(
                  stream: _onlineCountStream,
                  builder: (_, s) {
                    final count = s.data ?? 0;
                    return GestureDetector(
                      onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const OnlineOrdersScreen())),
                      child: Container(
                        padding: const EdgeInsets.all(15),
                        decoration: BoxDecoration(
                          color: cSurface,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                              color: cGreen.withValues(alpha: 0.2), width: 1.5),
                          boxShadow: kShadowSm,
                        ),
                        child: Row(children: [
                          QIconTile(
                            icon: const Icon(Icons.language_outlined,
                                color: cGreen, size: 20),
                            tone: 'green',
                          ),
                          const SizedBox(width: 13),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(tr('Онлайн-заказы', 'Онлайн тапсырыстар'),
                                    style: manrope(14.5, FontWeight.w700,
                                        color: cInk)),
                                Text(
                                  count == 0
                                      ? tr('Нет новых заказов', 'Жаңа тапсырыс жоқ')
                                      : tr('$count новых ждут подтверждения', '$count жаңасы растауды күтуде'),
                                  style: manrope(12.5, FontWeight.w500,
                                      color: cInk3),
                                ),
                              ],
                            ),
                          ),
                          if (count > 0)
                            Container(
                              constraints: const BoxConstraints(
                                  minWidth: 24, minHeight: 24),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                  color: cRed,
                                  borderRadius: BorderRadius.circular(12)),
                              child: Center(
                                child: Text('$count',
                                    style: manrope(12.5, FontWeight.w800,
                                        color: Colors.white)),
                              ),
                            )
                          else
                            const Icon(Icons.chevron_right_rounded,
                                color: cInk3, size: 20),
                        ]),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 12),

                // Returns block
                StreamBuilder<List<ReturnModel>>(
                  stream: _returnsStream,
                  builder: (_, s) {
                    final all = s.data ?? [];
                    final newCount = all
                        .where((r) => r.status == ReturnStatus.requested)
                        .length;
                    return GestureDetector(
                      onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const AdminReturnsScreen())),
                      child: Container(
                        padding: const EdgeInsets.all(15),
                        decoration: BoxDecoration(
                          color: cSurface,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                              color: cGreen.withValues(alpha: 0.2), width: 1.5),
                          boxShadow: kShadowSm,
                        ),
                        child: Row(children: [
                          QIconTile(
                            icon: const Icon(Icons.assignment_return_outlined,
                                color: cGreen, size: 20),
                            tone: 'green',
                          ),
                          const SizedBox(width: 13),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(tr('Возвраты', 'Қайтарулар'),
                                    style: manrope(14.5, FontWeight.w700,
                                        color: cInk)),
                                Text(
                                  newCount == 0
                                      ? tr('Нет новых запросов', 'Жаңа сұраныс жоқ')
                                      : tr('$newCount новых запросов', '$newCount жаңа сұраныс'),
                                  style: manrope(12.5, FontWeight.w500,
                                      color: cInk3),
                                ),
                              ],
                            ),
                          ),
                          if (newCount > 0)
                            Container(
                              constraints: const BoxConstraints(
                                  minWidth: 24, minHeight: 24),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                  color: cAmber,
                                  borderRadius: BorderRadius.circular(12)),
                              child: Center(
                                child: Text('$newCount',
                                    style: manrope(12.5, FontWeight.w800,
                                        color: Colors.white)),
                              ),
                            )
                          else
                            const Icon(Icons.chevron_right_rounded,
                                color: cInk3, size: 20),
                        ]),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 12),

                // Quick actions
                QSecLabel(tr('Быстрые действия', 'Жылдам әрекеттер')),

                // Sellers
                StreamBuilder<List<Map<String, dynamic>>>(
                  stream: _pendingStream,
                  builder: (_, snap) {
                    final pending = snap.data?.length ?? 0;
                    return StreamBuilder<List<Map<String, dynamic>>>(
                      stream: _sellersStream,
                      builder: (_, selSnap) {
                        final active = selSnap.data?.length ?? 0;
                        return _QMenuItem(
                          icon: Icons.group_outlined,
                          tone: 'green',
                          title: tr('Продавцы', 'Сатушылар'),
                          sub: tr('$active активных · $pending запросов', '$active белсенді · $pending сұраныс'),
                          badge: pending > 0 ? '$pending' : null,
                          onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const SellersScreen())),
                        );
                      },
                    );
                  },
                ),

                const SizedBox(height: 10),

                // Warehouses
                StreamBuilder<List<WarehouseModel>>(
                  stream: _warehousesStream,
                  builder: (_, s) {
                    final whs = s.data ?? [];
                    return FutureBuilder<int>(
                      future: _stockFuture,
                      builder: (_, stockSnap) {
                        final total = stockSnap.data ?? 0;
                        return _QMenuItem(
                          icon: Icons.storefront_outlined,
                          tone: 'blue',
                          title: tr('Склады', 'Қоймалар'),
                          sub: tr('${whs.length} складов · $total шт.', '${whs.length} қойма · $total дана'),
                          onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const WarehousesScreen())),
                        );
                      },
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ]),
    );
  }
}

// ── Local QMenuItem ────────────────────────────────────────────────────────────
class _QMenuItem extends StatelessWidget {
  final IconData icon;
  final String tone;
  final String title;
  final String? sub;
  final String? badge;
  final VoidCallback onTap;

  const _QMenuItem({
    required this.icon,
    required this.tone,
    required this.title,
    this.sub,
    this.badge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
          decoration: BoxDecoration(
            color: cSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cLine),
          ),
          child: Row(children: [
            QIconTile(
              icon: Icon(icon, color: _iconColor(), size: 20),
              tone: tone,
              size: 40,
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: manrope(14.5, FontWeight.w700, color: cInk)),
                  if (sub != null)
                    Text(sub!,
                        style: manrope(12.5, FontWeight.w500, color: cInk3)),
                ],
              ),
            ),
            if (badge != null) ...[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: cRedTint, borderRadius: BorderRadius.circular(9)),
                child: Text(badge!,
                    style: manrope(11.5, FontWeight.w700,
                        color: const Color(0xFFB11A2B))),
              ),
              const SizedBox(width: 6),
            ],
            const Icon(Icons.chevron_right_rounded, color: cInk3, size: 20),
          ]),
        ),
      );

  Color _iconColor() {
    switch (tone) {
      case 'blue':
        return cBlue;
      case 'red':
        return cRed;
      case 'amber':
        return cAmber;
      default:
        return cGreen;
    }
  }
}
