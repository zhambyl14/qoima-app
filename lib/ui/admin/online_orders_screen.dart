import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../data/models/order_model.dart';
import '../../data/services/firestore_service.dart';
import '../../theme/qoima_design.dart';
import '../client/reservation_timer_widget.dart';

class OnlineOrdersScreen extends StatefulWidget {
  const OnlineOrdersScreen({super.key});

  @override
  State<OnlineOrdersScreen> createState() => _OnlineOrdersScreenState();
}

class _OnlineOrdersScreenState extends State<OnlineOrdersScreen> {
  final _service = FirestoreService();
  final _codeCtrl = TextEditingController();
  String _filter = 'active';

  // Ағынды бір рет жасаймыз — фильтр басқан сайын (setState) тізім спиннермен
  // қайта жүктелмеуі үшін. Экрандағы үш StreamBuilder осы бір ағынды бөліседі.
  late final Stream<List<OrderModel>> _ordersStream =
      _service.watchOnlineOrders();

  OrderModel? _lookupResult;
  bool _lookupLoading = false;
  String? _lookupError;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _lookup() async {
    final code = _codeCtrl.text.trim();
    if (code.isEmpty) return;
    setState(() {
      _lookupLoading = true;
      _lookupError = null;
      _lookupResult = null;
    });
    try {
      final order = await _service.lookupOnlineOrder(code);
      if (!mounted) return;
      setState(() {
        _lookupResult = order;
        _lookupLoading = false;
        _lookupError =
            order == null ? 'Неверный код или заказ не найден' : null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _lookupError = e.toString();
          _lookupLoading = false;
        });
      }
    }
  }

  List<OrderModel> _applyFilter(List<OrderModel> all) {
    switch (_filter) {
      case 'active':
        return all
            .where((o) =>
                o.status == OrderModel.statusPending ||
                o.status == OrderModel.statusReserved ||
                o.status == OrderModel.statusRejected ||
                o.status == OrderModel.statusConfirmed)
            .toList();
      case 'done':
        return all
            .where((o) => o.status == OrderModel.statusCompleted)
            .toList();
      case 'cancelled':
        return all
            .where((o) => o.status == OrderModel.statusCancelled)
            .toList();
      default:
        return all;
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
              child: Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
                  child: Row(children: [
                    GestureDetector(
                      onTap: () => Navigator.maybePop(context),
                      child: Container(
                        width: 38, height: 38,
                        margin: const EdgeInsets.only(right: 10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.chevron_left_rounded,
                            color: Colors.white, size: 22),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Онлайн-заказы',
                              style: manrope(23, FontWeight.w800,
                                  color: Colors.white, letterSpacing: -0.5)),
                          StreamBuilder<List<OrderModel>>(
                            stream: _ordersStream,
                            builder: (_, s) {
                              final review = (s.data ?? [])
                                  .where((o) => o.isAwaitingReview)
                                  .length;
                              return Text(
                                review > 0
                                    ? 'Ждут проверки: $review'
                                    : 'Нет заказов на проверке',
                                style: manrope(13, FontWeight.w500,
                                    color: Colors.white.withValues(alpha: 0.78)));
                            },
                          ),
                        ],
                      ),
                    ),
                  ]),
                ),

                // Code lookup
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: Row(children: [
                    Expanded(
                      child: Container(
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: TextField(
                          controller: _codeCtrl,
                          onSubmitted: (_) => _lookup(),
                          style: const TextStyle(
                              color: Colors.black87, fontSize: 14),
                          decoration: const InputDecoration(
                            hintText: 'Введите код заказа...',
                            hintStyle:
                                TextStyle(color: Colors.black38, fontSize: 14),
                            prefixIcon: Icon(Icons.qr_code_scanner_rounded,
                                color: cGreen, size: 20),
                            filled: false,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            disabledBorder: InputBorder.none,
                            errorBorder: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _lookupLoading ? null : _lookup,
                      child: Container(
                        height: 44,
                        width: 80,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: _lookupLoading
                            ? const Center(
                                child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        color: cGreen,
                                        strokeWidth: 2)))
                            : const Center(
                                child: Text('Найти',
                                    style: TextStyle(
                                        color: cGreen,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13))),
                      ),
                    ),
                  ]),
                ),

                // Filter tabs
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: StreamBuilder<List<OrderModel>>(
                    stream: _ordersStream,
                    builder: (ctx, snap) {
                      final all = snap.data ?? [];
                      final active = all
                          .where((o) =>
                              o.status == OrderModel.statusPending ||
                              o.status == OrderModel.statusReserved ||
                              o.status == OrderModel.statusConfirmed)
                          .length;
                      final done = all
                          .where((o) => o.status == OrderModel.statusCompleted)
                          .length;
                      final cancelled = all
                          .where((o) => o.status == OrderModel.statusCancelled)
                          .length;

                      return Row(children: [
                        _FilterChip(
                            label: 'Активные $active',
                            value: 'active',
                            current: _filter,
                            onTap: (v) => setState(() {
                                  _filter = v;
                                  _lookupResult = null;
                                })),
                        const SizedBox(width: 8),
                        _FilterChip(
                            label: 'Завершено $done',
                            value: 'done',
                            current: _filter,
                            onTap: (v) => setState(() {
                                  _filter = v;
                                  _lookupResult = null;
                                })),
                        const SizedBox(width: 8),
                        _FilterChip(
                            label: 'Всё ${all.length}',
                            value: 'all',
                            current: _filter,
                            onTap: (v) => setState(() {
                                  _filter = v;
                                  _lookupResult = null;
                                })),
                        const SizedBox(width: 8),
                        _FilterChip(
                            label: 'Отменено $cancelled',
                            value: 'cancelled',
                            current: _filter,
                            onTap: (v) => setState(() {
                                  _filter = v;
                                  _lookupResult = null;
                                })),
                      ]);
                    },
                  ),
                ),
              ])),
        ),

        // ── Body ─────────────────────────────────────────────────────────────
        Expanded(
          child: StreamBuilder<List<OrderModel>>(
            stream: _ordersStream,
            builder: (ctx, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(
                    child: CircularProgressIndicator(color: cGreen));
              }

              final all = snap.data ?? [];

              // Мерзімі өткен тапсырыстарды on-read авто-болдырмаймыз
              for (final o in all) {
                if (o.isExpired &&
                    (o.status == OrderModel.statusRejected ||
                        o.status == OrderModel.statusReserved ||
                        (o.status == OrderModel.statusPending &&
                            o.receiptUrl.isEmpty))) {
                  _service.cancelOnlineOrder(o).ignore();
                }
              }

              return ListView(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 20),
                children: [
                  // Code lookup result
                  if (_lookupError != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cRedTint,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: cRed.withValues(alpha: 0.2)),
                      ),
                      child: Row(children: [
                        const Icon(Icons.error_outline,
                            color: cRed, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Text(_lookupError!,
                                style: const TextStyle(
                                    color: cRed, fontSize: 13))),
                        GestureDetector(
                            onTap: () => setState(() {
                                  _lookupError = null;
                                  _codeCtrl.clear();
                                }),
                            child: const Icon(Icons.close,
                                color: cRed, size: 18)),
                      ]),
                    ),
                    const SizedBox(height: 12),
                  ],

                  if (_lookupResult != null) ...[
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: cGreen, width: 2),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: cGreen,
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(14)),
                          ),
                          child: Row(children: [
                            const Icon(Icons.check_circle_outline,
                                color: Colors.white, size: 16),
                            const SizedBox(width: 8),
                            const Text('Заказ найден',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13)),
                            const Spacer(),
                            GestureDetector(
                                onTap: () => setState(() {
                                      _lookupResult = null;
                                      _codeCtrl.clear();
                                    }),
                                child: const Icon(Icons.close,
                                    color: Colors.white, size: 18)),
                          ]),
                        ),
                        _OrderCard(
                          order: _lookupResult!,
                          service: _service,
                          onChanged: () => setState(() {
                            _lookupResult = null;
                            _codeCtrl.clear();
                          }),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Filtered list
                  ..._applyFilter(all).map((order) => _OrderCard(
                        order: order,
                        service: _service,
                        onChanged: () => setState(() {}),
                      )),

                  if (_applyFilter(all).isEmpty && _lookupResult == null)
                    Padding(
                      padding: const EdgeInsets.only(top: 60),
                      child: Column(children: [
                        Icon(Icons.inbox_outlined,
                            size: 56, color: Colors.grey.shade300),
                        const SizedBox(height: 12),
                        Text(
                          _filter == 'review'
                              ? 'Нет чеков на проверке'
                              : _filter == 'active'
                                  ? 'Нет активных заказов'
                                  : _filter == 'done'
                                      ? 'Нет завершённых заказов'
                                      : _filter == 'cancelled'
                                          ? 'Нет отменённых заказов'
                                          : 'Заказов нет',
                          style: const TextStyle(
                              fontSize: 15, color: cInk2),
                        ),
                      ]),
                    ),
                ],
              );
            },
          ),
        ),
      ]),
    );
  }
}

// ── Order card ─────────────────────────────────────────────────────────────────
class _OrderCard extends StatefulWidget {
  final OrderModel order;
  final FirestoreService service;
  final VoidCallback onChanged;
  const _OrderCard(
      {required this.order, required this.service, required this.onChanged});

  @override
  State<_OrderCard> createState() => _OrderCardState();
}

class _OrderCardState extends State<_OrderCard> {
  bool _loading = false;
  late final ConfettiController _confetti;

  @override
  void initState() {
    super.initState();
    _confetti = ConfettiController(duration: const Duration(seconds: 2));
  }

  @override
  void dispose() {
    _confetti.dispose();
    super.dispose();
  }

  OrderModel get o => widget.order;

  Color get _typeColor {
    switch (o.orderType) {
      case OrderModel.typeSmartReservation:
        return const Color(0xFF3B82F6);
      case OrderModel.typeClickCollect:
        return cGreen;
      case OrderModel.typeDelivery:
        return const Color(0xFFF59E0B);
      default:
        return cInk3;
    }
  }

  String get _typeLabel {
    switch (o.orderType) {
      case OrderModel.typeSmartReservation:
        return 'СМАРТ-БРОНЬ';
      case OrderModel.typeClickCollect:
        return 'CLICK & COLLECT';
      case OrderModel.typeDelivery:
        return 'ДОСТАВКА';
      default:
        return o.orderType.toUpperCase();
    }
  }

  String get _statusLabel {
    switch (o.status) {
      case OrderModel.statusPending:
        return 'Ожидает оплаты';
      case OrderModel.statusReserved:
        return 'Бронь подтверждена';
      case OrderModel.statusRejected:
        return 'Чек отклонён';
      case OrderModel.statusConfirmed:
        return 'Оплачено · Готов к выдаче';
      case OrderModel.statusCompleted:
        return 'Завершён';
      case OrderModel.statusCancelled:
        return 'Отменён';
      default:
        return o.status;
    }
  }

  Color get _statusColor {
    switch (o.status) {
      case OrderModel.statusPending:
        return cAmber;
      case OrderModel.statusReserved:
        return const Color(0xFF3B82F6);
      case OrderModel.statusRejected:
        return cRed;
      case OrderModel.statusConfirmed:
      case OrderModel.statusCompleted:
        return cGreen;
      case OrderModel.statusCancelled:
        return cRed;
      default:
        return cInk3;
    }
  }

  Future<void> _handOver() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Выдача товара'),
        content: Text(o.isSmartReservation && o.inStorePaymentMethod.isNotEmpty
            ? 'Выдать товар клиенту?\n\nДоплата: ${_payMethodLabel(o.inStorePaymentMethod)}'
            : 'Выдать товар клиенту?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Нет')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: cGreen, foregroundColor: Colors.white),
              child: const Text('Да, выдать')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _loading = true);
    try {
      await widget.service.markHandedOver(o);
      if (mounted) {
        _confetti.play();
        HapticFeedback.mediumImpact();
        widget.onChanged();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.toString()),
            backgroundColor: cRed,
            behavior: SnackBarBehavior.floating));
      }
    }
  }

  Future<void> _handOverReserved() async {
    final method = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 36, height: 4,
              decoration: BoxDecoration(color: cLine, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          Text('Выдача товара · Доплата ${o.remainingAmount.toStringAsFixed(0)} ₸',
              style: manrope(16, FontWeight.w800, color: cInk)),
          const SizedBox(height: 4),
          Text('Клиент доплату қалай берді?',
              style: manrope(13, FontWeight.w500, color: cInk2)),
          const SizedBox(height: 20),
          _PayBtn(label: '💵  Наличный', color: cGreen,
              onTap: () => Navigator.pop(ctx, 'cash')),
          const SizedBox(height: 10),
          _PayBtn(label: '📱  Kaspi', color: const Color(0xFFEB3333),
              onTap: () => Navigator.pop(ctx, 'kaspi')),
        ]),
      ),
    );
    if (method == null || !mounted) return;
    setState(() => _loading = true);
    try {
      await widget.service.handOverWithDoplate(o, method);
      if (mounted) {
        _confetti.play();
        HapticFeedback.mediumImpact();
        widget.onChanged();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.toString()),
            backgroundColor: cRed,
            behavior: SnackBarBehavior.floating));
      }
    }
  }

  Future<void> _cancel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Отмена заказа'),
        content: const Text('Заказ будет отменён, товар вернётся на склад.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: cRed,
                  foregroundColor: Colors.white),
              child: const Text('Отменить заказ')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _loading = true);
    try {
      await widget.service.cancelOnlineOrder(o);
      if (mounted) widget.onChanged();
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.toString()),
            backgroundColor: cRed,
            behavior: SnackBarBehavior.floating));
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    final isActive = o.status == OrderModel.statusPending ||
        o.status == OrderModel.statusReserved ||
        o.status == OrderModel.statusRejected ||
        o.status == OrderModel.statusConfirmed;

    return Stack(
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: o.isAwaitingReview
                ? Border.all(color: cAmber, width: 1.5)
                : null,
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 3))
            ],
          ),
          child: _loading
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                      child: CircularProgressIndicator(color: cGreen)))
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  // Type + status header
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: _typeColor.withValues(alpha: 0.08),
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(16)),
                    ),
                    child: Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _typeColor,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(_typeLabel,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w800)),
                      ),
                      const Spacer(),
                      if (o.isSmartReservation &&
                          (o.status == OrderModel.statusPending ||
                              o.status == OrderModel.statusReserved))
                        ReservationTimerWidget(expiresAt: o.expiresAt),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _statusColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(_statusLabel,
                            style: TextStyle(
                                color: _statusColor,
                                fontSize: 11,
                                fontWeight: FontWeight.w700)),
                      ),
                    ]),
                  ),

                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Order number
                          if (o.orderNumber > 0)
                            Text(
                              '#${o.orderNumber.toString().padLeft(5, '0')}',
                              style: manrope(13, FontWeight.w700, color: cInk3),
                            ),

                          // Client info
                          const SizedBox(height: 4),
                          Row(children: [
                            const Icon(Icons.person_outline,
                                size: 16, color: cInk3),
                            const SizedBox(width: 6),
                            Expanded(
                                child: Text(
                                    o.clientName.isNotEmpty
                                        ? o.clientName
                                        : 'Имя не указано',
                                    style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: cInk))),
                          ]),
                          const SizedBox(height: 2),
                          Row(children: [
                            const Icon(Icons.phone_outlined,
                                size: 14, color: cInk3),
                            const SizedBox(width: 6),
                            Text(o.clientPhone,
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: cInk2)),
                            const SizedBox(width: 12),
                            GestureDetector(
                                onTap: () {
                                  Clipboard.setData(
                                      ClipboardData(text: o.clientPhone));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text('Телефон скопирован'),
                                          behavior: SnackBarBehavior.floating,
                                          duration: Duration(seconds: 1)));
                                },
                                child: const Icon(Icons.copy_outlined,
                                    size: 14, color: cInk3)),
                          ]),

                          const Divider(height: 16),

                          // Items
                          ...o.items.map((item) => Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 2),
                                child: Row(children: [
                                  Expanded(
                                      child: Text(
                                          '${item.productName}  (EU ${item.size})',
                                          style: const TextStyle(
                                              fontSize: 13,
                                              color: cInk))),
                                  Text(
                                      '×${item.qty}  ${item.subtotal.toStringAsFixed(0)} ₸',
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color: cInk2)),
                                ]),
                              )),

                          // Addresses
                          if (o.warehouseAddress.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.location_on_outlined,
                                      size: 14, color: cInk3),
                                  const SizedBox(width: 4),
                                  Expanded(
                                      child: Text(o.warehouseAddress,
                                          style: const TextStyle(
                                              fontSize: 12,
                                              color: cInk2))),
                                ]),
                          ],
                          if (o.isDelivery && o.address.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.local_shipping_outlined,
                                      size: 14, color: cInk3),
                                  const SizedBox(width: 4),
                                  Expanded(
                                      child: Text(o.address,
                                          style: const TextStyle(
                                              fontSize: 12,
                                              color: cInk2))),
                                ]),
                          ],

                          const Divider(height: 16),

                          // Payment summary
                          if (o.isSmartReservation) ...[
                            _PayRow(
                                label: 'Сумма товаров',
                                value: '${o.total.toStringAsFixed(0)} ₸'),
                            _PayRow(
                                label: 'Задаток (10%)',
                                value: '${o.depositAmount.toStringAsFixed(0)} ₸',
                                valueColor: cGreen),
                            if (o.paymentBank.isNotEmpty)
                              _PayRow(
                                  label: 'Задаток через',
                                  value: _payMethodLabel(o.paymentBank),
                                  valueColor: _payMethodColor(o.paymentBank)),
                            _PayRow(
                                label: 'Доплата в магазине',
                                value: '${o.remainingAmount.toStringAsFixed(0)} ₸',
                                valueColor: cAmber,
                                bold: true),
                            if (o.inStorePaymentMethod.isNotEmpty)
                              _PayRow(
                                  label: 'Доплата через',
                                  value: _payMethodLabel(o.inStorePaymentMethod),
                                  valueColor: _payMethodColor(o.inStorePaymentMethod)),
                          ] else if (o.isDelivery) ...[
                            _PayRow(
                                label: 'Сумма товаров',
                                value: '${o.total.toStringAsFixed(0)} ₸'),
                            if (o.deliveryFee > 0)
                              _PayRow(
                                  label: 'Доставка',
                                  value: '${o.deliveryFee.toStringAsFixed(0)} ₸'),
                            _PayRow(
                                label: 'Итого к оплате',
                                value: '${o.totalWithDelivery.toStringAsFixed(0)} ₸',
                                valueColor: cGreen,
                                bold: true),
                            if (o.paymentBank.isNotEmpty)
                              _PayRow(
                                  label: 'Оплачено через',
                                  value: _payMethodLabel(o.paymentBank),
                                  valueColor: _payMethodColor(o.paymentBank)),
                          ] else ...[
                            _PayRow(
                                label: 'Итого к оплате',
                                value: '${o.total.toStringAsFixed(0)} ₸',
                                valueColor: cGreen,
                                bold: true),
                            if (o.paymentBank.isNotEmpty)
                              _PayRow(
                                  label: 'Оплачено через',
                                  value: _payMethodLabel(o.paymentBank),
                                  valueColor: _payMethodColor(o.paymentBank)),
                          ],

                          // Action buttons
                          if (isActive) ...[
                            const SizedBox(height: 12),

                            // Pending — waiting for client payment
                            if (o.status == OrderModel.statusPending)
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                    vertical: 10, horizontal: 12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFFBEB),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                      color: cAmber.withValues(alpha: 0.3)),
                                ),
                                child: const Text(
                                  '⏳ Ожидает оплаты от клиента',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF92400E)),
                                ),
                              ),

                            // Reserved → выдать + доплата (одним шагом)
                            if (o.status == OrderModel.statusReserved)
                              ElevatedButton(
                                onPressed: _handOverReserved,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: cGreen,
                                  foregroundColor: Colors.white,
                                  minimumSize:
                                      const Size(double.infinity, 44),
                                  shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(10)),
                                  elevation: 0,
                                ),
                                child: Text(
                                    'Выдать товар · доплата ${o.remainingAmount.toStringAsFixed(0)} ₸',
                                    style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700)),
                              ),

                            // Confirmed → admin can hand over directly
                            if (o.status == OrderModel.statusConfirmed)
                              ElevatedButton(
                                onPressed: _handOver,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: cGreen,
                                  foregroundColor: Colors.white,
                                  minimumSize:
                                      const Size(double.infinity, 44),
                                  shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(10)),
                                  elevation: 0,
                                ),
                                child: const Text('Выдать товар',
                                    style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700)),
                              ),

                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton(
                                onPressed: _cancel,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: cRed,
                                  side: const BorderSide(color: cRed),
                                  shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(10)),
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 8),
                                ),
                                child: const Text('Отменить заказ',
                                    style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700)),
                              ),
                            ),
                          ],
                        ]),
                  ),
                ]),
        ),
        Align(
          alignment: Alignment.topCenter,
          child: ConfettiWidget(
            confettiController: _confetti,
            blastDirectionality: BlastDirectionality.explosive,
            maxBlastForce: 20,
            minBlastForce: 5,
            emissionFrequency: 0.5,
            numberOfParticles: 25,
            gravity: 0.2,
            colors: const [
              cGreen, cGreen, cAmber,
              Color(0xFF3B82F6), Colors.purple,
            ],
          ),
        ),
      ],
    );
  }
}

class _PayRow extends StatelessWidget {
  final String label, value;
  final Color? valueColor;
  final bool bold;
  const _PayRow(
      {required this.label,
      required this.value,
      this.valueColor,
      this.bold = false});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: const TextStyle(fontSize: 12, color: cInk2)),
            Text(value,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                  color: valueColor ?? cInk,
                )),
          ],
        ),
      );
}

class _FilterChip extends StatelessWidget {
  final String label, value, current;
  final void Function(String) onTap;
  const _FilterChip(
      {required this.label,
      required this.value,
      required this.current,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final active = value == current;
    return GestureDetector(
      onTap: () => onTap(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active
              ? Colors.white
              : Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: active ? cGreen : Colors.white,
            )),
      ),
    );
  }
}

// ── Shared payment helpers ─────────────────────────────────────────────────────
// Канондық кілтке келтіреді (ескі деректер 'Kaspi'/'Halyk Bank' үшін).
String _normMethod(String m) {
  final s = m.toLowerCase();
  if (s.contains('kaspi')) return 'kaspi';
  if (s.contains('halyk')) return 'halyk';
  if (s == 'cash' || s.contains('налич')) return 'cash';
  return s;
}

String _payMethodLabel(String method) {
  switch (_normMethod(method)) {
    case 'kaspi':  return '📱 Kaspi';
    case 'halyk':  return '📱 Halyk Bank';
    case 'cash':   return '💵 Наличный';
    default:       return method.isNotEmpty ? method : '—';
  }
}

Color _payMethodColor(String method) {
  switch (_normMethod(method)) {
    case 'kaspi': return const Color(0xFFEB3333);
    case 'halyk': return const Color(0xFF00A550);
    default:      return cGreen;
  }
}

class _PayBtn extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _PayBtn({required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        height: 50,
        child: ElevatedButton(
          onPressed: onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 0,
          ),
          child: Text(label, style: manrope(14, FontWeight.w700, color: Colors.white)),
        ),
      );
}
