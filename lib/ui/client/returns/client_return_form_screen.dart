import 'package:flutter/material.dart';
import '../../../core/app_user.dart';
import '../../../core/l10n_ext.dart';
import '../../../data/models/order_model.dart';
import '../../../data/models/return_model.dart';
import '../../../data/services/return_service.dart';
import '../../../theme/qoima_design.dart';
import 'client_return_status_screen.dart';

class ClientReturnFormScreen extends StatefulWidget {
  final OrderModel order;
  const ClientReturnFormScreen({super.key, required this.order});

  @override
  State<ClientReturnFormScreen> createState() =>
      _ClientReturnFormScreenState();
}

class _ClientReturnFormScreenState extends State<ClientReturnFormScreen> {
  int _page = 0; // 0=items  1=reason+note  2=delivery  3=summary

  late final Map<String, ({bool selected, ReturnItem item})> _itemMap = {
    for (final i in widget.order.items)
      '${i.batchId}__${i.size}': (
        selected: true,
        item: ReturnItem(
          productId: i.productId,
          productTitle: i.productName,
          batchId: i.batchId,
          size: i.size,
          quantity: i.qty,
          pricePerUnit: i.price,
        ),
      ),
  };

  ReturnReason _reason = ReturnReason.sizeNotFit;
  final _noteCtrl = TextEditingController();
  ReturnPickup _pickup = ReturnPickup.selfBring;
  // Қайтару әдісі = төлем әдісі (таңдау жоқ). Онлайн заказ электронды төленеді →
  // карта. paymentBank бос болса да refundMethodForPayment карта қайтарады.
  late final RefundMethod _refundMethod =
      refundMethodForPayment(widget.order.paymentBank);
  bool _submitting = false;

  static const double _courierFee = 1500;

  List<ReturnItem> get _selectedItems =>
      _itemMap.values.where((e) => e.selected).map((e) => e.item).toList();

  double get _refundTotal =>
      _selectedItems.fold(0.0, (s, i) => s + i.subtotal) -
      (_pickup == ReturnPickup.courier ? _courierFee : 0);

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  void _next() {
    if (_page == 0 && _selectedItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.l10n.returnSelectItemsHint),
        backgroundColor: cAmber,
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    setState(() => _page++);
  }

  void _back() {
    if (_page > 0) {
      setState(() => _page--);
    } else {
      Navigator.pop(context);
    }
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    try {
      final returned = await ReturnService().createReturnRequest(
        input: ReturnRequestInput(
          adminUid: widget.order.adminUid,
          clientUid: AppUser.current.uid,
          clientName: AppUser.current.name,
          clientPhone: AppUser.current.phone,
          orderId: widget.order.id,
          items: _selectedItems,
          reason: _reason,
          reasonNote: _noteCtrl.text.trim().isEmpty
              ? null
              : _noteCtrl.text.trim(),
          photoUrls: const [],
          pickup: _pickup,
          refundMethod: _refundMethod,
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(context.l10n.returnSuccessMsg),
          backgroundColor: cGreen,
          behavior: SnackBarBehavior.floating,
        ));
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
              builder: (_) => ClientReturnStatusScreen(ret: returned)),
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
      if (mounted) setState(() => _submitting = false);
    }
  }

  // ── Page titles ─────────────────────────────────────────────────────────────
  String _pageTitle(BuildContext context) {
    switch (_page) {
      case 0:
        return context.l10n.returnItemsSection;
      case 1:
        return context.l10n.returnReasonLabel;
      case 2:
        return context.l10n.returnPickupLabel;
      default:
        return context.l10n.returnSummaryTitle;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cBg,
      body: Column(children: [
        // ── Header ──────────────────────────────────────────────────────────
        Container(
          decoration: const BoxDecoration(gradient: kGrad),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 16),
              child: Row(children: [
                GestureDetector(
                  onTap: _back,
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
                      Text(context.l10n.returnCreateButton,
                          style: manrope(21, FontWeight.w800,
                              color: Colors.white, letterSpacing: -0.5)),
                      Text(_pageTitle(context),
                          style: manrope(13, FontWeight.w500,
                              color:
                                  Colors.white.withValues(alpha: 0.75))),
                    ],
                  ),
                ),
                // Step indicator
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('${_page + 1}/4',
                      style: manrope(12, FontWeight.w700,
                          color: Colors.white)),
                ),
              ]),
            ),
          ),
        ),

        // ── Page content ────────────────────────────────────────────────────
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: KeyedSubtree(
              key: ValueKey(_page),
              child: _page == 0
                  ? _ItemsPage(
                      itemMap: _itemMap,
                      onToggle: (k, v) =>
                          setState(() => _itemMap[k] = v),
                      onNext: _next,
                    )
                  : _page == 1
                      ? _ReasonPage(
                          reason: _reason,
                          noteCtrl: _noteCtrl,
                          onReasonChanged: (r) =>
                              setState(() => _reason = r),
                          onNext: _next,
                        )
                      : _page == 2
                          ? _DeliveryPage(
                              pickup: _pickup,
                              refundMethod: _refundMethod,
                              onPickupChanged: (p) =>
                                  setState(() => _pickup = p),
                              onNext: _next,
                              courierFee: _courierFee,
                            )
                          : _SummaryPage(
                              items: _selectedItems,
                              reason: _reason,
                              note: _noteCtrl.text.trim(),
                              pickup: _pickup,
                              refundMethod: _refundMethod,
                              refundTotal: _refundTotal,
                              courierFee: _courierFee,
                              onSubmit: _submit,
                              submitting: _submitting,
                            ),
            ),
          ),
        ),
      ]),
    );
  }
}

// ── Page 0: Select items ──────────────────────────────────────────────────────
class _ItemsPage extends StatelessWidget {
  final Map<String, ({bool selected, ReturnItem item})> itemMap;
  final void Function(String, ({bool selected, ReturnItem item})) onToggle;
  final VoidCallback onNext;

  const _ItemsPage({
    required this.itemMap,
    required this.onToggle,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final hasSelection = itemMap.values.any((e) => e.selected);
    return Column(children: [
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
          children: [
            Text(context.l10n.returnSelectItemsHint,
                style: manrope(13, FontWeight.w600, color: cInk3)),
            const SizedBox(height: 10),
            ...itemMap.entries.map((e) {
              final entry = e.value;
              return GestureDetector(
                onTap: () => onToggle(
                    e.key, (selected: !entry.selected, item: entry.item)),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: entry.selected ? cGreenTint : cSurface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: entry.selected ? cGreen : cLine,
                        width: entry.selected ? 1.5 : 1),
                  ),
                  child: Row(children: [
                    Icon(
                      entry.selected
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      color: entry.selected ? cGreen : cInk3,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(entry.item.productTitle,
                              style: manrope(13.5, FontWeight.w700,
                                  color: cInk),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          Text(
                              'Р.${entry.item.size}  ×${entry.item.quantity}',
                              style: manrope(12, FontWeight.w500,
                                  color: cInk3)),
                        ],
                      ),
                    ),
                    Text('${entry.item.subtotal.toStringAsFixed(0)} ₸',
                        style:
                            manrope(13.5, FontWeight.w700, color: cInk)),
                  ]),
                ),
              );
            }),
          ],
        ),
      ),
      _NextButton(label: 'Далее', enabled: hasSelection, onTap: onNext),
    ]);
  }
}

// ── Page 1: Reason + note + photos placeholder ────────────────────────────────
class _ReasonPage extends StatelessWidget {
  final ReturnReason reason;
  final TextEditingController noteCtrl;
  final ValueChanged<ReturnReason> onReasonChanged;
  final VoidCallback onNext;

  const _ReasonPage({
    required this.reason,
    required this.noteCtrl,
    required this.onReasonChanged,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
          children: [
            Text(context.l10n.returnReasonLabel,
                style: manrope(13, FontWeight.w600, color: cInk3)),
            const SizedBox(height: 10),
            ...ReturnReason.values.map((r) => GestureDetector(
                  onTap: () => onReasonChanged(r),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: reason == r ? cGreenTint : cSurface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: reason == r ? cGreen : cLine,
                          width: reason == r ? 1.5 : 1),
                    ),
                    child: Row(children: [
                      Icon(
                        reason == r
                            ? Icons.radio_button_checked_rounded
                            : Icons.radio_button_unchecked_rounded,
                        color: reason == r ? cGreen : cInk3,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Text(r.label(context),
                          style: manrope(13.5, FontWeight.w600,
                              color: reason == r ? cGreenDeep : cInk)),
                    ]),
                  ),
                )),

            const SizedBox(height: 16),

            Text(context.l10n.returnNotesLabel,
                style: manrope(13, FontWeight.w600, color: cInk3)),
            const SizedBox(height: 8),
            TextField(
              controller: noteCtrl,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: context.l10n.returnEnterRejectReason,
                filled: true,
                fillColor: cSurface,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: cLine)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: cLine)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: cGreen)),
                contentPadding: const EdgeInsets.all(14),
              ),
            ),

            const SizedBox(height: 16),

            // Photos placeholder
            Text(context.l10n.returnPhotosLabel,
                style: manrope(13, FontWeight.w600, color: cInk3)),
            const SizedBox(height: 8),
            Container(
              height: 90,
              decoration: BoxDecoration(
                color: cSurface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: cLine, style: BorderStyle.solid),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.add_photo_alternate_outlined,
                        color: cInk3, size: 28),
                    const SizedBox(height: 4),
                    Text('Фото жүктеу (жоспарда)',
                        style: manrope(12, FontWeight.w500, color: cInk3)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      _NextButton(label: 'Далее', onTap: onNext),
    ]);
  }
}

// ── Page 2: Delivery method + refund method ───────────────────────────────────
class _DeliveryPage extends StatelessWidget {
  final ReturnPickup pickup;
  final RefundMethod refundMethod;
  final ValueChanged<ReturnPickup> onPickupChanged;
  final VoidCallback onNext;
  final double courierFee;

  const _DeliveryPage({
    required this.pickup,
    required this.refundMethod,
    required this.onPickupChanged,
    required this.onNext,
    required this.courierFee,
  });

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
          children: [
            Text(context.l10n.returnPickupLabel,
                style: manrope(13, FontWeight.w600, color: cInk3)),
            const SizedBox(height: 10),
            ...ReturnPickup.values.map((p) {
              final active = pickup == p;
              final isCourier = p == ReturnPickup.courier;
              return GestureDetector(
                onTap: () => onPickupChanged(p),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: active ? cGreenTint : cSurface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: active ? cGreen : cLine,
                        width: active ? 1.5 : 1),
                  ),
                  child: Row(children: [
                    Icon(
                      active
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_unchecked_rounded,
                      color: active ? cGreen : cInk3,
                      size: 22,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.label(context),
                              style: manrope(14, FontWeight.w700,
                                  color: active ? cGreenDeep : cInk)),
                          Text(
                            isCourier
                                ? '${courierFee.toStringAsFixed(0)} ₸'
                                : 'Тегін',
                            style: manrope(12, FontWeight.w600,
                                color: isCourier ? cAmber : cGreen),
                          ),
                        ],
                      ),
                    ),
                  ]),
                ),
              );
            }),

            const SizedBox(height: 16),

            Text(context.l10n.returnRefundMethodLabel,
                style: manrope(13, FontWeight.w600, color: cInk3)),
            const SizedBox(height: 10),
            // Қайтару әдісі төлем әдісіне тең — өзгертуге болмайды.
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cGreenTint,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: cGreen, width: 1.5),
              ),
              child: Row(children: [
                Icon(
                  refundMethod == RefundMethod.cash
                      ? Icons.payments_outlined
                      : Icons.credit_card_rounded,
                  color: cGreen,
                  size: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(refundMethod.label(context),
                          style: manrope(14, FontWeight.w700,
                              color: cGreenDeep)),
                      Text('Төлем әдісіне сәйкес',
                          style:
                              manrope(11.5, FontWeight.w500, color: cInk3)),
                    ],
                  ),
                ),
                const Icon(Icons.lock_outline_rounded, color: cInk3, size: 18),
              ]),
            ),
          ],
        ),
      ),
      _NextButton(label: 'Далее', onTap: onNext),
    ]);
  }
}

// ── Page 3: Summary ───────────────────────────────────────────────────────────
class _SummaryPage extends StatelessWidget {
  final List<ReturnItem> items;
  final ReturnReason reason;
  final String note;
  final ReturnPickup pickup;
  final RefundMethod refundMethod;
  final double refundTotal;
  final double courierFee;
  final VoidCallback onSubmit;
  final bool submitting;

  const _SummaryPage({
    required this.items,
    required this.reason,
    required this.note,
    required this.pickup,
    required this.refundMethod,
    required this.refundTotal,
    required this.courierFee,
    required this.onSubmit,
    required this.submitting,
  });

  @override
  Widget build(BuildContext context) {
    final isCourier = pickup == ReturnPickup.courier;
    final itemsTotal = items.fold(0.0, (s, i) => s + i.subtotal);

    return Column(children: [
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
          children: [
            Text(context.l10n.returnSummaryTitle,
                style: manrope(15, FontWeight.w800, color: cInk)),
            const SizedBox(height: 14),

            // Items
            _SummarySection(
              title: context.l10n.returnItemsSection,
              child: Column(
                children: items
                    .map((i) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(children: [
                            Expanded(
                              child: Text(
                                '${i.productTitle}  Р.${i.size}  ×${i.quantity}',
                                style:
                                    manrope(13, FontWeight.w500, color: cInk),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text('${i.subtotal.toStringAsFixed(0)} ₸',
                                style:
                                    manrope(13, FontWeight.w700, color: cInk)),
                          ]),
                        ))
                    .toList(),
              ),
            ),

            const SizedBox(height: 10),

            // Reason
            _SummarySection(
              title: context.l10n.returnReasonLabel,
              child: Text(reason.label(context),
                  style: manrope(13.5, FontWeight.w600, color: cInk)),
            ),

            if (note.isNotEmpty) ...[
              const SizedBox(height: 10),
              _SummarySection(
                title: context.l10n.returnNotesLabel,
                child: Text(note,
                    style: manrope(13, FontWeight.w500, color: cInk2)),
              ),
            ],

            const SizedBox(height: 10),

            // Delivery
            _SummarySection(
              title: context.l10n.returnPickupLabel,
              child: Row(children: [
                Expanded(
                  child: Text(pickup.label(context),
                      style: manrope(13.5, FontWeight.w600, color: cInk)),
                ),
                Text(
                  isCourier
                      ? '-${courierFee.toStringAsFixed(0)} ₸'
                      : 'Тегін',
                  style: manrope(13, FontWeight.w600,
                      color: isCourier ? cAmber : cGreen),
                ),
              ]),
            ),

            const SizedBox(height: 10),

            // Refund method
            _SummarySection(
              title: context.l10n.returnRefundMethodLabel,
              child: Text(refundMethod.label(context),
                  style: manrope(13.5, FontWeight.w600, color: cInk)),
            ),

            const SizedBox(height: 14),

            // Total
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cGreenTint,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: cGreen.withValues(alpha: 0.4)),
              ),
              child: Column(children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Тауарлар сомасы',
                        style: manrope(13, FontWeight.w500, color: cInk2)),
                    Text('${itemsTotal.toStringAsFixed(0)} ₸',
                        style: manrope(13, FontWeight.w600, color: cInk)),
                  ],
                ),
                if (isCourier) ...[
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Курьер',
                          style:
                              manrope(13, FontWeight.w500, color: cInk2)),
                      Text('-${courierFee.toStringAsFixed(0)} ₸',
                          style:
                              manrope(13, FontWeight.w600, color: cAmber)),
                    ],
                  ),
                ],
                const Divider(height: 14, color: cGreen),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(context.l10n.returnAmountSection,
                        style: manrope(14, FontWeight.w700, color: cInk)),
                    Text('${refundTotal.toStringAsFixed(0)} ₸',
                        style: manrope(16, FontWeight.w800,
                            color: cGreenDeep)),
                  ],
                ),
              ]),
            ),
          ],
        ),
      ),

      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: submitting ? null : onSubmit,
            style: ElevatedButton.styleFrom(
              backgroundColor: cGreen,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            child: submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : Text(context.l10n.returnCreateButton,
                    style: manrope(15, FontWeight.w700,
                        color: Colors.white)),
          ),
        ),
      ),
    ]);
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────
class _NextButton extends StatelessWidget {
  final String label;
  final bool enabled;
  final VoidCallback onTap;
  const _NextButton(
      {required this.label, this.enabled = true, required this.onTap});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: enabled ? onTap : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: cGreen,
              foregroundColor: Colors.white,
              disabledBackgroundColor: cLine,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            child: Text(label,
                style: manrope(15, FontWeight.w700, color: Colors.white)),
          ),
        ),
      );
}

class _SummarySection extends StatelessWidget {
  final String title;
  final Widget child;
  const _SummarySection({required this.title, required this.child});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cLine),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: manrope(11.5, FontWeight.w600, color: cInk3)
                    .copyWith(letterSpacing: 0.3)),
            const SizedBox(height: 6),
            child,
          ],
        ),
      );
}
