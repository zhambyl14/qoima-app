import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:html' as html;
import '../../core/app_user.dart';
import '../../data/models/order_model.dart';
import '../../data/services/client_service.dart';
import '../../data/services/cloudinary_service.dart';
import '../../data/services/firestore_service.dart';
import '../../theme/qoima_design.dart';
import 'reservation_timer_widget.dart';

class ClientOrdersScreen extends StatefulWidget {
  const ClientOrdersScreen({super.key});

  @override
  State<ClientOrdersScreen> createState() => _ClientOrdersScreenState();
}

class _ClientOrdersScreenState extends State<ClientOrdersScreen> {
  int _tabIndex = 0; // 0=active, 1=completed

  @override
  Widget build(BuildContext context) {
    final phone = context.read<AppUser>().phone;

    return Scaffold(
      backgroundColor: cBg,
      body: Column(children: [
        QGradientHeader(
          title: 'Мои заказы',
          subtitle: 'История покупок',
          compact: true,
        ),
        Expanded(
          child: phone.isEmpty
              ? Center(
                  child: Text('Нет номера телефона',
                      style: manrope(15, FontWeight.w500, color: cInk2)))
              : StreamBuilder<List<OrderModel>>(
                  stream: ClientService().watchClientOrders(phone),
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(
                          child: CircularProgressIndicator(color: cGreen));
                    }
                    final all = snap.data ?? [];

                    // Мерзімі өткен өз тапсырыстарын авто-болдырмаймыз
                    for (final o in all) {
                      if (o.isExpired) {
                        ClientService().cancelOrder(o).ignore();
                      }
                    }

                    final active = all.where((o) =>
                        o.status == OrderModel.statusPending ||
                        o.status == OrderModel.statusReserved ||
                        o.status == OrderModel.statusRejected ||
                        o.status == OrderModel.statusConfirmed ||
                        o.status == OrderModel.statusReady).toList();

                    final completed = all.where((o) =>
                        o.status == OrderModel.statusCompleted ||
                        o.status == OrderModel.statusCancelled).toList();

                    final shown = _tabIndex == 0 ? active : completed;

                    return Column(children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                        child: Row(children: [
                          _TabChip(
                            label: 'Активные',
                            count: active.length,
                            active: _tabIndex == 0,
                            onTap: () => setState(() => _tabIndex = 0),
                          ),
                          const SizedBox(width: 8),
                          _TabChip(
                            label: 'Завершённые',
                            count: completed.length,
                            active: _tabIndex == 1,
                            onTap: () => setState(() => _tabIndex = 1),
                          ),
                        ]),
                      ),
                      Expanded(
                        child: shown.isEmpty
                            ? Center(
                                child: Column(
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
                                    children: [
                                    const Icon(Icons.receipt_long_outlined,
                                        size: 56, color: cInk3),
                                    const SizedBox(height: 12),
                                    Text('Нет заказов',
                                        style: manrope(
                                            16, FontWeight.w500,
                                            color: cInk2)),
                                  ]))
                            : ListView.builder(
                                padding: const EdgeInsets.fromLTRB(
                                    16, 8, 16, 20),
                                itemCount: shown.length,
                                itemBuilder: (_, i) =>
                                    _OrderCard(order: shown[i]),
                              ),
                      ),
                    ]);
                  },
                ),
        ),
      ]),
    );
  }
}

// ── Tab chip ───────────────────────────────────────────────────────────────────
class _TabChip extends StatelessWidget {
  final String label;
  final int count;
  final bool active;
  final VoidCallback onTap;
  const _TabChip(
      {required this.label,
      required this.count,
      required this.active,
      required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: active ? cInk : cSurface,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: active ? cInk : cLine),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(label,
                style: manrope(12.5, FontWeight.w700,
                    color: active ? Colors.white : cInk2)),
            if (count > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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

// ── Order card ─────────────────────────────────────────────────────────────────
class _OrderCard extends StatefulWidget {
  final OrderModel order;
  const _OrderCard({required this.order});

  @override
  State<_OrderCard> createState() => _OrderCardState();
}

class _OrderCardState extends State<_OrderCard> {
  bool _showQr = false;
  bool _cancelling = false;
  bool _uploading = false;

  OrderModel get o => widget.order;

  String get _statusTone {
    switch (o.status) {
      case OrderModel.statusRejected:
        return 'red';
      case OrderModel.statusPending:
        return 'amber';
      case OrderModel.statusReserved:
        return 'blue';
      case OrderModel.statusConfirmed:
      case OrderModel.statusReady:
      case OrderModel.statusCompleted:
        return 'green';
      case OrderModel.statusCancelled:
        return 'red';
      default:
        return 'gray';
    }
  }

  String get _statusLabel {
    switch (o.status) {
      case OrderModel.statusPending:
        return o.receiptUrl.isEmpty ? 'Ожидает чека' : 'На проверке';
      case OrderModel.statusReserved:
        return 'Бронь подтверждена';
      case OrderModel.statusRejected:
        return 'Чек отклонён';
      case OrderModel.statusConfirmed:
        return 'Оплачено · Готов';
      case OrderModel.statusReady:
        return 'Готов';
      case OrderModel.statusCompleted:
        return 'Выдан';
      case OrderModel.statusCancelled:
        return 'Отменён';
      default:
        return o.status;
    }
  }

  IconData get _statusIcon {
    switch (o.status) {
      case OrderModel.statusRejected:
        return Icons.cancel_outlined;
      case OrderModel.statusPending:
        return Icons.access_time_rounded;
      case OrderModel.statusReserved:
        return Icons.lock_clock_outlined;
      case OrderModel.statusConfirmed:
        return Icons.check_circle_outline_rounded;
      default:
        return Icons.check_circle_outline_rounded;
    }
  }

  String get _typeLabel {
    switch (o.orderType) {
      case OrderModel.typeClickCollect:
        return 'Click & Collect';
      case OrderModel.typeSmartReservation:
        return 'Смарт-Бронь';
      case OrderModel.typeDelivery:
        return 'Доставка';
      default:
        return o.orderType;
    }
  }

  String get _typeTone {
    switch (o.orderType) {
      case OrderModel.typeClickCollect:
        return 'green';
      case OrderModel.typeDelivery:
        return 'amber';
      default:
        return 'blue';
    }
  }

  bool get _canCancel =>
      o.status == OrderModel.statusPending ||
      o.status == OrderModel.statusReserved ||
      o.status == OrderModel.statusRejected;

  bool get _showQrBtn =>
      (o.isSmartReservation && o.status == OrderModel.statusReserved) ||
      (o.isClickCollect &&
          o.status == OrderModel.statusConfirmed);

  bool get _needsReceipt =>
      o.status == OrderModel.statusPending && o.receiptUrl.isEmpty;

  bool get _canResubmit => o.status == OrderModel.statusRejected;

  Future<void> _cancel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Отменить заказ',
            style: manrope(17, FontWeight.w700, color: cInk)),
        content: Text('Отменить этот заказ?',
            style: manrope(14, FontWeight.w500, color: cInk2)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Нет',
                  style: manrope(14, FontWeight.w600, color: cInk2))),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('Да', style: manrope(14, FontWeight.w600, color: cRed))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _cancelling = true);
    try {
      await ClientService().cancelOrder(o);
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

  Future<void> _pickAndUploadReceipt() async {
    // iOS Safari требует нативного HTML file input вместо file_picker
    if (kIsWeb) {
      _pickFileWeb();
    } else {
      _pickFileNative();
    }
  }

  void _pickFileWeb() {
    final html.InputElement input = html.document.createElement('input') as html.InputElement;
    input.type = 'file';
    input.accept = 'image/*,.pdf';
    input.onChange.listen((event) async {
      final files = input.files;
      if (files == null || files.isEmpty) return;

      final file = files[0];
      final reader = html.FileReader();
      reader.onLoadEnd.listen((_) async {
        if (!mounted) return;
        final bytes = reader.result as List<int>;
        
        setState(() => _uploading = true);
        try {
          final url = await CloudinaryService().uploadReceiptBytes(bytes, file.name);
          if (!mounted) return;
          final svc = FirestoreService();
          if (o.status == OrderModel.statusRejected) {
            await svc.resubmitReceipt(o, url);
          } else {
            await svc.submitReceipt(o, url);
          }
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Чек отправлен, ожидайте подтверждения'),
              behavior: SnackBarBehavior.floating,
            ));
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Ошибка: ${e.toString()}'),
              behavior: SnackBarBehavior.floating,
            ));
          }
        } finally {
          if (mounted) setState(() => _uploading = false);
        }
      });
      reader.readAsArrayBuffer(file);
    });
    input.click();
  }

  Future<void> _pickFileNative() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
      withData: true,
    );
    if (res == null || res.files.isEmpty || !mounted) return;
    final f = res.files.single;
    if (f.bytes == null) return;

    setState(() => _uploading = true);
    try {
      final url = await CloudinaryService().uploadReceiptBytes(f.bytes!, f.name);
      if (!mounted) return;
      final svc = FirestoreService();
      if (o.status == OrderModel.statusRejected) {
        await svc.resubmitReceipt(o, url);
      } else {
        await svc.submitReceipt(o, url);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Чек отправлен, ожидайте подтверждения'),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Ошибка загрузки: $e'),
          backgroundColor: cRed,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _open2Gis(String address) async {
    final encoded = Uri.encodeComponent(address);
    final dgis = Uri.parse('dgis://2gis.ru/search/$encoded');
    if (await canLaunchUrl(dgis)) {
      await launchUrl(dgis);
    } else {
      await launchUrl(
        Uri.parse('https://2gis.kz/search/$encoded'),
        mode: LaunchMode.externalApplication,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: o.status == OrderModel.statusRejected
              ? cRed.withValues(alpha: 0.3)
              : cLine,
          width: o.status == OrderModel.statusRejected ? 1.5 : 1,
        ),
        boxShadow: kShadowSm,
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Header row: number + status
          Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  o.orderNumber > 0
                      ? '#${o.orderNumber.toString().padLeft(5, '0')}'
                      : '#—',
                  style: manrope(15.5, FontWeight.w800, color: cInk),
                ),
                QPill(
                  _statusLabel,
                  tone: _statusTone,
                  icon: Icon(_statusIcon,
                      size: 13,
                      color: _statusTone == 'blue'
                          ? const Color(0xFF1A5BD0)
                          : _statusTone == 'green'
                              ? cGreenDeep
                              : _statusTone == 'amber'
                                  ? const Color(0xFF92400E)
                                  : const Color(0xFFB11A2B)),
                ),
              ]),

          const SizedBox(height: 10),

          // Store name + type + total
          Row(children: [
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(o.storeName,
                        style: manrope(13.5, FontWeight.w700, color: cInk),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    QPill(_typeLabel, tone: _typeTone),
                  ]),
            ),
            const SizedBox(width: 12),
            Text(money(o.total),
                style: manrope(15, FontWeight.w800, color: cInk)),
          ]),

          // Items summary
          if (o.items.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(height: 1, color: cLine2),
            const SizedBox(height: 8),
            ...o.items.map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Row(children: [
                    Expanded(
                        child: Text(
                      '${item.productName}  (${item.size})',
                      style: manrope(12.5, FontWeight.w500, color: cInk2),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    )),
                    Text(
                      '×${item.qty}  ${item.subtotal.toStringAsFixed(0)} ₸',
                      style: manrope(12, FontWeight.w600, color: cInk3),
                    ),
                  ]),
                )),
          ],

          // SmartRes deposit info
          if (o.isSmartReservation && o.depositAmount > 0) ...[
            const SizedBox(height: 6),
            Container(height: 1, color: cLine2),
            const SizedBox(height: 6),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Депозит (10%)',
                  style: manrope(12, FontWeight.w500, color: cInk2)),
              Text('${o.depositAmount.toStringAsFixed(0)} ₸',
                  style: manrope(12, FontWeight.w600, color: cGreen)),
            ]),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Доплата в магазине',
                  style: manrope(12, FontWeight.w500, color: cInk2)),
              Text('${o.remainingAmount.toStringAsFixed(0)} ₸',
                  style: manrope(12, FontWeight.w700, color: cAmber)),
            ]),
          ],

          // Rejection reason block
          if (o.status == OrderModel.statusRejected &&
              o.rejectionReason.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: cRedTint,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: cRed.withValues(alpha: 0.2)),
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.error_outline, color: cRed, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Причина отклонения: ${o.rejectionReason}',
                    style: manrope(12, FontWeight.w500, color: cRed),
                  ),
                ),
              ]),
            ),
          ],

          // Payment card requisites (shown when payment is needed)
          if (_needsReceipt || _canResubmit) ...[
            const SizedBox(height: 8),
            _PaymentCardBlock(order: o),
          ],

          // Pending without receipt — upload hint
          if (_needsReceipt) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: cAmber.withValues(alpha: 0.3)),
              ),
              child: Row(children: [
                const Icon(Icons.upload_file_outlined, color: cAmber, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Прикрепите чек об оплате, чтобы подтвердить заказ',
                    style: manrope(12, FontWeight.w500,
                        color: const Color(0xFF92400E)),
                  ),
                ),
              ]),
            ),
          ],

          // Pickup address
          if (!o.isDelivery && o.warehouseAddress.isNotEmpty) ...[
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => _open2Gis(o.warehouseAddress),
              child: Row(children: [
                const Icon(Icons.location_on_outlined, color: cGreen, size: 14),
                const SizedBox(width: 4),
                Expanded(
                    child: Text(o.warehouseAddress,
                        style: manrope(12, FontWeight.w500, color: cGreen,
                            letterSpacing: -0.2),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis)),
                const Icon(Icons.open_in_new_rounded, color: cGreen, size: 12),
              ]),
            ),
          ],

          // Countdown таймері (deadlineAt бар болса — чек жіберу / бронь)
          if (o.deadlineAt != null &&
              (o.status == OrderModel.statusPending ||
                  o.status == OrderModel.statusRejected ||
                  o.status == OrderModel.statusReserved)) ...[
            const SizedBox(height: 6),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              ReservationTimerWidget(
                expiresAt: o.deadlineAt!,
                onExpired: () {
                  // auto-cancel орын-жерде жоқ, UI жайлап stream арқылы жаңарады
                },
              ),
            ]),
          ],

          // QR section (expanded)
          if (_showQr) ...[
            const SizedBox(height: 12),
            Center(
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cSurface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: cLine),
                ),
                child: QrImageView(
                  data: o.orderNumber.toString(),
                  version: QrVersions.auto,
                  size: 160,
                  backgroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                o.orderNumber > 0
                    ? '#${o.orderNumber.toString().padLeft(5, '0')}'
                    : '',
                style:
                    manrope(22, FontWeight.w800, color: cInk, letterSpacing: 2),
              ),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text('Покажите продавцу этот QR код',
                  style: manrope(12, FontWeight.w500, color: cInk2)),
            ),
          ],

          // Action buttons
          const SizedBox(height: 10),

          // QR button for confirmed click&collect / reserved smart-res
          if (_showQrBtn)
            QSoftButton(
              label: _showQr ? 'Скрыть QR-код' : 'Показать QR-код',
              height: 44,
              icon: Icon(
                _showQr ? Icons.visibility_off_outlined : Icons.qr_code_rounded,
                color: cGreenDeep,
                size: 18,
              ),
              onPressed: () => setState(() => _showQr = !_showQr),
            ),

          // Upload receipt button
          if (_needsReceipt || _canResubmit) ...[
            if (_showQrBtn) const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton.icon(
                onPressed: _uploading ? null : _pickAndUploadReceipt,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _canResubmit ? cRed : cGreen,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(11)),
                  elevation: 0,
                ),
                icon: _uploading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : Icon(
                        _canResubmit
                            ? Icons.upload_file_outlined
                            : Icons.attach_file_rounded,
                        size: 18),
                label: Text(
                  _uploading
                      ? 'Загрузка...'
                      : _canResubmit
                          ? 'Загрузить новый чек'
                          : 'Прикрепить чек об оплате',
                  style: manrope(13, FontWeight.w700),
                ),
              ),
            ),
          ],

          if (_canCancel) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 40,
              child: OutlinedButton(
                onPressed: _cancelling ? null : _cancel,
                style: OutlinedButton.styleFrom(
                  foregroundColor: cRed,
                  side: const BorderSide(color: cRed),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(11)),
                ),
                child: _cancelling
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            color: cRed, strokeWidth: 2))
                    : Text('Отменить заказ',
                        style: manrope(13, FontWeight.w700, color: cRed)),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}

// ── Payment card block ─────────────────────────────────────────────────────────
class _PaymentCardBlock extends StatelessWidget {
  final OrderModel order;
  const _PaymentCardBlock({required this.order});

  String _masked(String digits) {
    if (digits.length < 4) return digits;
    final buf = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      if (i > 0 && i % 4 == 0) buf.write(' ');
      buf.write(digits[i]);
    }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    final cardNumber = order.paymentCardNumber;
    final cardHolder = order.paymentCardHolder;
    final bank = order.paymentBank;

    if (cardNumber.isEmpty && cardHolder.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBEB),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: cAmber.withValues(alpha: 0.3)),
        ),
        child: Row(children: [
          const Icon(Icons.credit_card_outlined, color: cAmber, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Продавец ещё не указал реквизиты, свяжитесь с продавцом',
              style: manrope(12, FontWeight.w500,
                  color: const Color(0xFF92400E)),
            ),
          ),
        ]),
      );
    }

    final masked = _masked(cardNumber);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cGreenTint,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cGreen.withValues(alpha: 0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.credit_card_outlined, color: cGreen, size: 16),
          const SizedBox(width: 6),
          Text('Карта для оплаты',
              style: manrope(12, FontWeight.w600, color: cGreenDeep)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(masked,
                  style: manrope(16, FontWeight.w800, color: cInk,
                      letterSpacing: 1)),
              if (cardHolder.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(cardHolder,
                    style: manrope(12, FontWeight.w600, color: cInk2)),
              ],
              if (bank.isNotEmpty) ...[
                const SizedBox(height: 1),
                Text(bank,
                    style: manrope(11, FontWeight.w500, color: cInk3)),
              ],
            ]),
          ),
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: cardNumber));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Номер карты скопирован'),
                behavior: SnackBarBehavior.floating,
                duration: Duration(seconds: 2),
              ));
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: cGreen,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.copy_rounded, color: Colors.white, size: 14),
                const SizedBox(width: 4),
                Text('Копировать',
                    style: manrope(11, FontWeight.w700, color: Colors.white)),
              ]),
            ),
          ),
        ]),
      ]),
    );
  }
}
