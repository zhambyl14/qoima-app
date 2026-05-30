import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/models/store_model.dart';
import '../../data/models/product_model.dart';
import '../../data/models/batch_model.dart';
import '../../data/models/cart_item_model.dart';
import '../../data/services/client_service.dart';
import '../../theme/qoima_design.dart';
import 'client_product_detail.dart';
import 'client_filters_sheet.dart';
import 'client_shell.dart';

// ── Filters state ──────────────────────────────────────────────────────────────
class ClientFilters {
  final String search;
  final String? storeId;
  final Set<String> types;
  final Set<String> brands;
  final Set<String> sizes;
  final Set<String> colors;
  final Set<String> categories;
  final double? minPrice;
  final double? maxPrice;

  const ClientFilters({
    this.search = '',
    this.storeId,
    this.types = const {},
    this.brands = const {},
    this.sizes = const {},
    this.colors = const {},
    this.categories = const {},
    this.minPrice,
    this.maxPrice,
  });

  int get activeCount {
    int c = 0;
    if (storeId != null) c++;
    if (types.isNotEmpty) c++;
    if (brands.isNotEmpty) c++;
    if (sizes.isNotEmpty) c++;
    if (colors.isNotEmpty) c++;
    if (categories.isNotEmpty) c++;
    if (minPrice != null || maxPrice != null) c++;
    return c;
  }

  ClientFilters copyWith({
    String? search,
    Object? storeId = _sentinel,
    Set<String>? types,
    Set<String>? brands,
    Set<String>? sizes,
    Set<String>? colors,
    Set<String>? categories,
    Object? minPrice = _sentinel,
    Object? maxPrice = _sentinel,
  }) =>
      ClientFilters(
        search: search ?? this.search,
        storeId: storeId == _sentinel ? this.storeId : storeId as String?,
        types: types ?? this.types,
        brands: brands ?? this.brands,
        sizes: sizes ?? this.sizes,
        colors: colors ?? this.colors,
        categories: categories ?? this.categories,
        minPrice: minPrice == _sentinel ? this.minPrice : minPrice as double?,
        maxPrice: maxPrice == _sentinel ? this.maxPrice : maxPrice as double?,
      );
}

const _sentinel = Object();

// ── Screen ─────────────────────────────────────────────────────────────────────
class ClientHomeScreen extends StatefulWidget {
  const ClientHomeScreen({super.key});

  @override
  State<ClientHomeScreen> createState() => _ClientHomeScreenState();
}

class _ClientHomeScreenState extends State<ClientHomeScreen> {
  final _service = ClientService();
  final _scrollCtrl = ScrollController();
  final _searchCtrl = TextEditingController();

  List<StoreModel> _stores = [];
  List<({ProductModel product, List<BatchModel> batches})> _pairs = [];
  Map<String, StoreModel> _productStoreMap = {};
  bool _loadingStores = true;
  bool _loadingProducts = false;
  ClientFilters _filters = const ClientFilters();
  String? _errorMessage;
  int _displayCount = 20;
  String _selectedType = ''; // '' = Все

  List<String> get _uniqueTypes {
    final cats = _pairs
        .map((p) => p.product.category)
        .where((c) => c.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return cats;
  }

  List<({ProductModel product, List<BatchModel> batches})> get _shown {
    final f = _filters;
    final filtered = _pairs.where((pair) {
      final p = pair.product;
      final b = pair.batches;
      if (_selectedType.isNotEmpty && p.category != _selectedType) return false;
      if (f.types.isNotEmpty && !f.types.contains(p.type)) return false;
      if (f.brands.isNotEmpty && !f.brands.contains(p.brand)) return false;
      if (f.colors.isNotEmpty && !f.colors.contains(p.color)) return false;
      if (f.categories.isNotEmpty && !f.categories.contains(p.category)) {
        return false;
      }
      if (f.search.isNotEmpty) {
        final q = f.search.toLowerCase();
        if (!p.name.toLowerCase().contains(q) &&
            !p.brand.toLowerCase().contains(q)) {
          return false;
        }
      }
      if (f.sizes.isNotEmpty) {
        final hasSize =
            b.any((bt) => f.sizes.any((s) => bt.availableSizes.containsKey(s)));
        if (!hasSize) return false;
      }
      if (f.minPrice != null || f.maxPrice != null) {
        final hasPrice = b.any((bt) =>
            (f.minPrice == null || bt.sellingPrice >= f.minPrice!) &&
            (f.maxPrice == null || bt.sellingPrice <= f.maxPrice!));
        if (!hasPrice) return false;
      }
      return true;
    }).toList();

    final isFiltered = f.search.isNotEmpty || f.activeCount > 0;
    return isFiltered ? filtered : filtered.take(_displayCount).toList();
  }

  bool get _hasMore =>
      _filters.search.isEmpty &&
      _filters.activeCount == 0 &&
      _displayCount < _pairs.length;

  @override
  void initState() {
    super.initState();
    _loadAllProducts();
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_hasMore &&
        _scrollCtrl.position.pixels >=
            _scrollCtrl.position.maxScrollExtent - 200) {
      setState(() => _displayCount += 20);
    }
  }

  Future<void> _loadAllProducts() async {
    setState(() {
      _loadingStores = true;
      _errorMessage = null;
    });
    try {
      final stores = await _service.getPublishedStores();
      if (!mounted) return;
      setState(() {
        _stores = stores;
        _loadingStores = false;
        if (stores.isNotEmpty) _loadingProducts = true;
      });
      if (stores.isEmpty) return;

      final pairs = <({ProductModel product, List<BatchModel> batches})>[];
      final storeMap = <String, StoreModel>{};
      for (final store in stores) {
        if (store.visibleWarehouseIds.isEmpty) continue;
        final sp = await _service.getStoreProductsWithBatches(
            store.adminUid, store.visibleWarehouseIds);
        for (final p in sp) {
          storeMap[p.product.id] = store;
        }
        pairs.addAll(sp);
      }
      if (!mounted) return;
      setState(() {
        _pairs = pairs;
        _productStoreMap = storeMap;
        _loadingProducts = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingStores = false;
          _loadingProducts = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  void _openFilters() async {
    if (_stores.isEmpty) return;
    final updated = await showModalBottomSheet<ClientFilters>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ClientFiltersSheet(
        pairs: _pairs,
        stores: _stores,
        current: _filters,
      ),
    );
    if (updated != null && mounted) {
      setState(() {
        _filters = updated;
        _displayCount = 20;
      });
    }
  }

  void _removeFilter(String key) {
    setState(() {
      _displayCount = 20;
      switch (key) {
        case 'store':
          _filters = _filters.copyWith(storeId: null);
          break;
        case 'types':
          _filters = _filters.copyWith(types: {});
          break;
        case 'brands':
          _filters = _filters.copyWith(brands: {});
          break;
        case 'sizes':
          _filters = _filters.copyWith(sizes: {});
          break;
        case 'colors':
          _filters = _filters.copyWith(colors: {});
          break;
        case 'cats':
          _filters = _filters.copyWith(categories: {});
          break;
        case 'price':
          _filters = _filters.copyWith(minPrice: null, maxPrice: null);
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final activeChips = _buildActiveChips();
    // Show filtered store name, or generic "Каталог" when no store filter active
    final filteredStore = _filters.storeId != null && _stores.isNotEmpty
        ? _stores.firstWhere((s) => s.adminUid == _filters.storeId,
            orElse: () => _stores.first)
        : null;
    final storeName = filteredStore?.storeName ?? 'Каталог';
    final storeAddress = filteredStore?.address ?? '';

    return Scaffold(
      backgroundColor: cBg,
      body: SafeArea(
        child: Column(children: [
          // ── Gradient header ─────────────────────────────────────────────
          Container(
            decoration: const BoxDecoration(gradient: kGrad),
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
                child: Row(children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(storeName,
                            style: manrope(23, FontWeight.w800,
                                color: Colors.white, letterSpacing: -0.5)),
                        if (storeAddress.isNotEmpty)
                          Text(storeAddress,
                              style: manrope(13, FontWeight.w500,
                                  color: Colors.white.withValues(alpha: 0.78))),
                      ],
                    ),
                  ),
                  QHeaderBtn(Icons.favorite_border_rounded),
                ]),
              ),
              // Search row
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: Row(children: [
                  Expanded(
                    child: Container(
                      height: 46,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(children: [
                        const SizedBox(width: 12),
                        Icon(Icons.search_rounded,
                            color: Colors.white.withValues(alpha: 0.8),
                            size: 19),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _searchCtrl,
                            onChanged: (q) => setState(() {
                              _filters = _filters.copyWith(search: q.trim());
                              _displayCount = 20;
                            }),
                            style: manrope(14.5, FontWeight.w500,
                                color: Colors.white),
                            decoration: InputDecoration(
                              hintText: 'Поиск обуви...',
                              hintStyle: manrope(14.5, FontWeight.w500,
                                  color: Colors.white.withValues(alpha: 0.8)),
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.zero,
                              isDense: true,
                              suffixIcon: _filters.search.isNotEmpty
                                  ? GestureDetector(
                                      onTap: () {
                                        _searchCtrl.clear();
                                        setState(() => _filters =
                                            _filters.copyWith(search: ''));
                                      },
                                      child: Icon(Icons.close_rounded,
                                          color: Colors.white.withValues(
                                              alpha: 0.8),
                                          size: 18))
                                  : null,
                            ),
                          ),
                        ),
                      ]),
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: _openFilters,
                    child: Stack(clipBehavior: Clip.none, children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.tune_rounded,
                            color: Colors.white, size: 20),
                      ),
                      if (_filters.activeCount > 0)
                        Positioned(
                          top: -4,
                          right: -4,
                          child: Container(
                            width: 18,
                            height: 18,
                            decoration: const BoxDecoration(
                                color: cAmber, shape: BoxShape.circle),
                            child: Center(
                              child: Text('${_filters.activeCount}',
                                  style: manrope(10, FontWeight.w800,
                                      color: Colors.white)),
                            ),
                          ),
                        ),
                    ]),
                  ),
                ]),
              ),
              // Category type chips
              if (_uniqueTypes.isNotEmpty)
                SizedBox(
                  height: 38,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
                    itemCount: _uniqueTypes.length + 1,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) {
                      final type = i == 0 ? '' : _uniqueTypes[i - 1];
                      final label = i == 0 ? 'Все' : type;
                      final active = _selectedType == type;
                      return GestureDetector(
                        onTap: () => setState(() {
                          _selectedType = type;
                          _displayCount = 20;
                        }),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 7),
                          decoration: BoxDecoration(
                            color: active
                                ? cGreen
                                : cSurface,
                            borderRadius: BorderRadius.circular(11),
                            border: Border.all(
                                color: active ? cGreen : cLine),
                          ),
                          child: Text(
                            label,
                            style: manrope(12.5, FontWeight.w700,
                                color: active ? Colors.white : cInk2),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              // Active filter chips
              if (activeChips.isNotEmpty)
                SizedBox(
                  height: 34,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
                    children: activeChips,
                  ),
                ),
            ]),
          ),

          // ── Body ────────────────────────────────────────────────────────
          Expanded(
            child: _loadingStores
                ? const Center(
                    child: CircularProgressIndicator(color: cGreen))
                : _errorMessage != null
                    ? _EmptyState(
                        icon: Icons.error_outline_rounded,
                        message: _errorMessage!)
                    : _stores.isEmpty
                        ? const _EmptyState(
                            icon: Icons.storefront_outlined,
                            message: 'Нет активных магазинов')
                        : _loadingProducts
                            ? const Center(
                                child: CircularProgressIndicator(color: cGreen))
                            : _shown.isEmpty
                                ? _EmptyState(
                                    icon: Icons.search_off_rounded,
                                    message: _filters.search.isEmpty
                                        ? 'Нет товаров'
                                        : '«${_filters.search}» не найдено')
                                : GridView.builder(
                                    controller: _scrollCtrl,
                                    padding: const EdgeInsets.fromLTRB(
                                        12, 14, 12, 20),
                                    gridDelegate:
                                        const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 2,
                                      childAspectRatio: 0.68,
                                      crossAxisSpacing: 12,
                                      mainAxisSpacing: 12,
                                    ),
                                    itemCount:
                                        _shown.length + (_hasMore ? 1 : 0),
                                    itemBuilder: (_, i) {
                                      if (i == _shown.length) {
                                        return const Center(
                                          child: Padding(
                                            padding: EdgeInsets.all(16),
                                            child: CircularProgressIndicator(
                                                color: cGreen, strokeWidth: 2),
                                          ),
                                        );
                                      }
                                      final pair = _shown[i];
                                      final store = _productStoreMap[pair.product.id];
                                      final price = pair.batches.isNotEmpty
                                          ? pair.batches.first.sellingPrice
                                          : 0.0;
                                      return _ProductCard(
                                        product: pair.product,
                                        batches: pair.batches,
                                        price: price,
                                        store: store,
                                        tone: i % 5,
                                        onTap: (p) {
                                          if (store == null) return;
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  ClientProductDetail(
                                                product: p,
                                                store: store,
                                              ),
                                            ),
                                          );
                                        },
                                      );
                                    },
                                  ),
          ),
        ]),
      ),
    );
  }

  List<Widget> _buildActiveChips() {
    final chips = <Widget>[];
    final f = _filters;

    if (f.storeId != null) {
      final name = _stores
          .firstWhere((s) => s.adminUid == f.storeId,
              orElse: () => _stores.first)
          .storeName;
      chips.add(_FilterChipTag(
          label: 'Магазин: $name', onRemove: () => _removeFilter('store')));
    }
    if (f.types.isNotEmpty) {
      chips.add(_FilterChipTag(
          label: f.types.join(', '), onRemove: () => _removeFilter('types')));
    }
    if (f.brands.isNotEmpty) {
      chips.add(_FilterChipTag(
          label: f.brands.join(', '), onRemove: () => _removeFilter('brands')));
    }
    if (f.sizes.isNotEmpty) {
      chips.add(_FilterChipTag(
          label: f.sizes.join(', '), onRemove: () => _removeFilter('sizes')));
    }
    if (f.colors.isNotEmpty) {
      chips.add(_FilterChipTag(
          label: f.colors.join(', '), onRemove: () => _removeFilter('colors')));
    }
    if (f.categories.isNotEmpty) {
      chips.add(_FilterChipTag(
          label: f.categories.join(', '),
          onRemove: () => _removeFilter('cats')));
    }
    if (f.minPrice != null || f.maxPrice != null) {
      final lo = f.minPrice?.toStringAsFixed(0) ?? '0';
      final hi = f.maxPrice?.toStringAsFixed(0) ?? '∞';
      chips.add(_FilterChipTag(
          label: '$lo–$hi ₸', onRemove: () => _removeFilter('price')));
    }
    return chips;
  }
}

// ── Filter chip ────────────────────────────────────────────────────────────────
class _FilterChipTag extends StatelessWidget {
  final String label;
  final VoidCallback onRemove;
  const _FilterChipTag({required this.label, required this.onRemove});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label,
              style: manrope(11, FontWeight.w700, color: cGreen)),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onRemove,
            child: const Icon(Icons.close_rounded, size: 14, color: cGreen),
          ),
        ]),
      );
}

// ── Product card ───────────────────────────────────────────────────────────────
class _ProductCard extends StatelessWidget {
  final ProductModel product;
  final List<BatchModel> batches;
  final double price;
  final StoreModel? store;
  final int tone;
  final void Function(ProductModel) onTap;

  const _ProductCard({
    required this.product,
    required this.batches,
    required this.price,
    required this.store,
    required this.tone,
    required this.onTap,
  });

  void _quickAdd(BuildContext context) {
    if (store == null) {
      onTap(product);
      return;
    }
    // Collect available sizes across all batches
    final Map<String, ({int qty, BatchModel batch})> available = {};
    for (final b in batches) {
      b.availableSizes.forEach((size, qty) {
        if (qty > 0) {
          final existing = available[size];
          if (existing == null || qty > existing.qty) {
            available[size] = (qty: qty, batch: b);
          }
        }
      });
    }
    if (available.isEmpty) {
      onTap(product);
      return;
    }
    final sortedSizes = available.keys.toList()
      ..sort((a, b) =>
          (int.tryParse(a) ?? 0).compareTo(int.tryParse(b) ?? 0));

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _SizePickerSheet(
        product: product,
        store: store!,
        price: price,
        sortedSizes: sortedSizes,
        available: {for (final e in available.entries) e.key: e.value},
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onTap(product),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: cSurface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: cLine),
          boxShadow: kShadowSm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image area
            Stack(children: [
              QShoeImage(
                imageUrl:
                    product.images.isNotEmpty ? product.images.first : null,
                height: 120,
                tone: tone,
              ),
              Positioned(
                top: 7,
                right: 7,
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.9),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.favorite_border_rounded,
                      size: 16, color: cInk3),
                ),
              ),
            ]),
            const SizedBox(height: 9),
            // Name
            Text(product.name,
                style: manrope(13.5, FontWeight.w700, color: cInk),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
            const Spacer(),
            // Price + add button
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    price > 0 ? money(price) : '—',
                    style: manrope(13.5, FontWeight.w800, color: cInk),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                GestureDetector(
                  onTap: () => _quickAdd(context),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: cGreen,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.add_rounded,
                        color: Colors.white, size: 18),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Quick size picker sheet ────────────────────────────────────────────────────
class _SizePickerSheet extends StatefulWidget {
  final ProductModel product;
  final StoreModel store;
  final double price;
  final List<String> sortedSizes;
  final Map<String, ({int qty, BatchModel batch})> available;

  const _SizePickerSheet({
    required this.product,
    required this.store,
    required this.price,
    required this.sortedSizes,
    required this.available,
  });

  @override
  State<_SizePickerSheet> createState() => _SizePickerSheetState();
}

class _SizePickerSheetState extends State<_SizePickerSheet> {
  String? _selected;

  void _confirm() {
    if (_selected == null) return;
    final entry = widget.available[_selected!]!;
    context.read<CartProvider>().addItem(CartItemModel(
          productId: widget.product.id,
          productName: widget.product.name,
          batchId: entry.batch.id,
          size: _selected!,
          qty: 1,
          price: widget.price,
          adminUid: widget.store.adminUid,
          storeName: widget.store.storeName,
          imageUrl: widget.product.images.isNotEmpty
              ? widget.product.images.first
              : '',
          warehouseId: entry.batch.warehouseId,
          warehouseAddress: '',
        ));
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${widget.product.name} (${_selected!}) добавлен'),
      backgroundColor: cGreen,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: cSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 36, height: 4,
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
              color: cLine, borderRadius: BorderRadius.circular(2)),
        ),
        Row(children: [
          if (widget.product.images.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(widget.product.images.first,
                  width: 48, height: 48, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                      width: 48, height: 48,
                      decoration: BoxDecoration(
                          color: cGreenTint,
                          borderRadius: BorderRadius.circular(10)))),
            )
          else
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                  color: cGreenTint,
                  borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.inventory_2_outlined, color: cGreen, size: 22),
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.product.name,
                  style: manrope(14, FontWeight.w700, color: cInk),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(money(widget.price),
                  style: manrope(13.5, FontWeight.w800, color: cGreen)),
            ]),
          ),
        ]),
        const SizedBox(height: 16),
        QSecLabel('Выберите размер'),
        Wrap(
          spacing: 9,
          runSpacing: 9,
          children: widget.sortedSizes.map((size) {
            final sel = _selected == size;
            return GestureDetector(
              onTap: () => setState(() => _selected = size),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 56,
                height: 50,
                decoration: BoxDecoration(
                  color: sel ? cGreenTint : cSurface,
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(
                      color: sel ? cGreen : cLine, width: 1.5),
                ),
                child: Center(
                  child: Text(size,
                      style: manrope(15.5, FontWeight.w800,
                          color: sel ? cGreen : cInk)),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 20),
        QPrimaryButton(
          label: 'Добавить в корзину',
          onPressed: _selected != null ? _confirm : null,
          height: 52,
          icon: const Icon(Icons.shopping_cart_outlined,
              color: Colors.white, size: 18),
        ),
      ]),
    );
  }
}

// ── Empty state ────────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  const _EmptyState({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 56, color: cInk3),
          const SizedBox(height: 12),
          Text(message,
              style: manrope(15, FontWeight.w500, color: cInk2)),
        ]),
      );
}
