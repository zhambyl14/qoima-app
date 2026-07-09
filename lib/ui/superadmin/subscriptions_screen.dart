import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';
import '../../data/models/store_model.dart';
import '../../data/models/user_model.dart';
import '../../data/repositories/store_moderation_repository.dart';
import '../../theme/qoima_design.dart';
import 'owner_products_screen.dart';

import '../../core/lang.dart';

/// Superadmin (модератор) — дүкен иелерінің жазылым (подписка) мониторингі.
/// Тіркелген уақыт, доступ мерзімі, «бітейін деп тұр» / «асып кеткен» статусы;
/// ұзарту (+1/+3/+6/+12 ай немесе нақты күн), товарларды көру, блоктау.
class SubscriptionsScreen extends StatefulWidget {
  const SubscriptionsScreen({super.key});

  @override
  State<SubscriptionsScreen> createState() => _SubscriptionsScreenState();
}

class _SubscriptionsScreenState extends State<SubscriptionsScreen> {
  final _repo = StoreModerationRepository();
  int _tab = 0; // 0 Все · 1 Истекают · 2 Просрочены · 3 Без подписки

  // Сұрыптау рангісі: асып кеткен → бітейін деп тұр → белсенді → жазылымсыз.
  int _rank(UserModel o) {
    if (!o.hasSubscription) return 3;
    if (o.isExpired) return 0;
    if (o.isExpiringSoon) return 1;
    return 2;
  }

  List<UserModel> _sorted(List<UserModel> owners) {
    final list = [...owners];
    list.sort((a, b) {
      final ra = _rank(a), rb = _rank(b);
      if (ra != rb) return ra.compareTo(rb);
      // Бір ранг ішінде — мерзімі жақынырақ (аз күн қалған) жоғарыда.
      final da = a.daysLeft, db = b.daysLeft;
      if (da != null && db != null && da != db) return da.compareTo(db);
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return list;
  }

  List<UserModel> _filter(List<UserModel> owners) {
    switch (_tab) {
      case 1:
        return owners.where((o) => o.isExpiringSoon).toList();
      case 2:
        return owners.where((o) => o.isExpired).toList();
      case 3:
        return owners.where((o) => !o.hasSubscription).toList();
      default:
        return owners;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cBg,
      body: StreamBuilder<List<UserModel>>(
        stream: _repo.watchOwners(),
        builder: (context, ownersSnap) {
          final owners = _sorted(ownersSnap.data ?? []);
          final expiring = owners.where((o) => o.isExpiringSoon).length;
          final expired = owners.where((o) => o.isExpired).length;
          final noSub = owners.where((o) => !o.hasSubscription).length;
          final list = _filter(owners);

          return StreamBuilder<List<StoreModel>>(
            stream: _repo.watchAllShops(),
            builder: (context, shopsSnap) {
              final storeByOwner = {
                for (final s in shopsSnap.data ?? <StoreModel>[])
                  s.adminUid: s,
              };

              return Column(children: [
                QGradientHeader(
                  title: tr('Подписки', 'Жазылымдар'),
                  subtitle: tr('Доступ владельцев магазинов',
                      'Дүкен иелерінің доступы'),
                  compact: true,
                  showBack: true,
                  bottom: [
                    const SizedBox(height: 12),
                    Row(children: [
                      _StatChip(
                          icon: Icons.warning_amber_rounded,
                          label: tr('Истекает', 'Бітеді'),
                          count: expiring,
                          tone: 'amber'),
                      const SizedBox(width: 8),
                      _StatChip(
                          icon: Icons.error_outline_rounded,
                          label: tr('Просрочено', 'Асып кетті'),
                          count: expired,
                          tone: 'red'),
                    ]),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 34,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          _TabChip(
                              label: tr('Все (${owners.length})',
                                  'Барлығы (${owners.length})'),
                              active: _tab == 0,
                              onTap: () => setState(() => _tab = 0)),
                          _TabChip(
                              label: tr('Истекают ($expiring)',
                                  'Бітейін деп тұр ($expiring)'),
                              active: _tab == 1,
                              onTap: () => setState(() => _tab = 1)),
                          _TabChip(
                              label: tr('Просрочены ($expired)',
                                  'Асып кеткен ($expired)'),
                              active: _tab == 2,
                              onTap: () => setState(() => _tab = 2)),
                          _TabChip(
                              label: tr('Без подписки ($noSub)',
                                  'Жазылымсыз ($noSub)'),
                              active: _tab == 3,
                              onTap: () => setState(() => _tab = 3)),
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
                              itemBuilder: (_, i) => _OwnerSubRow(
                                owner: list[i],
                                store: storeByOwner[list[i].uid],
                                onExtend: () => _showExtendSheet(list[i]),
                                onProducts: () => _openProducts(
                                    list[i], storeByOwner[list[i].uid]),
                                onBlock: () => _showBlockSheet(list[i]),
                                onUnblock: () => _unblock(list[i]),
                                onClear: () => _clear(list[i]),
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

  void _openProducts(UserModel owner, StoreModel? store) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OwnerProductsScreen(
          ownerUid: owner.uid,
          ownerName: owner.name,
          storeName: store?.storeName ?? '',
        ),
      ),
    );
  }

  Future<void> _showExtendSheet(UserModel owner) async {
    final result = await showModalBottomSheet<_ExtendResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ExtendSheet(owner: owner),
    );
    if (result == null) return;
    try {
      if (result.customDate != null) {
        await _repo.setSubscriptionUntil(
            ownerUid: owner.uid, until: result.customDate!);
      } else {
        await _repo.grantSubscription(
          ownerUid: owner.uid,
          months: result.months!,
          currentUntil: owner.subscriptionUntil,
        );
      }
      _snack(tr('Подписка обновлена', 'Жазылым жаңартылды'), cGreen);
    } catch (e) {
      _snack(e.toString(), cRed);
    }
  }

  Future<void> _clear(UserModel owner) async {
    final ok = await _confirm(
        tr('Сбросить подписку?', 'Жазылымды тазалау?'),
        tr('Доступ «${owner.name}» станет «без подписки».',
            '«${owner.name}» доступы «жазылымсыз» болады.'));
    if (ok != true) return;
    try {
      await _repo.clearSubscription(owner.uid);
      _snack(tr('Подписка сброшена', 'Жазылым тазаланды'), cInk);
    } catch (e) {
      _snack(e.toString(), cRed);
    }
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
      builder: (_) => _BlockReasonSheet(owner: owner),
    );
    if (reason == null || reason.trim().isEmpty) return;
    try {
      await _repo.blockOwner(
        ownerUid: owner.uid,
        reason: reason.trim(),
        blockedBy: Supabase.instance.client.auth.currentUser!.id,
      );
      _snack(tr('«${owner.name}» заблокирован', '«${owner.name}» блокталды'),
          cInk);
    } catch (e) {
      _snack(e.toString(), cRed);
    }
  }

  Future<bool?> _confirm(String title, String body) => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: cSurface,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Text(title, style: manrope(16, FontWeight.w800, color: cInk)),
          content:
              Text(body, style: manrope(14, FontWeight.w500, color: cInk2)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(tr('Отмена', 'Болдырмау'),
                    style: manrope(14, FontWeight.w600, color: cInk2))),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(tr('Да', 'Иә'),
                    style: manrope(14, FontWeight.w700, color: cRed))),
          ],
        ),
      );

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
              child: const Icon(Icons.card_membership_outlined,
                  color: cGreen, size: 34),
            ),
            const SizedBox(height: 14),
            Text(tr('Пусто', 'Бос'),
                style: manrope(16, FontWeight.w700, color: cInk)),
          ],
        ),
      );
}

// ── Stat chip (header summary) ───────────────────────────────────────────────
class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;
  final String tone;
  const _StatChip(
      {required this.icon,
      required this.label,
      required this.count,
      required this.tone});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        ),
        child: Row(children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label,
                style: manrope(12.5, FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.9))),
          ),
          Text('$count',
              style: manrope(16, FontWeight.w800, color: Colors.white)),
        ]),
      ),
    );
  }
}

// ── Tab chip ─────────────────────────────────────────────────────────────────
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

// ── Owner subscription row ───────────────────────────────────────────────────
class _OwnerSubRow extends StatelessWidget {
  final UserModel owner;
  final StoreModel? store;
  final VoidCallback onExtend;
  final VoidCallback onProducts;
  final VoidCallback onBlock;
  final VoidCallback onUnblock;
  final VoidCallback onClear;
  const _OwnerSubRow({
    required this.owner,
    required this.store,
    required this.onExtend,
    required this.onProducts,
    required this.onBlock,
    required this.onUnblock,
    required this.onClear,
  });

  ({String tone, String label}) get _statusPill {
    if (owner.blocked) return (tone: 'red', label: tr('Блок', 'Блок'));
    if (!owner.hasSubscription) {
      return (tone: 'ink', label: tr('Нет подписки', 'Жазылымсыз'));
    }
    final d = owner.daysLeft ?? 0;
    if (owner.isExpired) {
      return (
        tone: 'red',
        label: tr('Просрочено ${-d} дн', '${-d} күн асты')
      );
    }
    if (owner.isExpiringSoon) {
      return (tone: 'amber', label: tr('Осталось $d дн', '$d күн қалды'));
    }
    return (tone: 'green', label: tr('Активна $d дн', 'Белсенді $d күн'));
  }

  @override
  Widget build(BuildContext context) {
    final pill = _statusPill;
    final storeName = store?.storeName.trim() ?? '';
    final blocked = owner.blocked;
    final until = owner.subscriptionUntil;

    return Container(
      decoration: BoxDecoration(
        color: cSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: owner.isExpired && !blocked ? cRed : cLine,
            width: owner.isExpired && !blocked ? 1.4 : 1),
        boxShadow: kShadowSm,
      ),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.all(13),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
                      style: manrope(14.5, FontWeight.w800, color: cInk)),
                  if (storeName.isNotEmpty)
                    Text('«$storeName»',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: manrope(12, FontWeight.w500, color: cInk3)),
                  const SizedBox(height: 6),
                  _InfoLine(
                    icon: Icons.event_available_rounded,
                    text: owner.createdAt != null
                        ? tr('Регистрация: ${_fmtDate(owner.createdAt!)}',
                            'Тіркелген: ${_fmtDate(owner.createdAt!)}')
                        : tr('Дата регистрации неизвестна',
                            'Тіркелген күні белгісіз'),
                  ),
                  const SizedBox(height: 3),
                  _InfoLine(
                    icon: Icons.schedule_rounded,
                    color: owner.isExpired
                        ? cRed
                        : (owner.isExpiringSoon ? cAmber : cInk3),
                    text: until != null
                        ? tr('Доступ до: ${_fmtDate(until)}',
                            'Доступ дейін: ${_fmtDate(until)}')
                        : tr('Подписка не выдана', 'Жазылым берілмеген'),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            QPill(pill.label, tone: pill.tone),
          ]),
        ),
        Container(height: 1, color: cLine),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 9),
          child: Row(children: [
            Expanded(
              child: _ActionBtn(
                label: tr('Продлить', 'Ұзарту'),
                bg: cGreenTint,
                fg: cGreenDeep,
                icon: Icons.add_rounded,
                onTap: onExtend,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ActionBtn(
                label: tr('Товары', 'Товарлар'),
                bg: cBg,
                fg: cInk2,
                icon: Icons.inventory_2_outlined,
                onTap: onProducts,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ActionBtn(
                label:
                    blocked ? tr('Разблок', 'Блоктан алу') : tr('Блок', 'Блок'),
                bg: blocked ? cGreenTint : cRedTint,
                fg: blocked ? cGreenDeep : cRed,
                icon: blocked
                    ? Icons.lock_open_rounded
                    : Icons.lock_outline_rounded,
                onTap: blocked ? onUnblock : onBlock,
              ),
            ),
            if (owner.hasSubscription) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onClear,
                child: Container(
                  height: 40,
                  width: 40,
                  decoration: BoxDecoration(
                      color: cBg, borderRadius: BorderRadius.circular(11)),
                  child: const Icon(Icons.restart_alt_rounded,
                      color: cInk3, size: 18),
                ),
              ),
            ],
          ]),
        ),
      ]),
    );
  }
}

class _InfoLine extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? color;
  const _InfoLine({required this.icon, required this.text, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? cInk3;
    return Row(children: [
      Icon(icon, size: 13, color: c),
      const SizedBox(width: 5),
      Expanded(
        child: Text(text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: manrope(11.5, FontWeight.w600, color: c)),
      ),
    ]);
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
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(11)),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: fg, size: 16),
          const SizedBox(width: 6),
          Flexible(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: manrope(13, FontWeight.w700, color: fg)),
          ),
        ]),
      ),
    );
  }
}

// ── Extend result ────────────────────────────────────────────────────────────
class _ExtendResult {
  final int? months;
  final DateTime? customDate;
  const _ExtendResult({this.months, this.customDate});
}

// ── Extend sheet (+1/+3/+6/+12 ай немесе нақты күн) ──────────────────────────
class _ExtendSheet extends StatelessWidget {
  final UserModel owner;
  const _ExtendSheet({required this.owner});

  static const _presets = [1, 3, 6, 12];

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    final until = owner.subscriptionUntil;
    final active = until != null && until.isAfter(DateTime.now());

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
                    color: cGreenTint, shape: BoxShape.circle),
                child: const Icon(Icons.card_membership_rounded,
                    color: cGreen, size: 26),
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: Text(tr('Продлить доступ', 'Доступты ұзарту'),
                  style: manrope(17, FontWeight.w800, color: cInk)),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text(
                  active
                      ? tr('Сейчас до ${_fmtDate(until)} — продление добавится к сроку',
                          'Қазір ${_fmtDate(until)} дейін — ұзарту мерзімге қосылады')
                      : tr('Отсчёт начнётся с сегодня',
                          'Есеп бүгіннен басталады'),
                  textAlign: TextAlign.center,
                  style: manrope(12.5, FontWeight.w500, color: cInk2)),
            ),
            const SizedBox(height: 18),
            QSecLabel(tr('Выберите срок', 'Мерзімді таңдаңыз')),
            const SizedBox(height: 8),
            Row(
              children: _presets.map((m) {
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: m == _presets.last ? 0 : 8),
                    child: GestureDetector(
                      onTap: () => Navigator.pop(
                          context, _ExtendResult(months: m)),
                      child: Container(
                        height: 64,
                        decoration: BoxDecoration(
                          color: cGreenTint,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: cGreen.withValues(alpha: 0.3)),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('+$m',
                                style: manrope(20, FontWeight.w800,
                                    color: cGreenDeep)),
                            Text(tr('мес', 'ай'),
                                style: manrope(11, FontWeight.w600,
                                    color: cGreenDeep)),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 14),
            GestureDetector(
              onTap: () async {
                final now = DateTime.now();
                final picked = await showDatePicker(
                  context: context,
                  initialDate: active ? until : now.add(const Duration(days: 30)),
                  firstDate: now,
                  lastDate: DateTime(now.year + 5),
                );
                if (picked != null && context.mounted) {
                  Navigator.pop(context, _ExtendResult(customDate: picked));
                }
              },
              child: Container(
                height: 52,
                decoration: BoxDecoration(
                  color: cBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: cLine),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.calendar_month_rounded,
                        color: cInk2, size: 19),
                    const SizedBox(width: 8),
                    Text(tr('Выбрать точную дату', 'Нақты күнді таңдау'),
                        style: manrope(14, FontWeight.w700, color: cInk2)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ── Block reason sheet ───────────────────────────────────────────────────────
const _blockReasons = [
  'Подписка истекла · не оплачено',
  'Продажа поддельных товаров',
  'Запрещённый товар',
  'Нарушение закона · решение суда',
  'Повторные жалобы (3+)',
];

class _BlockReasonSheet extends StatefulWidget {
  final UserModel owner;
  const _BlockReasonSheet({required this.owner});

  @override
  State<_BlockReasonSheet> createState() => _BlockReasonSheetState();
}

class _BlockReasonSheetState extends State<_BlockReasonSheet> {
  int _selected = -1;
  final _customCtrl = TextEditingController();

  bool get _isCustom => _selected == _blockReasons.length;
  String get _reason => _isCustom
      ? _customCtrl.text.trim()
      : (_selected >= 0 ? _blockReasons[_selected] : '');

  @override
  void initState() {
    super.initState();
    // Мерзімі асып кеткен болса — «подписка истекла» әдепкі таңдаулы.
    if (widget.owner.isExpired) _selected = 0;
  }

  @override
  void dispose() {
    _customCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom +
        MediaQuery.of(context).padding.bottom;
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
              child: Text(tr('Заблокировать владельца', 'Иесін блоктау'),
                  style: manrope(17, FontWeight.w800, color: cInk)),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text(
                  tr('«${widget.owner.name}» и его продавцы потеряют доступ',
                      '«${widget.owner.name}» мен оның сатушылары доступты жоғалтады'),
                  textAlign: TextAlign.center,
                  style: manrope(12.5, FontWeight.w500, color: cInk2)),
            ),
            const SizedBox(height: 18),
            QSecLabel(tr('Причина', 'Себеп')),
            const SizedBox(height: 8),
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
                      border: Border.all(color: sel ? cRed : cLine, width: 1.5),
                    ),
                    child: Row(children: [
                      Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: sel ? cRed : cInk3, width: 2),
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
                            style: manrope(13.5,
                                sel ? FontWeight.w700 : FontWeight.w600,
                                color:
                                    sel ? const Color(0xFFB11A2B) : cInk2)),
                      ),
                    ]),
                  ),
                ),
              );
            }),
            if (_isCustom) ...[
              const SizedBox(height: 2),
              TextField(
                controller: _customCtrl,
                maxLines: 2,
                onChanged: (_) => setState(() {}),
                style: manrope(14, FontWeight.w600, color: cInk),
                decoration: InputDecoration(
                  hintText: tr('Опишите причину', 'Себебін сипаттаңыз'),
                  hintStyle: manrope(13.5, FontWeight.w500, color: cInk3),
                  filled: true,
                  fillColor: cBg,
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(13),
                      borderSide: const BorderSide(color: cLine)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(13),
                      borderSide: const BorderSide(color: cRed, width: 1.5)),
                ),
              ),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed:
                    canSubmit ? () => Navigator.pop(context, _reason) : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: cRed,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: cRed.withValues(alpha: 0.4),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15)),
                ),
                child: Text(tr('Подтвердить блокировку', 'Блоктауды растау'),
                    style: manrope(15, FontWeight.w700, color: Colors.white)),
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

String _two(int v) => v.toString().padLeft(2, '0');
String _fmtDate(DateTime d) => '${_two(d.day)}.${_two(d.month)}.${d.year}';
