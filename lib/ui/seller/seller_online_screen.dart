import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/app_user.dart';
import '../../core/warehouse_context.dart';
import '../../data/models/order_model.dart';
import '../../data/services/firestore_service.dart';
import '../../theme/qoima_design.dart';
import '../client/reservation_timer_widget.dart';
import '../../data/models/return_model.dart';
import '../../data/services/return_service.dart';

import '../../core/lang.dart';
class SellerOnlineScreen extends StatefulWidget {
  const SellerOnlineScreen({super.key});

  @override
  State<SellerOnlineScreen> createState() => _SellerOnlineScreenState();
}

class _SellerOnlineScreenState extends State<SellerOnlineScreen> {
  final _service = FirestoreService();
  final _codeCtrl = TextEditingController();
  String _filter = 'active';

  // Ағынды бір рет жасаймыз — фильтр басқан сайын (setState) тізім қайта
  // жазылып, спиннермен жыпылықтамауы үшін. Әрі бір экранда екі StreamBuilder
  // бір ағынды бөліседі (бұрын екі бөлек listener болатын).
  late final Stream<List<OrderModel>> _ordersStream =
      _service.watchOnlineOrders();
  late final Stream<List<ReturnModel>> _returnsStream =
      ReturnService().watchSellerReturns(AppUser.current.ownerUid);

  OrderModel? _lookupResult;
  String? _lookupError;

  String _warehouseId(BuildContext ctx) {
    final wCtx = ctx.read<WarehouseContext>();
    if (wCtx.current != null) return wCtx.current!.id;
    return ctx.read<AppUser>().assignedWarehouseId;
  }

  String _warehouseName(BuildContext ctx) {
    final wCtx = ctx.read<WarehouseContext>();
    return wCtx.current?.name ?? tr('Склад', 'Қойма');
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
            ? tr('Этот заказ не относится к вашему складу', 'Бұл тапсырыс сіздің қоймаңызға тиесілі емес')
            : found == null
                ? tr('Заказ не найден', 'Тапсырыс табылмады')
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
                o.status == OrderModel.statusPending ||
                o.status == OrderModel.statusReserved ||
                o.status == OrderModel.statusRejected ||
                o.status == OrderModel.statusConfirmed)
            .toList();
      case 'done':
        return all
            .where((o) =>
                o.status == OrderModel.statusCompleted ||
                o.status == OrderModel.statusReturned)
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
                        Text(tr('Онлайн-заказы', 'Онлайн тапсырыстар'),
                            style: manrope(23, FontWeight.w800,
                                color: Colors.white, letterSpacing: -0.5)),
                        Text(tr('Склад: $whName', 'Қойма: $whName'),
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
                                MediaQuery.of(ctx).viewInsets.bottom + MediaQuery.of(ctx).padding.bottom + 28,
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
                            Text(tr('Введите код заказа', 'Тапсырыс кодын енгізіңіз'),
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
                                      hintText: tr('Код заказа...', 'Тапсырыс коды...'),
                                      hintStyle: manrope(
                                          15, FontWeight.w500,
                                          color: cInk3),
                                      filled: false,
                                      border: InputBorder.none,
                                      enabledBorder: InputBorder.none,
                                      focusedBorder: InputBorder.none,
                                      disabledBorder: InputBorder.none,
                                      errorBorder: InputBorder.none,
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
                              label: tr('Найти заказ', 'Тапсырысты табу'),
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
                  stream: _ordersStream,
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
                          label: tr('Все ${all.length}', 'Барлығы ${all.length}'),
                          value: 'all',
                          current: _filter,
                          onTap: (v) => setState(() {
                                _filter = v;
                                _lookupResult = null;
                              })),
                      const SizedBox(width: 8),
                      _FilterChip(
                          label: tr('Активных $active', 'Белсенді $active'),
                          value: 'active',
                          current: _filter,
                          onTap: (v) => setState(() {
                                _filter = v;
                                _lookupResult = null;
                              })),
                      const SizedBox(width: 8),
                      _FilterChip(
                          label: tr('Завершено $done', 'Аяқталды $done'),
                          value: 'done',
                          current: _filter,
                          onTap: (v) => setState(() {
                                _filter = v;
                                _lookupResult = null;
                              })),
                      const SizedBox(width: 8),
                      _FilterChip(
                          label: tr('Отменено $cancelled', 'Бас тартылды $cancelled'),
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
            stream: _ordersStream,
            builder: (_, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(
                    child: CircularProgressIndicator(color: cGreen));
              }

              final all = (snap.data ?? [])
                  .where((o) => whId.isEmpty || o.warehouseId == whId)
                  .toList();

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

              final waiting = all
                  .where((o) =>
                      o.status == OrderModel.statusReserved ||
                      o.status == OrderModel.statusPending)
                  .length;
              final doneToday = all
                  .where((o) => o.status == OrderModel.statusCompleted)
                  .length;

              return RefreshIndicator(
                color: cGreen,
                onRefresh: () => _service.refreshOnlineOrders(),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
                  children: [
                  // Returns banner
                  StreamBuilder<List<ReturnModel>>(
                    stream: _returnsStream,
                    builder: (_, rSnap) {
                      final pending = (rSnap.data ?? [])
                          .where((r) => r.status == ReturnStatus.requested)
                          .length;
                      if (pending == 0) return const SizedBox.shrink();
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: cAmberTint,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: cAmber.withValues(alpha: 0.35)),
                        ),
                        child: Row(children: [
                          const Icon(Icons.assignment_return_rounded,
                              color: cAmber, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              tr('$pending возвратов ждут решения', '$pending қайтарым шешімді күтуде'),
                              style: manrope(13.5, FontWeight.w700,
                                  color: const Color(0xFF92400E)),
                            ),
                          ),
                        ]),
                      );
                    },
                  ),
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
                            Text(tr('Ждут выдачи', 'Беруді күтуде'),
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
                            Text(tr('Выдано сегодня', 'Бүгін берілді'),
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
                            Text(tr('Заказ найден', 'Тапсырыс табылды'),
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
                      child: QSecLabel(tr('В выдаче', 'Беруде')),
                    ),

                  // Orders list
                  ..._applyFilter(all).map((order) => _OrderCard(
                        key: ValueKey(order.id),
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
                              ? tr('Нет активных заказов', 'Белсенді тапсырыс жоқ')
                              : _filter == 'done'
                                  ? tr('Нет завершённых заказов', 'Аяқталған тапсырыс жоқ')
                                  : _filter == 'cancelled'
                                      ? tr('Нет отменённых заказов', 'Бас тартылған тапсырыс жоқ')
                                      : tr('Заказов нет', 'Тапсырыс жоқ'),
                          style: manrope(15, FontWeight.w500, color: cInk2),
                        ),
                      ]),
                    ),
                  ],
                ),
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
      {super.key,
      required this.order,
      required this.service,
      required this.onChanged});

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
        return tr('Бронь', 'Бронь');
      case OrderModel.typeClickCollect:
        return tr('Самовывоз', 'Өзі алып кетеді');
      case OrderModel.typeDelivery:
        return tr('Доставка', 'Жеткізу');
      default:
        return o.orderType;
    }
  }

  String get _statusLabel {
    switch (o.status) {
      case OrderModel.statusPending:
        return tr('На проверке', 'Тексеруде');
      case OrderModel.statusRejected:
        return tr('Чек отклонён', 'Чек қабылданбады');
      case OrderModel.statusReserved:
        return tr('Бронь · ждёт доплату', 'Бронь · доплата күтілуде');
      case OrderModel.statusConfirmed:
        return tr('Оплачено · выдать', 'Төленді · беру');
      case OrderModel.statusCompleted:
        return tr('Завершён', 'Аяқталды');
      case OrderModel.statusCancelled:
        return tr('Отменён', 'Бас тартылды');
      case OrderModel.statusReturned:
        return tr('Возврат', 'Қайтару');
      default:
        return o.status;
    }
  }

  String get _statusTone {
    switch (o.status) {
      case OrderModel.statusPending:
      case OrderModel.statusRejected:
        return 'amber';
      case OrderModel.statusReserved:
        return 'blue';
      case OrderModel.statusConfirmed:
      case OrderModel.statusCompleted:
        return 'green';
      case OrderModel.statusCancelled:
      case OrderModel.statusReturned:
        return 'red';
      default:
        return 'gray';
    }
  }

  bool get _isActive =>
      o.status == OrderModel.statusPending ||
      o.status == OrderModel.statusReserved ||
      o.status == OrderModel.statusRejected ||
      o.status == OrderModel.statusConfirmed;

  Future<void> _handOver() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(tr('Выдача товара', 'Тауар беру')),
        content: Text(o.isSmartReservation && o.inStorePaymentMethod.isNotEmpty
            ? tr('Выдать товар клиенту?\n\nДоплата: ${_payMethodLabel(o.inStorePaymentMethod)}', 'Тауарды клиентке беру керек пе?\n\nДоплата: ${_payMethodLabel(o.inStorePaymentMethod)}')
            : tr('Выдать товар клиенту? Оплата подтверждена.', 'Тауарды клиентке беру керек пе? Төлем расталды.')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr('Нет', 'Жоқ'))),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: cGreen, foregroundColor: Colors.white),
              child: Text(tr('Да, выдать', 'Иә, беру'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _loading = true);
    try {
      await widget.service.markHandedOver(o);
      if (mounted) {
        setState(() => _loading = false);
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

  Future<void> _handOverReserved() async {
    final method = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 36, height: 4,
              decoration: BoxDecoration(
                  color: cLine, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          Text(tr('Выдача товара · Доплата ${o.remainingAmount.toStringAsFixed(0)} ₸', 'Тауар беру · Доплата ${o.remainingAmount.toStringAsFixed(0)} ₸'),
              style: manrope(16, FontWeight.w800, color: cInk)),
          const SizedBox(height: 4),
          Text(tr('Как клиент внёс доплату?', 'Клиент доплату қалай берді?'),
              style: manrope(13, FontWeight.w500, color: cInk2)),
          const SizedBox(height: 20),
          _PayBtn(label: tr('💵  Наличный', '💵  Қолма-қол'), color: cGreen,
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
        setState(() => _loading = false);
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
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(tr('Отмена заказа', 'Тапсырысты болдырмау')),
        content:
            Text(tr('Заказ будет отменён, товар вернётся на склад.', 'Тапсырыс болдырылмайды, тауар қоймаға оралады.')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr('Отмена', 'Болдырмау'))),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: cRed, foregroundColor: Colors.white),
              child: Text(tr('Отменить заказ', 'Тапсырысты болдырмау'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _loading = true);
    try {
      await widget.service.cancelOnlineOrder(o);
      if (mounted) {
        setState(() => _loading = false);
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
              o.clientName.isNotEmpty ? o.clientName : tr('Имя не указано', 'Аты көрсетілмеген'),
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
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(tr('Телефон скопирован', 'Телефон көшірілді')),
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
              (o.status == OrderModel.statusPending ||
                  o.status == OrderModel.statusReserved)) ...[
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
                label: tr('Сумма товаров', 'Тауар сомасы'),
                value: '${o.total.toStringAsFixed(0)} ₸'),
            _PayRow(
                label: 'Депозит (10%)',
                value: '${o.depositAmount.toStringAsFixed(0)} ₸',
                valueColor: cGreen),
            if (o.paymentBank.isNotEmpty)
              _PayRow(
                  label: tr('Депозит через', 'Депозит әдісі'),
                  value: _payMethodLabel(o.paymentBank),
                  valueColor: _payMethodColor(o.paymentBank)),
            _PayRow(
                label: tr('Доплата в магазине', 'Дүкенде доплата'),
                value: '${o.remainingAmount.toStringAsFixed(0)} ₸',
                valueColor: cAmber,
                bold: true),
            if (o.inStorePaymentMethod.isNotEmpty)
              _PayRow(
                  label: tr('Доплата через', 'Доплата әдісі'),
                  value: _payMethodLabel(o.inStorePaymentMethod),
                  valueColor: _payMethodColor(o.inStorePaymentMethod)),
          ] else if (o.isDelivery) ...[
            _PayRow(
                label: tr('Сумма товаров', 'Тауар сомасы'),
                value: '${o.total.toStringAsFixed(0)} ₸'),
            if (o.deliveryFee > 0)
              _PayRow(
                  label: tr('Доставка', 'Жеткізу'),
                  value: '${o.deliveryFee.toStringAsFixed(0)} ₸'),
            _PayRow(
                label: tr('Итого оплачено', 'Барлығы төленді'),
                value: '${o.totalWithDelivery.toStringAsFixed(0)} ₸',
                valueColor: cGreen,
                bold: true),
            if (o.paymentBank.isNotEmpty)
              _PayRow(
                  label: tr('Оплачено через', 'Төлем әдісі'),
                  value: _payMethodLabel(o.paymentBank),
                  valueColor: _payMethodColor(o.paymentBank)),
          ] else ...[
            _PayRow(
                label: tr('Итого оплачено', 'Барлығы төленді'),
                value: '${o.total.toStringAsFixed(0)} ₸',
                valueColor: cGreen,
                bold: true),
            if (o.paymentBank.isNotEmpty)
              _PayRow(
                  label: tr('Оплачено через', 'Төлем әдісі'),
                  value: _payMethodLabel(o.paymentBank),
                  valueColor: _payMethodColor(o.paymentBank)),
          ],

          // Action buttons
          if (_isActive) ...[
            const SizedBox(height: 12),

            // confirmed → hand over
            if (o.status == OrderModel.statusConfirmed)
              QPrimaryButton(
                label: o.isDelivery ? tr('Доставлено', 'Жеткізілді') : tr('Выдать товар', 'Тауар беру'),
                height: 46,
                icon: const Icon(Icons.check_circle_outline_rounded,
                    color: Colors.white, size: 18),
                onPressed: _handOver,
              ),

            // reserved → выдать + доплата (одним шагом)
            if (o.status == OrderModel.statusReserved)
              QPrimaryButton(
                label: tr('Выдать товар · доплата ${o.remainingAmount.toStringAsFixed(0)} ₸', 'Тауар беру · доплата ${o.remainingAmount.toStringAsFixed(0)} ₸'),
                height: 46,
                icon: const Icon(Icons.check_circle_outline_rounded,
                    color: Colors.white, size: 18),
                onPressed: _handOverReserved,
              ),

            // pending/rejected → locked, waiting for admin
            if (o.status == OrderModel.statusPending ||
                o.status == OrderModel.statusRejected)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: cBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: cLine),
                ),
                child: Text(
                  tr('Ожидает подтверждения оплаты администратором', 'Әкімшінің төлем растауы күтілуде'),
                  textAlign: TextAlign.center,
                  style: manrope(12.5, FontWeight.w600, color: cInk3),
                ),
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
                child: Text(tr('Отменить', 'Болдырмау'),
                    style: manrope(13, FontWeight.w700, color: cRed)),
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

// ── Payment helpers ───────────────────────────────────────────────────────────
// Канондық кілтке келтіреді (ескі деректер 'Kaspi'/'Halyk Bank' үшін).
String _normMethod(String m) {
  final s = m.toLowerCase();
  if (s.contains('kaspi')) return 'kaspi';
  if (s.contains('halyk')) return 'halyk';
  if (s == 'card' || s.contains('карт')) return 'card';
  if (s == 'cash' || s.contains('налич')) return 'cash';
  return s;
}

String _payMethodLabel(String method) {
  switch (_normMethod(method)) {
    case 'kaspi': return '📱 Kaspi';
    case 'halyk': return '📱 Halyk Bank';
    case 'card':  return tr('💳 Оплата картой', '💳 Картамен төлем');
    case 'cash':  return tr('💵 Наличный', '💵 Қолма-қол');
    default:      return method.isNotEmpty ? method : '—';
  }
}

Color _payMethodColor(String method) {
  switch (_normMethod(method)) {
    case 'kaspi': return const Color(0xFFEB3333);
    case 'halyk': return const Color(0xFF00A550);
    case 'card':  return const Color(0xFF3B82F6);
    default:      return cGreen;
  }
}

class _PayBtn extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _PayBtn(
      {required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        height: 50,
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
              style: manrope(14, FontWeight.w700, color: Colors.white)),
        ),
      );
}
