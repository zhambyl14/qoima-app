import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../data/models/shop_request_model.dart';
import '../../data/models/store_edit_request_model.dart';
import '../../data/repositories/shop_request_repository.dart';
import '../../data/repositories/store_edit_repository.dart';
import '../../data/services/auth_service.dart';
import '../../theme/qoima_design.dart';
import 'banners_screen.dart';
import 'marketplace_shops_screen.dart';
import 'reject_reason_sheet.dart';
import 'shop_request_detail_screen.dart';
import 'store_edit_requests_screen.dart';

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
  int _tab = 0; // 0 Все · 1 Новые · 2 Одобренные · 3 Отклонённые

  String get _uid => FirebaseAuth.instance.currentUser!.uid;

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
      _snack('Магазин «${req.shopName}» одобрен', cGreen);
    } catch (e) {
      _snack(e.toString(), cRed);
    }
  }

  Future<void> _reject(ShopRequestModel req) async {
    final note = await showRejectReasonSheet(
      context,
      title: 'Отклонение заявки',
      subtitle: req.shopName,
    );
    if (note == null) return;
    try {
      await _repo.rejectRequest(
          requestId: req.id, reviewedBy: _uid, reviewNote: note);
      _snack('Заявка отклонена', cInk);
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
        title: Text('Выйти', style: manrope(16, FontWeight.w800, color: cInk)),
        content: Text('Выйти из аккаунта?',
            style: manrope(14, FontWeight.w500, color: cInk2)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Нет',
                  style: manrope(14, FontWeight.w600, color: cInk2))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child:
                  Text('Выйти', style: manrope(14, FontWeight.w700, color: cRed))),
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
              title: 'Заявки магазинов',
              subtitle: 'Управление маркетплейсом',
              compact: true,
              action: _HeaderActions(
                editPending: _editPending,
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
                          label: 'Все (${all.length})',
                          active: _tab == 0,
                          onTap: () => setState(() => _tab = 0)),
                      _TabChip(
                          label: 'Новые ($pending)',
                          active: _tab == 1,
                          onTap: () => setState(() => _tab = 1)),
                      _TabChip(
                          label: 'Одобренные',
                          active: _tab == 2,
                          onTap: () => setState(() => _tab = 2)),
                      _TabChip(
                          label: 'Отклонённые',
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
            Text('Нет заявок',
                style: manrope(16, FontWeight.w700, color: cInk)),
            const SizedBox(height: 4),
            Text('В этой категории пока пусто',
                style: manrope(13, FontWeight.w500, color: cInk3)),
          ],
        ),
      );
}

// ── Header actions (маркетплейс + өзгерту запростары + баннер + шығу) ─────────────
class _HeaderActions extends StatelessWidget {
  final Stream<List<StoreEditRequestModel>> editPending;
  final VoidCallback onSignOut;
  const _HeaderActions({required this.editPending, required this.onSignOut});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
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
    if (req.isApproved) return (tone: 'green', label: 'Одобрено');
    if (req.isRejected) return (tone: 'red', label: 'Отклонено');
    return (tone: 'amber', label: 'Новая');
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
                        '${req.category}${req.city.isNotEmpty ? ' · ${req.city}' : ''}',
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
                    label: 'Одобрить',
                    bg: cGreenTint,
                    fg: cGreenDeep,
                    onTap: onApprove,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _SmallBtn(
                    label: 'Отклонить',
                    bg: cRedTint,
                    fg: cRed,
                    onTap: onReject,
                  ),
                ),
                const SizedBox(width: 8),
                _SmallBtn(
                  label: 'Детали',
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
