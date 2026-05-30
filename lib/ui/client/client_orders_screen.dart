import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/app_user.dart';
import '../../data/models/order_model.dart';
import '../../data/services/client_service.dart';
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

                    final active = all.where((o) =>
                        o.status == OrderModel.statusReserved ||
                        o.status == OrderModel.statusPending ||
                        o.status == OrderModel.statusConfirmed ||
                        o.status == OrderModel.statusReady).toList();

                    final completed = all.where((o) =>
                        o.status == OrderModel.statusCompleted ||
                        o.status == OrderModel.statusCancelled).toList();

                    final shown = _tabIndex == 0 ? active : completed;

                    return Column(children: [
                      // Tabs
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

  OrderModel get o => widget.order;

  String get _statusTone {
    switch (o.status) {
      case OrderModel.statusReserved:
      case OrderModel.statusPending:
      case OrderModel.statusConfirmed:
        return 'blue';
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
      case OrderModel.statusReserved:
        return 'Активна';
      case OrderModel.statusPending:
        return 'Ожидание';
      case OrderModel.statusConfirmed:
        return 'Подтверждён';
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
      case OrderModel.statusReserved:
      case OrderModel.statusPending:
        return Icons.access_time_rounded;
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
      o.status == OrderModel.statusReserved ||
      o.status == OrderModel.statusPending;

  bool get _showQrBtn =>
      (o.isSmartReservation && o.status == OrderModel.statusReserved) ||
      (o.isClickCollect &&
          o.status != OrderModel.statusCancelled &&
          o.status != OrderModel.statusCompleted);

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
        border: Border.all(color: cLine),
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

          // Timer (active reservation)
          if (o.isSmartReservation &&
              o.status == OrderModel.statusReserved) ...[
            const SizedBox(height: 6),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              ReservationTimerWidget(expiresAt: o.expiresAt),
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
