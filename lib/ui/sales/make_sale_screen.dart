import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/app_user.dart';
import '../../core/warehouse_context.dart';
import '../../data/models/models.dart';
import '../../data/services/firestore_service.dart';
import '../../theme/app_theme.dart';
import '../shared/mandatory_warehouse_picker.dart';

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
    if (mounted)
      setState(() {
        _cart = items;
        _step = 1;
        _isConfirming = false;
      });
  }

  // ── Сатуды растау ─────────────────────────────────────────────────────────
  Future<void> _confirm() async {
    if (_isConfirming) return;
    setState(() => _isConfirming = true);
    final whId = _activeWarehouseId(context);
    try {
      final validItems = _cart.where((c) => c.qty > 0).toList();
      if (validItems.isEmpty) {
        _snack('Выберите хотя бы 1 пару', isError: true);
        return;
      }

      // Pre-flight: if any cart item's batch belongs to a different warehouse
      // than the current one, the admin reassigned us while we were mid-sale.
      final hasConflict = validItems.any(
          (c) => c.batch.warehouseId.isNotEmpty && c.batch.warehouseId != whId);
      if (hasConflict) {
        _snack(
          'Ошибка: Ваша привязка к складу была изменена Админом. Данная продажа отменена.',
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
                  title: const Text('Тауар брондалған'),
                  content: Text('${item.product.name} (р. ${entry.key}) — '
                      'онлайн тапсырыспен брондалған. '
                      'Аздан кейін қайталаңыз.'),
                  actions: [
                    ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            foregroundColor: Colors.white),
                        child: const Text('Түсіндім')),
                  ],
                ),
              );
            }
            setState(() => _isConfirming = false);
            return;
          }
        }
      }

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
          idempotencyKey: key,
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
            Text('Продано $totalQty пар · ${totalPrice.toStringAsFixed(0)} ₸'),
          ]),
          backgroundColor: AppTheme.success,
          behavior: SnackBarBehavior.floating,
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
        backgroundColor: isError ? AppTheme.danger : AppTheme.success,
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
    final whName = wCtx.current?.name ?? 'Нет склада';

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
          child: Column(children: [
        // ── Premium Header ────────────────────────────────────────────────
        Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [
              Color(0xFF0F1F5C),
              Color(0xFF1E3A8A),
              Color(0xFF2D4FB5)
            ], begin: Alignment.topLeft, end: Alignment.bottomRight),
            boxShadow: [
              BoxShadow(
                  color: const Color(0xFF1E3A8A).withValues(alpha: 0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 6))
            ],
          ),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
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
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.18)),
                        borderRadius: BorderRadius.circular(11)),
                    child: const Icon(Icons.arrow_back_ios_new,
                        color: Colors.white, size: 15)),
              ),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(_step == 0 ? 'Новая продажа' : 'Размер и скидка',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.3)),
                    Text('Шаг ${_step + 1}/2',
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 11)),
                  ])),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    border:
                        Border.all(color: Colors.white.withValues(alpha: 0.2)),
                    borderRadius: BorderRadius.circular(20)),
                child: Text('${_step + 1} / 2',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13)),
              ),
            ]),
            const SizedBox(height: 12),
            // Warehouse pill
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.18)),
                  borderRadius: BorderRadius.circular(14)),
              child: Row(children: [
                Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.warehouse_outlined,
                        color: Colors.white, size: 15)),
                const SizedBox(width: 10),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      const Text('СКЛАД ПРОДАЖИ',
                          style: TextStyle(
                              color: Colors.white38,
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8)),
                      Text(whName,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w700)),
                    ])),
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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8)),
                      child: const Text('Сменить',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600)),
                    ),
                  ),
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
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24),
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
                  Text('${item.product.name} — Скидка',
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary)),
                  const SizedBox(height: 4),
                  Text('Базовая цена: ${item.base.toStringAsFixed(0)} ₸',
                      style: const TextStyle(
                          fontSize: 13, color: AppTheme.textSecondary)),
                  const SizedBox(height: 14),
                  Row(children: [
                    _ToggleBtn(
                        label: '% от цены',
                        active: byPercent,
                        onTap: () => setS(() => byPercent = true)),
                    const SizedBox(width: 8),
                    _ToggleBtn(
                        label: '₸ Новая цена',
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
                                          color: AppTheme.primary
                                              .withValues(alpha: 0.08),
                                          borderRadius:
                                              BorderRadius.circular(20),
                                          border: Border.all(
                                              color: AppTheme.primary
                                                  .withValues(alpha: 0.2))),
                                      child: Text('$p%',
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              color: AppTheme.primary))),
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
                    style: const TextStyle(
                        fontSize: 15, color: AppTheme.textPrimary),
                    decoration: InputDecoration(
                      labelText: byPercent ? 'Скидка %' : 'Финальная цена ₸',
                      suffixText: byPercent ? '%' : '₸',
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppTheme.border)),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                              color: AppTheme.primary, width: 1.5)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primary,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
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
                          child: const Text('Применить',
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
        const Text('Выберите склад для продажи',
            style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary)),
        const SizedBox(height: 12),
        ...warehouses.map((wh) => ListTile(
              leading: Icon(Icons.warehouse_outlined,
                  color: wh.id == currentId
                      ? AppTheme.primary
                      : AppTheme.textHint),
              title: Text(wh.name,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              trailing: wh.id == currentId
                  ? const Icon(Icons.check_rounded, color: AppTheme.primary)
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
  final void Function(String) onToggle;

  const _Step1(
      {required this.productStream,
      required this.selectedIds,
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
              child: CircularProgressIndicator(color: AppTheme.primary));
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
                      color: AppTheme.primary.withValues(alpha: 0.07),
                      shape: BoxShape.circle),
                  child: Icon(Icons.inventory_2_outlined,
                      size: 36, color: AppTheme.primary.withValues(alpha: 0.4)),
                ),
                const SizedBox(height: 16),
                const Text('На этом складе нет товаров',
                    style: TextStyle(
                        fontSize: 15,
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 6),
                const Text('Выберите другой склад',
                    style: TextStyle(fontSize: 12, color: AppTheme.textHint)),
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
                border: Border.all(color: AppTheme.border),
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
                    const TextStyle(fontSize: 14, color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Название, бренд, категория...',
                  hintStyle:
                      const TextStyle(color: AppTheme.textHint, fontSize: 13),
                  prefixIcon: const Icon(Icons.search_rounded,
                      color: AppTheme.textHint, size: 20),
                  suffixIcon: _query.isNotEmpty
                      ? GestureDetector(
                          onTap: () {
                            _searchCtrl.clear();
                            setState(() => _query = '');
                          },
                          child: const Icon(Icons.close_rounded,
                              color: AppTheme.textHint, size: 18))
                      : null,
                  border: InputBorder.none,
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
                    Text('«$_query» не найдено',
                        style: const TextStyle(
                            fontSize: 14, color: AppTheme.textSecondary)),
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
                            ? AppTheme.primary.withValues(alpha: 0.06)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: sel ? AppTheme.primary : AppTheme.border,
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
                                    sel ? AppTheme.primary : Colors.transparent,
                                border: Border.all(
                                    color: sel
                                        ? AppTheme.primary
                                        : AppTheme.border,
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
                                      color: AppTheme.primary,
                                      letterSpacing: 1)),
                              const SizedBox(height: 2),
                              Text(p.name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                      color: AppTheme.textPrimary),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                              Text('${p.type} · ${p.category}',
                                  style: const TextStyle(
                                      fontSize: 11,
                                      color: AppTheme.textSecondary)),
                            ])),
                        if (sel)
                          Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                  color: AppTheme.primary,
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
          color: AppTheme.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10)),
      child: const Icon(Icons.inventory_2_outlined,
          color: AppTheme.primary, size: 20));
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
                color: AppTheme.primary.withValues(alpha: 0.03),
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
                          color: AppTheme.primary,
                          letterSpacing: 1)),
                  Text(item.product.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: AppTheme.textPrimary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  Text('${item.batch.sellingPrice.toStringAsFixed(0)} ₸/пара',
                      style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.success,
                          fontWeight: FontWeight.w700)),
                ])),
            GestureDetector(
                onTap: onRemove,
                child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                        color: AppTheme.dangerLight,
                        borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.close,
                        size: 14, color: AppTheme.danger))),
          ]),
          const SizedBox(height: 12),

          // Размер секциясының тақырыбы
          const Text('РАЗМЕР И КОЛИЧЕСТВО',
              style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textSecondary,
                  letterSpacing: 0.8)),
          const SizedBox(height: 8),

          // Размер чиптері
          if (_availSizes.isEmpty)
            const Text('В этой партии нет остатка',
                style: TextStyle(color: AppTheme.danger, fontSize: 12))
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
                      ? AppTheme.warning.withValues(alpha: 0.08)
                      : AppTheme.background,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: item.discountPercent > 0
                          ? AppTheme.warning.withValues(alpha: 0.4)
                          : AppTheme.border)),
              child: Row(children: [
                Icon(Icons.discount_outlined,
                    size: 16,
                    color: item.discountPercent > 0
                        ? AppTheme.warning
                        : AppTheme.textHint),
                const SizedBox(width: 8),
                Expanded(
                    child: item.discountPercent > 0
                        ? Text(
                            '-${item.discountPercent.toStringAsFixed(0)}%  ·  '
                            '${item.total.toStringAsFixed(0)} ₸',
                            style: const TextStyle(
                                fontSize: 12,
                                color: AppTheme.warning,
                                fontWeight: FontWeight.w600))
                        : const Text('Добавить скидку',
                            style: TextStyle(
                                fontSize: 12, color: AppTheme.textHint))),
                if (item.qty > 0)
                  Text('${item.total.toStringAsFixed(0)} ₸',
                      style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: AppTheme.primary)),
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
          color: AppTheme.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10)),
      child: const Icon(Icons.inventory_2_outlined,
          color: AppTheme.primary, size: 18));

  void _showQtyInput(BuildContext ctx, String size, int max, int current) {
    final ctrl = TextEditingController(text: '$current');
    showDialog(
      context: ctx,
      builder: (dCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Размер $size · макс. $max пар',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        content: TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            autofocus: true,
            decoration: InputDecoration(
                suffixText: 'пар',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(
                        color: AppTheme.primary, width: 1.5)))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dCtx),
              child: const Text('Отмена',
                  style: TextStyle(color: AppTheme.textSecondary))),
          ElevatedButton(
              onPressed: () {
                final v = int.tryParse(ctrl.text) ?? 0;
                _setQty(size, v.clamp(0, max));
                Navigator.pop(dCtx);
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
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
              ? AppTheme.primary.withValues(alpha: 0.06)
              : AppTheme.background,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: active
                  ? AppTheme.primary.withValues(alpha: 0.4)
                  : AppTheme.border,
              width: active ? 1.5 : 1)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        GestureDetector(
            onTap: cartQty > 0 ? onMinus : null,
            child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                    color: cartQty > 0
                        ? AppTheme.danger.withValues(alpha: 0.8)
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
                              ? AppTheme.primary
                              : AppTheme.textPrimary)),
                  Text(cartQty > 0 ? '$cartQty' : '0',
                      style: TextStyle(
                          fontSize: 11,
                          color: active ? AppTheme.primary : AppTheme.textHint,
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
                        cartQty < max ? AppTheme.primary : Colors.grey.shade100,
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
              const Text('Итого:',
                  style:
                      TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
              Text('${baseTotal.toStringAsFixed(0)} ₸',
                  style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.textHint,
                      decoration: TextDecoration.lineThrough)),
            ]),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Итого: $totalQty пар',
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 14)),
            Text('${finalTotal.toStringAsFixed(0)} ₸',
                style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.primary,
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
                      step == 1 ? AppTheme.success : AppTheme.primary,
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
                              ? 'Далее · $selectedCount товаров'
                              : 'Подтвердить продажу · ${finalTotal.toStringAsFixed(0)} ₸',
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
              color: active ? AppTheme.primary : AppTheme.background,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: active ? AppTheme.primary : AppTheme.border)),
          child: Text(label,
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: active ? Colors.white : AppTheme.textSecondary)),
        ),
      );
}
