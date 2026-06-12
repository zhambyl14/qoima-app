import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/warehouse_context.dart';
import '../../../data/models/store_discount_model.dart';
import '../../../data/models/store_model.dart';
import '../../../data/repositories/my_store_repository.dart';
import '../../../data/services/firestore_service.dart';
import '../../../theme/qoima_design.dart';
import '../promos/promos_screen.dart';
import 'admin_my_store_discounts_screen.dart';
import 'admin_store_visibility_screen.dart';
import 'ms_widgets.dart';
import 'store_data_screen.dart';

class AdminMyStoreHubScreen extends StatelessWidget {
  const AdminMyStoreHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final service = FirestoreService();
    final repo = MyStoreRepository();

    return Scaffold(
      backgroundColor: cBg,
      body: StreamBuilder<StoreModel?>(
        stream: service.watchStore(),
        builder: (context, snap) {
          final store = snap.data;
          final name = (store?.storeName.isNotEmpty ?? false)
              ? store!.storeName
              : 'Мой магазин';
          final isOnline = store?.isPublished ?? false;

          return Column(children: [
            // ── Gradient header ────────────────────────────────────────
            Container(
              decoration: const BoxDecoration(gradient: kGrad),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 22),
                  child: Column(children: [
                    Row(children: [
                      GestureDetector(
                        onTap: () => Navigator.maybePop(context),
                        child: Container(
                          width: 38, height: 38,
                          margin: const EdgeInsets.only(right: 12),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.chevron_left_rounded,
                              color: Colors.white, size: 22),
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Менің дүкенім',
                                style: manrope(22, FontWeight.w800,
                                    color: Colors.white, letterSpacing: -0.5)),
                            Text(name,
                                style: manrope(13, FontWeight.w500,
                                    color: Colors.white.withValues(alpha: 0.75))),
                          ],
                        ),
                      ),
                    ]),
                    const SizedBox(height: 16),

                    // Online toggle → StoreModel.isPublished
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 13),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.13),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Row(children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          width: 10, height: 10,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isOnline
                                ? const Color(0xFF4AFF98)
                                : Colors.white.withValues(alpha: 0.35),
                            boxShadow: isOnline
                                ? [BoxShadow(
                                    color: const Color(0xFF4AFF98)
                                        .withValues(alpha: 0.4),
                                    blurRadius: 8)]
                                : [],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            isOnline
                                ? 'Онлайн-витрина қосулы'
                                : 'Онлайн-витрина өшірулі',
                            style: manrope(14, FontWeight.w700,
                                color: Colors.white),
                          ),
                        ),
                        MSToggle(
                          on: isOnline,
                          onTap: store == null
                              ? null
                              : () => service.saveStore(
                                  store.copyWith(isPublished: !isOnline)),
                        ),
                      ]),
                    ),
                  ]),
                ),
              ),
            ),

            // ── Body ───────────────────────────────────────────────────
            Expanded(
              child: StreamBuilder<List<StoreDiscountModel>>(
                stream: repo.watchDiscounts(),
                builder: (context, dSnap) {
                  final disc =
                      (dSnap.data ?? []).where((d) => d.isActive).length;
                  // Нақты бар (жабылмаған) қоймалар ғана есептеледі.
                  final warehouses = context.watch<WarehouseContext>().all;
                  final existingIds = warehouses.map((w) => w.id).toSet();
                  final whTotal = warehouses.length;
                  final whVisible = (store?.visibleWarehouseIds ?? const [])
                      .where(existingIds.contains)
                      .length;

                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (store != null && store.isBlocked) ...[
                          Container(
                            padding: const EdgeInsets.all(13),
                            decoration: BoxDecoration(
                              color: cRedTint,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Row(children: [
                              const Icon(Icons.lock_outline_rounded,
                                  color: cRed, size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Магазин заблокирован',
                                        style: manrope(13.5, FontWeight.w800,
                                            color: const Color(0xFFB11A2B))),
                                    if (store.blockReason.isNotEmpty)
                                      Text(store.blockReason,
                                          style: manrope(12, FontWeight.w500,
                                              color: cInk2, height: 1.35)),
                                  ],
                                ),
                              ),
                            ]),
                          ),
                          const SizedBox(height: 16),
                        ],
                        // Quick stats
                        Row(children: [
                          _HubStat(icon: Icons.percent_rounded, val: '$disc', lbl: 'Акция', tone: 'red'),
                          const SizedBox(width: 10),
                          _HubStat(icon: Icons.warehouse_outlined, val: '$whTotal', lbl: 'Қойма', tone: 'green'),
                          const SizedBox(width: 10),
                          _HubStat(icon: Icons.language_rounded, val: isOnline ? 'ON' : 'OFF', lbl: 'Витрина', tone: 'blue'),
                        ]),
                        const SizedBox(height: 20),

                        QSecLabel('Акциялар'),
                        const SizedBox(height: 8),
                        QMenuItem(
                          icon: Icons.percent_rounded, tone: 'red',
                          title: 'Скидки на товары',
                          subtitle: disc > 0 ? '$disc активных' : 'Нет активных скидок',
                          onTap: () => Navigator.push(context,
                              MaterialPageRoute(builder: (_) => const AdminMyStoreDiscountsScreen())),
                        ),
                        const SizedBox(height: 10),
                        QMenuItem(
                          icon: Icons.local_activity_outlined, tone: 'purple',
                          title: 'Промокоды',
                          subtitle: 'Коды со скидкой для клиентов',
                          onTap: () => Navigator.push(context,
                              MaterialPageRoute(builder: (_) => const PromosScreen())),
                        ),
                        const SizedBox(height: 20),

                        QSecLabel('Магазин'),
                        const SizedBox(height: 8),
                        QMenuItem(
                          icon: Icons.warehouse_outlined, tone: 'green',
                          title: 'Витрина қоймалары',
                          subtitle: whVisible > 0
                              ? '$whVisible / $whTotal қойма көрсетілген'
                              : 'Қойма таңдалмаған',
                          onTap: () => Navigator.push(context,
                              MaterialPageRoute(builder: (_) => const AdminStoreVisibilityScreen())),
                        ),
                        const SizedBox(height: 10),
                        QMenuItem(
                          icon: Icons.storefront_rounded, tone: 'blue',
                          title: 'Данные магазина',
                          subtitle: 'Реквизиты и владелец',
                          onTap: () => Navigator.push(context,
                              MaterialPageRoute(builder: (_) => const StoreDataScreen())),
                        ),
                        const SizedBox(height: 32),
                      ],
                    ),
                  );
                },
              ),
            ),
          ]);
        },
      ),
    );
  }
}

// ── _HubStat ───────────────────────────────────────────────────────────────────
class _HubStat extends StatelessWidget {
  final IconData icon;
  final String val, lbl, tone;
  const _HubStat({required this.icon, required this.val, required this.lbl, required this.tone});

  Color get _bg => {'red': cRedTint, 'purple': cPurpleTint, 'blue': cBlueTint, 'green': cGreenTint}[tone] ?? cGreenTint;
  Color get _fg => {'red': cRed, 'purple': cPurple, 'blue': cBlue, 'green': cGreen}[tone] ?? cGreen;

  @override
  Widget build(BuildContext context) => Expanded(
        child: QCard(
          padding: const EdgeInsets.symmetric(vertical: 13),
          child: Column(children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(11)),
              child: Icon(icon, color: _fg, size: 17),
            ),
            const SizedBox(height: 8),
            Text(val, style: manrope(20, FontWeight.w800, color: cInk, letterSpacing: -0.3)),
            const SizedBox(height: 1),
            Text(lbl, style: manrope(11.5, FontWeight.w600, color: cInk3)),
          ]),
        ),
      );
}

