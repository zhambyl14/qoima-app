import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/app_user.dart';
import '../../data/models/order_model.dart';
import '../../data/services/client_service.dart';
import '../../theme/app_theme.dart';
import 'reservation_timer_widget.dart';

class ClientOrdersScreen extends StatelessWidget {
  const ClientOrdersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final phone = context.read<AppUser>().phone;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Тапсырыстар'),
        backgroundColor: AppTheme.primary,
      ),
      body: phone.isEmpty
          ? const Center(
              child: Text('Телефон нөмірі жоқ',
                  style: TextStyle(color: AppTheme.textSecondary)))
          : StreamBuilder<List<OrderModel>>(
              stream: ClientService().watchClientOrders(phone),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(
                      child:
                          CircularProgressIndicator(color: AppTheme.primary));
                }
                final orders = snap.data ?? [];
                if (orders.isEmpty) {
                  return const Center(
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.receipt_long_outlined,
                              size: 64, color: AppTheme.textHint),
                          SizedBox(height: 16),
                          Text('Тапсырыс жоқ',
                              style: TextStyle(
                                  fontSize: 16, color: AppTheme.textSecondary)),
                        ]),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: orders.length,
                  itemBuilder: (_, i) => _OrderCard(order: orders[i]),
                );
              },
            ),
    );
  }
}

class _OrderCard extends StatefulWidget {
  final OrderModel order;
  const _OrderCard({required this.order});

  @override
  State<_OrderCard> createState() => _OrderCardState();
}

class _OrderCardState extends State<_OrderCard> {
  bool _cancelling = false;

  Color get _statusColor {
    switch (widget.order.status) {
      case OrderModel.statusReserved:
        return const Color(0xFF3B82F6);
      case OrderModel.statusPending:
        return AppTheme.warning;
      case OrderModel.statusConfirmed:
        return AppTheme.primary;
      case OrderModel.statusReady:
        return AppTheme.success;
      case OrderModel.statusCompleted:
        return AppTheme.success;
      case OrderModel.statusCancelled:
        return AppTheme.danger;
      default:
        return AppTheme.textHint;
    }
  }

  String get _statusLabel {
    switch (widget.order.status) {
      case OrderModel.statusReserved:
        return 'Брондалды';
      case OrderModel.statusPending:
        return 'Күтуде';
      case OrderModel.statusConfirmed:
        return 'Расталды';
      case OrderModel.statusReady:
        return 'Дайын';
      case OrderModel.statusCompleted:
        return 'Аяқталды';
      case OrderModel.statusCancelled:
        return 'Бас тартылды';
      default:
        return widget.order.status;
    }
  }

  String get _typeLabel {
    switch (widget.order.orderType) {
      case OrderModel.typeClickCollect:
        return 'Click & Collect';
      case OrderModel.typeSmartReservation:
        return 'Смарт-Бронь';
      case OrderModel.typeDelivery:
        return 'Доставка';
      default:
        return widget.order.orderType;
    }
  }

  Future<void> _cancel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Тапсырысты бас тарту'),
        content: const Text('Тапсырыстан бас тартқыңыз келеді ме?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Жоқ')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child:
                  const Text('Иә', style: TextStyle(color: AppTheme.danger))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _cancelling = true);
    try {
      await ClientService().cancelOrder(widget.order);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString()),
          backgroundColor: AppTheme.danger,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  bool get _canCancel =>
      widget.order.status == OrderModel.statusReserved ||
      widget.order.status == OrderModel.statusPending;

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
    final order = widget.order;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header row
        Row(children: [
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(order.storeName,
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary)),
              if (order.orderNumber > 0)
                Text('#${order.orderNumber.toString().padLeft(5, '0')}',
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textHint)),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
                color: _statusColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6)),
            child: Text(_statusLabel,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: _statusColor)),
          ),
        ]),
        const SizedBox(height: 2),
        Text(_typeLabel,
            style:
                const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
        const SizedBox(height: 8),

        // Items
        ...order.items.map((item) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(children: [
                Expanded(
                    child: Text('${item.productName}  (${item.size})',
                        style: const TextStyle(
                            fontSize: 13, color: AppTheme.textPrimary))),
                Text('×${item.qty}  ${item.subtotal.toStringAsFixed(0)} ₸',
                    style: const TextStyle(
                        fontSize: 12, color: AppTheme.textSecondary)),
              ]),
            )),

        const Divider(height: 16),

        // Payment summary
        if (order.isSmartReservation) ...[
          _PayRow('Тауар сомасы', '${order.total.toStringAsFixed(0)} ₸'),
          _PayRow(
              'Төленген депозит', '${order.depositAmount.toStringAsFixed(0)} ₸',
              color: const Color(0xFF3B82F6)),
          _PayRow(
              'Дүкенде қалады', '${order.remainingAmount.toStringAsFixed(0)} ₸',
              color: AppTheme.textSecondary),
        ] else if (order.isDelivery) ...[
          _PayRow('Тауар', '${order.total.toStringAsFixed(0)} ₸'),
          _PayRow('Жеткізу', '+${order.deliveryFee.toStringAsFixed(0)} ₸',
              color: const Color(0xFFF59E0B)),
          _PayRow('Барлығы', '${order.totalWithDelivery.toStringAsFixed(0)} ₸',
              bold: true),
        ] else
          _PayRow('Төленді', '${order.total.toStringAsFixed(0)} ₸',
              bold: true, color: AppTheme.success),

        // Warehouse address for SmartRes / ClickCollect
        if (!order.isDelivery && order.warehouseAddress.isNotEmpty) ...[
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => _open2Gis(order.warehouseAddress),
            child: Row(children: [
              const Icon(Icons.location_on_outlined,
                  color: AppTheme.primary, size: 14),
              const SizedBox(width: 4),
              Expanded(
                  child: Text(order.warehouseAddress,
                      style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.primary,
                          decoration: TextDecoration.underline))),
              const Icon(Icons.open_in_new_rounded,
                  color: AppTheme.primary, size: 12),
            ]),
          ),
        ],

        // Timer for active SmartReservation
        if (order.isSmartReservation &&
            order.status == OrderModel.statusReserved) ...[
          const SizedBox(height: 6),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            ReservationTimerWidget(expiresAt: order.expiresAt),
          ]),
        ],

        // QR code for SmartReservation (reserved status)
        if (order.isSmartReservation &&
            order.status == OrderModel.statusReserved) ...[
          const SizedBox(height: 12),
          Center(
              child: QrImageView(
            data: order.orderNumber.toString(),
            version: QrVersions.auto,
            size: 140,
            backgroundColor: Colors.white,
          )),
          const SizedBox(height: 4),
          Center(
              child: Text(
            '#${order.orderNumber.toString().padLeft(5, '0')}',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: AppTheme.primary,
              letterSpacing: 2,
            ),
          )),
          const Center(
              child: Text('Сатушыға осы QR кодты көрсетіңіз',
                  style:
                      TextStyle(fontSize: 11, color: AppTheme.textSecondary))),
        ],

        // QR code for Click & Collect (non-cancelled)
        if (order.isClickCollect &&
            order.status != OrderModel.statusCancelled &&
            order.status != OrderModel.statusCompleted) ...[
          const SizedBox(height: 12),
          Center(
              child: QrImageView(
            data: order.orderNumber.toString(),
            version: QrVersions.auto,
            size: 140,
            backgroundColor: Colors.white,
          )),
          const SizedBox(height: 4),
          Center(
              child: Text(
            '#${order.orderNumber.toString().padLeft(5, '0')}',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: AppTheme.primary,
              letterSpacing: 2,
            ),
          )),
          const Center(
              child: Text('Дүкенге осы QR кодты көрсетіңіз',
                  style:
                      TextStyle(fontSize: 11, color: AppTheme.textSecondary))),
        ],

        // Cancel button
        if (_canCancel) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 40,
            child: OutlinedButton(
              onPressed: _cancelling ? null : _cancel,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.danger,
                side: const BorderSide(color: AppTheme.danger),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: _cancelling
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          color: AppTheme.danger, strokeWidth: 2))
                  : const Text('Бас тарту', style: TextStyle(fontSize: 13)),
            ),
          ),
        ],
      ]),
    );
  }
}

class _PayRow extends StatelessWidget {
  final String label, value;
  final Color? color;
  final bool bold;
  const _PayRow(this.label, this.value, {this.color, this.bold = false});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child:
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label,
              style:
                  const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
          Text(value,
              style: TextStyle(
                  fontSize: bold ? 14 : 12,
                  fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                  color: color ?? AppTheme.textPrimary)),
        ]),
      );
}
