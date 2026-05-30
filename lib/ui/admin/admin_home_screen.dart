import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_user.dart';
import '../../data/models/models.dart';
import '../../data/services/firestore_service.dart';
import '../../theme/qoima_design.dart';
import '../profile/sellers_screen.dart';
import '../profile/warehouses_screen.dart';
import 'online_orders_screen.dart';

class AdminHomeScreen extends StatelessWidget {
  const AdminHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appUser = context.watch<AppUser>();
    final service = FirestoreService();
    final name = appUser.name.isNotEmpty ? appUser.name : 'Добрый день';

    return Scaffold(
      backgroundColor: cBg,
      body: Column(children: [
        // ── Header with business-code card ────────────────────────────
        Container(
          decoration: const BoxDecoration(gradient: kGrad),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title row
                  Row(children: [
                    Expanded(
                      child: StreamBuilder<StoreModel?>(
                        stream: service.watchStore(),
                        builder: (_, s) {
                          final storeName = s.data?.storeName ?? '';
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name,
                                  style: manrope(23, FontWeight.w800,
                                      color: Colors.white, letterSpacing: -0.5)),
                              if (storeName.isNotEmpty)
                                Text('Магазин «$storeName»',
                                    style: manrope(13, FontWeight.w500,
                                        color: Colors.white.withValues(alpha: 0.78))),
                            ],
                          );
                        },
                      ),
                    ),
                    // Bell with pending requests badge
                    StreamBuilder<List<Map<String, dynamic>>>(
                      stream: service.watchPendingRequests(),
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
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 32),
            children: [
              // Metric cards row
              Row(children: [
                // Revenue card
                Expanded(
                  child: StreamBuilder<List<SaleModel>>(
                    stream: service.watchSalesForMonth(DateTime.now()),
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
                            Text('Выручка за месяц',
                                style: manrope(12, FontWeight.w600,
                                    color: cInk3)),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 12),
                // Pairs on warehouses card — counted from actual batch data
                Expanded(
                  child: FutureBuilder<int>(
                    future: _countTotalPairs(service),
                    builder: (_, snap) {
                      final pairs = snap.data ?? 0;
                      return QCard(
                        padding: const EdgeInsets.all(15),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            QIconTile(
                              icon: const Icon(Icons.inventory_2_outlined,
                                  color: cBlue, size: 19),
                              tone: 'blue',
                              size: 38,
                            ),
                            const SizedBox(height: 9),
                            Text('$pairs',
                                style: manrope(22, FontWeight.w800,
                                    color: cInk, letterSpacing: -0.5)),
                            const SizedBox(height: 2),
                            Text('Пар на складах',
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
                stream: service.watchActiveOnlineCount(),
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
                              Text('Онлайн-заказы',
                                  style: manrope(14.5, FontWeight.w700,
                                      color: cInk)),
                              Text(
                                count == 0
                                    ? 'Нет новых заказов'
                                    : '$count новых ждут подтверждения',
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

              // Quick actions
              const QSecLabel('Быстрые действия'),

              // Sellers
              StreamBuilder<List<Map<String, dynamic>>>(
                stream: service.watchPendingRequests(),
                builder: (_, snap) {
                  final pending = snap.data?.length ?? 0;
                  return StreamBuilder<List<Map<String, dynamic>>>(
                    stream: service.watchActiveSellers(),
                    builder: (_, selSnap) {
                      final active = selSnap.data?.length ?? 0;
                      return _QMenuItem(
                        icon: Icons.group_outlined,
                        tone: 'green',
                        title: 'Продавцы',
                        sub: '$active активных · $pending запросов',
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
                stream: service.watchWarehouses(),
                builder: (_, s) {
                  final whs = s.data ?? [];
                  final total = whs.fold<int>(0, (a, w) => a + (w.totalPairs));
                  return _QMenuItem(
                    icon: Icons.storefront_outlined,
                    tone: 'blue',
                    title: 'Склады',
                    sub: '${whs.length} складов · $total пар',
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const WarehousesScreen())),
                  );
                },
              ),
            ],
          ),
        ),
      ]),
    );
  }

  Future<int> _countTotalPairs(FirestoreService service) async {
    try {
      final (batchesMap, _) = await service.getAllBatchesGrouped();
      int total = 0;
      for (final batches in batchesMap.values) {
        for (final batch in batches) {
          for (final qty in batch.sizesQuantity.values) {
            total += qty;
          }
        }
      }
      return total;
    } catch (_) {
      return 0;
    }
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
