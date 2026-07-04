import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/app_user.dart';
import '../../data/models/order_model.dart';
import '../../data/models/return_model.dart';
import '../../data/services/client_service.dart';
import '../../data/services/firestore_service.dart';
import '../../data/services/return_service.dart';
import '../../core/order_helpers.dart';
import '../../theme/qoima_design.dart';
import 'reservation_timer_widget.dart';
import 'returns/client_return_form_screen.dart';
import 'returns/client_returns_history_screen.dart';

import '../../core/lang.dart';
class ClientOrdersScreen extends StatefulWidget {
  final VoidCallback? onBack;
  const ClientOrdersScreen({super.key, this.onBack});

  @override
  State<ClientOrdersScreen> createState() => _ClientOrdersScreenState();
}

class _ClientOrdersScreenState extends State<ClientOrdersScreen> {
  int _tabIndex = 0; // 0=active, 1=completed, 2=returns

  final ClientService _service = ClientService();
  // v11: тапсырыстар clientUid бойынша сұралады (email-auth токенінде телефон жоқ).
  late final String _uid = AppUser.current.uid;
  late final Stream<List<OrderModel>> _ordersStream =
      _service.watchClientOrders(_uid);
  late final Stream<List<ReturnModel>> _returnsStream =
      ReturnService().watchClientReturns(AppUser.current.uid);

  @override
  Widget build(BuildContext context) {
    final uid = _uid;

    return Scaffold(
      backgroundColor: cBg,
      body: Column(children: [
        QGradientHeader(
          title: tr('Мои заказы', 'Тапсырыстарым'),
          subtitle: tr('История покупок', 'Сатып алу тарихы'),
          compact: true,
          showBack: true,
          onBack: widget.onBack,
        ),
        Expanded(
          child: uid.isEmpty
              ? Center(
                  child: Text(tr('Требуется вход', 'Кіру қажет'),
                      style: manrope(15, FontWeight.w500, color: cInk2)))
              : StreamBuilder<List<ReturnModel>>(
                  stream: _returnsStream,
                  builder: (context, retSnap) {
                    // Бір тапсырыс — бір рет қана қайтарылады. Сондықтан БАС ТАРТЫЛҒАН
                    // (rejected) емес кез келген қайтару тапсырысты қайта қайтаруға
                    // жабады (өңделуде де, қайтарылған да). Кілт → соңғы статус.
                    final returnStatusByOrder = <String, ReturnStatus>{};
                    for (final r in (retSnap.data ?? [])) {
                      final oid = r.orderId;
                      if (oid == null || oid.isEmpty) continue;
                      if (r.status == ReturnStatus.rejected) continue;
                      // retSnap тізімі createdAt бойынша кему ретімен — алғашқысы соңғы
                      returnStatusByOrder.putIfAbsent(oid, () => r.status);
                    }

                    return StreamBuilder<List<OrderModel>>(
                      stream: _ordersStream,
                      builder: (context, snap) {
                        if (snap.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                              child: CircularProgressIndicator(
                                  color: cGreen));
                        }
                        final all = snap.data ?? [];

                        for (final o in all) {
                          if (o.isExpired) {
                            _service.cancelOrder(o).ignore();
                          }
                        }

                        final active = all
                            .where((o) =>
                                o.status == OrderModel.statusPending ||
                                o.status == OrderModel.statusReserved ||
                                o.status == OrderModel.statusRejected ||
                                o.status == OrderModel.statusConfirmed ||
                                o.status == OrderModel.statusReady)
                            .toList();

                        final completed = all
                            .where((o) =>
                                o.status ==
                                    OrderModel.statusCompleted ||
                                o.status ==
                                    OrderModel.statusCancelled ||
                                o.status ==
                                    OrderModel.statusReturned)
                            .toList();

                        return Column(children: [
                          Padding(
                            padding:
                                const EdgeInsets.fromLTRB(16, 14, 16, 4),
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(children: [
                                _TabChip(
                                  label: tr('Активные', 'Белсенді'),
                                  count: active.length,
                                  active: _tabIndex == 0,
                                  onTap: () =>
                                      setState(() => _tabIndex = 0),
                                ),
                                const SizedBox(width: 8),
                                _TabChip(
                                  label: tr('Завершённые', 'Аяқталған'),
                                  count: completed.length,
                                  active: _tabIndex == 1,
                                  onTap: () =>
                                      setState(() => _tabIndex = 1),
                                ),
                                const SizedBox(width: 8),
                                _TabChip(
                                  label: tr('Возвраты', 'Қайтарулар'),
                                  count: retSnap.data?.length ?? 0,
                                  active: _tabIndex == 2,
                                  onTap: () =>
                                      setState(() => _tabIndex = 2),
                                ),
                              ]),
                            ),
                          ),
                          Expanded(
                            child: _tabIndex == 2
                                ? const ClientReturnsHistoryScreen()
                                : _buildOrderList(
                                    context,
                                    _tabIndex == 0
                                        ? active
                                        : completed,
                                    returnStatusByOrder,
                                  ),
                          ),
                        ]);
                      },
                    );
                  },
                ),
        ),
      ]),
    );
  }

  Widget _buildOrderList(BuildContext context, List<OrderModel> orders,
      Map<String, ReturnStatus> returnStatusByOrder) {
    if (orders.isEmpty) {
      return Center(
          child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
            const Icon(Icons.receipt_long_outlined,
                size: 56, color: cInk3),
            const SizedBox(height: 12),
            Text(tr('Заказов нет', 'Тапсырыс жоқ'),
                style: manrope(16, FontWeight.w500, color: cInk2)),
          ]));
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      itemCount: orders.length,
      itemBuilder: (_, i) {
        final o = orders[i];
        // 14-day window: use createdAt as proxy since there is no completedAt field.
        final withinWindow = DateTime.now()
                .difference(o.createdAt)
                .inDays <=
            14;
        final canReturn = o.status == OrderModel.statusCompleted &&
            withinWindow;
        final returnStatus =
            o.id.isNotEmpty ? returnStatusByOrder[o.id] : null;
        final hasReturn = returnStatus != null;
        // Қайтарылған (refunded) — аяқталған; басқасы (requested/approved/received)
        // — өңделуде. Екеуінде де қайтаруды қайталауға болмайды.
        final returnDone = returnStatus == ReturnStatus.refunded;
        return _OrderCard(
          order: o,
          canReturn: canReturn,
          hasActiveReturn: hasReturn,
          returnDone: returnDone,
          onReturnTap: canReturn && !hasReturn
              ? () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) =>
                          ClientReturnFormScreen(order: o)))
              : null,
        );
      },
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
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
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
  final bool canReturn;
  final bool hasActiveReturn;
  final bool returnDone;
  final VoidCallback? onReturnTap;
  const _OrderCard({
    required this.order,
    this.canReturn = false,
    this.hasActiveReturn = false,
    this.returnDone = false,
    this.onReturnTap,
  });

  @override
  State<_OrderCard> createState() => _OrderCardState();
}

class _OrderCardState extends State<_OrderCard> {
  bool _showQr = false;
  bool _cancelling = false;
  bool _uploading = false;

  OrderModel get o => widget.order;

  String get _statusTone => orderStatusTone(o.status);
  String get _statusLabel => orderStatusLabel(o.status);

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
        return tr('Доставка', 'Жеткізу');
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
      (o.isClickCollect && o.status == OrderModel.statusConfirmed);

  bool get _needsReceipt =>
      o.status == OrderModel.statusPending && o.receiptUrl.isEmpty;

  Future<void> _cancel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(tr('Отменить заказ', 'Тапсырысты болдырмау'),
            style: manrope(17, FontWeight.w700, color: cInk)),
        content: Text(tr('Отменить этот заказ?', 'Осы тапсырысты болдырмау керек пе?'),
            style: manrope(14, FontWeight.w500, color: cInk2)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr('Нет', 'Жоқ'),
                  style: manrope(14, FontWeight.w600, color: cInk2))),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr('Да', 'Иә'),
                  style: manrope(14, FontWeight.w600, color: cRed))),
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

  Future<void> _payOnline(String method) async {
    Navigator.pop(context);
    setState(() => _uploading = true);
    try {
      await FirestoreService().confirmPaymentByClient(o, method);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString()),
          backgroundColor: cRed,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _showPaymentSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Text(tr('Способ оплаты', 'Төлем тәсілі'),
              style: manrope(18, FontWeight.w800, color: cInk)),
          const SizedBox(height: 4),
          Text(tr('Выберите банк для перевода', 'Аударым үшін банк таңдаңыз'),
              style: manrope(13, FontWeight.w500, color: cInk2)),
          const SizedBox(height: 20),
          _PayMethodBtn(
            label: 'Kaspi',
            color: const Color(0xFFEB3333),
            onTap: () => _payOnline('kaspi'),
          ),
          const SizedBox(height: 12),
          _PayMethodBtn(
            label: 'Halyk Bank',
            color: const Color(0xFF00A550),
            onTap: () => _payOnline('halyk'),
          ),
          const SizedBox(height: 4),
        ]),
      ),
    );
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

  Future<void> _callPhone(String phone) async {
    final digits = phone.replaceAll(RegExp(r'[^\d+]'), '');
    if (digits.isEmpty) return;
    final uri = Uri.parse('tel:$digits');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
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
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
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

          // Чек нөмірі (заказ нөмірінен бөлек) — тауар берілгенде беріледі
          if (o.receiptNumber.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(children: [
              const Icon(Icons.receipt_long_outlined, size: 13, color: cInk3),
              const SizedBox(width: 4),
              Text('Чек: ${o.receiptNumber}',
                  style: manrope(12, FontWeight.w600, color: cInk2)),
            ]),
          ],

          const SizedBox(height: 10),

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
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              if (o.promoDiscount > 0)
                Text(money(o.total),
                    style: manrope(11.5, FontWeight.w500, color: cInk3)
                        .copyWith(decoration: TextDecoration.lineThrough)),
              Text(money(o.finalTotal),
                  style: manrope(15, FontWeight.w800, color: cInk)),
            ]),
          ]),

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

          if (o.promoDiscount > 0) ...[
            const SizedBox(height: 6),
            Container(height: 1, color: cLine2),
            const SizedBox(height: 6),
            Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Промокод ${o.promoCode}',
                      style: manrope(12, FontWeight.w500, color: cInk2)),
                  Text('−${money(o.promoDiscount)}',
                      style: manrope(12, FontWeight.w700, color: cGreen)),
                ]),
          ],

          if (o.isSmartReservation && o.depositAmount > 0) ...[
            const SizedBox(height: 6),
            Container(height: 1, color: cLine2),
            const SizedBox(height: 6),
            Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Депозит (10%)',
                      style: manrope(12, FontWeight.w500, color: cInk2)),
                  Text('${o.depositAmount.toStringAsFixed(0)} ₸',
                      style: manrope(12, FontWeight.w600, color: cGreen)),
                ]),
            Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(tr('Доплата в магазине', 'Дүкенде доплата'),
                      style: manrope(12, FontWeight.w500, color: cInk2)),
                  Text('${o.remainingAmount.toStringAsFixed(0)} ₸',
                      style: manrope(12, FontWeight.w700, color: cAmber)),
                ]),
          ],

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
              child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.error_outline, color: cRed, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        tr('Причина отклонения: ${o.rejectionReason}', 'Қабылданбау себебі: ${o.rejectionReason}'),
                        style: manrope(12, FontWeight.w500, color: cRed),
                      ),
                    ),
                  ]),
            ),
          ],

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
                const Icon(Icons.payment_outlined, color: cAmber, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tr('Оплатите заказ через Kaspi или Halyk Bank', 'Тапсырысты Kaspi немесе Halyk Bank арқылы төлеңіз'),
                    style: manrope(12, FontWeight.w500,
                        color: const Color(0xFF92400E)),
                  ),
                ),
              ]),
            ),
          ],

          if (!o.isDelivery && o.warehouseAddress.isNotEmpty) ...[
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => _open2Gis(o.warehouseAddress),
              child: Row(children: [
                const Icon(Icons.location_on_outlined,
                    color: cGreen, size: 14),
                const SizedBox(width: 4),
                Expanded(
                    child: Text(o.warehouseAddress,
                        style: manrope(12, FontWeight.w500, color: cGreen,
                            letterSpacing: -0.2),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis)),
                const Icon(Icons.open_in_new_rounded,
                    color: cGreen, size: 12),
              ]),
            ),
          ],

          if (!o.isDelivery && o.storePhone.isNotEmpty) ...[
            const SizedBox(height: 6),
            GestureDetector(
              onTap: () => _callPhone(o.storePhone),
              child: Row(children: [
                const Icon(Icons.phone_outlined, color: cGreen, size: 14),
                const SizedBox(width: 4),
                Expanded(
                    child: Text(tr('Магазин: ${o.storePhone}', 'Дүкен: ${o.storePhone}'),
                        style: manrope(12, FontWeight.w500, color: cGreen,
                            letterSpacing: -0.2),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis)),
                const Icon(Icons.call_rounded, color: cGreen, size: 12),
              ]),
            ),
          ],

          if (o.deadlineAt != null &&
              (o.status == OrderModel.statusPending ||
                  o.status == OrderModel.statusRejected ||
                  o.status == OrderModel.statusReserved)) ...[
            const SizedBox(height: 6),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              ReservationTimerWidget(
                expiresAt: o.deadlineAt!,
                onExpired: () {},
              ),
            ]),
          ],

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
                style: manrope(22, FontWeight.w800, color: cInk,
                    letterSpacing: 2),
              ),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text(tr('Покажите продавцу этот QR код', 'Сатушыға осы QR кодты көрсетіңіз'),
                  style: manrope(12, FontWeight.w500, color: cInk2)),
            ),
          ],

          const SizedBox(height: 10),

          if (_showQrBtn)
            QSoftButton(
              label: _showQr ? tr('Скрыть QR-код', 'QR-кодты жасыру') : tr('Показать QR-код', 'QR-кодты көрсету'),
              height: 44,
              icon: Icon(
                _showQr
                    ? Icons.visibility_off_outlined
                    : Icons.qr_code_rounded,
                color: cGreenDeep,
                size: 18,
              ),
              onPressed: () => setState(() => _showQr = !_showQr),
            ),

          if (_needsReceipt) ...[
            if (_showQrBtn) const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _uploading ? null : _showPaymentSheet,
                style: ElevatedButton.styleFrom(
                  backgroundColor: cGreen,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(11)),
                  elevation: 0,
                ),
                child: _uploading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : Text(tr('Оплатить', 'Төлеу'),
                        style: manrope(14, FontWeight.w700)),
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
                    : Text(tr('Отменить заказ', 'Тапсырысты болдырмау'),
                        style: manrope(13, FontWeight.w700, color: cRed)),
              ),
            ),
          ],

          // Return button for completed orders within 14-day window
          if (widget.canReturn) ...[
            const SizedBox(height: 8),
            if (widget.hasActiveReturn)
              widget.returnDone
                  ? QPill(
                      tr('Возвращён', 'Қайтарылды'),
                      tone: 'green',
                      icon: const Icon(Icons.check_circle_outline_rounded,
                          size: 12, color: cGreenDeep),
                    )
                  : QPill(
                      tr('В обработке', 'Өңдеуде'),
                      tone: 'amber',
                      icon: const Icon(Icons.loop_rounded,
                          size: 12, color: Color(0xFF92400E)),
                    )
            else
              SizedBox(
                width: double.infinity,
                height: 40,
                child: OutlinedButton.icon(
                  onPressed: widget.onReturnTap,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: cGreen,
                    side: BorderSide(color: cGreen.withValues(alpha: 0.5)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(11)),
                  ),
                  icon: const Icon(Icons.assignment_return_outlined,
                      size: 16, color: cGreen),
                  label: Text(tr('Оформить возврат', 'Қайтару жасау'),
                      style: manrope(13, FontWeight.w700, color: cGreen)),
                ),
              ),
          ],
        ]),
      ),
    );
  }
}

// ── Payment method button ─────────────────────────────────────────────────────
class _PayMethodBtn extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _PayMethodBtn(
      {required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
          elevation: 0,
        ),
        child: Text(label,
            style: manrope(15, FontWeight.w700, color: Colors.white)),
      ),
    );
  }
}
