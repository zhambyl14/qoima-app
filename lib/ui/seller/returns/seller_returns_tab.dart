import 'package:flutter/material.dart';
import '../../../core/app_user.dart';
import '../../../core/l10n_ext.dart';
import '../../../data/models/return_model.dart';
import '../../../data/services/return_service.dart';
import '../../../theme/qoima_design.dart';
import 'seller_return_review_screen.dart';
import 'seller_return_receive_screen.dart';

import '../../../core/lang.dart';
class SellerReturnsTab extends StatefulWidget {
  const SellerReturnsTab({super.key});

  @override
  State<SellerReturnsTab> createState() => _SellerReturnsTabState();
}

class _SellerReturnsTabState extends State<SellerReturnsTab> {
  late final Stream<List<ReturnModel>> _stream =
      ReturnService().watchSellerReturns(AppUser.current.ownerUid);

  // 'all' | 'pending' | 'approved' | 'done'
  String _filter = 'all';

  List<ReturnModel> _applyFilter(List<ReturnModel> all) {
    switch (_filter) {
      case 'pending':
        return all.where((r) => r.status == ReturnStatus.requested).toList();
      case 'approved':
        return all
            .where((r) =>
                r.status == ReturnStatus.approved ||
                r.status == ReturnStatus.received)
            .toList();
      case 'done':
        return all
            .where((r) =>
                r.status == ReturnStatus.refunded ||
                r.status == ReturnStatus.rejected)
            .toList();
      default:
        return all;
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ReturnModel>>(
      stream: _stream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: cGreen));
        }
        final all = snap.data ?? [];
        final shown = _applyFilter(all);

        return Column(children: [
          // 4 filter pills
          SizedBox(
            height: 50,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              children: [
                _Chip(
                  label: context.l10n.returnFilterAll,
                  active: _filter == 'all',
                  onTap: () => setState(() => _filter = 'all'),
                ),
                const SizedBox(width: 8),
                _Chip(
                  label: context.l10n.returnFilterPending,
                  active: _filter == 'pending',
                  count: all
                      .where((r) => r.status == ReturnStatus.requested)
                      .length,
                  onTap: () => setState(() => _filter = 'pending'),
                ),
                const SizedBox(width: 8),
                _Chip(
                  label: context.l10n.returnFilterApproved,
                  active: _filter == 'approved',
                  count: all
                      .where((r) =>
                          r.status == ReturnStatus.approved ||
                          r.status == ReturnStatus.received)
                      .length,
                  onTap: () => setState(() => _filter = 'approved'),
                ),
                const SizedBox(width: 8),
                _Chip(
                  label: context.l10n.returnFilterCompleted,
                  active: _filter == 'done',
                  count: all
                      .where((r) =>
                          r.status == ReturnStatus.refunded ||
                          r.status == ReturnStatus.rejected)
                      .length,
                  onTap: () => setState(() => _filter = 'done'),
                ),
              ],
            ),
          ),

          Expanded(
            child: shown.isEmpty
                ? Center(
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.assignment_return_outlined,
                              size: 56, color: cInk3),
                          const SizedBox(height: 12),
                          Text(context.l10n.returnNoReturns,
                              style:
                                  manrope(16, FontWeight.w500, color: cInk2)),
                        ]))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                    itemCount: shown.length,
                    itemBuilder: (_, i) => _ReturnCard(ret: shown[i]),
                  ),
          ),
        ]);
      },
    );
  }
}

// ── Return card ───────────────────────────────────────────────────────────────
class _ReturnCard extends StatelessWidget {
  final ReturnModel ret;
  const _ReturnCard({required this.ret});

  @override
  Widget build(BuildContext context) {
    final d = ret.createdAt;
    final dateStr =
        '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

    return GestureDetector(
      onTap: () {
        if (ret.status == ReturnStatus.approved) {
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => SellerReturnReceiveScreen(ret: ret)));
        } else {
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => SellerReturnReviewScreen(ret: ret)));
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: cSurface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: ret.status == ReturnStatus.requested
                ? cAmber.withValues(alpha: 0.4)
                : cLine,
            width: ret.status == ReturnStatus.requested ? 1.5 : 1,
          ),
          boxShadow: kShadowSm,
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Text(ret.id,
                    style: manrope(14, FontWeight.w800, color: cInk)),
                const Spacer(),
                QPill(ret.status.label(context), tone: ret.status.tone),
              ]),
              const SizedBox(height: 6),
              Row(children: [
                QPill(ret.type.label(context), tone: ret.type.tone),
                const SizedBox(width: 8),
                Text(dateStr,
                    style: manrope(12, FontWeight.w500, color: cInk3)),
              ]),
              if (ret.clientName.isNotEmpty || ret.clientPhone.isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(children: [
                  const Icon(Icons.person_outline, size: 14, color: cInk3),
                  const SizedBox(width: 4),
                  Text(
                    ret.clientName.isNotEmpty
                        ? ret.clientName
                        : ret.clientPhone,
                    style: manrope(12.5, FontWeight.w500, color: cInk2),
                  ),
                ]),
              ],
              const SizedBox(height: 6),
              Row(children: [
                Expanded(
                  child: Text(
                    ret.items.isEmpty
                        ? '—'
                        : ret.items.map((i) => i.productTitle).join(', '),
                    style: manrope(12.5, FontWeight.w500, color: cInk2),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text('${ret.totalAmount.toStringAsFixed(0)} ₸',
                    style: manrope(14.5, FontWeight.w800, color: cInk)),
              ]),
              if (ret.status == ReturnStatus.requested) ...[
                const SizedBox(height: 8),
                QPill(tr('Требует рассмотрения', 'Қарау қажет'),
                    tone: 'amber',
                    icon: const Icon(Icons.priority_high_rounded,
                        size: 12, color: Color(0xFF92400E))),
              ],
              if (ret.status == ReturnStatus.approved) ...[
                const SizedBox(height: 8),
                QPill(tr('Ожидает приёмки', 'Қабылдау күтілуде'),
                    tone: 'blue',
                    icon: const Icon(Icons.move_to_inbox_outlined,
                        size: 12, color: Color(0xFF1A5BD0))),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Filter chip ───────────────────────────────────────────────────────────────
class _Chip extends StatelessWidget {
  final String label;
  final bool active;
  final int? count;
  final VoidCallback onTap;

  const _Chip({
    required this.label,
    required this.active,
    this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: active ? cInk : cSurface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: active ? cInk : cLine),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(label,
                style: manrope(12.5, FontWeight.w700,
                    color: active ? Colors.white : cInk2)),
            if ((count ?? 0) > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: active
                      ? Colors.white.withValues(alpha: 0.2)
                      : cGreenTint,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('$count',
                    style: manrope(10.5, FontWeight.w800,
                        color: active ? Colors.white : cGreenDeep)),
              ),
            ],
          ]),
        ),
      );
}
