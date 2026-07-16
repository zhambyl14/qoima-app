import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/warehouse_context.dart';
import '../../../data/models/store_discount_model.dart';
import '../../../data/models/store_model.dart';
import '../../../data/repositories/my_store_repository.dart';
import '../../../data/services/firestore_service.dart';
import '../../../theme/qoima_design.dart';
import '../../client/store_public_screen.dart';
import '../promos/promos_screen.dart';
import 'admin_my_store_discounts_screen.dart';
import 'admin_reviews_screen.dart';
import 'admin_store_visibility_screen.dart';
import 'ms_widgets.dart';
import 'store_data_screen.dart';

import '../../../core/lang.dart';
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
              : tr('Мой магазин', 'Менің дүкенім');
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
                            Text(tr('Мой магазин', 'Менің дүкенім'),
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
                    _OnlineToggleRow(store: store),
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
                                    Text(tr('Магазин заблокирован', 'Дүкен блокталған'),
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
                          _HubStat(icon: Icons.warehouse_outlined, val: '$whTotal', lbl: tr('Склад', 'Қойма'), tone: 'green'),
                          const SizedBox(width: 10),
                          _HubStat(icon: Icons.language_rounded, val: isOnline ? 'ON' : 'OFF', lbl: 'Витрина', tone: 'blue'),
                        ]),
                        const SizedBox(height: 20),

                        QSecLabel(tr('Акции', 'Акциялар')),
                        const SizedBox(height: 8),
                        QMenuItem(
                          icon: Icons.percent_rounded, tone: 'red',
                          title: tr('Скидки на товары', 'Тауарларға жеңілдіктер'),
                          subtitle: disc > 0 ? tr('$disc активных', '$disc белсенді') : tr('Нет активных скидок', 'Белсенді жеңілдік жоқ'),
                          onTap: () => Navigator.push(context,
                              MaterialPageRoute(builder: (_) => const AdminMyStoreDiscountsScreen())),
                        ),
                        const SizedBox(height: 10),
                        QMenuItem(
                          icon: Icons.local_activity_outlined, tone: 'purple',
                          title: tr('Промокоды', 'Промокодтар'),
                          subtitle: tr('Коды со скидкой для клиентов', 'Клиенттерге жеңілдік кодтары'),
                          onTap: () => Navigator.push(context,
                              MaterialPageRoute(builder: (_) => const PromosScreen())),
                        ),
                        const SizedBox(height: 20),

                        QSecLabel(tr('Покупатели', 'Сатып алушылар')),
                        const SizedBox(height: 8),
                        QMenuItem(
                          icon: Icons.rate_review_outlined, tone: 'amber',
                          title: tr('Отзывы покупателей', 'Сатып алушы пікірлері'),
                          subtitle: tr('Читайте и отвечайте на отзывы', 'Пікірлерді оқып, жауап беріңіз'),
                          onTap: () => Navigator.push(context,
                              MaterialPageRoute(builder: (_) => const AdminReviewsScreen())),
                        ),
                        const SizedBox(height: 10),
                        QMenuItem(
                          icon: Icons.visibility_outlined, tone: 'blue',
                          title: tr('Витрина глазами клиента', 'Витрина клиент көзімен'),
                          subtitle: store == null
                              ? tr('Магазин ещё не создан', 'Дүкен әлі жасалмаған')
                              : tr('Как покупатели видят ваш каталог', 'Каталогыңыз клиентке қалай көрінеді'),
                          onTap: store == null
                              ? () {}
                              : () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) => StorePublicScreen(
                                          store: store, previewMode: true))),
                        ),
                        const SizedBox(height: 20),

                        QSecLabel(tr('Магазин', 'Дүкен')),
                        const SizedBox(height: 8),
                        QMenuItem(
                          icon: Icons.warehouse_outlined, tone: 'green',
                          title: tr('Склады витрины', 'Витрина қоймалары'),
                          subtitle: whVisible > 0
                              ? tr('$whVisible / $whTotal складов отображается', '$whVisible / $whTotal қойма көрсетілген')
                              : tr('Склад не выбран', 'Қойма таңдалмаған'),
                          onTap: () => Navigator.push(context,
                              MaterialPageRoute(builder: (_) => const AdminStoreVisibilityScreen())),
                        ),
                        const SizedBox(height: 10),
                        QMenuItem(
                          icon: Icons.storefront_rounded, tone: 'blue',
                          title: tr('Данные магазина', 'Дүкен деректері'),
                          subtitle: tr('Реквизиты и владелец', 'Реквизиттер мен иесі'),
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

// ── Online toggle — optimistic (realtime растауын күтпей бірден басады) ──────
class _OnlineToggleRow extends StatefulWidget {
  final StoreModel? store;
  const _OnlineToggleRow({required this.store});

  @override
  State<_OnlineToggleRow> createState() => _OnlineToggleRowState();
}

class _OnlineToggleRowState extends State<_OnlineToggleRow> {
  // null — сервер мәнін көрсетеміз; сақтау кезінде осы жерге тез арада
  // «болжамды» мәнді жазамыз, realtime растаса (didUpdateWidget) тазаланады.
  bool? _optimistic;
  bool _saving = false;

  @override
  void didUpdateWidget(_OnlineToggleRow old) {
    super.didUpdateWidget(old);
    if (widget.store?.isPublished != old.store?.isPublished) {
      _optimistic = null;
    }
  }

  Future<void> _toggle() async {
    final store = widget.store;
    if (store == null || _saving) return;
    final next = !(_optimistic ?? store.isPublished);
    HapticFeedback.selectionClick();
    setState(() {
      _optimistic = next;
      _saving = true;
    });
    try {
      await FirestoreService().saveStore(store.copyWith(isPublished: next));
    } catch (_) {
      if (!mounted) return;
      setState(() => _optimistic = !next); // сәтсіз — артқа қайтарамыз
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(tr(
            'Не удалось изменить статус витрины. Проверьте интернет.',
            'Витрина күйін өзгерту сәтсіз аяқталды. Интернетті тексеріңіз.')),
        backgroundColor: cRed,
      ));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isOnline = _optimistic ?? (widget.store?.isPublished ?? false);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
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
                    color: const Color(0xFF4AFF98).withValues(alpha: 0.4),
                    blurRadius: 8)]
                : [],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            isOnline
                ? tr('Онлайн-витрина включена', 'Онлайн-витрина қосулы')
                : tr('Онлайн-витрина выключена', 'Онлайн-витрина өшірулі'),
            style: manrope(14, FontWeight.w700, color: Colors.white),
          ),
        ),
        Opacity(
          opacity: _saving ? 0.5 : 1,
          child: MSToggle(
            on: isOnline,
            onTap: widget.store == null ? null : _toggle,
          ),
        ),
      ]),
    );
  }
}

