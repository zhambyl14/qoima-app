import 'package:flutter/material.dart';
import '../../data/models/store_model.dart';
import '../../data/models/product_model.dart';
import '../../data/models/batch_model.dart';
import '../../data/services/client_service.dart';
import '../../theme/app_theme.dart';
import 'client_product_detail.dart';
import 'client_filters_sheet.dart';

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

  List<({ProductModel product, List<BatchModel> batches})> get _shown {
    final f = _filters;
    final filtered = _pairs.where((pair) {
      final p = pair.product;
      final b = pair.batches;
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

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────────────
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF1E3A8A), Color(0xFF2D4FB5)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                    child: Row(children: [
                      const Icon(Icons.storefront_rounded,
                          color: Colors.white, size: 22),
                      const SizedBox(width: 8),
                      const Text('Магазин',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w800)),
                    ]),
                  ),
                  // Search bar + filter button
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                    child: Row(children: [
                      Expanded(
                        child: Container(
                          height: 42,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: TextField(
                            controller: _searchCtrl,
                            onChanged: (q) => setState(() {
                              _filters = _filters.copyWith(search: q.trim());
                              _displayCount = 20;
                            }),
                            style: const TextStyle(
                                color: Colors.black87, fontSize: 14),
                            decoration: InputDecoration(
                              hintText: 'Поиск товара...',
                              hintStyle: const TextStyle(
                                  color: Colors.black54, fontSize: 14),
                              prefixIcon: const Icon(Icons.search_rounded,
                                  color: AppTheme.primary, size: 20),
                              suffixIcon: _filters.search.isNotEmpty
                                  ? GestureDetector(
                                      onTap: () {
                                        _searchCtrl.clear();
                                        setState(() {
                                          _filters =
                                              _filters.copyWith(search: '');
                                        });
                                      },
                                      child: const Icon(Icons.close_rounded,
                                          color: AppTheme.textHint, size: 18))
                                  : null,
                              border: InputBorder.none,
                              contentPadding:
                                  const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: _openFilters,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Container(
                              height: 42,
                              width: 42,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(12),
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
                                    color: Color(0xFFF59E0B),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Center(
                                    child: Text('${_filters.activeCount}',
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w800)),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 8),

                  // Active filter chips row
                  if (activeChips.isNotEmpty)
                    SizedBox(
                      height: 36,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                        children: activeChips,
                      ),
                    ),
                ],
              ),
            ),

            // ── Body ──────────────────────────────────────────────────────
            Expanded(
              child: _loadingStores
                  ? const Center(
                      child: CircularProgressIndicator(color: AppTheme.primary))
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
                                  child: CircularProgressIndicator(
                                      color: AppTheme.primary))
                              : _shown.isEmpty
                                  ? _EmptyState(
                                      icon: Icons.search_off_rounded,
                                      message: _filters.search.isNotEmpty
                                          ? '«${_filters.search}» не найдено'
                                          : 'Нет товаров')
                                  : GridView.builder(
                                      controller: _scrollCtrl,
                                      padding: const EdgeInsets.fromLTRB(
                                          12, 12, 12, 20),
                                      gridDelegate:
                                          const SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: 2,
                                        childAspectRatio: 0.72,
                                        crossAxisSpacing: 10,
                                        mainAxisSpacing: 10,
                                      ),
                                      itemCount:
                                          _shown.length + (_hasMore ? 1 : 0),
                                      itemBuilder: (_, i) {
                                        if (i == _shown.length) {
                                          return const Center(
                                            child: Padding(
                                              padding: EdgeInsets.all(16),
                                              child: CircularProgressIndicator(
                                                  color: AppTheme.primary,
                                                  strokeWidth: 2),
                                            ),
                                          );
                                        }
                                        final pair = _shown[i];
                                        return _ProductCard(
                                          product: pair.product,
                                          onTap: (p) {
                                            final store =
                                                _productStoreMap[p.id];
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
          ],
        ),
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

// ── Filter chip tag ────────────────────────────────────────────────────────────
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
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.primary)),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onRemove,
            child: const Icon(Icons.close_rounded,
                size: 14, color: AppTheme.primary),
          ),
        ]),
      );
}

// ── Product card ───────────────────────────────────────────────────────────────
class _ProductCard extends StatelessWidget {
  final ProductModel product;
  final void Function(ProductModel) onTap;
  const _ProductCard({required this.product, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onTap(product),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 2)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
                child: product.images.isNotEmpty
                    ? Image.network(product.images.first,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        errorBuilder: (_, __, ___) => _PlaceholderImage())
                    : _PlaceholderImage(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(product.brand,
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.primary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(product.name,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text(product.type,
                      style: const TextStyle(
                          fontSize: 11, color: AppTheme.textHint)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaceholderImage extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        color: AppTheme.primary.withValues(alpha: 0.06),
        child: const Center(
            child:
                Icon(Icons.image_outlined, color: AppTheme.textHint, size: 40)),
      );
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  const _EmptyState({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 56, color: AppTheme.textHint),
          const SizedBox(height: 12),
          Text(message,
              style:
                  const TextStyle(fontSize: 15, color: AppTheme.textSecondary)),
        ]),
      );
}
