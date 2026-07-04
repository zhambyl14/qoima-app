import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/app_user.dart';
import '../../../core/warehouse_context.dart';
import '../../../data/models/models.dart';
import '../../../data/services/firestore_service.dart';
import '../../../theme/qoima_design.dart';
import '../../../theme/qoima_v2.dart';
import '../../shared/mandatory_warehouse_picker.dart';

import '../../../core/lang.dart';
// ── CartItem ──────────────────────────────────────────────────────────────────
class CartItem {
  final ProductModel product;
  final BatchModel batch;
  Map<String, int> sizes;
  double discountPercent;

  CartItem({
    required this.product,
    required this.batch,
    Map<String, int>? sizes,
    this.discountPercent = 0,
  }) : sizes = sizes ?? {};

  int get qty => sizes.values.fold(0, (a, b) => a + b);
  double get base => batch.sellingPrice * qty;
  double get total => base * (1 - discountPercent / 100);
  double get discountAmount => base - total;
}

// ── MakeSaleScreen ────────────────────────────────────────────────────────────
class MakeSaleScreen extends StatefulWidget {
  const MakeSaleScreen({super.key});
  @override
  State<MakeSaleScreen> createState() => _MakeSaleScreenState();
}

class _MakeSaleScreenState extends State<MakeSaleScreen> {
  final _service = FirestoreService();
  final _headerSearchCtrl = TextEditingController();
  String _headerQ = '';

  int _step = 0;
  final Set<String> _selectedIds = {};
  List<CartItem> _cart = [];
  bool _isConfirming = false;
  List<ReservationModel> _latestReservations = const [];

  @override
  void initState() {
    super.initState();
    _service.cleanupExpiredReservations().ignore();
  }

  @override
  void dispose() {
    _headerSearchCtrl.dispose();
    super.dispose();
  }

  String _activeWarehouseId(BuildContext ctx) =>
      ctx.read<WarehouseContext>().current?.id ??
      ctx.read<AppUser>().assignedWarehouseId;

  Stream<List<ProductModel>> _productStream(String whId) {
    if (whId.isNotEmpty) {
      return _service
          .watchProductsInWarehouse(whId)
          .map((list) => list.map((e) => e.product).toList());
    }
    return _service.watchProducts();
  }

  // ── Қадам 1 → 2 ───────────────────────────────────────────────────────────
  Future<void> _goToStep2() async {
    if (_isConfirming) return;
    setState(() => _isConfirming = true);
    if (_selectedIds.isEmpty) {
      setState(() => _isConfirming = false);
      return;
    }
    if (!await ensureWarehouseSelected(context)) {
      if (mounted) setState(() => _isConfirming = false);
      return;
    }
    if (!mounted) return;
    final whId = _activeWarehouseId(context);
    final items = <CartItem>[];
    final noStock = <String>[];

    for (final id in _selectedIds) {
      final prod = await _service.getProduct(id);
      if (prod == null) continue;
      final batches = await _service.getBatches(id);

      final whBatches = whId.isNotEmpty
          ? batches
              .where((b) =>
                  b.warehouseId == whId &&
                  b.sizesQuantity.values.any((q) => q > 0))
              .toList()
          : batches
              .where((b) => b.sizesQuantity.values.any((q) => q > 0))
              .toList();

      if (whBatches.isEmpty) {
        noStock.add(prod.name);
        continue;
      }
      items.add(CartItem(product: prod, batch: whBatches.first));
    }

    if (noStock.isNotEmpty && mounted) {
      _snack('Нет на этом складе: ${noStock.join(', ')}', isError: true);
    }
    if (items.isEmpty) {
      if (mounted) setState(() => _isConfirming = false);
      return;
    }
    if (mounted) {
      setState(() {
        _cart = items;
        _step = 1;
        _isConfirming = false;
      });
    }
  }

  // ── Төлем түрін таңдау ────────────────────────────────────────────────────
  Future<String?> _pickPaymentMethod() => showModalBottomSheet<String>(
        context: context,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (ctx) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 16),
            Text(tr('Тип оплаты', 'Төлем түрі'), style: manrope(18, FontWeight.w800, color: cInk)),
            const SizedBox(height: 4),
            Text(tr('Как клиент оплатил?', 'Клиент қалай төледі?'),
                style: manrope(13, FontWeight.w500, color: cInk2)),
            const SizedBox(height: 20),
            _PaymentMethodTile(
              label: tr('💵  Наличный', '💵  Қолма-қол'),
              onTap: () => Navigator.pop(ctx, 'cash'),
            ),
            const SizedBox(height: 10),
            _PaymentMethodTile(
              label: '📱  Kaspi',
              color: const Color(0xFFEB3333),
              onTap: () => Navigator.pop(ctx, 'kaspi'),
            ),
          ]),
        ),
      );

  // ── Сатуды растау ─────────────────────────────────────────────────────────
  Future<void> _confirm() async {
    if (_isConfirming) return;

    final paymentMethod = await _pickPaymentMethod();
    if (paymentMethod == null || !mounted) return;

    setState(() => _isConfirming = true);
    final whId = _activeWarehouseId(context);
    try {
      final validItems = _cart.where((c) => c.qty > 0).toList();
      if (validItems.isEmpty) {
        _snack(tr('Выберите хотя бы 1 товар', 'Кемінде 1 тауар таңдаңыз'), isError: true);
        return;
      }

      // Pre-flight: if any cart item's batch belongs to a different warehouse
      // than the current one, the admin reassigned us while we were mid-sale.
      final hasConflict = validItems.any(
          (c) => c.batch.warehouseId.isNotEmpty && c.batch.warehouseId != whId);
      if (hasConflict) {
        _snack(
          tr('Ошибка: Ваша привязка к складу была изменена Админом. Данная продажа отменена.', 'Қате: Қоймаға байлануыңызды Әкімші өзгертті. Бұл сатылым болдырылмады.'),
          isError: true,
        );
        setState(() {
          _isConfirming = false;
          _step = 0;
          _cart.clear();
          _selectedIds.clear();
        });
        return;
      }

      // Block if any selected size is currently reserved by an online order
      for (final item in validItems) {
        for (final entry in item.sizes.entries) {
          if (entry.value <= 0) continue;
          final isBlocked = _latestReservations.any((r) =>
              r.batchId == item.batch.id && r.size == entry.key && r.isActive);
          if (isBlocked) {
            if (mounted) {
              await showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  title: Text(tr('Товар забронирован', 'Тауар брондалған')),
                  content: Text(tr(
                      '${item.product.name} (р. ${entry.key}) — '
                          'забронирован онлайн-заказом. '
                          'Повторите чуть позже.',
                      '${item.product.name} (ө. ${entry.key}) — '
                          'онлайн тапсырыспен брондалған. '
                          'Аздан кейін қайталаңыз.')),
                  actions: [
                    ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: cGreen,
                            foregroundColor: Colors.white,
                            elevation: 0),
                        child: Text(tr('Понятно', 'Түсінікті'))),
                  ],
                ),
              );
            }
            setState(() => _isConfirming = false);
            return;
          }
        }
      }

      // Реттік чек нөмірі (ЧЕК-00001, ЧЕК-00002, ...) — себеттегі бүкіл товарға ортақ.
      final receipt = await _service.nextReceiptNumber();
      for (final item in validItems) {
        // Use a stable idempotency key per item so double-taps can't create
        // duplicate sales even if the first network call is still in flight.
        final key = '${item.product.id}_${item.batch.id}_'
            '${DateTime.now().millisecondsSinceEpoch ~/ 3000}';
        await _service.makeSale(
          productId: item.product.id,
          batchId: item.batch.id,
          sizesSold: Map.from(item.sizes),
          discountPercent: item.discountPercent,
          warehouseId: whId,
          paymentMethod: paymentMethod,
          idempotencyKey: key,
          receiptNumber: receipt,
        );
      }
      final totalQty = validItems.fold(0, (s, c) => s + c.qty);
      final totalPrice = validItems.fold(0.0, (s, c) => s + c.total);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Row(children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                  tr('Продано $totalQty шт. · ${totalPrice.toStringAsFixed(0)} ₸\n$receipt', 'Сатылды $totalQty дана · ${totalPrice.toStringAsFixed(0)} ₸\n$receipt')),
            ),
          ]),
          backgroundColor: cGreen,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ));
      }
    } catch (e) {
      _snack(e.toString().replaceFirst('SaleException: ', ''), isError: true);
    } finally {
      if (mounted) setState(() => _isConfirming = false);
    }
  }

  void _snack(String msg, {bool isError = false}) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: isError ? cRed : cGreen,
        behavior: SnackBarBehavior.floating,
      ));

  @override
  Widget build(BuildContext context) {
    // WarehouseContext.current is now reactive for both admin AND seller
    // (main.dart calls wCtx.load() for both roles). AppUser fallback is only
    // used during the brief moment before the initial load completes.
    final wCtx = context.watch<WarehouseContext>();
    final whId =
        wCtx.current?.id ?? context.read<AppUser>().assignedWarehouseId;
    final whName = wCtx.current?.name ?? tr('Нет склада', 'Қойма жоқ');

    return Scaffold(
      backgroundColor: cBg,
      body: SafeArea(
          child: Column(children: [
        // ── Header ────────────────────────────────────────────────────────
        Container(
          decoration: const BoxDecoration(gradient: kGrad),
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 16),
          child: Column(children: [
            Row(children: [
              GestureDetector(
                onTap: () {
                  if (_step == 1) {
                    setState(() => _step = 0);
                  } else {
                    Navigator.pop(context);
                  }
                },
                child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.chevron_left_rounded,
                        color: Colors.white, size: 22)),
              ),
              const SizedBox(width: 10),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(_step == 0 ? tr('Новая продажа', 'Жаңа сатылым') : tr('Размер и скидка', 'Өлшем және жеңілдік'),
                        style: manrope(21, FontWeight.w800,
                            color: Colors.white, letterSpacing: -0.4)),
                    Text(tr('Склад: $whName', 'Қойма: $whName'),
                        style: manrope(13, FontWeight.w500,
                            color: Colors.white.withValues(alpha: 0.78))),
                  ])),
              // Warehouse switch (admin)
              if (context.read<AppUser>().isAdmin && _step == 0)
                GestureDetector(
                  onTap: () async {
                    final whs = await _service.getWarehouses();
                    if (!context.mounted) return;
                    final wCtx = context.read<WarehouseContext>();
                    showModalBottomSheet(
                      context: context,
                      shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.vertical(
                              top: Radius.circular(22))),
                      builder: (_) => _WhPickerSheet(
                        warehouses: whs,
                        currentId: wCtx.current?.id ?? '',
                        onSelect: (wh) {
                          wCtx.switchTo(wh);
                          Navigator.pop(context);
                        },
                      ),
                    );
                  },
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.swap_horiz_rounded,
                        color: Colors.white, size: 20),
                  ),
                ),
              // Scan button
              const SizedBox(width: 8),
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.qr_code_scanner_rounded,
                    color: Colors.white, size: 20),
              ),
            ]),
            const SizedBox(height: 12),
            // Search bar — real TextField
            Container(
              height: 46,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(children: [
                const SizedBox(width: 12),
                Icon(Icons.search_rounded,
                    color: Colors.white.withValues(alpha: 0.8), size: 19),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _headerSearchCtrl,
                    onChanged: (v) => setState(() => _headerQ = v.trim()),
                    style: manrope(14.5, FontWeight.w500, color: Colors.white),
                    decoration: InputDecoration(
                      hintText: tr('Найти товар или сканировать...', 'Тауар іздеу немесе сканерлеу...'),
                      hintStyle: manrope(14.5, FontWeight.w500,
                          color: Colors.white.withValues(alpha: 0.8)),
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      errorBorder: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      isDense: true,
                      suffixIcon: _headerQ.isNotEmpty
                          ? GestureDetector(
                              onTap: () {
                                _headerSearchCtrl.clear();
                                setState(() => _headerQ = '');
                              },
                              child: Icon(Icons.close_rounded,
                                  color: Colors.white.withValues(alpha: 0.8),
                                  size: 18))
                          : null,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ]),
            ),
          ]),
        ),

        // ── Content ───────────────────────────────────────────────────────
        Expanded(
          child: _step == 0
              ? _Step1(
                  productStream: _productStream(whId),
                  selectedIds: _selectedIds,
                  externalQuery: _headerQ,
                  onToggle: (id) => setState(() {
                    if (_selectedIds.contains(id)) {
                      _selectedIds.remove(id);
                    } else {
                      _selectedIds.add(id);
                    }
                  }),
                )
              : StreamBuilder<List<ReservationModel>>(
                  stream: _service.watchActiveReservations(),
                  builder: (_, rSnap) {
                    _latestReservations = rSnap.data ?? const [];
                    return _Step2(
                      cart: _cart,
                      reservations: _latestReservations,
                      onSizeChanged: (ci, sizes) =>
                          setState(() => _cart[ci].sizes = sizes),
                      onDiscount: (ci) => _showDiscountSheet(ci),
                      onRemove: (ci) => setState(() {
                        _cart.removeAt(ci);
                        if (_cart.isEmpty) _step = 0;
                      }),
                    );
                  },
                ),
        ),

        // ── Footer ────────────────────────────────────────────────────────
        _Footer(
          step: _step,
          selectedCount: _selectedIds.length,
          cart: _cart,
          isLoading: _isConfirming,
          onNext: _step == 0 ? _goToStep2 : _confirm,
        ),
      ])),
    );
  }

  // ── Скидка Modal ──────────────────────────────────────────────────────────
  void _showDiscountSheet(int cartIndex) {
    final item = _cart[cartIndex];
    bool byPercent = true;
    final ctrl = TextEditingController(
        text: item.discountPercent > 0
            ? item.discountPercent.toStringAsFixed(0)
            : '');
    final presets = [5, 10, 15, 20, 25, 30];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          void applyPercent(double pct) => ctrl.text = pct.toStringAsFixed(0);
          return Padding(
            padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 16,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + MediaQuery.of(ctx).padding.bottom + 24),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                      child: Container(
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                              color: Colors.grey.shade300,
                              borderRadius: BorderRadius.circular(2)))),
                  const SizedBox(height: 14),
                  Text(tr('${item.product.name} — Скидка', '${item.product.name} — Жеңілдік'),
                      style: manrope(16, FontWeight.w700, color: cInk)),
                  const SizedBox(height: 4),
                  Text(tr('Базовая цена: ${item.base.toStringAsFixed(0)} ₸', 'Базалық баға: ${item.base.toStringAsFixed(0)} ₸'),
                      style: manrope(13, FontWeight.w500, color: cInk2)),
                  const SizedBox(height: 14),
                  Row(children: [
                    _ToggleBtn(
                        label: tr('% от цены', '% бағадан'),
                        active: byPercent,
                        onTap: () => setS(() => byPercent = true)),
                    const SizedBox(width: 8),
                    _ToggleBtn(
                        label: tr('₸ Новая цена', '₸ Жаңа баға'),
                        active: !byPercent,
                        onTap: () => setS(() => byPercent = false)),
                  ]),
                  const SizedBox(height: 12),
                  if (byPercent)
                    Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: presets
                            .map((p) => GestureDetector(
                                  onTap: () {
                                    setS(() {});
                                    applyPercent(p.toDouble());
                                  },
                                  child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 14, vertical: 6),
                                      decoration: BoxDecoration(
                                          color: cGreenTint,
                                          borderRadius:
                                              BorderRadius.circular(20)),
                                      child: Text('$p%',
                                          style: manrope(13, FontWeight.w700,
                                              color: cGreenDeep))),
                                ))
                            .toList()),
                  const SizedBox(height: 12),
                  TextField(
                    controller: ctrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))
                    ],
                    style: manrope(15, FontWeight.w600, color: cInk),
                    decoration: InputDecoration(
                      labelText: byPercent ? tr('Скидка %', 'Жеңілдік %') : tr('Финальная цена ₸', 'Соңғы баға ₸'),
                      suffixText: byPercent ? '%' : '₸',
                      filled: true,
                      fillColor: cSurface,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: cLine, width: 1.5)),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: cLine, width: 1.5)),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: cGreen, width: 1.5)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: cGreen,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(15)),
                              elevation: 0),
                          onPressed: () {
                            final val = double.tryParse(ctrl.text) ?? 0;
                            double pct;
                            if (byPercent) {
                              pct = val.clamp(0, 100);
                            } else {
                              pct = item.base > 0
                                  ? ((1 - val / item.base) * 100).clamp(0, 100)
                                  : 0;
                            }
                            setState(
                                () => _cart[cartIndex].discountPercent = pct);
                            Navigator.pop(ctx);
                          },
                          child: Text(tr('Применить', 'Қолдану'),
                              style: TextStyle(fontWeight: FontWeight.w700)))),
                ]),
          );
        },
      ),
    );
  }
}

// ── Warehouse picker sheet ────────────────────────────────────────────────────
class _WhPickerSheet extends StatelessWidget {
  final List<WarehouseModel> warehouses;
  final String currentId;
  final void Function(WarehouseModel) onSelect;
  const _WhPickerSheet(
      {required this.warehouses,
      required this.currentId,
      required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Center(
            child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height: 14),
        Text(tr('Выберите склад для продажи', 'Сату үшін қойма таңдаңыз'),
            style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: cInk)),
        const SizedBox(height: 12),
        ...warehouses.map((wh) => ListTile(
              leading: Icon(Icons.warehouse_outlined,
                  color: wh.id == currentId
                      ? cGreen
                      : cInk3),
              title: Text(wh.name,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              trailing: wh.id == currentId
                  ? const Icon(Icons.check_rounded, color: cGreen)
                  : null,
              onTap: () => onSelect(wh),
            )),
      ]),
    );
  }
}

// ── Қадам 1: Товар таңдау + поиск ────────────────────────────────────────────
class _Step1 extends StatefulWidget {
  final Stream<List<ProductModel>> productStream;
  final Set<String> selectedIds;
  final String externalQuery;
  final void Function(String) onToggle;

  const _Step1(
      {required this.productStream,
      required this.selectedIds,
      this.externalQuery = '',
      required this.onToggle});

  @override
  State<_Step1> createState() => _Step1State();
}

class _Step1State extends State<_Step1> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<ProductModel> _filter(List<ProductModel> all) {
    if (_query.isEmpty) return all;
    final q = _query.toLowerCase();
    return all
        .where((p) =>
            p.name.toLowerCase().contains(q) ||
            p.brand.toLowerCase().contains(q) ||
            p.type.toLowerCase().contains(q) ||
            p.category.toLowerCase().contains(q) ||
            p.articul.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ProductModel>>(
      stream: widget.productStream,
      builder: (_, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: cGreen));
        }
        final allProducts = (snap.data ?? [])
            .where((p) => p.status == ProductModel.statusInStock)
            .toList();

        if (allProducts.isEmpty) {
          return Center(
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                      color: cGreenTint,
                      shape: BoxShape.circle),
                  child: Icon(Icons.inventory_2_outlined,
                      size: 36, color: cGreen.withValues(alpha: 0.4)),
                ),
                const SizedBox(height: 16),
                Text(tr('На этом складе нет товаров', 'Бұл қоймада тауар жоқ'),
                    style: TextStyle(
                        fontSize: 15,
                        color: cInk2,
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 6),
                Text(tr('Выберите другой склад', 'Басқа қойма таңдаңыз'),
                    style: TextStyle(fontSize: 12, color: cInk3)),
              ]));
        }

        if (widget.selectedIds.isNotEmpty) {
          final validIds = widget.selectedIds
              .where((id) => allProducts.any((p) => p.id == id))
              .toSet();
          if (validIds.length != widget.selectedIds.length) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              widget.selectedIds
                ..clear()
                ..addAll(validIds);
            });
          }
        }

        final products = _filter(allProducts);

        return Column(children: [
          // ── Search bar ───────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: cLine),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 2))
                ],
              ),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _query = v.trim()),
                style:
                    const TextStyle(fontSize: 14, color: cInk),
                decoration: InputDecoration(
                  hintText: tr('Название, бренд, категория...', 'Атауы, бренд, категория...'),
                  hintStyle:
                      const TextStyle(color: cInk3, fontSize: 13),
                  prefixIcon: const Icon(Icons.search_rounded,
                      color: cInk3, size: 20),
                  suffixIcon: _query.isNotEmpty
                      ? GestureDetector(
                          onTap: () {
                            _searchCtrl.clear();
                            setState(() => _query = '');
                          },
                          child: const Icon(Icons.close_rounded,
                              color: cInk3, size: 18))
                      : null,
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 13),
                ),
              ),
            ),
          ),

          // ── Empty search result ──────────────────────────────────────────
          if (products.isEmpty)
            Expanded(
              child: Center(
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                    Icon(Icons.search_off_rounded,
                        size: 52, color: Colors.grey.shade300),
                    const SizedBox(height: 12),
                    Text(tr('«$_query» не найдено', '«$_query» табылмады'),
                        style: const TextStyle(
                            fontSize: 14, color: cInk2)),
                  ])),
            )
          else
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                itemCount: products.length,
                itemBuilder: (_, i) {
                  final p = products[i];
                  final sel = widget.selectedIds.contains(p.id);
                  return GestureDetector(
                    onTap: () => widget.onToggle(p.id),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: sel
                            ? cGreenTint
                            : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: sel ? cGreen : cLine,
                            width: sel ? 1.5 : 1),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 8,
                              offset: const Offset(0, 2))
                        ],
                      ),
                      child: Row(children: [
                        // Checkbox
                        AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                                color:
                                    sel ? cGreen : Colors.transparent,
                                border: Border.all(
                                    color: sel
                                        ? cGreen
                                        : cLine,
                                    width: 2),
                                borderRadius: BorderRadius.circular(7)),
                            child: sel
                                ? const Icon(Icons.check,
                                    color: Colors.white, size: 14)
                                : null),
                        const SizedBox(width: 12),
                        // Image
                        ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: p.images.isNotEmpty
                                ? Image.network(p.images.first,
                                    width: 46,
                                    height: 46,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) =>
                                        _imgPlaceholder())
                                : _imgPlaceholder()),
                        const SizedBox(width: 12),
                        // Info
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text(p.brand.toUpperCase(),
                                  style: const TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800,
                                      color: cGreen,
                                      letterSpacing: 1)),
                              const SizedBox(height: 2),
                              Text(p.name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                      color: cInk),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 3),
                              Row(children: [
                                QCategoryTag(
                                    category: categoryByKey(
                                        p.effectiveCategoryKey),
                                    fontSize: 9.5),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                      [p.type, p.category]
                                          .where((s) => s.isNotEmpty)
                                          .map(trValue)
                                          .join(' · '),
                                      style: const TextStyle(
                                          fontSize: 11, color: cInk2),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                ),
                              ]),
                            ])),
                        if (sel)
                          Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                  color: cGreen,
                                  borderRadius: BorderRadius.circular(6)),
                              child: const Text('✓',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800))),
                      ]),
                    ),
                  );
                },
              ), // closes ListView.builder
            ), // closes Expanded (else branch)
        ]); // closes Column(children:[...])
      },
    );
  }

  Widget _imgPlaceholder() => Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
          color: cGreenTint,
          borderRadius: BorderRadius.circular(10)),
      child: const Icon(Icons.inventory_2_outlined,
          color: cGreen, size: 20));
}

// ── Қадам 2: Размерлер + скидка ──────────────────────────────────────────────
class _Step2 extends StatelessWidget {
  final List<CartItem> cart;
  final List<ReservationModel> reservations;
  final void Function(int, Map<String, int>) onSizeChanged;
  final void Function(int) onDiscount;
  final void Function(int) onRemove;

  const _Step2({
    required this.cart,
    required this.reservations,
    required this.onSizeChanged,
    required this.onDiscount,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      itemCount: cart.length,
      itemBuilder: (_, ci) => _CartCard(
        item: cart[ci],
        cartIndex: ci,
        reservations: reservations,
        onSizeChanged: (s) => onSizeChanged(ci, s),
        onDiscount: () => onDiscount(ci),
        onRemove: () => onRemove(ci),
      ),
    );
  }
}

class _CartCard extends StatelessWidget {
  final CartItem item;
  final int cartIndex;
  final List<ReservationModel> reservations;
  final void Function(Map<String, int>) onSizeChanged;
  final VoidCallback onDiscount;
  final VoidCallback onRemove;

  const _CartCard({
    required this.item,
    required this.cartIndex,
    required this.reservations,
    required this.onSizeChanged,
    required this.onDiscount,
    required this.onRemove,
  });

  Map<String, int> get _availSizes {
    final m = Map.fromEntries(
        item.batch.sizesQuantity.entries.where((e) => e.value > 0));
    final sorted = m.entries.toList()
      ..sort((a, b) =>
          (int.tryParse(a.key) ?? 0).compareTo(int.tryParse(b.key) ?? 0));
    return Map.fromEntries(sorted);
  }

  void _setQty(String size, int qty) {
    final max = _availSizes[size] ?? 0;
    final newSizes = Map<String, int>.from(item.sizes);
    if (qty <= 0) {
      newSizes.remove(size);
    } else {
      newSizes[size] = qty.clamp(0, max);
    }
    onSizeChanged(newSizes);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 12,
                offset: const Offset(0, 3)),
            BoxShadow(
                color: cGreenTint.withValues(alpha: 0.5),
                blurRadius: 6,
                offset: const Offset(0, 1)),
          ]),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Товар жолы
          Row(children: [
            ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: item.product.images.isNotEmpty
                    ? Image.network(item.product.images.first,
                        width: 42,
                        height: 42,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _img())
                    : _img()),
            const SizedBox(width: 10),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(item.product.brand.toUpperCase(),
                      style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: cGreen,
                          letterSpacing: 1)),
                  Text(item.product.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: cInk),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  Text(tr('${item.batch.sellingPrice.toStringAsFixed(0)} ₸/шт.', '${item.batch.sellingPrice.toStringAsFixed(0)} ₸/дана'),
                      style: const TextStyle(
                          fontSize: 12,
                          color: cGreen,
                          fontWeight: FontWeight.w700)),
                ])),
            GestureDetector(
                onTap: onRemove,
                child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                        color: cRedTint,
                        borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.close,
                        size: 14, color: cRed))),
          ]),
          const SizedBox(height: 12),

          // Размер секциясының тақырыбы (метка зависит от категории)
          Text(
              tr('${categoryByKey(item.product.effectiveCategoryKey).sizeLabel.toUpperCase()} И КОЛИЧЕСТВО', '${categoryByKey(item.product.effectiveCategoryKey).sizeLabel.toUpperCase()} ЖӘНЕ САНЫ'),
              style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  color: cInk2,
                  letterSpacing: 0.8)),
          const SizedBox(height: 8),

          // Размер чиптері
          if (_availSizes.isEmpty)
            Text(tr('В этой партии нет остатка', 'Бұл партияда қалдық жоқ'),
                style: TextStyle(color: cRed, fontSize: 12))
          else
            Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _availSizes.entries.map((e) {
                  final size = e.key;
                  final maxQ = e.value;
                  final cartQ = item.sizes[size] ?? 0;
                  // Check if any active reservation blocks this size on this batch
                  final res = reservations
                      .where((r) =>
                          r.batchId == item.batch.id &&
                          r.size == size &&
                          r.isActive)
                      .toList();
                  final isReserved = res.isNotEmpty;
                  final minsLeft = isReserved ? res.first.minutesLeft : 0;
                  return _SizeChip(
                    size: size,
                    max: maxQ,
                    cartQty: cartQ,
                    isReserved: isReserved,
                    reservedMinutes: minsLeft,
                    onMinus: isReserved ? null : () => _setQty(size, cartQ - 1),
                    onPlus: isReserved ? null : () => _setQty(size, cartQ + 1),
                    onTap: isReserved
                        ? null
                        : () => _showQtyInput(context, size, maxQ, cartQ),
                  );
                }).toList()),

          const SizedBox(height: 12),

          // Скидка жолы
          GestureDetector(
            onTap: onDiscount,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                  color: item.discountPercent > 0
                      ? cAmberTint
                      : cBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: item.discountPercent > 0
                          ? cAmber.withValues(alpha: 0.4)
                          : cLine)),
              child: Row(children: [
                Icon(Icons.discount_outlined,
                    size: 16,
                    color: item.discountPercent > 0
                        ? cAmber
                        : cInk3),
                const SizedBox(width: 8),
                Expanded(
                    child: item.discountPercent > 0
                        ? Text(
                            '-${item.discountPercent.toStringAsFixed(0)}%  ·  '
                            '${item.total.toStringAsFixed(0)} ₸',
                            style: const TextStyle(
                                fontSize: 12,
                                color: cAmber,
                                fontWeight: FontWeight.w600))
                        : Text(tr('Добавить скидку', 'Жеңілдік қосу'),
                            style: TextStyle(
                                fontSize: 12, color: cInk3))),
                if (item.qty > 0)
                  Text('${item.total.toStringAsFixed(0)} ₸',
                      style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: cGreen)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _img() => Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
          color: cGreenTint,
          borderRadius: BorderRadius.circular(10)),
      child: const Icon(Icons.inventory_2_outlined,
          color: cGreen, size: 18));

  void _showQtyInput(BuildContext ctx, String size, int max, int current) {
    final ctrl = TextEditingController(text: '$current');
    showDialog(
      context: ctx,
      builder: (dCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(tr('Размер $size · макс. $max шт.', 'Өлшем $size · макс. $max дана'),
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        content: TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            autofocus: true,
            decoration: InputDecoration(
                suffixText: tr('шт.', 'дана'),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(
                        color: cGreen, width: 1.5)))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dCtx),
              child: Text(tr('Отмена', 'Болдырмау'),
                  style: TextStyle(color: cInk2))),
          ElevatedButton(
              onPressed: () {
                final v = int.tryParse(ctrl.text) ?? 0;
                _setQty(size, v.clamp(0, max));
                Navigator.pop(dCtx);
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: cGreen,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8))),
              child: const Text('ОК')),
        ],
      ),
    );
  }
}

// ── Size Chip ─────────────────────────────────────────────────────────────────
class _SizeChip extends StatelessWidget {
  final String size;
  final int max, cartQty;
  final bool isReserved;
  final int reservedMinutes;
  final VoidCallback? onMinus, onPlus, onTap;

  const _SizeChip({
    required this.size,
    required this.max,
    required this.cartQty,
    this.isReserved = false,
    this.reservedMinutes = 0,
    required this.onMinus,
    required this.onPlus,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (isReserved) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.shade300)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(size,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade400)),
          const SizedBox(height: 2),
          Text('🔒 $reservedMinutes мин',
              style: TextStyle(
                  fontSize: 9,
                  color: Colors.grey.shade500,
                  fontWeight: FontWeight.w600)),
        ]),
      );
    }

    final active = cartQty > 0;
    return Container(
      decoration: BoxDecoration(
          color: active
              ? cGreenTint
              : cBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: active
                  ? cGreen.withValues(alpha: 0.4)
                  : cLine,
              width: active ? 1.5 : 1)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        GestureDetector(
            onTap: cartQty > 0 ? onMinus : null,
            child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                    color: cartQty > 0
                        ? cRed.withValues(alpha: 0.8)
                        : Colors.grey.shade100,
                    borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(9),
                        bottomLeft: Radius.circular(9))),
                child: Icon(Icons.remove,
                    size: 13,
                    color: cartQty > 0 ? Colors.white : Colors.grey.shade400))),
        GestureDetector(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 7),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(size,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: active
                              ? cGreen
                              : cInk)),
                  Text(cartQty > 0 ? '$cartQty' : '0',
                      style: TextStyle(
                          fontSize: 11,
                          color: active ? cGreen : cInk3,
                          fontWeight:
                              active ? FontWeight.w700 : FontWeight.w400)),
                ],
              ),
            )),
        GestureDetector(
            onTap: cartQty < max ? onPlus : null,
            child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                    color:
                        cartQty < max ? cGreen : Colors.grey.shade100,
                    borderRadius: const BorderRadius.only(
                        topRight: Radius.circular(9),
                        bottomRight: Radius.circular(9))),
                child: Icon(Icons.add,
                    size: 13,
                    color:
                        cartQty < max ? Colors.white : Colors.grey.shade400))),
      ]),
    );
  }
}

// ── Footer ────────────────────────────────────────────────────────────────────
class _Footer extends StatelessWidget {
  final int step, selectedCount;
  final List<CartItem> cart;
  final bool isLoading;
  final VoidCallback onNext;

  const _Footer(
      {required this.step,
      required this.selectedCount,
      required this.cart,
      required this.isLoading,
      required this.onNext});

  @override
  Widget build(BuildContext context) {
    final totalQty = cart.fold(0, (s, c) => s + c.qty);
    final baseTotal = cart.fold(0.0, (s, c) => s + c.base);
    final finalTotal = cart.fold(0.0, (s, c) => s + c.total);
    final hasDiscount = baseTotal != finalTotal;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      decoration: BoxDecoration(color: Colors.white, boxShadow: [
        BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, -4))
      ]),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (step == 1 && totalQty > 0) ...[
          if (hasDiscount)
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(tr('Итого:', 'Барлығы:'),
                  style:
                      TextStyle(color: cInk2, fontSize: 13)),
              Text('${baseTotal.toStringAsFixed(0)} ₸',
                  style: const TextStyle(
                      fontSize: 13,
                      color: cInk3,
                      decoration: TextDecoration.lineThrough)),
            ]),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(tr('Итого: $totalQty шт.', 'Барлығы: $totalQty дана'),
                style: const TextStyle(
                    color: cInk2, fontSize: 14)),
            Text('${finalTotal.toStringAsFixed(0)} ₸',
                style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: cGreen,
                    letterSpacing: -0.5)),
          ]),
          const SizedBox(height: 10),
        ],
        SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: isLoading
                  ? null
                  : (step == 0 && selectedCount == 0)
                      ? null
                      : onNext,
              style: ElevatedButton.styleFrom(
                  backgroundColor:
                      step == 1 ? cGreen : cGreen,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey.shade200,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0),
              child: isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(
                          step == 0
                              ? Icons.arrow_forward_rounded
                              : Icons.check_circle_outline_rounded,
                          size: 18),
                      const SizedBox(width: 8),
                      Text(
                          step == 0
                              ? tr('Далее · $selectedCount товаров', 'Әрі қарай · $selectedCount тауар')
                              : tr('Подтвердить продажу · ${finalTotal.toStringAsFixed(0)} ₸', 'Сатуды растау · ${finalTotal.toStringAsFixed(0)} ₸'),
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 14)),
                    ]),
            )),
      ]),
    );
  }
}

// ── Toggle Button ─────────────────────────────────────────────────────────────
class _ToggleBtn extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _ToggleBtn(
      {required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
              color: active ? cGreen : cBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: active ? cGreen : cLine)),
          child: Text(label,
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: active ? Colors.white : cInk2)),
        ),
      );
}

// ── Payment method tile (Наличный / Kaspi) ────────────────────────────────────
class _PaymentMethodTile extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _PaymentMethodTile({
    required this.label,
    required this.onTap,
    this.color = cGreen,
  });

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
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
        ),
        child: Text(label, style: manrope(15, FontWeight.w700, color: Colors.white)),
      ),
    );
  }
}

