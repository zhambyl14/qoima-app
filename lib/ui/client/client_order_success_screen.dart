import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../data/models/order_model.dart';
import '../../theme/app_theme.dart';

class ClientOrderSuccessScreen extends StatefulWidget {
  final OrderModel order;

  const ClientOrderSuccessScreen({super.key, required this.order});

  @override
  State<ClientOrderSuccessScreen> createState() =>
      _ClientOrderSuccessScreenState();
}

class _ClientOrderSuccessScreenState extends State<ClientOrderSuccessScreen> {
  Timer? _timer;
  int _minutesLeft = 60;

  @override
  void initState() {
    super.initState();
    if (widget.order.isSmartReservation) {
      _minutesLeft = widget.order.minutesLeft;
      _timer = Timer.periodic(const Duration(minutes: 1), (_) {
        if (!mounted) return;
        setState(() => _minutesLeft = widget.order.minutesLeft);
        if (_minutesLeft <= 0) _timer?.cancel();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  OrderModel get o => widget.order;

  String get _typeLabel {
    switch (o.orderType) {
      case OrderModel.typeSmartReservation:
        return 'Смарт-бронь';
      case OrderModel.typeClickCollect:
        return 'Click & Collect';
      case OrderModel.typeDelivery:
        return 'Доставка';
      default:
        return o.orderType;
    }
  }

  Color get _typeColor {
    switch (o.orderType) {
      case OrderModel.typeSmartReservation:
        return const Color(0xFF3B82F6);
      case OrderModel.typeClickCollect:
        return AppTheme.success;
      case OrderModel.typeDelivery:
        return const Color(0xFFF59E0B);
      default:
        return AppTheme.primary;
    }
  }

  Future<void> _openMaps() async {
    final addr = Uri.encodeComponent(o.warehouseAddress);
    final geoUri = Uri.parse('geo:0,0?q=$addr');
    if (await canLaunchUrl(geoUri)) {
      await launchUrl(geoUri);
    } else {
      final webUri = Uri.parse('https://2gis.kz/search/$addr');
      await launchUrl(webUri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final code = o.pickupCode.isNotEmpty
        ? o.pickupCode
        : o.id.substring(0, 8).toUpperCase();

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.primary,
        title: const Text('Заказ оформлен'),
        leading: IconButton(
          icon: const Icon(Icons.home_rounded),
          onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
        child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
          // ── Success icon ─────────────────────────────────────────────
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppTheme.success.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_circle_rounded,
                color: AppTheme.success, size: 44),
          ),
          const SizedBox(height: 14),
          Text('Заказ принят!',
              style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textPrimary)),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: _typeColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(_typeLabel,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _typeColor)),
          ),
          const SizedBox(height: 24),

          // ── Pickup code card ─────────────────────────────────────────
          if (!o.isDelivery) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 16,
                      offset: const Offset(0, 4))
                ],
              ),
              child: Column(children: [
                const Text('Код получения',
                    style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 8),
                // QR code
                QrImageView(
                  data: code,
                  version: QrVersions.auto,
                  size: 160,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: AppTheme.textPrimary,
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                // Numeric code
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: code));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Код скопирован'),
                      behavior: SnackBarBehavior.floating,
                      duration: Duration(seconds: 1),
                    ));
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: AppTheme.primary.withValues(alpha: 0.2)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(code,
                          style: const TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.primary,
                              letterSpacing: 3)),
                      const SizedBox(width: 10),
                      const Icon(Icons.copy_rounded,
                          color: AppTheme.primary, size: 18),
                    ]),
                  ),
                ),
                const SizedBox(height: 8),
                const Text('Покажите этот код или QR продавцу',
                    style:
                        TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                    textAlign: TextAlign.center),
              ]),
            ),
            const SizedBox(height: 16),
          ],

          // ── Timer (smart reservation only) ──────────────────────────
          if (o.isSmartReservation) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: _minutesLeft <= 10
                    ? AppTheme.dangerLight
                    : const Color(0xFFFFF7ED),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _minutesLeft <= 10
                      ? AppTheme.danger.withValues(alpha: 0.3)
                      : const Color(0xFFF59E0B).withValues(alpha: 0.4),
                ),
              ),
              child: Row(children: [
                Icon(Icons.timer_outlined,
                    color: _minutesLeft <= 10
                        ? AppTheme.danger
                        : const Color(0xFFF59E0B),
                    size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Бронь действует',
                            style: TextStyle(
                                fontSize: 12,
                                color: _minutesLeft <= 10
                                    ? AppTheme.danger
                                    : const Color(0xFFB45309),
                                fontWeight: FontWeight.w500)),
                        Text('$_minutesLeft мин.',
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: _minutesLeft <= 10
                                    ? AppTheme.danger
                                    : const Color(0xFFB45309))),
                      ]),
                ),
              ]),
            ),
            const SizedBox(height: 16),
          ],

          // ── Pickup address card ──────────────────────────────────────
          if (!o.isDelivery && o.warehouseAddress.isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 2))
                ],
              ),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Icon(Icons.store_outlined,
                          color: AppTheme.primary, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(o.storeName,
                              style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.textPrimary))),
                    ]),
                    const SizedBox(height: 8),
                    Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.location_on_outlined,
                              color: AppTheme.textHint, size: 16),
                          const SizedBox(width: 6),
                          Expanded(
                              child: Text(o.warehouseAddress,
                                  style: const TextStyle(
                                      fontSize: 13,
                                      color: AppTheme.textSecondary))),
                        ]),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _openMaps,
                          icon: const Icon(Icons.navigation_outlined, size: 16),
                          label: const Text('Маршрут'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.primary,
                            side: const BorderSide(color: AppTheme.primary),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                      ),
                    ]),
                  ]),
            ),
            const SizedBox(height: 16),
          ],

          // ── Delivery address ─────────────────────────────────────────
          if (o.isDelivery && o.address.isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.local_shipping_outlined,
                    color: AppTheme.primary, size: 18),
                const SizedBox(width: 10),
                Expanded(
                    child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Адрес доставки',
                        style: TextStyle(
                            fontSize: 12, color: AppTheme.textSecondary)),
                    const SizedBox(height: 4),
                    Text(o.address,
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary)),
                  ],
                )),
              ]),
            ),
            const SizedBox(height: 16),
          ],

          // ── Order summary ────────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Состав заказа',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary)),
              const SizedBox(height: 10),
              ...o.items.map((item) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(children: [
                      Expanded(
                          child: Text(
                        '${item.productName}  EU ${item.size}',
                        style: const TextStyle(
                            fontSize: 13, color: AppTheme.textPrimary),
                      )),
                      Text(
                          '×${item.qty}  ${item.subtotal.toStringAsFixed(0)} ₸',
                          style: const TextStyle(
                              fontSize: 12, color: AppTheme.textSecondary)),
                    ]),
                  )),
              const Divider(height: 16),
              if (o.isSmartReservation) ...[
                _SummaryRow('Сумма товаров', '${o.total.toStringAsFixed(0)} ₸'),
                _SummaryRow(
                    'Депозит (10%)', '${o.depositAmount.toStringAsFixed(0)} ₸',
                    valueColor: AppTheme.success),
                _SummaryRow('Доплата в магазине',
                    '${o.remainingAmount.toStringAsFixed(0)} ₸',
                    bold: true),
              ] else if (o.isDelivery) ...[
                _SummaryRow('Товары', '${o.total.toStringAsFixed(0)} ₸'),
                if (o.deliveryFee > 0)
                  _SummaryRow(
                      'Доставка', '${o.deliveryFee.toStringAsFixed(0)} ₸'),
                _SummaryRow('Итого оплачено',
                    '${o.totalWithDelivery.toStringAsFixed(0)} ₸',
                    valueColor: AppTheme.success, bold: true),
              ] else ...[
                _SummaryRow('Итого оплачено', '${o.total.toStringAsFixed(0)} ₸',
                    valueColor: AppTheme.success, bold: true),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label, value;
  final Color? valueColor;
  final bool bold;
  const _SummaryRow(this.label, this.value,
      {this.valueColor, this.bold = false});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child:
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label,
              style:
                  const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
          Text(value,
              style: TextStyle(
                  fontSize: bold ? 15 : 13,
                  fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                  color: valueColor ?? AppTheme.textPrimary)),
        ]),
      );
}
