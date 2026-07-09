import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';
import '../../data/models/shop_request_model.dart';
import '../../data/models/store_edit_request_model.dart';
import '../../data/models/user_model.dart';
import '../../data/repositories/shop_request_repository.dart';
import '../../data/repositories/store_edit_repository.dart';
import '../../data/repositories/store_moderation_repository.dart';
import '../../data/services/auth_service.dart';
import '../../theme/qoima_design.dart';
import 'banners_screen.dart';
import 'marketplace_shops_screen.dart';
import 'reject_reason_sheet.dart';
import 'shop_owners_screen.dart';
import 'shop_request_detail_screen.dart';
import 'store_edit_requests_screen.dart';
import 'subscriptions_screen.dart';

import '../../core/lang.dart';
/// Superadmin (маркетплейс модераторы) басты экраны — дүкен заявкалары.
/// Корневой gate role=='superadmin' болғанда осыны home етіп көрсетеді.
class ShopRequestsScreen extends StatefulWidget {
  const ShopRequestsScreen({super.key});

  @override
  State<ShopRequestsScreen> createState() => _ShopRequestsScreenState();
}

class _ShopRequestsScreenState extends State<ShopRequestsScreen> {
  final _repo = ShopRequestRepository();
  // Тұрақты ағын — header badge-і outer StreamBuilder әр rebuild-те қайта
  // жазылмауы үшін бір рет құрылады.
  late final Stream<List<StoreEditRequestModel>> _editPending =
      StoreEditRepository().watchPending();
  // Жазылым badge-і — бітейін деп тұрған + асып кеткен иелер саны.
  late final Stream<List<UserModel>> _owners =
      StoreModerationRepository().watchOwners();
  int _tab = 0; // 0 Все · 1 Новые · 2 Одобренные · 3 Отклонённые

  String get _uid => Supabase.instance.client.auth.currentUser!.id;

  List<ShopRequestModel> _filter(List<ShopRequestModel> all) {
    switch (_tab) {
      case 1:
        return all.where((r) => r.isPending).toList();
      case 2:
        return all.where((r) => r.isApproved).toList();
      case 3:
        return all.where((r) => r.isRejected).toList();
      default:
        return all;
    }
  }

  Future<void> _approve(ShopRequestModel req) async {
    try {
      await _repo.approveRequest(requestId: req.id, reviewedBy: _uid);
      _snack(tr('Магазин «${req.shopName}» одобрен', '«${req.shopName}» дүкені мақұлданды'), cGreen);
    } catch (e) {
      _snack(e.toString(), cRed);
    }
  }

  Future<void> _reject(ShopRequestModel req) async {
    final note = await showRejectReasonSheet(
      context,
      title: tr('Отклонение заявки', 'Өтінімді қабылдамау'),
      subtitle: req.shopName,
    );
    if (note == null) return;
    try {
      await _repo.rejectRequest(
          requestId: req.id, reviewedBy: _uid, reviewNote: note);
      _snack(tr('Заявка отклонена', 'Өтінім қабылданбады'), cInk);
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

  Future<void> _signOut() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cSurface,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(tr('Выйти', 'Шығу'), style: manrope(16, FontWeight.w800, color: cInk)),
        content: Text(tr('Выйти из аккаунта?', 'Аккаунттан шығу керек пе?'),
            style: manrope(14, FontWeight.w500, color: cInk2)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Нет', 'Жоқ'),
                  style: manrope(14, FontWeight.w600, color: cInk2))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child:
                  Text(tr('Выйти', 'Шығу'), style: manrope(14, FontWeight.w700, color: cRed))),
        ],
      ),
    );
    if (ok == true) await AuthService().signOut();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cBg,
      body: StreamBuilder<List<ShopRequestModel>>(
        stream: _repo.watchAllRequests(),
        builder: (context, snap) {
          final all = snap.data ?? [];
          final pending = all.where((r) => r.isPending).length;
          final list = _filter(all);

          return Column(children: [
            QGradientHeader(
              title: tr('Заявки магазинов', 'Дүкен өтінімдері'),
              subtitle: tr('Управление маркетплейсом', 'Маркетплейсті басқару'),
              compact: true,
              action: _HeaderActions(
                editPending: _editPending,
                owners: _owners,
                onSignOut: _signOut,
              ),
              bottom: [
                const SizedBox(height: 14),
                SizedBox(
                  height: 34,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      _TabChip(
                          label: tr('Все (${all.length})', 'Барлығы (${all.length})'),
                          active: _tab == 0,
                          onTap: () => setState(() => _tab = 0)),
                      _TabChip(
                          label: tr('Новые ($pending)', 'Жаңа ($pending)'),
                          active: _tab == 1,
                          onTap: () => setState(() => _tab = 1)),
                      _TabChip(
                          label: tr('Одобренные', 'Мақұлданғандар'),
                          active: _tab == 2,
                          onTap: () => setState(() => _tab = 2)),
                      _TabChip(
                          label: tr('Отклонённые', 'Қабылданбағандар'),
                          active: _tab == 3,
                          onTap: () => setState(() => _tab = 3)),
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
                          itemBuilder: (_, i) => _RequestCard(
                            req: list[i],
                            onApprove: () => _approve(list[i]),
                            onReject: () => _reject(list[i]),
                            onOpen: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => ShopRequestDetailScreen(
                                        req: list[i]))),
                          ),
                        ),
            ),
          ]);
        },
      ),
    );
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
              child: const Icon(Icons.inbox_outlined, color: cGreen, size: 34),
            ),
            const SizedBox(height: 14),
            Text(tr('Нет заявок', 'Өтінім жоқ'),
                style: manrope(16, FontWeight.w700, color: cInk)),
            const SizedBox(height: 4),
            Text(tr('В этой категории пока пусто', 'Бұл санатта әзірге бос'),
                style: manrope(13, FontWeight.w500, color: cInk3)),
          ],
        ),
      );
}

// ── Header actions (маркетплейс + өзгерту запростары + баннер + шығу) ─────────────
class _HeaderActions extends StatelessWidget {
  final Stream<List<StoreEditRequestModel>> editPending;
  final Stream<List<UserModel>> owners;
  final VoidCallback onSignOut;
  const _HeaderActions(
      {required this.editPending,
      required this.owners,
      required this.onSignOut});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      StreamBuilder<List<UserModel>>(
        stream: owners,
        builder: (context, snap) {
          final list = snap.data ?? [];
          // Назар аударуды талап ететіндер: мерзімі жақын + асып кеткен.
          final urgent = list
              .where((o) => o.isExpiringSoon || o.isExpired)
              .length;
          return QHeaderBtn(Icons.card_membership_outlined,
              badge: urgent,
              onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const SubscriptionsScreen()),
                  ));
        },
      ),
      const SizedBox(width: 8),
      QHeaderBtn(Icons.manage_accounts_outlined,
          onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ShopOwnersScreen()),
              )),
      const SizedBox(width: 8),
      QHeaderBtn(Icons.storefront_outlined,
          onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const MarketplaceShopsScreen()),
              )),
      const SizedBox(width: 8),
      StreamBuilder<List<StoreEditRequestModel>>(
        stream: editPending,
        builder: (context, snap) {
          final count = snap.data?.length ?? 0;
          return QHeaderBtn(Icons.edit_note_rounded,
              badge: count,
              onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const StoreEditRequestsScreen()),
                  ));
        },
      ),
      const SizedBox(width: 8),
      QHeaderBtn(Icons.photo_library_outlined,
          onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const BannersScreen()),
              )),
      const SizedBox(width: 8),
      QHeaderBtn(Icons.logout_rounded, onTap: onSignOut),
    ]);
  }
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

// ── Request card ────────────────────────────────────────────────────────────────
class _RequestCard extends StatelessWidget {
  final ShopRequestModel req;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onOpen;

  const _RequestCard({
    required this.req,
    required this.onApprove,
    required this.onReject,
    required this.onOpen,
  });

  ({String tone, String label}) get _statusPill {
    if (req.isApproved) return (tone: 'green', label: tr('Одобрено', 'Мақұлданды'));
    if (req.isRejected) return (tone: 'red', label: tr('Отклонено', 'Қабылданбады'));
    return (tone: 'amber', label: tr('Новая', 'Жаңа'));
  }

  @override
  Widget build(BuildContext context) {
    final pill = _statusPill;
    final tone =
        req.isApproved ? 'green' : (req.isRejected ? 'red' : 'amber');
    final iconColor =
        req.isApproved ? cGreen : (req.isRejected ? cRed : cAmber);

    return GestureDetector(
      onTap: onOpen,
      child: Container(
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
                icon: Icon(Icons.store_outlined, color: iconColor, size: 20),
                tone: tone,
                size: 44,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(req.shopName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: manrope(14.5, FontWeight.w800, color: cInk)),
                    const SizedBox(height: 2),
                    Text(
                        '${trValue(req.category)}${req.city.isNotEmpty ? ' · ${trValue(req.city)}' : ''}',
                        style:
                            manrope(12.5, FontWeight.w500, color: cInk3)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  QPill(pill.label, tone: pill.tone),
                  const SizedBox(height: 4),
                  Text(_fmtDate(req.createdAt),
                      style: manrope(11, FontWeight.w500, color: cInk3)),
                ],
              ),
            ]),
          ),
          if (req.isPending) ...[
            Container(height: 1, color: cLine),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 9),
              child: Row(children: [
                Expanded(
                  child: _SmallBtn(
                    label: tr('Одобрить', 'Мақұлдау'),
                    bg: cGreenTint,
                    fg: cGreenDeep,
                    onTap: onApprove,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _SmallBtn(
                    label: tr('Отклонить', 'Қабылдамау'),
                    bg: cRedTint,
                    fg: cRed,
                    onTap: onReject,
                  ),
                ),
                const SizedBox(width: 8),
                _SmallBtn(
                  label: tr('Детали', 'Егжей-тегжей'),
                  bg: cBg,
                  fg: cInk2,
                  onTap: onOpen,
                ),
              ]),
            ),
          ],
        ]),
      ),
    );
  }
}

class _SmallBtn extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;
  final VoidCallback onTap;
  const _SmallBtn(
      {required this.label,
      required this.bg,
      required this.fg,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(11)),
        child: Center(
          child: Text(label,
              style: manrope(13, FontWeight.w700, color: fg)),
        ),
      ),
    );
  }
}

String _two(int v) => v.toString().padLeft(2, '0');
String _fmtDate(DateTime d) => '${_two(d.day)}.${_two(d.month)}.${d.year}';
