import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/app_user.dart';
import '../../core/warehouse_context.dart';
import '../../data/models/order_model.dart';
import '../../data/services/firestore_service.dart';
import '../../theme/qoima_design.dart';
import '../client/reservation_timer_widget.dart';

class SellerOnlineScreen extends StatefulWidget {
  const SellerOnlineScreen({super.key});

  @override
  State<SellerOnlineScreen> createState() => _SellerOnlineScreenState();
}

class _SellerOnlineScreenState extends State<SellerOnlineScreen> {
  final _service = FirestoreService();
  final _codeCtrl = TextEditingController();
  String _filter = 'active';

  OrderModel? _lookupResult;
  String? _lookupError;

  String _warehouseId(BuildContext ctx) {
    final wCtx = ctx.read<WarehouseContext>();
    if (wCtx.current != null) return wCtx.current!.id;
    return ctx.read<AppUser>().assignedWarehouseId;
  }

  String _warehouseName(BuildContext ctx) {
    final wCtx = ctx.read<WarehouseContext>();
    return wCtx.current?.name ?? 'Склад';
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _lookup(String whId) async {
    final code = _codeCtrl.text.trim();
    if (code.isEmpty) return;
    setState(() {
      _lookupError = null;
      _lookupResult = null;
    });
    try {
      final order = await _service.lookupOnlineOrder(code);
      if (!mounted) return;
      final found =
          (order != null && order.warehouseId == whId) ? order : null;
      setState(() {
        _lookupResult = found;
        _lookupError = order != null && found == null
            ? 'Бұл тапсырыс сіздің қоймаңызға тиесілі емес'
            : found == null
                ? 'Тапсырыс табылмады'
                : null;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _lookupError = e.toString());
      }
    }
  }

  List<OrderModel> _applyFilter(List<OrderModel> all) {
    switch (_filter) {
      case 'active':
        return all
            .where((o) =>
                o.status == OrderModel.statusReserved ||
                o.status == OrderModel.statusPending)
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
    final whId = _warehouseId(context);
    final whName = _warehouseName(context);

    return Scaffold(
      backgroundColor: cBg,
      body: Column(children: [
        // ── Header ────────────────────────────────────────────────────────────
        Container(
          decoration: const BoxDecoration(gradient: kGrad),
          child: SafeArea(
            bottom: false,
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
                child: Row(children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Онлайн-заказы',
                            style: manrope(23, FontWeight.w800,
                                color: Colors.white, letterSpacing: -0.5)),
                        Text('Склад: $whName',
                            style: manrope(13, FontWeight.w500,
                                color: Colors.white.withValues(alpha: 0.78))),
                      ],
                    ),
                  ),
                  QHeaderBtn(
                    Icons.qr_code_scanner_rounded,
                    onTap: () {
                      _codeCtrl.clear();
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        shape: const RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.vertical(top: Radius.circular(22))),
                        builder: (ctx) => Padding(
                          padding: EdgeInsets.only(
                            left: 20,
                            right: 20,
                            top: 16,
                            bottom:
                                MediaQuery.of(ctx).viewInsets.bottom + 28,
                          ),
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            Center(
                                child: Container(
                                    width: 36,
                                    height: 4,
                                    decoration: BoxDecoration(
                                        color: Colors.grey.shade300,
                                        borderRadius:
                                            BorderRadius.circular(2)))),
                            const SizedBox(height: 14),
                            Text('Введите код заказа',
                                style: manrope(16, FontWeight.w700, color: cInk)),
                            const SizedBox(height: 12),
                            Container(
                              height: 52,
                              decoration: BoxDecoration(
                                color: cSurface,
                                borderRadius: BorderRadius.circular(14),
                                border:
                                    Border.all(color: cLine, width: 1.5),
                              ),
                              child: Row(children: [
                                const SizedBox(width: 14),
                                const Icon(Icons.qr_code_rounded,
                                    color: cGreen, size: 20),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: TextField(
                                    controller: _codeCtrl,
                                    autofocus: true,
                                    style: manrope(15, FontWeight.w600,
                                        color: cInk),
                                    decoration: InputDecoration(
                                      hintText: 'Код заказа...',
                                      hintStyle: manrope(
                                          15, FontWeight.w500,
                                          color: cInk3),
                                      border: InputBorder.none,
                                      contentPadding: EdgeInsets.zero,
                                      isDense: true,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 14),
                              ]),
                            ),
                            const SizedBox(height: 14),
                            QPrimaryButton(
                              label: 'Найти заказ',
                              onPressed: () {
                                Navigator.pop(ctx);
                                _lookup(whId);
                              },
                            ),
                          ]),
                        ),
                      );
                    },
                  ),
                ]),
              ),

              // Filter chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: StreamBuilder<List<OrderModel>>(
                  stream: _service.watchOnlineOrders(),
                  builder: (_, snap) {
                    final all = (snap.data ?? [])
                        .where(
                            (o) => whId.isEmpty || o.warehouseId == whId)
                        .toList();
                    final active = all
                        .where((o) =>
                            o.status == OrderModel.statusReserved ||
                            o.status == OrderModel.statusPending)
                        .length;
                    final done = all
                        .where(
                            (o) => o.status == OrderModel.statusCompleted)
                        .length;
                    final cancelled = all
                        .where(
                            (o) => o.status == OrderModel.statusCancelled)
                        .length;

                    return Row(children: [
                      _FilterChip(
                          label: 'Все ${all.length}',
                          value: 'all',
                          current: _filter,
                          onTap: (v) => setState(() {
                                _filter = v;
                                _lookupResult = null;
                              })),
                      const SizedBox(width: 8),
                      _FilterChip(
                          label: 'Активных $active',
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
            ]),
          ),
        ),

        // ── Body ──────────────────────────────────────────────────────────────
        Expanded(
          child: StreamBuilder<List<OrderModel>>(
            stream: _service.watchOnlineOrders(),
            builder: (_, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(
                    child: CircularProgressIndicator(color: cGreen));
              }

              final all = (snap.data ?? [])
                  .where((o) => whId.isEmpty || o.warehouseId == whId)
                  .toList();

              final waiting = all
                  .where((o) =>
                      o.status == OrderModel.statusReserved ||
                      o.status == OrderModel.statusPending)
                  .length;
              final doneToday = all
                  .where((o) => o.status == OrderModel.statusCompleted)
                  .length;

              return ListView(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
                children: [
                  // Stats row
                  Row(children: [
                    Expanded(
                      child: QCard(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('$waiting',
                                style: manrope(24, FontWeight.w800,
                                    color: cGreen)),
                            Text('Ждут выдачи',
                                style: manrope(12, FontWeight.w600,
                                    color: cInk3)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: QCard(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('$doneToday',
                                style: manrope(24, FontWeight.w800,
                                    color: cInk)),
                            Text('Выдано сегодня',
                                style: manrope(12, FontWeight.w600,
                                    color: cInk3)),
                          ],
                        ),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 16),

                  // Lookup error
                  if (_lookupError != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cRedTint,
                        borderRadius: BorderRadius.circular(12),
                        border:
                            Border.all(color: cRed.withValues(alpha: 0.3)),
                      ),
                      child: Row(children: [
                        const Icon(Icons.error_outline,
                            color: cRed, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Text(_lookupError!,
                                style:
                                    manrope(13, FontWeight.w500, color: cRed))),
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

                  // Lookup result
                  if (_lookupResult != null) ...[
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: cGreen, width: 2),
                      ),
                      child: Column(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: cGreen,
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(16)),
                          ),
                          child: Row(children: [
                            const Icon(Icons.check_circle_outline,
                                color: Colors.white, size: 16),
                            const SizedBox(width: 8),
                            Text('Заказ найден',
                                style: manrope(13, FontWeight.w700,
                                    color: Colors.white)),
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

                  // Section label
                  if (_applyFilter(all).isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: QSecLabel('В выдаче'),
                    ),

                  // Orders list
                  ..._applyFilter(all).map((order) => _OrderCard(
                        order: order,
                        service: _service,
                        onChanged: () => setState(() {}),
                      )),

                  if (_applyFilter(all).isEmpty && _lookupResult == null)
                    Padding(
                      padding: const EdgeInsets.only(top: 48),
                      child: Column(children: [
                        Container(
                          width: 72,
                          height: 72,
                          decoration: const BoxDecoration(
                              color: cLine2, shape: BoxShape.circle),
                          child: const Icon(Icons.inbox_outlined,
                              size: 34, color: cInk3),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _filter == 'active'
                              ? 'Нет активных заказов'
                              : _filter == 'done'
                                  ? 'Нет завершённых заказов'
                                  : _filter == 'cancelled'
                                      ? 'Нет отменённых заказов'
                                      : 'Заказов нет',
                          style: manrope(15, FontWeight.w500, color: cInk2),
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

  OrderModel get o => widget.order;

  String get _typeTone {
    switch (o.orderType) {
      case OrderModel.typeSmartReservation:
        return 'blue';
      case OrderModel.typeClickCollect:
        return 'green';
      case OrderModel.typeDelivery:
        return 'amber';
      default:
        return 'gray';
    }
  }

  String get _typeLabel {
    switch (o.orderType) {
      case OrderModel.typeSmartReservation:
        return 'Смарт-Бронь';
      case OrderModel.typeClickCollect:
        return 'Click & Collect';
      case OrderModel.typeDelivery:
        return 'Доставка';
      default:
        return o.orderType;
    }
  }

  String get _statusLabel {
    switch (o.status) {
      case OrderModel.statusReserved:
        return 'Зарезервирован';
      case OrderModel.statusPending:
        return 'В ожидании';
      case OrderModel.statusCompleted:
        return 'Завершён';
      case OrderModel.statusCancelled:
        return 'Отменён';
      default:
        return o.status;
    }
  }

  String get _statusTone {
    switch (o.status) {
      case OrderModel.statusReserved:
        return 'amber';
      case OrderModel.statusPending:
        return 'green';
      case OrderModel.statusCompleted:
        return 'green';
      case OrderModel.statusCancelled:
        return 'red';
      default:
        return 'gray';
    }
  }

  String get _confirmLabel {
    if (o.isSmartReservation) return 'Полная оплата';
    if (o.isDelivery) return 'Доставлено';
    return 'Сканировать и выдать';
  }

  bool get _isActive =>
      o.status == OrderModel.statusReserved ||
      o.status == OrderModel.statusPending;

  Future<void> _confirm() async {
    final action = o.isSmartReservation
        ? 'Клиент оплатил полную сумму?'
        : o.isDelivery
            ? 'Отметить товар как доставленный?'
            : 'Отметить товар как выданный?';
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Подтверждение'),
        content: Text(action),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Нет')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: cGreen, foregroundColor: Colors.white),
              child: const Text('Да, подтвердить')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _loading = true);
    try {
      await widget.service.confirmOnlineOrder(o);
      if (mounted) {
        HapticFeedback.lightImpact();
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
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Отмена заказа'),
        content:
            const Text('Заказ будет отменён, товар вернётся на склад.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: cRed, foregroundColor: Colors.white),
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
    if (_loading) {
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        child: QCard(
          padding: const EdgeInsets.all(24),
          child: const Center(
              child: CircularProgressIndicator(color: cGreen)),
        ),
      );
    }

    final shortId = o.id.length > 6
        ? o.id.substring(0, 6).toUpperCase()
        : o.id.toUpperCase();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: QCard(
        padding: const EdgeInsets.all(14),
        border: Border.all(
            color: cGreen.withValues(alpha: 0.2), width: 1.5),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Order number + type pill
          Row(children: [
            Text('#$shortId',
                style: manrope(16, FontWeight.w800, color: cInk)),
            const Spacer(),
            QPill(_typeLabel, tone: _typeTone),
            const SizedBox(width: 8),
            QPill(_statusLabel, tone: _statusTone),
          ]),
          const SizedBox(height: 6),

          // Client
          Row(children: [
            const Icon(Icons.person_outline, size: 15, color: cInk3),
            const SizedBox(width: 6),
            Text(
              o.clientName.isNotEmpty ? o.clientName : 'Имя не указано',
              style: manrope(13.5, FontWeight.w600, color: cInk2),
            ),
          ]),

          // Phone + copy
          const SizedBox(height: 2),
          Row(children: [
            const Icon(Icons.phone_outlined, size: 14, color: cInk3),
            const SizedBox(width: 6),
            Text(o.clientPhone,
                style: manrope(12, FontWeight.w500, color: cInk2)),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: o.clientPhone));
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Телефон скопирован'),
                    behavior: SnackBarBehavior.floating,
                    duration: Duration(seconds: 1)));
              },
              child: const Icon(Icons.copy_outlined,
                  size: 14, color: cInk3),
            ),
          ]),

          // Pickup code
          if (o.pickupCode.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(children: [
              const Icon(Icons.qr_code_rounded, size: 14, color: cGreen),
              const SizedBox(width: 6),
              Text(o.pickupCode,
                  style: manrope(13, FontWeight.w700,
                      color: cGreen, letterSpacing: 1)),
            ]),
          ],

          // Reservation timer
          if (o.isSmartReservation &&
              o.status == OrderModel.statusReserved) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
              decoration: BoxDecoration(
                color: cBlueTint,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(children: [
                const Icon(Icons.access_time_rounded,
                    size: 15, color: cBlue),
                const SizedBox(width: 6),
                ReservationTimerWidget(expiresAt: o.expiresAt),
              ]),
            ),
          ],

          const Divider(height: 16, color: cLine),

          // Items
          ...o.items.map((item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(children: [
                  Expanded(
                      child: Text('${item.productName} (EU ${item.size})',
                          style: manrope(13, FontWeight.w500, color: cInk))),
                  Text(
                      '×${item.qty}  ${item.subtotal.toStringAsFixed(0)} ₸',
                      style: manrope(12, FontWeight.w500, color: cInk2)),
                ]),
              )),

          const Divider(height: 16, color: cLine),

          // Payment summary
          if (o.isSmartReservation) ...[
            _PayRow(
                label: 'Сумма товаров',
                value: '${o.total.toStringAsFixed(0)} ₸'),
            _PayRow(
                label: 'Депозит оплачен (10%)',
                value: '${o.depositAmount.toStringAsFixed(0)} ₸',
                valueColor: cGreen),
            _PayRow(
                label: 'Доплата в магазине',
                value: '${o.remainingAmount.toStringAsFixed(0)} ₸',
                valueColor: cAmber,
                bold: true),
          ] else if (o.isDelivery) ...[
            _PayRow(
                label: 'Сумма товаров',
                value: '${o.total.toStringAsFixed(0)} ₸'),
            if (o.deliveryFee > 0)
              _PayRow(
                  label: 'Доставка',
                  value: '${o.deliveryFee.toStringAsFixed(0)} ₸'),
            _PayRow(
                label: 'Итого оплачено',
                value: '${o.totalWithDelivery.toStringAsFixed(0)} ₸',
                valueColor: cGreen,
                bold: true),
          ] else ...[
            _PayRow(
                label: 'Итого оплачено',
                value: '${o.total.toStringAsFixed(0)} ₸',
                valueColor: cGreen,
                bold: true),
          ],

          // Action buttons
          if (_isActive) ...[
            const SizedBox(height: 12),
            QPrimaryButton(
              label: _confirmLabel,
              height: 46,
              icon: const Icon(Icons.qr_code_scanner_rounded,
                  color: Colors.white, size: 18),
              onPressed: _confirm,
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 38,
              child: OutlinedButton(
                onPressed: _cancel,
                style: OutlinedButton.styleFrom(
                  foregroundColor: cRed,
                  side: const BorderSide(color: cRed),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: EdgeInsets.zero,
                ),
                child:
                    Text('Отменить', style: manrope(13, FontWeight.w700, color: cRed)),
              ),
            ),
          ],
        ]),
      ),
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
                style: manrope(12, FontWeight.w500, color: cInk2)),
            Text(value,
                style: manrope(
                  13,
                  bold ? FontWeight.w700 : FontWeight.w500,
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: active
              ? Colors.white
              : Colors.white.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Text(label,
            style: manrope(
              12.5,
              FontWeight.w700,
              color: active ? cGreen : Colors.white.withValues(alpha: 0.9),
            )),
      ),
    );
  }
}
