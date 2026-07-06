import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/app_user.dart';
import '../../../core/l10n_ext.dart';
import '../../../core/warehouse_context.dart';
import '../../../data/models/models.dart';
import '../../../data/services/firestore_service.dart';
import '../../../theme/qoima_design.dart';
import '../../../theme/qoima_v2.dart';
import '../../shared/skeletons.dart';
import 'add_product_screen.dart';
import 'product_detail_screen.dart';

import '../../../core/lang.dart';
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
  String _categoryKey = ''; // '' = все категории
  String _type = ''; // '' = все типы (категория таңдалғанда ғана қолданылады)
  _SortType _sort = _SortType.nameAz;
  final _searchCtrl = TextEditingController();

  // Карточкалар үшін batch деректері — енді жеке prefetch емес, негізгі
  // ағыннан (watchProductsWithBatches) бірге келеді. Қос оқу жойылды.
  Map<String, List<BatchModel>> _batchCache = {};
  // Pull-to-refresh кезінде ағынды қайта жасап, жаңа деректер тарту үшін.
  int _refreshTick = 0;

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

  // Бронь/ClickCollect резервтерін алып тастаған нақты бос қалдық
  int _totalQtyForProduct(String productId) =>
      (_batchCache[productId] ?? []).fold(0, (a, b) => a + b.totalAvailable);

  int get _cachedTotalPairs {
    int total = 0;
    for (final batches in _batchCache.values) {
      for (final b in batches) { total += b.totalAvailable; }
    }
    return total;
  }

  List<ProductModel> _filter(List<ProductModel> all) {
    var list = List<ProductModel>.from(all);
    if (_categoryKey.isNotEmpty) {
      list =
          list.where((p) => p.effectiveCategoryKey == _categoryKey).toList();
      if (_type.isNotEmpty) {
        list = list.where((p) => p.type == _type).toList();
      }
    }
    if (_tab == 1) {
      list = list.where((p) => p.status == ProductModel.statusInStock).toList();
    } else if (_tab == 2) {
      // Заканчиваются: в наличии, но меньше 10 пар
      list = list
          .where((p) =>
              p.status == ProductModel.statusInStock &&
              _totalQtyForProduct(p.id) < 10)
          .toList();
    } else if (_tab == 3) {
      // Нет: продано или 0 остаток
      list = list
          .where((p) =>
              p.status == ProductModel.statusSold ||
              _totalQtyForProduct(p.id) == 0)
          .toList();
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

  void _showSortSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: const EdgeInsets.all(20),
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
                const SizedBox(height: 16),
                Text(ctx.l10n.sortBy,
                    style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: cInk)),
                const SizedBox(height: 16),
                _SortOption(
                    icon: '🔤',
                    title: ctx.l10n.sortAZ,
                    selected: _sort == _SortType.nameAz,
                    onTap: () {
                      setState(() => _sort = _SortType.nameAz);
                      Navigator.pop(ctx);
                    }),
                _SortOption(
                    icon: '🔡',
                    title: ctx.l10n.sortZA,
                    selected: _sort == _SortType.nameZa,
                    onTap: () {
                      setState(() => _sort = _SortType.nameZa);
                      Navigator.pop(ctx);
                    }),
                _SortOption(
                    icon: '📦',
                    title: ctx.l10n.sortManyStock,
                    selected: _sort == _SortType.stockHigh,
                    onTap: () {
                      setState(() => _sort = _SortType.stockHigh);
                      Navigator.pop(ctx);
                    }),
                _SortOption(
                    icon: '⚠️',
                    title: ctx.l10n.sortFewStock,
                    selected: _sort == _SortType.stockLow,
                    onTap: () {
                      setState(() => _sort = _SortType.stockLow);
                      Navigator.pop(ctx);
                    }),
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
    final warehouseId = context.watch<WarehouseContext>().current?.id ??
        context.read<AppUser>().assignedWarehouseId;

    return Scaffold(
      backgroundColor: cBg,
      body: StreamBuilder<
          List<({ProductModel product, List<BatchModel> batches})>>(
        key: ValueKey('$warehouseId:$_refreshTick'),
        stream: _service.watchProductsWithBatches(warehouseId: warehouseId),
        builder: (context, snap) {
          final data = snap.data ?? const [];
          final allProducts = data.map((e) => e.product).toList();
          // batch деректері негізгі ағыннан бірге келеді — жеке prefetch жоқ.
          _batchCache = {for (final e in data) e.product.id: e.batches};

          final inStockCount = allProducts
              .where((p) => p.status == ProductModel.statusInStock)
              .length;
          final presentCatKeys = kCategories
              .map((c) => c.key)
              .where((k) =>
                  allProducts.any((p) => p.effectiveCategoryKey == k))
              .toList();
          // Категория бойынша дана саны (бос қалдық) — чиптегі көрсеткіш.
          final Map<String, int> qtyByCat = {};
          for (final p in allProducts) {
            qtyByCat[p.effectiveCategoryKey] =
                (qtyByCat[p.effectiveCategoryKey] ?? 0) +
                    _totalQtyForProduct(p.id);
          }
          // Таңдалған категория ішіндегі тип (вид) бойынша дана саны.
          final Map<String, int> qtyByType = {};
          if (_categoryKey.isNotEmpty) {
            for (final p in allProducts
                .where((p) => p.effectiveCategoryKey == _categoryKey)) {
              if (p.type.isEmpty) continue;
              qtyByType[p.type] =
                  (qtyByType[p.type] ?? 0) + _totalQtyForProduct(p.id);
            }
          }
          final filtered = _filter(allProducts);

          return RefreshIndicator(
            color: cGreen,
            onRefresh: () async {
              // Ағынды қайта құрып (key өзгереді), жаңа товар + batch тартамыз.
              setState(() => _refreshTick++);
              await _service.refreshProducts();
            },
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
            // ── Header ────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Container(
                decoration: const BoxDecoration(
                    gradient: LinearGradient(
                        colors: [Color(0xFF00713F), Color(0xFF00A862)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight)),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.readOnly ? 'Qoima' : tr('Товары', 'Тауарлар'),
                                    style: manrope(
                                      widget.readOnly ? 28 : 23,
                                      FontWeight.w800,
                                      color: Colors.white,
                                      letterSpacing: -0.5,
                                    ),
                                  ),
                                  Text(
                                    widget.readOnly
                                        ? context.l10n.inStockSubtitle
                                        : tr('$inStockCount мод. · $_cachedTotalPairs шт.', '$inStockCount мод. · $_cachedTotalPairs дана'),
                                    style: manrope(13, FontWeight.w500,
                                        color: Colors.white
                                            .withValues(alpha: 0.78)),
                                  ),
                                ],
                              ),
                            ),
                            if (!widget.readOnly)
                              GestureDetector(
                                onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (_) =>
                                            const AddProductScreen())),
                                child: Container(
                                  height: 38,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.16),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.add_rounded,
                                            color: Colors.white, size: 20),
                                        const SizedBox(width: 6),
                                        Text(tr('Добавить', 'Қосу'),
                                            style: manrope(13.5, FontWeight.w700,
                                                color: Colors.white)),
                                      ]),
                                ),
                              ),
                          ]),

                          // Current warehouse badge — visible for both admin and seller.
                          const SizedBox(height: 8),
                          Consumer<WarehouseContext>(
                            builder: (_, wCtx, __) {
                              final name = wCtx.current?.name;
                              if (name == null) return const SizedBox.shrink();
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                        color: Colors.white
                                            .withValues(alpha: 0.25))),
                                child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.warehouse_outlined,
                                          color: Colors.white70, size: 14),
                                      const SizedBox(width: 6),
                                      Text(name,
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600)),
                                    ]),
                              );
                            },
                          ),

                          const SizedBox(height: 14),
                          // Search + filter
                          Row(children: [
                            Expanded(
                              child: Container(
                                height: 46,
                                decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.16),
                                    borderRadius: BorderRadius.circular(14)),
                                child: TextField(
                                  controller: _searchCtrl,
                                  onChanged: (v) =>
                                      setState(() => _q = v.toLowerCase()),
                                  style: manrope(14.5, FontWeight.w500,
                                      color: Colors.white),
                                  decoration: InputDecoration(
                                      hintText: context.l10n.searchHint,
                                      hintStyle: manrope(14.5, FontWeight.w500,
                                          color: Colors.white.withValues(
                                              alpha: 0.8)),
                                      prefixIcon: Icon(Icons.search_rounded,
                                          color: Colors.white.withValues(
                                              alpha: 0.8),
                                          size: 19),
                                      suffixIcon: _q.isNotEmpty
                                          ? IconButton(
                                              icon: Icon(Icons.close_rounded,
                                                  size: 15,
                                                  color: Colors.white
                                                      .withValues(alpha: 0.8)),
                                              onPressed: () {
                                                _searchCtrl.clear();
                                                setState(() => _q = '');
                                              })
                                          : null,
                                      filled: false,
                                      border: InputBorder.none,
                                      enabledBorder: InputBorder.none,
                                      focusedBorder: InputBorder.none,
                                      disabledBorder: InputBorder.none,
                                      errorBorder: InputBorder.none,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              vertical: 13)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            GestureDetector(
                              onTap: _showSortSheet,
                              child: Container(
                                  width: 46,
                                  height: 46,
                                  decoration: BoxDecoration(
                                      color:
                                          Colors.white.withValues(alpha: 0.16),
                                      borderRadius: BorderRadius.circular(14)),
                                  child: const Icon(Icons.tune_rounded,
                                      color: Colors.white, size: 20)),
                            ),
                          ]),
                          const SizedBox(height: 12),
                          // Tabs
                          if (!widget.readOnly) ...[
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(children: [
                                _StockChip(
                                    label: tr('Все', 'Барлығы'),
                                    i: 0,
                                    cur: _tab,
                                    onTap: (i) => setState(() => _tab = i)),
                                const SizedBox(width: 8),
                                _StockChip(
                                    label: tr('В наличии', 'Қолда бар'),
                                    i: 1,
                                    cur: _tab,
                                    onTap: (i) => setState(() => _tab = i)),
                                const SizedBox(width: 8),
                                _StockChip(
                                    label: tr('Заканчиваются', 'Таусылып жатыр'),
                                    i: 2,
                                    cur: _tab,
                                    onTap: (i) => setState(() => _tab = i)),
                                const SizedBox(width: 8),
                                _StockChip(
                                    label: tr('Нет', 'Жоқ'),
                                    i: 3,
                                    cur: _tab,
                                    onTap: (i) => setState(() => _tab = i)),
                              ]),
                            ),
                            if (presentCatKeys.length > 1) ...[
                              const SizedBox(height: 10),
                              SizedBox(
                                height: 34,
                                child: ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: presentCatKeys.length + 1,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(width: 8),
                                  itemBuilder: (_, i) {
                                    final key =
                                        i == 0 ? '' : presentCatKeys[i - 1];
                                    final active = _categoryKey == key;
                                    final cat =
                                        key.isEmpty ? null : categoryByKey(key);
                                    // Категориядағы дана саны — чипте көрінеді.
                                    final qty = key.isEmpty
                                        ? _cachedTotalPairs
                                        : (qtyByCat[key] ?? 0);
                                    return GestureDetector(
                                      onTap: () => setState(() {
                                        _categoryKey = key;
                                        _type = ''; // тип сүзгісі жаңа категорияға көшпейді
                                      }),
                                      child: AnimatedContainer(
                                        duration:
                                            const Duration(milliseconds: 150),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: active
                                              ? Colors.white
                                              : Colors.white
                                                  .withValues(alpha: 0.16),
                                          borderRadius:
                                              BorderRadius.circular(11),
                                        ),
                                        child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              if (cat != null) ...[
                                                CategoryIcon(
                                                    kind: cat.iconKey,
                                                    size: 14,
                                                    color: active
                                                        ? cGreenDeep
                                                        : Colors.white),
                                                const SizedBox(width: 6),
                                              ],
                                              Text(cat?.short ?? tr('Все', 'Барлығы'),
                                                  style: manrope(12.5,
                                                      FontWeight.w700,
                                                      color: active
                                                          ? cGreenDeep
                                                          : Colors.white)),
                                              const SizedBox(width: 5),
                                              Container(
                                                padding: const EdgeInsets
                                                    .symmetric(
                                                    horizontal: 6,
                                                    vertical: 1),
                                                decoration: BoxDecoration(
                                                  color: active
                                                      ? cGreenDeep.withValues(
                                                          alpha: 0.12)
                                                      : Colors.white
                                                          .withValues(
                                                              alpha: 0.22),
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                child: Text('$qty',
                                                    style: manrope(11,
                                                        FontWeight.w800,
                                                        color: active
                                                            ? cGreenDeep
                                                            : Colors.white)),
                                              ),
                                            ]),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                            // Категория ішіндегі тип (вид) бойынша сан + сүзгі.
                            if (_categoryKey.isNotEmpty &&
                                qtyByType.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              SizedBox(
                                height: 30,
                                child: ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: qtyByType.length + 1,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(width: 8),
                                  itemBuilder: (_, i) {
                                    final types = qtyByType.keys.toList()
                                      ..sort((a, b) => (qtyByType[b] ?? 0)
                                          .compareTo(qtyByType[a] ?? 0));
                                    final t = i == 0 ? '' : types[i - 1];
                                    final active = _type == t;
                                    final label = t.isEmpty
                                        ? tr('Все типы', 'Барлық түрі')
                                        : '${trValue(t)} · ${qtyByType[t]}';
                                    return GestureDetector(
                                      onTap: () =>
                                          setState(() => _type = t),
                                      child: AnimatedContainer(
                                        duration: const Duration(
                                            milliseconds: 150),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 11, vertical: 5),
                                        decoration: BoxDecoration(
                                          color: active
                                              ? Colors.white
                                              : Colors.white
                                                  .withValues(alpha: 0.12),
                                          borderRadius:
                                              BorderRadius.circular(9),
                                          border: Border.all(
                                              color: active
                                                  ? Colors.white
                                                  : Colors.white.withValues(
                                                      alpha: 0.3)),
                                        ),
                                        child: Center(
                                          child: Text(label,
                                              style: manrope(
                                                  11.5, FontWeight.w700,
                                                  color: active
                                                      ? cGreenDeep
                                                      : Colors.white)),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                            const SizedBox(height: 10),
                            _WarehouseChip(service: _service),
                          ] else ...[
                            _TabChip(
                                label: context.l10n.inStockLabel,
                                i: 1,
                                cur: _tab,
                                onTap: (i) => setState(() => _tab = i)),
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
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                                color: cGreen.withValues(alpha: 0.1),
                                shape: BoxShape.circle),
                            child: Icon(Icons.inventory_2_outlined,
                                size: 48,
                                color:
                                    cGreen.withValues(alpha: 0.1))),
                        const SizedBox(height: 16),
                        Text(
                            _tab == 2
                                ? tr('Нет проданных товаров', 'Сатылған тауар жоқ')
                                : _q.isNotEmpty
                                    ? tr('Ничего не найдено', 'Ештеңе табылмады')
                                    : tr('Товаров нет', 'Тауар жоқ'),
                            style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                                color: cInk2)),
                        if (_tab != 2 && _q.isEmpty) ...[
                          const SizedBox(height: 6),
                          Text(tr('Нажмите «+» чтобы добавить товар', 'Тауар қосу үшін «+» басыңыз'),
                              style: TextStyle(
                                  fontSize: 13, color: cInk3)),
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
                      product: filtered[i],
                      batches: _batchCache[filtered[i].id] ?? const [],
                      readOnly: widget.readOnly,
                      warehouseId: warehouseId,
                      service: _service,
                    ),
                    childCount: filtered.length,
                  ),
                ),
              ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ── Stock filter chip (dark active style per spec) ────────────────────────────
class _StockChip extends StatelessWidget {
  final String label;
  final int i, cur;
  final void Function(int) onTap;
  const _StockChip(
      {required this.label,
      required this.i,
      required this.cur,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final active = i == cur;
    return GestureDetector(
      onTap: () => onTap(i),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: active ? cInk : cSurface,
          borderRadius: BorderRadius.circular(11),
          border: active ? null : Border.all(color: cLine),
        ),
        child: Text(label,
            style: manrope(12.5, FontWeight.w700,
                color: active ? Colors.white : cInk2)),
      ),
    );
  }
}

// ── Product Card ──────────────────────────────────────────────────────────────
class _ProductCard extends StatelessWidget {
  final ProductModel product;
  final List<BatchModel>
      batches; // Pre-loaded by parent — no per-card Firebase call.
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
      onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => ProductDetailScreen(product: product))),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: cSurface,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
                color: Color(0x0D0C120F),
                blurRadius: 12,
                offset: const Offset(0, 3)),
            BoxShadow(
                color: cGreen.withValues(alpha: 0.1),
                blurRadius: 6,
                offset: const Offset(0, 1)),
          ],
        ),
        child: Row(children: [
          // Image
          ClipRRect(
              borderRadius:
                  const BorderRadius.horizontal(left: Radius.circular(16)),
              child: product.images.isNotEmpty
                  ? Image.network(product.images.first,
                      width: 100,
                      height: 115,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _placeholder(),
                      loadingBuilder: (_, child, prog) =>
                          prog == null ? child : _placeholder())
                  : _placeholder()),
          // Content
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Text(product.brand.toUpperCase(),
                          style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: cGreen,
                              letterSpacing: 1)),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                            color: inStock
                                ? const Color(0xFFD1FAE5)
                                : const Color(0xFFF3F4F6),
                            borderRadius: BorderRadius.circular(6)),
                        child: Text(
                            inStock
                                ? context.l10n.inStockLabel
                                : context.l10n.soldLabel,
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: inStock
                                    ? const Color(0xFF065F46)
                                    : cInk3)),
                      ),
                    ]),
                    const SizedBox(height: 4),
                    Text(product.name,
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: cInk,
                            letterSpacing: -0.3),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Row(children: [
                      QCategoryTag(
                          category:
                              categoryByKey(product.effectiveCategoryKey),
                          fontSize: 10),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                            [product.type, product.category]
                                .where((s) => s.isNotEmpty)
                                .map(trValue)
                                .join(' · '),
                            style: const TextStyle(fontSize: 12, color: cInk2),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                            color: cBg,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: cLine)),
                        child: Text(product.articul,
                            style: const TextStyle(
                                fontSize: 11,
                                fontFamily: 'monospace',
                                color: cInk2,
                                fontWeight: FontWeight.w500)),
                      ),
                      const Spacer(),
                      const Icon(Icons.chevron_right_rounded,
                          color: cInk3, size: 20),
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
      ..sort((a, b) =>
          (int.tryParse(a.key) ?? 0).compareTo(int.tryParse(b.key) ?? 0));

    if (readOnly) {
      final activeBatch = batches.firstWhere((b) => b.totalAvailable > 0,
          orElse: () => batches.first);
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text('${activeBatch.sellingPrice.toStringAsFixed(0)} ₸',
            style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: cGreen)),
      );
    }

    if (avail.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: SizedBox(
        height: 22,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: avail
              .take(7)
              .map((e) => Container(
                    margin: const EdgeInsets.only(right: 5),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                        color: cGreen.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(5)),
                    child: Text('${e.key}·${e.value}',
                        style: const TextStyle(
                            fontSize: 10,
                            color: cGreen,
                            fontWeight: FontWeight.w600)),
                  ))
              .toList(),
        ),
      ),
    );
  }

  Widget _placeholder() => Container(
      width: 100,
      height: 115,
      color: const Color(0xFFEEF2FF),
      child: const Icon(Icons.inventory_2_outlined,
          color: cGreen, size: 32));
}

// ── Аналитика header — N видов × M шт. ────────────────────────────────────────
class StockSummaryWidget extends StatelessWidget {
  final int kinds;
  final int pairs;
  const StockSummaryWidget(
      {super.key, required this.kinds, required this.pairs});

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(fontSize: 13, color: cInk2),
        children: [
          TextSpan(
              text: '$kinds',
              style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: cGreen,
                  fontSize: 15)),
          TextSpan(text: tr(' вид. товаров  ×  ', ' көр. тауар  ×  ')),
          TextSpan(
              text: '$pairs',
              style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: cGreen,
                  fontSize: 15)),
          TextSpan(text: tr(' шт.', ' дана')),
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
    final wCtx = context.watch<WarehouseContext>();
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
          Text(current?.name ?? tr('Выбор склада', 'Қойма таңдау'),
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
          const SizedBox(width: 4),
          const Icon(Icons.expand_more_rounded,
              color: Colors.white70, size: 14),
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
      {required this.warehouses,
      required this.currentId,
      required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Center(
            child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height: 16),
        Text(tr('Выбор склада', 'Қойма таңдау'),
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: cInk)),
        const SizedBox(height: 12),
        ...warehouses.map((wh) => ListTile(
              leading: Icon(Icons.warehouse_outlined,
                  color: wh.id == currentId
                      ? cGreen
                      : cInk3),
              title: Text(wh.name),
              subtitle: wh.isMain
                  ? Text(tr('Основной склад', 'Негізгі қойма'),
                      style: TextStyle(fontSize: 11, color: cInk3))
                  : null,
              trailing: wh.id == currentId
                  ? const Icon(Icons.check_rounded, color: cGreen)
                  : null,
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
  const _TabChip(
      {required this.label,
      required this.i,
      required this.cur,
      required this.onTap});

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
                color: active ? cGreen : Colors.white,
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
  const _SortOption(
      {required this.icon,
      required this.title,
      required this.selected,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
            color: selected
                ? cGreen.withValues(alpha: 0.1)
                : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: selected ? cGreen : cLine,
                width: selected ? 1.5 : 1)),
        child: Row(children: [
          Text(icon, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(
              child: Text(title,
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color:
                          selected ? cGreen : cInk))),
          if (selected)
            const Icon(Icons.check_rounded, color: cGreen, size: 20),
        ]),
      ),
    );
  }
}

