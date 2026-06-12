import 'package:flutter/material.dart';
import '../../data/models/store_edit_request_model.dart';
import '../../data/repositories/store_edit_repository.dart';
import '../../theme/qoima_design.dart';
import 'store_edit_diff_screen.dart';

/// Superadmin — дүкен мәліметтерін өзгерту запростары (v10 §10).
class StoreEditRequestsScreen extends StatefulWidget {
  const StoreEditRequestsScreen({super.key});

  @override
  State<StoreEditRequestsScreen> createState() =>
      _StoreEditRequestsScreenState();
}

class _StoreEditRequestsScreenState extends State<StoreEditRequestsScreen> {
  final _repo = StoreEditRepository();
  int _tab = 0; // 0 Ожидание · 1 Одобренные · 2 Отклонённые

  List<StoreEditRequestModel> _filter(List<StoreEditRequestModel> all) {
    switch (_tab) {
      case 1:
        return all.where((r) => r.isApproved).toList();
      case 2:
        return all.where((r) => r.isRejected || r.isCancelled).toList();
      default:
        return all.where((r) => r.isPending).toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cBg,
      body: StreamBuilder<List<StoreEditRequestModel>>(
        stream: _repo.watchAll(),
        builder: (context, snap) {
          final all = snap.data ?? [];
          final pending = all.where((r) => r.isPending).length;
          final approved = all.where((r) => r.isApproved).length;
          final rejected =
              all.where((r) => r.isRejected || r.isCancelled).length;
          final list = _filter(all);

          return Column(children: [
            QGradientHeader(
              title: 'Запросы на изменение',
              subtitle: pending > 0 ? '$pending в ожидании' : 'Нет новых',
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
                          label: 'Ожидание ($pending)',
                          active: _tab == 0,
                          onTap: () => setState(() => _tab = 0)),
                      _TabChip(
                          label: 'Одобренные ($approved)',
                          active: _tab == 1,
                          onTap: () => setState(() => _tab = 1)),
                      _TabChip(
                          label: 'Отклонённые ($rejected)',
                          active: _tab == 2,
                          onTap: () => setState(() => _tab = 2)),
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
                          itemBuilder: (_, i) => _EditReqCard(
                            req: list[i],
                            onOpen: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) =>
                                      StoreEditDiffScreen(req: list[i])),
                            ),
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
              child:
                  const Icon(Icons.edit_outlined, color: cGreen, size: 34),
            ),
            const SizedBox(height: 14),
            Text('Нет запросов',
                style: manrope(16, FontWeight.w700, color: cInk)),
            const SizedBox(height: 4),
            Text('В этой категории пока пусто',
                style: manrope(13, FontWeight.w500, color: cInk3)),
          ],
        ),
      );
}

// ── Risk heuristic ───────────────────────────────────────────────────────────────
String _risk(StoreEditRequestModel r) {
  final fields = r.changes.map((c) => c.field).toSet();
  if (fields
      .intersection({'paymentCardNumber', 'ownerIin', 'ownerName'}).isNotEmpty) {
    return 'high';
  }
  if (fields.contains('phone') || fields.contains('storeName')) return 'medium';
  return 'low';
}

({Color color, String tone, String label}) _riskInfo(String risk) {
  switch (risk) {
    case 'high':
      return (color: cRed, tone: 'red', label: 'Высокий риск');
    case 'medium':
      return (color: cAmber, tone: 'amber', label: 'Средний риск');
    default:
      return (color: cGreen, tone: 'green', label: 'Низкий риск');
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

// ── Edit request card ────────────────────────────────────────────────────────────
class _EditReqCard extends StatelessWidget {
  final StoreEditRequestModel req;
  final VoidCallback onOpen;
  const _EditReqCard({required this.req, required this.onOpen});

  ({String tone, String label}) get _statusPill {
    if (req.isApproved) return (tone: 'green', label: 'Одобрено');
    if (req.isRejected) return (tone: 'red', label: 'Отклонено');
    if (req.isCancelled) return (tone: 'gray', label: 'Отозвано');
    return (tone: 'amber', label: 'Новый');
  }

  @override
  Widget build(BuildContext context) {
    final risk = _riskInfo(_risk(req));
    final pill = _statusPill;
    return GestureDetector(
      onTap: onOpen,
      child: Container(
        decoration: BoxDecoration(
          color: cSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border(
            left: BorderSide(color: risk.color, width: 4),
            top: const BorderSide(color: cLine),
            right: const BorderSide(color: cLine),
            bottom: const BorderSide(color: cLine),
          ),
          boxShadow: kShadowSm,
        ),
        padding: const EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              QIconTile(
                icon: Icon(Icons.edit_outlined, color: risk.color, size: 20),
                tone: risk.tone,
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
                    Text(_fmtDateTime(req.createdAt),
                        style: manrope(11.5, FontWeight.w500, color: cInk3)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  QPill(pill.label, tone: pill.tone),
                  const SizedBox(height: 4),
                  if (req.isPending)
                    QPill(risk.label, tone: risk.tone),
                ],
              ),
            ]),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: req.changes
                  .map((c) => Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(
                          color: cBg,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(c.label,
                            style: manrope(11.5, FontWeight.w600,
                                color: cInk2)),
                      ))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }
}

String _two(int v) => v.toString().padLeft(2, '0');
String _fmtDateTime(DateTime d) =>
    '${_two(d.day)}.${_two(d.month)}.${d.year} ${_two(d.hour)}:${_two(d.minute)}';
