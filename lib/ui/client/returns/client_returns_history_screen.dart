import 'package:flutter/material.dart';
import '../../../core/app_user.dart';
import '../../../core/l10n_ext.dart';
import '../../../data/models/return_model.dart';
import '../../../data/services/return_service.dart';
import '../../../theme/qoima_design.dart';
import 'client_return_status_screen.dart';

/// Embedded widget (not a full route) — placed as a tab in ClientOrdersScreen.
class ClientReturnsHistoryScreen extends StatelessWidget {
  const ClientReturnsHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ReturnModel>>(
      stream: ReturnService().watchClientReturns(AppUser.current.uid),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: cGreen));
        }
        final returns = snap.data ?? [];
        if (returns.isEmpty) {
          return _Empty();
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          itemCount: returns.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) => _ReturnCard(ret: returns[i]),
        );
      },
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────
class _Empty extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: cGreenTint,
                shape: BoxShape.circle,
              ),
              child:
                  const Icon(Icons.assignment_return_outlined,
                      color: cGreen, size: 36),
            ),
            const SizedBox(height: 16),
            Text(context.l10n.returnNoReturns,
                style: manrope(16, FontWeight.w700, color: cInk)),
            const SizedBox(height: 6),
            Text(context.l10n.returnNoReturnsHint,
                style: manrope(13, FontWeight.w500, color: cInk3),
                textAlign: TextAlign.center),
          ],
        ),
      );
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
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => ClientReturnStatusScreen(ret: ret)),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: cSurface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: kShadowSm,
          border: Border.all(color: cLine),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _statusTint(ret.status),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(_statusIcon(ret.status),
                        color: _statusColor(ret.status), size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(ret.id,
                            style: manrope(14, FontWeight.w700, color: cInk),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        Text(dateStr,
                            style: manrope(11.5, FontWeight.w500, color: cInk3)),
                      ],
                    ),
                  ),
                  QPill(ret.status.label(context), tone: ret.status.tone),
                ],
              ),
            ),

            // Items preview
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              child: Text(
                ret.items
                    .take(2)
                    .map((i) => '${i.productTitle} ×${i.quantity}')
                    .join(', ') +
                    (ret.items.length > 2
                        ? ' +${ret.items.length - 2}'
                        : ''),
                style: manrope(12.5, FontWeight.w500, color: cInk2),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // Footer: total + chevron
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
              child: Row(
                children: [
                  Text('${ret.totalAmount.toStringAsFixed(0)} ₸',
                      style: manrope(16, FontWeight.w800, color: cGreen)),
                  const Spacer(),
                  const Icon(Icons.chevron_right_rounded,
                      color: cInk3, size: 20),
                ],
              ),
            ),

            // Amber notice if still pending
            if (ret.status == ReturnStatus.requested)
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  color: cAmber.withValues(alpha: 0.08),
                  borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(16)),
                  border: Border(
                      top: BorderSide(
                          color: cAmber.withValues(alpha: 0.2))),
                ),
                child: Text(context.l10n.returnStatusRequested,
                    style: manrope(12, FontWeight.w700, color: cAmber)),
              ),
          ],
        ),
      ),
    );
  }

  IconData _statusIcon(ReturnStatus s) => switch (s) {
        ReturnStatus.requested => Icons.hourglass_empty_rounded,
        ReturnStatus.approved => Icons.thumb_up_alt_outlined,
        ReturnStatus.rejected => Icons.cancel_outlined,
        ReturnStatus.received => Icons.inventory_2_outlined,
        ReturnStatus.refunded => Icons.check_circle_outline_rounded,
      };

  Color _statusColor(ReturnStatus s) => switch (s) {
        ReturnStatus.requested => cAmber,
        ReturnStatus.approved => cBlue,
        ReturnStatus.rejected => cRed,
        ReturnStatus.received => cGreen,
        ReturnStatus.refunded => cGreen,
      };

  Color _statusTint(ReturnStatus s) => switch (s) {
        ReturnStatus.requested => cAmber.withValues(alpha: 0.12),
        ReturnStatus.approved => cBlue.withValues(alpha: 0.1),
        ReturnStatus.rejected => cRedTint,
        ReturnStatus.received => cGreenTint,
        ReturnStatus.refunded => cGreenTint,
      };
}
