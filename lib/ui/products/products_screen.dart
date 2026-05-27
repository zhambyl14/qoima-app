import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_user.dart';
import '../../core/l10n_ext.dart';
import '../../core/warehouse_context.dart';
import '../../data/models/models.dart';
import '../../data/services/firestore_service.dart';
import '../../theme/app_theme.dart';
import '../shared/skeletons.dart';
import 'add_product_screen.dart';
import 'product_detail_screen.dart';

enum _SortType { nameAz, nameZa, stockHigh, stockLow }

class ProductsScreen extends StatefulWidget {
  final bool readOnly;
  const ProductsScreen({super.key, this.readOnly = false});
  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  final _service = FirestoreService();
  late int _tab;
  String _q = '';
  _SortType _sort = _SortType.nameAz;
  final _searchCtrl = TextEditingController();

  // Batch cache to avoid N+1 per-card Firestore reads.
  Map<String, List<BatchModel>> _batchCache = {};
  String _lastCacheKey = '';

  @override
  void initState() {
    super.initState();
    _tab = widget.readOnly ? 1 : 0;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<ProductModel> _filter(List<ProductModel> all) {
    var list = List<ProductModel>.from(all);
    if (_tab == 1) {
      list = list.where((p) => p.status == ProductModel.statusInStock).toList();
    } else if (_tab == 2) {
      list = list.where((p) => p.status == ProductModel.statusSold).toList();
    }
    if (_q.isNotEmpty) {
      list = list
          .where((p) =>
              p.name.toLowerCase().contains(_q) ||
              p.brand.toLowerCase().contains(_q) ||
              p.articul.toLowerCase().contains(_q) ||
              p.type.toLowerCase().contains(_q))
          .toList();
    }
    switch (_sort) {
      case _SortType.nameAz:
        list.sort((a, b) => a.name.compareTo(b.name));
        break;
      case _SortType.nameZa:
        list.sort((a, b) => b.name.compareTo(a.name));
        break;
      case _SortType.stockHigh:
      case _SortType.stockLow:
        list.sort((a, b) => a.name.compareTo(b.name));
        break;
    }
    return list;
  }

  // Prefetches batch data for all products in parallel (fixes N+1).
  // Uses a cache key to avoid redundant re-fetching on state-only rebuilds.
  void _prefetchBatches(List<ProductModel> products, String warehouseId) {
    final ids     = (products.map((p) => p.id).toList()..sort()).join(',');
    final cacheKey = '$warehouseId:$ids';
    if (cacheKey == _lastCacheKey) return;
    _lastCacheKey = cacheKey;

    Future.wait(products.map((p) => _service.getBatches(p.id))).then((results) {
      if (!mounted) return;
      final cache = <String, List<BatchModel>>{};
      for (var i = 0; i < products.length; i++) {
        cache[products[i].id] = warehouseId.isNotEmpty
            ? results[i].where((b) => b.warehouseId == warehouseId).toList()
            : results[i];
      }
      setState(() => _batchCache = cache);
    }).catchError((_) {
      // Prefetch errors are non-critical: cards will simply show no batch info.
      _lastCacheKey = ''; // Allow retry on next rebuild.
    });
  }

  void _showSortSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 36, height: 4,
                decoration: BoxDecoration(color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Text(ctx.l10n.sortBy,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary)),
            const SizedBox(height: 16),
            _SortOption(icon: '🔤', title: ctx.l10n.sortAZ,
                selected: _sort == _SortType.nameAz,
                onTap: () { setState(() => _sort = _SortType.nameAz); Navigator.pop(ctx); }),
            _SortOption(icon: '🔡', title: ctx.l10n.sortZA,
                selected: _sort == _SortType.nameZa,
                onTap: () { setState(() => _sort = _SortType.nameZa); Navigator.pop(ctx); }),
            _SortOption(icon: '📦', title: ctx.l10n.sortManyStock,
                selected: _sort == _SortType.stockHigh,
                onTap: () { setState(() => _sort = _SortType.stockHigh); Navigator.pop(ctx); }),
            _SortOption(icon: '⚠️', title: ctx.l10n.sortFewStock,
                selected: _sort == _SortType.stockLow,
                onTap: () { setState(() => _sort = _SortType.stockLow); Navigator.pop(ctx); }),
            const SizedBox(height: 8),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // WarehouseContext now works for both admin AND seller (loaded via load()).
    // Fallback to AppUser.assignedWarehouseId for safety during initial load.
    final warehouseId = context.watch<WarehouseContext>().current?.id
        ?? context.read<AppUser>().assignedWarehouseId;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: StreamBuilder<List<ProductModel>>(
        key: ValueKey(warehouseId),
        initialData: _service.cachedProducts,
        stream: warehouseId.isNotEmpty
            ? _service
                .watchProductsInWarehouse(warehouseId)
                .map((list) => list.map((e) => e.product).toList())
            : _service.watchProducts(),
        builder: (context, snap) {
          final allProducts = snap.data ?? [];

          // Kick off parallel batch preload when new product data arrives.
          if (snap.hasData) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _prefetchBatches(allProducts, warehouseId);
            });
          }

          final inStockCount = allProducts
              .where((p) => p.status == ProductModel.statusInStock)
              .length;
          final filtered = _filter(allProducts);

          return CustomScrollView(slivers: [
            // ── Header ────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                      colors: [Color(0xFF1E3A8A), Color(0xFF2D4FB5)],
                      begin: Alignment.topLeft, end: Alignment.bottomRight)),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text('Qoima',
                              style: TextStyle(color: Colors.white, fontSize: 28,
                                  fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                          Text(
                            widget.readOnly
                                ? context.l10n.inStockSubtitle
                                : context.l10n.manageWarehouseSubtitle,
                            style: const TextStyle(color: Colors.white60, fontSize: 13)),
                        ]),
                        const Spacer(),
                        FutureBuilder<int>(
                          future: _calcTotalPairs(
                              allProducts.where((p) => p.status == ProductModel.statusInStock).toList(),
                              warehouseId),
                          builder: (_, pairSnap) {
                            final pairs = pairSnap.data ?? 0;
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.2))),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                                Text('$inStockCount вид.',
                                    style: const TextStyle(color: Colors.white,
                                        fontWeight: FontWeight.w700, fontSize: 15)),
                                Text('$pairs пар',
                                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
                              ]),
                            );
                          },
                        ),
                      ]),

                      // Current warehouse badge — visible for both admin and seller.
                      const SizedBox(height: 8),
                      Consumer<WarehouseContext>(
                        builder: (_, wCtx, __) {
                          final name = wCtx.current?.name;
                          if (name == null) return const SizedBox.shrink();
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.25))),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              const Icon(Icons.warehouse_outlined,
                                  color: Colors.white70, size: 14),
                              const SizedBox(width: 6),
                              Text(name,
                                  style: const TextStyle(color: Colors.white,
                                      fontSize: 12, fontWeight: FontWeight.w600)),
                            ]),
                          );
                        },
                      ),

                      const SizedBox(height: 14),
                      // Search + sort
                      Row(children: [
                        Expanded(
                          child: Container(
                            height: 42,
                            decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(11)),
                            child: TextField(
                              controller: _searchCtrl,
                              onChanged: (v) => setState(() => _q = v.toLowerCase()),
                              style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary),
                              decoration: InputDecoration(
                                hintText: context.l10n.searchHint,
                                hintStyle: const TextStyle(color: AppTheme.textHint, fontSize: 13),
                                prefixIcon: const Icon(Icons.search, color: AppTheme.primary, size: 19),
                                suffixIcon: _q.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.close, size: 15, color: AppTheme.textHint),
                                        onPressed: () { _searchCtrl.clear(); setState(() => _q = ''); })
                                    : null,
                                filled: false, border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(vertical: 12)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: _showSortSheet,
                          child: Container(
                            width: 42, height: 42,
                            decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(11)),
                            child: const Icon(Icons.tune_rounded, color: Colors.white, size: 20)),
                        ),
                      ]),
                      const SizedBox(height: 12),
                      // Tabs
                      Row(children: [
                        if (!widget.readOnly) ...[
                          _TabChip(label: context.l10n.allProductsLabel, i: 0, cur: _tab,
                              onTap: (i) => setState(() => _tab = i)),
                          const SizedBox(width: 8),
                        ],
                        _TabChip(label: context.l10n.inStockLabel, i: 1, cur: _tab,
                            onTap: (i) => setState(() => _tab = i)),
                        if (!widget.readOnly) ...[
                          const SizedBox(width: 8),
                          _TabChip(label: context.l10n.soldLabel, i: 2, cur: _tab,
                              onTap: (i) => setState(() => _tab = i)),
                        ],
                      ]),
                      // Admin-only warehouse switcher chip.
                      if (!widget.readOnly) ...[
                        const SizedBox(height: 10),
                        _WarehouseChip(service: _service),
                      ],
                    ]),
                  ),
                ),
              ),
            ),

            // ── List ──────────────────────────────────────────────────
            if (snap.connectionState == ConnectionState.waiting)
              const SliverFillRemaining(
                hasScrollBody: true,
                child: ProductsSkeleton(),
              )
            else if (filtered.isEmpty)
              SliverFillRemaining(
                child: Center(
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.06),
                          shape: BoxShape.circle),
                      child: Icon(Icons.inventory_2_outlined, size: 48,
                          color: AppTheme.primary.withValues(alpha: 0.4))),
                    const SizedBox(height: 16),
                    Text(
                      _tab == 2 ? 'Нет проданных товаров'
                          : _q.isNotEmpty ? 'Ничего не найдено' : 'Товаров нет',
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600,
                          color: AppTheme.textSecondary)),
                    if (_tab != 2 && _q.isEmpty) ...[
                      const SizedBox(height: 6),
                      const Text('Нажмите «+» чтобы добавить товар',
                          style: TextStyle(fontSize: 13, color: AppTheme.textHint)),
                    ],
                  ]),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 100),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) => _ProductCard(
                      key: ValueKey(filtered[i].id),
                      product:     filtered[i],
                      batches:     _batchCache[filtered[i].id] ?? const [],
                      readOnly:    widget.readOnly,
                      warehouseId: warehouseId,
                      service:     _service,
                    ),
                    childCount: filtered.length,
                  ),
                ),
              ),
          ]);
        },
      ),
      floatingActionButton: (!widget.readOnly && _tab != 2)
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const AddProductScreen())),
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              elevation: 6,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Добавить', style: TextStyle(fontWeight: FontWeight.w700)))
          : null,
    );
  }

  Future<int> _calcTotalPairs(List<ProductModel> products, String warehouseId) async {
    int total = 0;
    for (final p in products) {
      try {
        final batches = _batchCache[p.id] ?? await _service.getBatches(p.id);
        final relevant = warehouseId.isNotEmpty
            ? batches.where((b) => b.warehouseId == warehouseId).toList()
            : batches;
        for (final b in relevant) { total += b.totalQuantity; }
      } catch (_) {}
    }
    return total;
  }
}

// ── Product Card ──────────────────────────────────────────────────────────────
class _ProductCard extends StatelessWidget {
  final ProductModel product;
  final List<BatchModel> batches; // Pre-loaded by parent — no per-card Firebase call.
  final FirestoreService service;
  final bool readOnly;
  final String warehouseId;

  const _ProductCard({
    super.key,
    required this.product,
    required this.batches,
    required this.service,
    this.readOnly = false,
    this.warehouseId = '',
  });

  @override
  Widget build(BuildContext context) {
    final inStock = product.status == ProductModel.statusInStock;
    return GestureDetector(
      onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => ProductDetailScreen(product: product))),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 12, offset: const Offset(0, 3)),
            BoxShadow(color: AppTheme.primary.withValues(alpha: 0.04),
                blurRadius: 6, offset: const Offset(0, 1)),
          ],
        ),
        child: Row(children: [
          // Image
          ClipRRect(
            borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
            child: product.images.isNotEmpty
                ? Image.network(product.images.first, width: 100, height: 115,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _placeholder(),
                    loadingBuilder: (_, child, prog) => prog == null ? child : _placeholder())
                : _placeholder()),
          // Content
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text(product.brand.toUpperCase(),
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800,
                          color: AppTheme.primary, letterSpacing: 1)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: inStock ? const Color(0xFFD1FAE5) : const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(6)),
                    child: Text(
                        inStock ? context.l10n.inStockLabel : context.l10n.soldLabel,
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                            color: inStock ? const Color(0xFF065F46) : AppTheme.textHint)),
                  ),
                ]),
                const SizedBox(height: 4),
                Text(product.name,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary, letterSpacing: -0.3),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text('${product.type} · ${product.category}',
                    style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                const SizedBox(height: 8),
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(color: AppTheme.background,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppTheme.border)),
                    child: Text(product.articul,
                        style: const TextStyle(fontSize: 11, fontFamily: 'monospace',
                            color: AppTheme.textSecondary, fontWeight: FontWeight.w500)),
                  ),
                  const Spacer(),
                  const Icon(Icons.chevron_right_rounded, color: AppTheme.textHint, size: 20),
                ]),
                // Batch summary from pre-loaded cache (no Firebase call here).
                _buildBatchSummary(context),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildBatchSummary(BuildContext context) {
    if (batches.isEmpty) return const SizedBox.shrink();

    final Map<String, int> total = {};
    for (final b in batches) {
      b.sizesQuantity.forEach((k, v) => total[k] = (total[k] ?? 0) + v);
    }
    final avail = total.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => (int.tryParse(a.key) ?? 0).compareTo(int.tryParse(b.key) ?? 0));

    if (readOnly) {
      final activeBatch = batches.firstWhere(
        (b) => b.totalQuantity > 0, orElse: () => batches.first);
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text('${activeBatch.sellingPrice.toStringAsFixed(0)} ₸',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800,
                color: AppTheme.success)),
      );
    }

    if (avail.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: SizedBox(
        height: 22,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: avail.take(7).map((e) => Container(
            margin: const EdgeInsets.only(right: 5),
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(5)),
            child: Text('${e.key}·${e.value}',
                style: const TextStyle(fontSize: 10, color: AppTheme.primary,
                    fontWeight: FontWeight.w600)),
          )).toList(),
        ),
      ),
    );
  }

  Widget _placeholder() => Container(
      width: 100, height: 115, color: const Color(0xFFEEF2FF),
      child: const Icon(Icons.inventory_2_outlined, color: AppTheme.primary, size: 32));
}

// ── Аналитика header — N видов × M пар ────────────────────────────────────────
class StockSummaryWidget extends StatelessWidget {
  final int kinds;
  final int pairs;
  const StockSummaryWidget({super.key, required this.kinds, required this.pairs});

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
        children: [
          TextSpan(text: '$kinds',
              style: const TextStyle(fontWeight: FontWeight.w800,
                  color: AppTheme.primary, fontSize: 15)),
          const TextSpan(text: ' вид. товаров  ×  '),
          TextSpan(text: '$pairs',
              style: const TextStyle(fontWeight: FontWeight.w800,
                  color: AppTheme.primary, fontSize: 15)),
          const TextSpan(text: ' пар'),
        ],
      ),
    );
  }
}

// ── Warehouse chip (admin only) ───────────────────────────────────────────────
class _WarehouseChip extends StatelessWidget {
  final FirestoreService service;
  const _WarehouseChip({required this.service});

  @override
  Widget build(BuildContext context) {
    final wCtx    = context.watch<WarehouseContext>();
    final current = wCtx.current;
    return GestureDetector(
      onTap: () async {
        final warehouses = await service.getWarehouses();
        if (!context.mounted) return;
        showModalBottomSheet(
          context: context,
          shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          builder: (_) => _WarehousePickerSheet(
            warehouses: warehouses,
            currentId: current?.id ?? '',
            onSelect: (wh) {
              context.read<WarehouseContext>().switchTo(wh);
              Navigator.pop(context);
            },
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.3))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.warehouse_outlined, color: Colors.white70, size: 14),
          const SizedBox(width: 6),
          Text(current?.name ?? 'Қойма таңдау',
              style: const TextStyle(color: Colors.white,
                  fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(width: 4),
          const Icon(Icons.expand_more_rounded, color: Colors.white70, size: 14),
        ]),
      ),
    );
  }
}

class _WarehousePickerSheet extends StatelessWidget {
  final List<WarehouseModel> warehouses;
  final String currentId;
  final void Function(WarehouseModel) onSelect;
  const _WarehousePickerSheet(
      {required this.warehouses, required this.currentId, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Center(child: Container(width: 36, height: 4,
            decoration: BoxDecoration(color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height: 16),
        const Text('Қойма таңдау',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary)),
        const SizedBox(height: 12),
        ...warehouses.map((wh) => ListTile(
          leading: Icon(Icons.warehouse_outlined,
              color: wh.id == currentId ? AppTheme.primary : AppTheme.textHint),
          title: Text(wh.name),
          subtitle: wh.isMain
              ? const Text('Негізгі қойма',
                  style: TextStyle(fontSize: 11, color: AppTheme.textHint))
              : null,
          trailing: wh.id == currentId
              ? const Icon(Icons.check_rounded, color: AppTheme.primary) : null,
          onTap: () => onSelect(wh),
        )),
      ]),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────
class _TabChip extends StatelessWidget {
  final String label;
  final int i, cur;
  final void Function(int) onTap;
  const _TabChip({required this.label, required this.i,
      required this.cur, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final active = i == cur;
    return GestureDetector(
      onTap: () => onTap(i),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20)),
        child: Text(label,
            style: TextStyle(
                color: active ? AppTheme.primary : Colors.white,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                fontSize: 13)),
      ),
    );
  }
}

class _SortOption extends StatelessWidget {
  final String icon, title;
  final bool selected;
  final VoidCallback onTap;
  const _SortOption({required this.icon, required this.title,
      required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primary.withValues(alpha: 0.07) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: selected ? AppTheme.primary : AppTheme.border,
              width: selected ? 1.5 : 1)),
        child: Row(children: [
          Text(icon, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(child: Text(title,
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14,
                  color: selected ? AppTheme.primary : AppTheme.textPrimary))),
          if (selected)
            const Icon(Icons.check_rounded, color: AppTheme.primary, size: 20),
        ]),
      ),
    );
  }
}
