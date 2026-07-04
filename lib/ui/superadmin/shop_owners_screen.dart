import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';
import '../../data/models/store_model.dart';
import '../../data/models/user_model.dart';
import '../../data/repositories/store_moderation_repository.dart';
import '../../theme/qoima_design.dart';

import '../../core/lang.dart';
/// Superadmin — дүкен иелерін басқару: ЖАЛПЫ блок (офлайн + онлайн).
/// Блокталған иесі мен оның сатушылары ешқандай әрекет жасай алмайды
/// (gate → BlockedScreen); сатушы иесінен босап шыға алады.
class ShopOwnersScreen extends StatefulWidget {
  const ShopOwnersScreen({super.key});

  @override
  State<ShopOwnersScreen> createState() => _ShopOwnersScreenState();
}

class _ShopOwnersScreenState extends State<ShopOwnersScreen> {
  final _repo = StoreModerationRepository();
  int _tab = 0; // 0 Активные · 1 Заблокированные

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cBg,
      body: StreamBuilder<List<UserModel>>(
        stream: _repo.watchOwners(),
        builder: (context, ownersSnap) {
          final owners = ownersSnap.data ?? [];
          final active = owners.where((o) => !o.blocked).length;
          final blocked = owners.where((o) => o.blocked).length;
          final list = (_tab == 1
                  ? owners.where((o) => o.blocked)
                  : owners.where((o) => !o.blocked))
              .toList();

          return StreamBuilder<List<StoreModel>>(
            stream: _repo.watchAllShops(),
            builder: (context, shopsSnap) {
              final storeByOwner = {
                for (final s in shopsSnap.data ?? <StoreModel>[])
                  s.adminUid: s,
              };

              return Column(children: [
                QGradientHeader(
                  title: tr('Владельцы магазинов', 'Дүкен иелері'),
                  subtitle: tr('Всего ${owners.length}', 'Барлығы ${owners.length}'),
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
                              label: tr('Активные ($active)', 'Белсенді ($active)'),
                              active: _tab == 0,
                              onTap: () => setState(() => _tab = 0)),
                          _TabChip(
                              label: tr('Заблокированные ($blocked)', 'Блокталғандар ($blocked)'),
                              active: _tab == 1,
                              onTap: () => setState(() => _tab = 1)),
                        ],
                      ),
                    ),
                  ],
                ),
                Expanded(
                  child: ownersSnap.connectionState == ConnectionState.waiting
                      ? const Center(
                          child: CircularProgressIndicator(
                              color: cGreen, strokeWidth: 2))
                      : list.isEmpty
                          ? _empty()
                          : ListView.separated(
                              padding:
                                  const EdgeInsets.fromLTRB(18, 16, 18, 28),
                              itemCount: list.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (_, i) => _OwnerRow(
                                owner: list[i],
                                store: storeByOwner[list[i].uid],
                                onBlock: () => _showBlockSheet(list[i]),
                                onUnblock: () => _unblock(list[i]),
                              ),
                            ),
                ),
              ]);
            },
          );
        },
      ),
    );
  }

  Future<void> _unblock(UserModel owner) async {
    try {
      await _repo.unblockOwner(owner.uid);
      _snack(tr('Владелец разблокирован', 'Иесі блоктан шығарылды'), cGreen);
    } catch (e) {
      _snack(e.toString(), cRed);
    }
  }

  Future<void> _showBlockSheet(UserModel owner) async {
    final reason = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BlockOwnerSheet(owner: owner),
    );
    if (reason == null || reason.trim().isEmpty) return;
    try {
      await _repo.blockOwner(
        ownerUid: owner.uid,
        reason: reason.trim(),
        blockedBy: Supabase.instance.client.auth.currentUser!.id,
      );
      _snack(tr('Владелец «${owner.name}» заблокирован', '«${owner.name}» иесі блокталды'), cInk);
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
              child: const Icon(Icons.person_outline_rounded,
                  color: cGreen, size: 34),
            ),
            const SizedBox(height: 14),
            Text(tr('Нет владельцев', 'Иелер жоқ'),
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

// ── Owner row ────────────────────────────────────────────────────────────────────
class _OwnerRow extends StatelessWidget {
  final UserModel owner;
  final StoreModel? store;
  final VoidCallback onBlock;
  final VoidCallback onUnblock;
  const _OwnerRow(
      {required this.owner,
      required this.store,
      required this.onBlock,
      required this.onUnblock});

  @override
  Widget build(BuildContext context) {
    final blocked = owner.blocked;
    final storeName = store?.storeName.trim() ?? '';
    final sub = [
      if (owner.email.isNotEmpty) owner.email,
      if (storeName.isNotEmpty) '«$storeName»',
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
                  blocked ? Icons.lock_rounded : Icons.person_rounded,
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
                  Text(owner.name.isNotEmpty ? owner.name : tr('Без имени', 'Атаусыз'),
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
                        style: manrope(12, FontWeight.w500, color: cInk3)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            QPill(blocked ? 'Блок' : tr('Активен', 'Белсенді'),
                tone: blocked ? 'red' : 'green'),
          ]),
        ),
        if (blocked && owner.blockReason.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(13, 0, 13, 10),
            child: Row(children: [
              const Icon(Icons.info_outline_rounded, color: cRed, size: 15),
              const SizedBox(width: 6),
              Expanded(
                child: Text(owner.blockReason,
                    style: manrope(11.5, FontWeight.w500, color: cInk2)),
              ),
            ]),
          ),
        Container(height: 1, color: cLine),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 9),
          child: blocked
              ? _ActionBtn(
                  label: tr('Разблокировать', 'Блоктан шығару'),
                  bg: cGreenTint,
                  fg: cGreenDeep,
                  icon: Icons.lock_open_rounded,
                  onTap: onUnblock,
                )
              : _ActionBtn(
                  label: tr('Заблокировать полностью', 'Толық блоктау'),
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

// ── Block owner sheet (себеп таңдау немесе өз мәтіні) ──────────────────────────
const _blockReasons = [
  'Продажа поддельных товаров',
  'Обман покупателей',
  'Запрещённый товар',
  'Нарушение закона · решение суда',
  'Повторные жалобы (3+)',
];

class _BlockOwnerSheet extends StatefulWidget {
  final UserModel owner;
  const _BlockOwnerSheet({required this.owner});

  @override
  State<_BlockOwnerSheet> createState() => _BlockOwnerSheetState();
}

class _BlockOwnerSheetState extends State<_BlockOwnerSheet> {
  int _selected = -1; // -1 ештеңе · _blockReasons.length = «Другая причина»
  final _customCtrl = TextEditingController();

  bool get _isCustom => _selected == _blockReasons.length;

  String get _reason =>
      _isCustom ? _customCtrl.text.trim() : (_selected >= 0 ? _blockReasons[_selected] : '');

  @override
  void dispose() {
    _customCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom;
    final canSubmit = _reason.isNotEmpty;
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
              child: Text(tr('Заблокировать владельца', 'Иесін блоктау'),
                  style: manrope(17, FontWeight.w800, color: cInk)),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text(
                  '«${widget.owner.name}»: магазин будет скрыт, владелец и '
                  'его продавцы потеряют доступ ко всем действиям',
                  textAlign: TextAlign.center,
                  style: manrope(12.5, FontWeight.w500, color: cInk2)),
            ),
            const SizedBox(height: 18),
            QSecLabel(tr('Выберите причину', 'Себепті таңдаңыз')),
            ...List.generate(_blockReasons.length + 1, (i) {
              final sel = _selected == i;
              final label = i < _blockReasons.length
                  ? trValue(_blockReasons[i])
                  : tr('Другая причина', 'Басқа себеп');
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
                        child: Text(label,
                            style: manrope(
                                13.5, sel ? FontWeight.w700 : FontWeight.w600,
                                color: sel
                                    ? const Color(0xFFB11A2B)
                                    : cInk2)),
                      ),
                    ]),
                  ),
                ),
              );
            }),
            if (_isCustom) ...[
              const SizedBox(height: 4),
              TextField(
                controller: _customCtrl,
                maxLines: 2,
                onChanged: (_) => setState(() {}),
                style: manrope(14, FontWeight.w600, color: cInk),
                decoration: InputDecoration(
                  hintText: tr('Опишите причину блокировки', 'Блоктау себебін сипаттаңыз'),
                  hintStyle: manrope(13.5, FontWeight.w500, color: cInk3),
                  filled: true,
                  fillColor: cBg,
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(13),
                      borderSide: const BorderSide(color: cLine)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(13),
                      borderSide:
                          const BorderSide(color: cRed, width: 1.5)),
                ),
              ),
              const SizedBox(height: 8),
            ],
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
                      'Продавцы этого магазина тоже будут заблокированы, '
                      'но смогут открепиться и перейти к другому владельцу.',
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
                onPressed: canSubmit
                    ? () => Navigator.pop(context, _reason)
                    : null,
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
                    Text(tr('Подтвердить блокировку', 'Блоктауды растау'),
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
                child: Text(tr('Отмена', 'Болдырмау'),
                    style: manrope(14.5, FontWeight.w700, color: cInk2)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
