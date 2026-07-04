import 'package:flutter/material.dart';
import '../../../core/l10n_ext.dart';
import '../../../data/models/return_model.dart';
import '../../../data/services/return_service.dart';
import '../../../theme/qoima_design.dart';

import '../../../core/lang.dart';
class ClientReturnStatusScreen extends StatelessWidget {
  final ReturnModel ret;
  const ClientReturnStatusScreen({super.key, required this.ret});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ReturnModel?>(
      stream: ReturnService().watchReturn(ret.adminUid, ret.id),
      builder: (context, snap) {
        final r = snap.data ?? ret;
        return _StatusBody(ret: r);
      },
    );
  }
}

class _StatusBody extends StatefulWidget {
  final ReturnModel ret;
  const _StatusBody({required this.ret});

  @override
  State<_StatusBody> createState() => _StatusBodyState();
}

class _StatusBodyState extends State<_StatusBody> {
  bool _cancelling = false;
  ReturnModel get r => widget.ret;

  Future<void> _cancel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(context.l10n.returnConfirmTitle,
            style: manrope(17, FontWeight.w700, color: cInk)),
        content: Text(context.l10n.returnCancelRequest,
            style: manrope(14, FontWeight.w500, color: cInk2)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.l10n.cancel,
                  style: manrope(14, FontWeight.w600, color: cInk2))),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.l10n.yes,
                  style: manrope(14, FontWeight.w600, color: cRed))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _cancelling = true);
    try {
      await ReturnService()
          .cancelReturnRequest(r.adminUid, r.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(context.l10n.returnCancelRequest),
          backgroundColor: cInk,
          behavior: SnackBarBehavior.floating,
        ));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString()),
          backgroundColor: cRed,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = r.createdAt;
    final dateStr =
        '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

    return Scaffold(
      backgroundColor: cBg,
      body: Column(children: [
        Container(
          decoration: const BoxDecoration(gradient: kGrad),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 16),
              child: Row(children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.arrow_back_rounded,
                        color: Colors.white, size: 20),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.id,
                          style: manrope(20, FontWeight.w800,
                              color: Colors.white, letterSpacing: -0.5)),
                      Text(dateStr,
                          style: manrope(12, FontWeight.w500,
                              color: Colors.white.withValues(alpha: 0.75))),
                    ],
                  ),
                ),
                QPill(r.status.label(context), tone: r.status.tone),
              ]),
            ),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              // Timeline
              _Sec(context.l10n.returnTimelineTitle),
              _Timeline(ret: r),

              const SizedBox(height: 20),

              // Store & type
              _Sec(context.l10n.returnSourceSection),
              QCard(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Row(tr('Тип', 'Түрі'), r.type.label(context)),
                    _Row(context.l10n.returnPickupLabel,
                        r.pickup.label(context)),
                    _Row(context.l10n.returnRefundMethodLabel,
                        r.refundMethod.label(context)),
                    if (r.orderId != null && r.orderId!.isNotEmpty)
                      _Row(tr('Заказ ID', 'Тапсырыс ID'), r.orderId!),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // Items
              _Sec(context.l10n.returnItemsSection),
              ...r.items.map((item) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cSurface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: cLine),
                    ),
                    child: Row(children: [
                      if (item.productImage != null &&
                          item.productImage!.isNotEmpty)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(item.productImage!,
                              width: 44,
                              height: 44,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => _Thumb()),
                        )
                      else
                        _Thumb(),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.productTitle,
                                style: manrope(13.5, FontWeight.w700,
                                    color: cInk),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                            Text(tr('Р.${item.size}  ×${item.quantity}', 'Ө.${item.size}  ×${item.quantity}'),
                                style: manrope(12, FontWeight.w500,
                                    color: cInk3)),
                          ],
                        ),
                      ),
                      Text('${item.subtotal.toStringAsFixed(0)} ₸',
                          style: manrope(14, FontWeight.w800, color: cInk)),
                    ]),
                  )),

              // Reason
              const SizedBox(height: 14),
              _Sec(context.l10n.returnReasonLabel),
              QCard(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.reason.label(context),
                        style: manrope(14, FontWeight.w700, color: cInk)),
                    if (r.reasonNote != null &&
                        r.reasonNote!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(r.reasonNote!,
                          style: manrope(13, FontWeight.w500, color: cInk2)),
                    ],
                  ],
                ),
              ),

              // Rejection notice
              if (r.status == ReturnStatus.rejected &&
                  r.rejectionReason != null &&
                  r.rejectionReason!.isNotEmpty) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cRedTint,
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: cRed.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.error_outline,
                          color: cRed, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${context.l10n.returnRejectReason}: ${r.rejectionReason}',
                          style:
                              manrope(13, FontWeight.w500, color: cRed),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Total
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: cSurface,
                  borderRadius: BorderRadius.circular(16),
                  border:
                      Border.all(color: cGreen.withValues(alpha: 0.2)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(context.l10n.returnAmountSection,
                        style:
                            manrope(14, FontWeight.w600, color: cInk2)),
                    Text('${r.totalAmount.toStringAsFixed(0)} ₸',
                        style:
                            manrope(18, FontWeight.w800, color: cGreen)),
                  ],
                ),
              ),

              // Cancel button — only when still requested
              if (r.status == ReturnStatus.requested) ...[
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: OutlinedButton(
                    onPressed: _cancelling ? null : _cancel,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: cRed,
                      side: const BorderSide(color: cRed),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _cancelling
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                color: cRed, strokeWidth: 2))
                        : Text(context.l10n.returnCancelRequest,
                            style: manrope(14, FontWeight.w700,
                                color: cRed)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ]),
    );
  }
}

// ── Timeline ──────────────────────────────────────────────────────────────────
class _Timeline extends StatelessWidget {
  final ReturnModel ret;
  const _Timeline({required this.ret});

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}  '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final steps = <({String label, DateTime? at, bool done})>[
      (
        label: context.l10n.returnTimelineStep1,
        at: ret.createdAt,
        done: true,
      ),
      (
        label: context.l10n.returnTimelineStep2,
        at: ret.approvedAt,
        done: ret.approvedAt != null ||
            ret.status == ReturnStatus.received ||
            ret.status == ReturnStatus.refunded,
      ),
      (
        label: context.l10n.returnTimelineStep3,
        at: ret.receivedAt,
        done: ret.receivedAt != null ||
            ret.status == ReturnStatus.refunded,
      ),
      (
        label: context.l10n.returnTimelineStep4,
        at: ret.refundedAt,
        done: ret.refundedAt != null,
      ),
    ];

    return Column(
      children: List.generate(steps.length, (i) {
        final step = steps[i];
        final isLast = i == steps.length - 1;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: step.done ? cGreen : cLine,
                  shape: BoxShape.circle,
                ),
                child: step.done
                    ? const Icon(Icons.check,
                        color: Colors.white, size: 13)
                    : null,
              ),
              if (!isLast)
                Container(
                    width: 2, height: 36, color: step.done ? cGreen : cLine),
            ]),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                    top: 2, bottom: isLast ? 0 : 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(step.label,
                        style: manrope(13.5, FontWeight.w700,
                            color: step.done ? cInk : cInk3)),
                    if (step.at != null)
                      Text(_fmt(step.at!),
                          style:
                              manrope(11.5, FontWeight.w500, color: cInk3)),
                  ],
                ),
              ),
            ),
          ],
        );
      }),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────
class _Sec extends StatelessWidget {
  final String text;
  const _Sec(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: manrope(13, FontWeight.w700, color: cInk3)
                .copyWith(letterSpacing: 0.3)),
      );
}

class _Row extends StatelessWidget {
  final String label, value;
  const _Row(this.label, this.value);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          Text(label, style: manrope(13, FontWeight.w500, color: cInk2)),
          const Spacer(),
          Flexible(
              child: Text(value,
                  style: manrope(13, FontWeight.w700, color: cInk),
                  textAlign: TextAlign.end)),
        ]),
      );
}

class _Thumb extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
            color: cGreenTint, borderRadius: BorderRadius.circular(8)),
        child: const Icon(Icons.inventory_2_outlined, color: cGreen, size: 22),
      );
}
