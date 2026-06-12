import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../data/models/store_model.dart';
import '../../data/repositories/store_moderation_repository.dart';
import '../../theme/qoima_design.dart';

/// Superadmin — маркетплейс дүкендерін басқару + блоктау (v10 §12).
class MarketplaceShopsScreen extends StatefulWidget {
  const MarketplaceShopsScreen({super.key});

  @override
  State<MarketplaceShopsScreen> createState() => _MarketplaceShopsScreenState();
}

class _MarketplaceShopsScreenState extends State<MarketplaceShopsScreen> {
  final _repo = StoreModerationRepository();
  int _tab = 0; // 0 Активные · 1 Заблокированные

  List<StoreModel> _filter(List<StoreModel> all) {
    // Дүкені бар (аты толтырылған) құжаттарды ғана көрсетеміз.
    final real = all.where((s) => s.storeName.trim().isNotEmpty).toList();
    return _tab == 1
        ? real.where((s) => s.isBlocked).toList()
        : real.where((s) => !s.isBlocked).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cBg,
      body: StreamBuilder<List<StoreModel>>(
        stream: _repo.watchAllShops(),
        builder: (context, snap) {
          final all = snap.data ?? [];
          final real =
              all.where((s) => s.storeName.trim().isNotEmpty).toList();
          final active = real.where((s) => !s.isBlocked).length;
          final blocked = real.where((s) => s.isBlocked).length;
          final list = _filter(all);

          return Column(children: [
            QGradientHeader(
              title: 'Магазины маркетплейса',
              subtitle: 'Всего ${real.length}',
              compact: true,
              showBack: true,
              bottom: [
                const SizedBox(height: 14),
                SizedBox(
                  height: 34,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      _TabChip(
                          label: 'Активные ($active)',
                          active: _tab == 0,
                          onTap: () => setState(() => _tab = 0)),
                      _TabChip(
                          label: 'Заблокированные ($blocked)',
                          active: _tab == 1,
                          onTap: () => setState(() => _tab = 1)),
                    ],
                  ),
                ),
              ],
            ),
            Expanded(
              child: snap.connectionState == ConnectionState.waiting
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: cGreen, strokeWidth: 2))
                  : list.isEmpty
                      ? _empty()
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
                          itemCount: list.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (_, i) => _ShopRow(
                            shop: list[i],
                            onBlock: () => _showBlockSheet(list[i]),
                            onUnblock: () => _unblock(list[i]),
                          ),
                        ),
            ),
          ]);
        },
      ),
    );
  }

  Future<void> _unblock(StoreModel shop) async {
    try {
      await _repo.unblockStore(shop.adminUid);
      _snack('Магазин разблокирован', cGreen);
    } catch (e) {
      _snack(e.toString(), cRed);
    }
  }

  Future<void> _showBlockSheet(StoreModel shop) async {
    final reason = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BlockSheet(shop: shop),
    );
    if (reason == null) return;
    try {
      await _repo.blockStore(
        ownerUid: shop.adminUid,
        reason: reason,
        blockedBy: FirebaseAuth.instance.currentUser!.uid,
      );
      _snack('Магазин «${shop.storeName}» заблокирован', cInk);
    } catch (e) {
      _snack(e.toString(), cRed);
    }
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
    ));
  }

  Widget _empty() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                  color: cGreenTint, shape: BoxShape.circle),
              child: const Icon(Icons.storefront_outlined,
                  color: cGreen, size: 34),
            ),
            const SizedBox(height: 14),
            Text('Нет магазинов',
                style: manrope(16, FontWeight.w700, color: cInk)),
          ],
        ),
      );
}

// ── Tab chip ───────────────────────────────────────────────────────────────────
class _TabChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _TabChip(
      {required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: active ? 0.22 : 0.10),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: Colors.white.withValues(alpha: active ? 0.4 : 0.15)),
        ),
        child: Center(
          child: Text(label,
              style: manrope(13, active ? FontWeight.w700 : FontWeight.w600,
                  color: Colors.white)),
        ),
      ),
    );
  }
}

// ── Shop row ─────────────────────────────────────────────────────────────────────
class _ShopRow extends StatelessWidget {
  final StoreModel shop;
  final VoidCallback onBlock;
  final VoidCallback onUnblock;
  const _ShopRow(
      {required this.shop, required this.onBlock, required this.onUnblock});

  @override
  Widget build(BuildContext context) {
    final blocked = shop.isBlocked;
    final sub = [
      if (shop.ownerName.isNotEmpty) shop.ownerName,
      if (shop.city.isNotEmpty) shop.city,
      if (shop.category.isNotEmpty) shop.category,
    ].join(' · ');

    return Container(
      decoration: BoxDecoration(
        color: cSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cLine),
        boxShadow: kShadowSm,
      ),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.all(13),
          child: Row(children: [
            QIconTile(
              icon: Icon(
                  blocked ? Icons.lock_rounded : Icons.storefront_rounded,
                  color: blocked ? cRed : cGreen,
                  size: 20),
              tone: blocked ? 'red' : 'green',
              size: 44,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(shop.storeName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: manrope(14.5, FontWeight.w800, color: cInk)
                          .copyWith(
                              decoration: blocked
                                  ? TextDecoration.lineThrough
                                  : null)),
                  if (sub.isNotEmpty)
                    Text(sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            manrope(12, FontWeight.w500, color: cInk3)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            QPill(blocked ? 'Блок' : 'Активен',
                tone: blocked ? 'red' : 'green'),
          ]),
        ),
        if (blocked && shop.blockReason.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(13, 0, 13, 10),
            child: Row(children: [
              const Icon(Icons.info_outline_rounded, color: cRed, size: 15),
              const SizedBox(width: 6),
              Expanded(
                child: Text(shop.blockReason,
                    style: manrope(11.5, FontWeight.w500, color: cInk2)),
              ),
            ]),
          ),
        Container(height: 1, color: cLine),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 9),
          child: blocked
              ? _ActionBtn(
                  label: 'Разблокировать',
                  bg: cGreenTint,
                  fg: cGreenDeep,
                  icon: Icons.lock_open_rounded,
                  onTap: onUnblock,
                )
              : _ActionBtn(
                  label: 'Заблокировать',
                  bg: cRedTint,
                  fg: cRed,
                  icon: Icons.lock_outline_rounded,
                  onTap: onBlock,
                ),
        ),
      ]),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final String label;
  final Color bg, fg;
  final IconData icon;
  final VoidCallback onTap;
  const _ActionBtn(
      {required this.label,
      required this.bg,
      required this.fg,
      required this.icon,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 40,
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(11)),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: fg, size: 17),
          const SizedBox(width: 7),
          Text(label, style: manrope(13.5, FontWeight.w700, color: fg)),
        ]),
      ),
    );
  }
}

// ── Block confirm sheet ──────────────────────────────────────────────────────────
const _blockReasons = [
  'Продажа поддельных товаров',
  'Обман покупателей',
  'Запрещённый товар',
  'Нарушение закона · решение суда',
  'Повторные жалобы (3+)',
];

class _BlockSheet extends StatefulWidget {
  final StoreModel shop;
  const _BlockSheet({required this.shop});

  @override
  State<_BlockSheet> createState() => _BlockSheetState();
}

class _BlockSheetState extends State<_BlockSheet> {
  int _selected = -1;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(18, 10, 18, 18 + bottom),
      decoration: const BoxDecoration(
        color: cSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                    color: cLine, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Center(
              child: Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(
                    color: cRedTint, shape: BoxShape.circle),
                child: const Icon(Icons.lock_outline_rounded,
                    color: cRed, size: 26),
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: Text('Заблокировать магазин',
                  style: manrope(17, FontWeight.w800, color: cInk)),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text(
                  '«${widget.shop.storeName}» будет скрыт с маркетплейса',
                  textAlign: TextAlign.center,
                  style: manrope(12.5, FontWeight.w500, color: cInk2)),
            ),
            const SizedBox(height: 18),
            const QSecLabel('Выберите причину'),
            ...List.generate(_blockReasons.length, (i) {
              final sel = _selected == i;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _selected = i),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 13, vertical: 12),
                    decoration: BoxDecoration(
                      color: sel ? cRedTint : cSurface,
                      borderRadius: BorderRadius.circular(13),
                      border:
                          Border.all(color: sel ? cRed : cLine, width: 1.5),
                    ),
                    child: Row(children: [
                      Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border:
                              Border.all(color: sel ? cRed : cInk3, width: 2),
                        ),
                        child: sel
                            ? Center(
                                child: Container(
                                  width: 10,
                                  height: 10,
                                  decoration: const BoxDecoration(
                                      color: cRed, shape: BoxShape.circle),
                                ),
                              )
                            : null,
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Text(_blockReasons[i],
                            style: manrope(13.5,
                                sel ? FontWeight.w700 : FontWeight.w600,
                                color: sel
                                    ? const Color(0xFFB11A2B)
                                    : cInk2)),
                      ),
                    ]),
                  ),
                ),
              );
            }),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cRedTint,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Row(children: [
                const Icon(Icons.gavel_rounded, color: cRed, size: 17),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                      'После блокировки владелец получит уведомление. '
                      'Действие записывается в журнал.',
                      style: manrope(11.5, FontWeight.w600,
                          color: const Color(0xFFB11A2B), height: 1.35)),
                ),
              ]),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _selected < 0
                    ? null
                    : () => Navigator.pop(context, _blockReasons[_selected]),
                style: ElevatedButton.styleFrom(
                  backgroundColor: cRed,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: cRed.withValues(alpha: 0.4),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.lock_rounded,
                        color: Colors.white, size: 19),
                    const SizedBox(width: 8),
                    Text('Подтвердить блокировку',
                        style:
                            manrope(15, FontWeight.w700, color: Colors.white)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  foregroundColor: cInk2,
                  side: const BorderSide(color: cLine),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15)),
                ),
                child: Text('Отмена',
                    style: manrope(14.5, FontWeight.w700, color: cInk2)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
