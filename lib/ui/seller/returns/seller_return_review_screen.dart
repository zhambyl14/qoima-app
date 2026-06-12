import 'package:flutter/material.dart';
import '../../../core/l10n_ext.dart';
import '../../../data/models/return_model.dart';
import '../../../data/services/return_service.dart';
import '../../../theme/qoima_design.dart';
import 'seller_return_receive_screen.dart';

/// Shows details of a return request for the seller to review (approve/reject).
/// Also used as a read-only detail view for received/refunded/rejected returns.
class SellerReturnReviewScreen extends StatelessWidget {
  final ReturnModel ret;
  const SellerReturnReviewScreen({super.key, required this.ret});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ReturnModel?>(
      stream: ReturnService().watchReturn(ret.adminUid, ret.id),
      builder: (context, snap) {
        final r = snap.data ?? ret;
        return _ReviewBody(ret: r);
      },
    );
  }
}

class _ReviewBody extends StatefulWidget {
  final ReturnModel ret;
  const _ReviewBody({required this.ret});

  @override
  State<_ReviewBody> createState() => _ReviewBodyState();
}

class _ReviewBodyState extends State<_ReviewBody> {
  bool _busy = false;
  final _rejectCtrl = TextEditingController();

  ReturnModel get r => widget.ret;

  @override
  void dispose() {
    _rejectCtrl.dispose();
    super.dispose();
  }

  Future<void> _approve() async {
    setState(() => _busy = true);
    try {
      await ReturnService().approveReturn(r.adminUid, r.id, r.adminUid);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(context.l10n.returnApproveSuccess),
          backgroundColor: cGreen,
          behavior: SnackBarBehavior.floating,
        ));
        // Navigate to receive screen so seller can continue immediately
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
              builder: (_) => SellerReturnReceiveScreen(ret: r)),
        );
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
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showRejectDialog() async {
    _rejectCtrl.clear();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(context.l10n.returnReject,
            style: manrope(17, FontWeight.w700, color: cInk)),
        content: TextField(
          controller: _rejectCtrl,
          autofocus: true,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: context.l10n.returnEnterRejectReason,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.l10n.cancel,
                  style: manrope(14, FontWeight.w600, color: cInk2))),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: cRed,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12))),
              child: Text(context.l10n.returnReject,
                  style:
                      manrope(14, FontWeight.w700, color: Colors.white))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final reason = _rejectCtrl.text.trim();
    if (reason.isEmpty) return;
    setState(() => _busy = true);
    try {
      await ReturnService().rejectReturn(r.adminUid, r.id, reason);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(context.l10n.returnRejectSuccess),
          backgroundColor: cRed,
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
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = r.createdAt;
    final dateStr =
        '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}  '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

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
                              color:
                                  Colors.white.withValues(alpha: 0.75))),
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
              // Client info
              _Sec('Клиент'),
              QCard(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (r.clientName.isNotEmpty)
                      _Row('Имя', r.clientName),
                    if (r.clientPhone.isNotEmpty)
                      _Row('Телефон', r.clientPhone),
                    _Row('Тип', r.type.label(context)),
                    _Row('Доставка', r.pickup.label(context)),
                    _Row('Возврат средств', r.refundMethod.label(context)),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // Items
              _Sec(context.l10n.returnItemsSection),
              ...r.items.map((item) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: cSurface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: cLine),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(children: [
                        if (item.productImage != null &&
                            item.productImage!.isNotEmpty)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(item.productImage!,
                                width: 44,
                                height: 44,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    _Thumb()),
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
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis),
                              Text('Р.${item.size}  ×${item.quantity}',
                                  style: manrope(12, FontWeight.w500,
                                      color: cInk3)),
                            ],
                          ),
                        ),
                        Text('${item.subtotal.toStringAsFixed(0)} ₸',
                            style:
                                manrope(14, FontWeight.w800, color: cInk)),
                      ]),
                    ),
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

              // Photos
              if (r.photoUrls.isNotEmpty) ...[
                const SizedBox(height: 14),
                _Sec(context.l10n.returnPhotosLabel),
                SizedBox(
                  height: 90,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: r.photoUrls.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) => ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(r.photoUrls[i],
                          width: 90, height: 90, fit: BoxFit.cover),
                    ),
                  ),
                ),
              ],

              // Rejection reason
              if (r.rejectionReason != null &&
                  r.rejectionReason!.isNotEmpty) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cRedTint,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: cRed.withValues(alpha: 0.2)),
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

              // Total row
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: cSurface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: cGreen.withValues(alpha: 0.2)),
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

              // Action buttons — only shown when status == requested
              if (r.status == ReturnStatus.requested) ...[
                const SizedBox(height: 20),
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _busy ? null : _showRejectDialog,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: cRed,
                        side: const BorderSide(color: cRed),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text(context.l10n.returnReject,
                          style: manrope(14, FontWeight.w700, color: cRed)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _busy ? null : _approve,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: cGreen,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2))
                          : Text(context.l10n.returnApprove,
                              style: manrope(14, FontWeight.w700,
                                  color: Colors.white)),
                    ),
                  ),
                ]),
              ],

              // Approved/received: жалғастыру (қабылдау → ақша қайтару) ӘРІ
              // тығырықтан шығу үшін бас тарту мүмкіндігі.
              // (Бұрын approved-та тек жалғастыру, received-те ЕШТЕҢЕ болмайтын →
              //  интернет жаңартылса таңдау жоғалып, возврат «Өңделуде» қалатын.)
              if (r.status == ReturnStatus.approved ||
                  r.status == ReturnStatus.received) ...[
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _busy
                        ? null
                        : () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) =>
                                    SellerReturnReceiveScreen(ret: r))),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: cGreen,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Text(
                        r.status == ReturnStatus.received
                            ? context.l10n.returnCompleteRefund
                            : context.l10n.returnReceiveTitle,
                        style: manrope(15, FontWeight.w700,
                            color: Colors.white)),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton(
                    onPressed: _busy ? null : _showRejectDialog,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: cRed,
                      side: const BorderSide(color: cRed),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Text(context.l10n.returnReject,
                        style: manrope(14, FontWeight.w700, color: cRed)),
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
                textAlign: TextAlign.end),
          ),
        ]),
      );
}

class _Thumb extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: cGreenTint,
          borderRadius: BorderRadius.circular(8),
        ),
        child:
            const Icon(Icons.inventory_2_outlined, color: cGreen, size: 22),
      );
}
