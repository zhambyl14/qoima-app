import 'package:flutter/material.dart';
import '../../../core/l10n_ext.dart';
import '../../../data/models/return_model.dart';
import '../../../data/services/return_service.dart';
import '../../../theme/qoima_design.dart';

import '../../../core/lang.dart';
/// Step: seller receives the physical item.
/// 1. Mark item condition (ok / bad)
/// 2. Optionally upload condition photos (shown as TODO — no new deps)
/// 3. "Mark received" → calls markReceived()
/// 4. Refund method bottom sheet → calls completeRefund()
class SellerReturnReceiveScreen extends StatefulWidget {
  final ReturnModel ret;
  const SellerReturnReceiveScreen({super.key, required this.ret});

  @override
  State<SellerReturnReceiveScreen> createState() =>
      _SellerReturnReceiveScreenState();
}

class _SellerReturnReceiveScreenState
    extends State<SellerReturnReceiveScreen> {
  bool _receiving = false;
  bool _refunding = false;

  ReturnModel get r => widget.ret;

  Future<void> _markReceived() async {
    setState(() => _receiving = true);
    try {
      // Тауар әрқашан жарамды деп қабылданады әрі қоймаға қайтарылады.
      await ReturnService().markReceived(
        adminUid: r.adminUid,
        returnId: r.id,
        itemConditionOk: true,
        conditionPhotos: const [],
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(context.l10n.returnReceiveSuccess),
          backgroundColor: cGreen,
          behavior: SnackBarBehavior.floating,
        ));
        // Immediately show refund method sheet
        _showRefundSheet();
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
      if (mounted) setState(() => _receiving = false);
    }
  }

  void _showRefundSheet() {
    RefundMethod selected = r.refundMethod;
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (_, setSheet) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(context.l10n.returnRefundTitle,
                  style: manrope(18, FontWeight.w800, color: cInk)),
              const SizedBox(height: 4),
              Text(context.l10n.returnRefundMethodLabel,
                  style: manrope(13, FontWeight.w500, color: cInk2)),
              const SizedBox(height: 20),
              // Қайтару әдісі төлем әдісіне тең — таңдау жоқ (read-only).
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cGreenTint,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: cGreen, width: 1.5),
                ),
                child: Row(children: [
                  Icon(
                    selected == RefundMethod.cash
                        ? Icons.payments_outlined
                        : Icons.credit_card_rounded,
                    color: cGreen,
                    size: 22,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(selected.label(context),
                        style: manrope(15, FontWeight.w700, color: cGreenDeep)),
                  ),
                  const Icon(Icons.lock_outline_rounded, color: cInk3, size: 18),
                ]),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _refunding
                      ? null
                      : () async {
                          Navigator.pop(sheetCtx);
                          await _completeRefund(selected);
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cGreen,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(context.l10n.returnCompleteRefund,
                      style: manrope(15, FontWeight.w700,
                          color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _completeRefund(RefundMethod method) async {
    setState(() => _refunding = true);
    try {
      await ReturnService().completeRefund(
        adminUid: r.adminUid,
        returnId: r.id,
        method: method,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(context.l10n.returnRefundSuccess),
          backgroundColor: cGreen,
          behavior: SnackBarBehavior.floating,
        ));
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(context.l10n.returnStockRestored),
          backgroundColor: cGreen,
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
      if (mounted) setState(() => _refunding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // If already received, skip straight to refund button
    final alreadyReceived = r.status == ReturnStatus.received;

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
                      Text(context.l10n.returnReceiveTitle,
                          style: manrope(21, FontWeight.w800,
                              color: Colors.white, letterSpacing: -0.5)),
                      Text(r.id,
                          style: manrope(13, FontWeight.w500,
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
              // Items summary
              Text(context.l10n.returnItemsSection,
                  style: manrope(13, FontWeight.w700, color: cInk3)
                      .copyWith(letterSpacing: 0.3)),
              const SizedBox(height: 8),
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
                          style:
                              manrope(14, FontWeight.w800, color: cInk)),
                    ]),
                  )),

              if (!alreadyReceived) ...[
                const SizedBox(height: 20),
                // Тауар әрқашан қоймаға қайтарылады — «жарамды/жарамсыз» таңдауы жоқ.
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cGreenTint,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: cGreen.withValues(alpha: 0.3)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.inventory_2_outlined,
                        color: cGreen, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(context.l10n.returnStockRestored,
                          style: manrope(12.5, FontWeight.w600,
                              color: cGreenDeep)),
                    ),
                  ]),
                ),

                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _receiving ? null : _markReceived,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: cGreen,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: cLine,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: _receiving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : Text(context.l10n.returnReceiveTitle,
                            style: manrope(15, FontWeight.w700,
                                color: Colors.white)),
                  ),
                ),
              ],

              // Already received — show refund button
              if (alreadyReceived) ...[
                const SizedBox(height: 20),
                if (r.itemConditionOk != null)
                  QPill(
                    r.itemConditionOk!
                        ? context.l10n.returnConditionOk
                        : context.l10n.returnConditionBad,
                    tone: r.itemConditionOk! ? 'green' : 'red',
                  ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _refunding ? null : _showRefundSheet,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: cGreen,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: _refunding
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : Text(context.l10n.returnCompleteRefund,
                            style: manrope(15, FontWeight.w700,
                                color: Colors.white)),
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

class _Thumb extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: cGreenTint,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.inventory_2_outlined,
            color: cGreen, size: 22),
      );
}
