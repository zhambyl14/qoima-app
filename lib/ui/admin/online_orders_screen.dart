import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../data/models/order_model.dart';
import '../../data/services/cloudinary_service.dart';
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
  String _filter = 'review'; // default: orders awaiting receipt review

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
      case 'review':
        return all.where((o) => o.isAwaitingReview).toList();
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
                            stream: _service.watchOnlineOrders(),
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
                            border: InputBorder.none,
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
                    stream: _service.watchOnlineOrders(),
                    builder: (ctx, snap) {
                      final all = snap.data ?? [];
                      final review =
                          all.where((o) => o.isAwaitingReview).length;
                      final active = all
                          .where((o) =>
                              o.status == OrderModel.statusPending ||
                              o.status == OrderModel.statusReserved ||
                              o.status == OrderModel.statusRejected ||
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
                            label: 'Проверка $review',
                            value: 'review',
                            current: _filter,
                            highlight: review > 0,
                            onTap: (v) => setState(() {
                                  _filter = v;
                                  _lookupResult = null;
                                })),
                        const SizedBox(width: 8),
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
            stream: _service.watchOnlineOrders(),
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
        return o.receiptUrl.isEmpty ? 'Ожидает чека' : 'На проверке оплаты';
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

  Future<void> _confirmPayment() async {
    final label = o.isSmartReservation
        ? 'Подтвердить получение задатка?'
        : 'Подтвердить оплату и разрешить выдачу?';
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Подтверждение оплаты'),
        content: Text(label),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Нет')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: cGreen,
                  foregroundColor: Colors.white),
              child: const Text('Да, подтвердить')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _loading = true);
    try {
      if (o.isSmartReservation) {
        await widget.service.confirmReservationDeposit(o);
      } else {
        await widget.service.confirmOnlinePayment(o);
      }
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

  Future<void> _handOver() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Выдача товара'),
        content: const Text('Выдать товар клиенту?'),
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

  Future<void> _acceptInStorePayment() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Принять доплату'),
        content: Text(
            'Клиент оплатил остаток ${o.remainingAmount.toStringAsFixed(0)} ₸ на складе?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Нет')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: cGreen, foregroundColor: Colors.white),
              child: const Text('Да, принять')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _loading = true);
    try {
      await widget.service.confirmInStorePayment(o);
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

  Future<void> _rejectReceipt() async {
    final reasons = [
      'Деньги не поступили',
      'Сумма не совпадает',
      'Чек нечитаемый / подделка',
      'Оплата на другие реквизиты',
    ];
    String selected = reasons.first;
    final TextEditingController customCtrl = TextEditingController();

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setBS) => Container(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                  width: 36, height: 4,
                  decoration: BoxDecoration(
                      color: cLine,
                      borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 14),
              Text('Причина отклонения',
                  style: manrope(17, FontWeight.w700, color: cInk)),
              const SizedBox(height: 14),
              ...reasons.map((r) => GestureDetector(
                    onTap: () => setBS(() => selected = r),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 11),
                      decoration: BoxDecoration(
                        color: selected == r ? cRedTint : cBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: selected == r
                                ? cRed.withValues(alpha: 0.4)
                                : cLine),
                      ),
                      child: Row(children: [
                        Expanded(
                            child: Text(r,
                                style: manrope(13.5, FontWeight.w600,
                                    color: selected == r ? cRed : cInk))),
                        if (selected == r)
                          const Icon(Icons.check_circle_rounded,
                              color: cRed, size: 18),
                      ]),
                    ),
                  )),
              const SizedBox(height: 8),
              TextField(
                controller: customCtrl,
                decoration: InputDecoration(
                  hintText: 'Или введите причину вручную...',
                  hintStyle: manrope(13, FontWeight.w400, color: cInk3),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: cLine)),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 11),
                ),
                onChanged: (v) => setBS(() => selected = v.isEmpty ? reasons.first : v),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: cRed,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12))),
                  child: Text('Отклонить чек',
                      style: manrope(14, FontWeight.w700)),
                ),
              ),
            ]),
          ),
        ),
      ),
    );

    if (confirmed != true || !mounted) return;
    final reason = customCtrl.text.trim().isNotEmpty
        ? customCtrl.text.trim()
        : selected;
    setState(() => _loading = true);
    try {
      await widget.service.rejectReceipt(o, reason);
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

  Future<void> _openOriginalReceipt() async {
    final uri = Uri.tryParse(o.receiptUrl);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _viewReceipt() {
    final previewUrl = CloudinaryService.receiptPreviewUrl(o.receiptUrl);
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(children: [
          InteractiveViewer(
            child: Image.network(
              previewUrl,
              fit: BoxFit.contain,
              loadingBuilder: (_, child, prog) => prog == null
                  ? child
                  : const Center(
                      child: CircularProgressIndicator(color: Colors.white)),
              errorBuilder: (_, __, ___) => const Center(
                child: Icon(Icons.broken_image, color: Colors.white, size: 48)),
            ),
          ),
          Positioned(
            top: 8, right: 8,
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.close, color: Colors.white, size: 20),
              ),
            ),
          ),
        ]),
      ),
    );
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
                                label: 'Итого к оплате',
                                value: '${o.totalWithDelivery.toStringAsFixed(0)} ₸',
                                valueColor: cGreen,
                                bold: true),
                          ] else ...[
                            _PayRow(
                                label: 'Итого к оплате',
                                value: '${o.total.toStringAsFixed(0)} ₸',
                                valueColor: cGreen,
                                bold: true),
                          ],

                          // Receipt image (tap to view full-screen)
                          if (o.receiptUrl.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            GestureDetector(
                              onTap: _viewReceipt,
                              child: Container(
                                height: 120,
                                decoration: BoxDecoration(
                                  color: cBg,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: cLine),
                                ),
                                child: Stack(children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: Image.network(
                                      CloudinaryService.receiptPreviewUrl(
                                          o.receiptUrl),
                                      width: double.infinity,
                                      height: 120,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => const Center(
                                        child: Icon(Icons.receipt_long_outlined,
                                            size: 36, color: cInk3),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    right: 8, bottom: 8,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.black54,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.zoom_in,
                                                color: Colors.white, size: 14),
                                            SizedBox(width: 4),
                                            Text('Просмотр',
                                                style: TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 11,
                                                    fontWeight:
                                                        FontWeight.w600)),
                                          ]),
                                    ),
                                  ),
                                ]),
                              ),
                            ),
                            // «Открыть оригинал» — PDF или фото в браузере
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                onPressed: _openOriginalReceipt,
                                icon: const Icon(Icons.open_in_new,
                                    size: 14, color: cInk3),
                                label: Text('Открыть оригинал',
                                    style:
                                        manrope(12, FontWeight.w500, color: cInk3)),
                                style: TextButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                    minimumSize: Size.zero,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap),
                              ),
                            ),
                          ],

                          // Rejection reason display
                          if (o.status == OrderModel.statusRejected &&
                              o.rejectionReason.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: cRedTint,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    const Icon(Icons.error_outline,
                                        color: cRed, size: 15),
                                    const SizedBox(width: 6),
                                    Expanded(
                                        child: Text(
                                            'Отклонено: ${o.rejectionReason}',
                                            style: manrope(
                                                12, FontWeight.w500,
                                                color: cRed))),
                                  ]),
                            ),
                          ],

                          // Action buttons
                          if (isActive) ...[
                            const SizedBox(height: 12),

                            // Confirm payment (only for pending with receipt)
                            if (o.isAwaitingReview)
                              Row(children: [
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: _confirmPayment,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: cGreen,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(10)),
                                      elevation: 0,
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 10),
                                    ),
                                    child: Text(
                                        o.isSmartReservation
                                            ? 'Подтвердить задаток'
                                            : 'Подтвердить оплату',
                                        style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700)),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: _rejectReceipt,
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: cRed,
                                      side: const BorderSide(color: cRed),
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(10)),
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 10),
                                    ),
                                    child: const Text('Отклонить',
                                        style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700)),
                                  ),
                                ),
                              ]),

                            // Pending without receipt
                            if (o.status == OrderModel.statusPending &&
                                o.receiptUrl.isEmpty)
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
                                  '⏳ Ожидает чека от клиента',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF92400E)),
                                ),
                              ),

                            // Reserved (deposit confirmed, waiting in-store)
                            // Reserved → admin да доплата қабылдай алады
                            if (o.status == OrderModel.statusReserved)
                              ElevatedButton(
                                onPressed: _acceptInStorePayment,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor:
                                      const Color(0xFF3B82F6),
                                  foregroundColor: Colors.white,
                                  minimumSize:
                                      const Size(double.infinity, 44),
                                  shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(10)),
                                  elevation: 0,
                                ),
                                child: Text(
                                    'Принять доплату ${o.remainingAmount.toStringAsFixed(0)} ₸',
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
  final bool highlight;
  final void Function(String) onTap;
  const _FilterChip(
      {required this.label,
      required this.value,
      required this.current,
      this.highlight = false,
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
              : highlight
                  ? Colors.white.withValues(alpha: 0.25)
                  : Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
          border: highlight && !active
              ? Border.all(color: cAmber, width: 1.5)
              : null,
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
