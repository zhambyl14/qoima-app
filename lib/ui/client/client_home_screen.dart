import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_user.dart';
import '../../data/models/store_model.dart';
import '../guest/guest_shell.dart';
import '../../data/models/product_model.dart';
import '../../data/models/batch_model.dart';
import '../../data/models/banner_model.dart';
import '../../data/services/client_service.dart';
import '../../data/repositories/banner_repository.dart';
import '../../theme/qoima_design.dart';
import '../shared/skeletons.dart';
import 'client_product_card.dart';
import 'client_product_detail.dart';
import 'client_shell.dart';

import '../../core/lang.dart';
// ── Filters state ──────────────────────────────────────────────────────────────
class ClientFilters {
  final String search;
  final String? storeId;
  final Set<String> categoryKeys; // тип товара v2 (shoes|tshirt|...)
  final Set<String> types;
  final Set<String> brands;
  final Set<String> sizes;
  final Set<String> colors;
  final Set<String> categories;
  final double? minPrice;
  final double? maxPrice;
  final bool onSale; // only show products with active discount

  const ClientFilters({
    this.search = '',
    this.storeId,
    this.categoryKeys = const {},
    this.types = const {},
    this.brands = const {},
    this.sizes = const {},
    this.colors = const {},
    this.categories = const {},
    this.minPrice,
    this.maxPrice,
    this.onSale = false,
  });

  int get activeCount {
    int c = 0;
    if (storeId != null) c++;
    if (categoryKeys.isNotEmpty) c++;
    if (types.isNotEmpty) c++;
    if (brands.isNotEmpty) c++;
    if (sizes.isNotEmpty) c++;
    if (colors.isNotEmpty) c++;
    if (categories.isNotEmpty) c++;
    if (minPrice != null || maxPrice != null) c++;
    if (onSale) c++;
    return c;
  }

  ClientFilters copyWith({
    String? search,
    Object? storeId = _sentinel,
    Set<String>? categoryKeys,
    Set<String>? types,
    Set<String>? brands,
    Set<String>? sizes,
    Set<String>? colors,
    Set<String>? categories,
    Object? minPrice = _sentinel,
    Object? maxPrice = _sentinel,
    bool? onSale,
  }) =>
      ClientFilters(
        search: search ?? this.search,
        storeId: storeId == _sentinel ? this.storeId : storeId as String?,
        categoryKeys: categoryKeys ?? this.categoryKeys,
        types: types ?? this.types,
        brands: brands ?? this.brands,
        sizes: sizes ?? this.sizes,
        colors: colors ?? this.colors,
        categories: categories ?? this.categories,
        minPrice: minPrice == _sentinel ? this.minPrice : minPrice as double?,
        maxPrice: maxPrice == _sentinel ? this.maxPrice : maxPrice as double?,
        onSale: onSale ?? this.onSale,
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
  String? _errorMessage;
  int _displayCount = 20;
  String _searchQuery = '';

  // Все группы — цветовые варианты (same name+brand+type) схлопнуты в одну.
  List<ProductGroup> get _allGroups =>
      groupProducts(_pairs.map((e) => e.product).toList());

  // Группы к показу: без запроса — пагинация; с запросом — smart-фильтр + сорт.
  List<ProductGroup> get _shownGroups {
    final groups = _allGroups;
    if (_searchQuery.isEmpty) return groups.take(_displayCount).toList();
    final q = _searchQuery;
    return groups.where((g) => productGroupMatches(g, q)).toList()
      ..sort((a, b) =>
          productGroupScore(b, q).compareTo(productGroupScore(a, q)));
  }

  bool get _hasMore =>
      _searchQuery.isEmpty && _displayCount < _allGroups.length;

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
    // Keep existing products visible while refreshing (don't flash spinner)
    final hasCache = _pairs.isNotEmpty;
    setState(() {
      if (!hasCache) _loadingStores = true;
      _errorMessage = null;
    });
    try {
      final allStores = await _service.getPublishedStores();
      if (!mounted) return;

      final clientCity = context.read<AppUser>().city;
      final stores = clientCity.isEmpty
          ? allStores
          : allStores.where((s) => s.city.isEmpty || s.city == clientCity).toList();

      final storesWithProducts =
          stores.where((s) => s.visibleWarehouseIds.isNotEmpty).toList();

      setState(() {
        _stores = stores;
        _loadingStores = false;
        // Жаңа жүктеу: тізімді тазалап, дүкендер бойынша біртіндеп толтырамыз.
        _pairs = [];
        _productStoreMap = {};
        _loadingProducts = storesWithProducts.isNotEmpty;
      });
      if (storesWithProducts.isEmpty) return;

      // Әр дүкеннің товарларын бөлек жүктеп, КЕЛЕ САЛЫСЫМЕН қосамыз — ең баяу
      // дүкенді күтпей, бірінші дүкеннің товарлары бірден көрінеді.
      var remaining = storesWithProducts.length;
      for (final store in storesWithProducts) {
        _service
            .getStoreProductsWithBatches(
                store.adminUid, store.visibleWarehouseIds)
            .then((res) {
          if (!mounted) return;
          setState(() {
            for (final p in res) {
              _productStoreMap[p.product.id] = store;
            }
            _pairs.addAll(res);
            if (--remaining == 0) _loadingProducts = false;
          });
        }).catchError((_) {
          if (!mounted) return;
          setState(() {
            if (--remaining == 0) _loadingProducts = false;
          });
        });
      }
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

  @override
  Widget build(BuildContext context) {
    final userName = context.watch<AppUser>().name.trim();
    final firstName = userName.isEmpty ? '' : userName.split(' ').first;

    // Группы к показу + карты «вариант → батчи/магазин» (для всех вариантов).
    final groups = _shownGroups;
    // Әр түс — жеке карточка.
    final cards = expandVariantCards(groups);
    final batchesById = {
      for (final pr in _pairs) pr.product.id: pr.batches
    };
    final storeById = {
      for (final pr in _pairs) pr.product.id: _productStoreMap[pr.product.id]
    };

    return Scaffold(
      backgroundColor: cBg,
      body: SafeArea(
        child: Column(children: [
          // ── Gradient header: greeting + bell + search ───────────────────
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
                        Text(
                          firstName.isEmpty
                              ? tr('Привет 👋', 'Сәлем 👋')
                              : tr('Привет, $firstName 👋', 'Сәлем, $firstName 👋'),
                          style: manrope(13.5, FontWeight.w600,
                              color: Colors.white.withValues(alpha: 0.85)),
                        ),
                        Text('Qoima',
                            style: manrope(24, FontWeight.w800,
                                color: Colors.white, letterSpacing: -0.5)),
                      ],
                    ),
                  ),
                  QHeaderBtn(Icons.notifications_none_rounded,
                      onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(tr('Уведомления — скоро', 'Хабарламалар — жақында')),
                              behavior: SnackBarBehavior.floating,
                              duration: Duration(seconds: 2),
                            ),
                          )),
                ]),
              ),
              // Search row
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: Container(
                  height: 46,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(children: [
                    const SizedBox(width: 12),
                    const Icon(Icons.search_rounded, color: cInk3, size: 19),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _searchCtrl,
                        cursorColor: cGreen,
                        onChanged: (q) => setState(() {
                          _searchQuery = q.trim();
                          _displayCount = 20;
                        }),
                        style: manrope(14.5, FontWeight.w600, color: cInk),
                        decoration: InputDecoration(
                          hintText: tr('Поиск товаров...', 'Тауарларды іздеу...'),
                          hintStyle:
                              manrope(14.5, FontWeight.w500, color: cInk3),
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                          errorBorder: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                          isDense: true,
                          suffixIcon: _searchQuery.isNotEmpty
                              ? GestureDetector(
                                  onTap: () {
                                    _searchCtrl.clear();
                                    setState(() => _searchQuery = '');
                                  },
                                  child: const Icon(Icons.close_rounded,
                                      color: cInk3, size: 18))
                              : null,
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
            ]),
          ),

          // ── Body: banner carousel + recommendations grid ────────────────
          Expanded(
            child: _loadingStores
                ? const CatalogGridSkeleton()
                : _errorMessage != null
                    ? ClientEmptyState(
                        icon: Icons.error_outline_rounded,
                        message: _errorMessage!)
                    : _stores.isEmpty
                        ? ClientEmptyState(
                            icon: Icons.storefront_outlined,
                            message: context.read<AppUser>().city.isNotEmpty
                                ? tr('В вашем городе пока нет магазинов', 'Қалаңызда әзірге дүкендер жоқ')
                                : tr('Активных магазинов нет', 'Белсенді дүкендер жоқ'))
                        : (_loadingProducts && _pairs.isEmpty)
                            ? const CatalogGridSkeleton()
                            : CustomScrollView(
                                controller: _scrollCtrl,
                                slivers: [
                                  const SliverToBoxAdapter(
                                      child: BannerCarousel()),
                                  SliverToBoxAdapter(
                                    child: Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                          16, 16, 16, 8),
                                      child: Text(tr('Рекомендуем вам', 'Ұсынылады сізге'),
                                          style: manrope(17, FontWeight.w800,
                                              color: cInk)),
                                    ),
                                  ),
                                  if (groups.isEmpty)
                                    SliverToBoxAdapter(
                                      child: Padding(
                                        padding:
                                            const EdgeInsets.only(top: 60),
                                        child: ClientEmptyState(
                                          icon: Icons.search_off_rounded,
                                          message: _searchQuery.isEmpty
                                              ? tr('Товаров нет', 'Тауарлар жоқ')
                                              : tr('«$_searchQuery» не найдено', '«$_searchQuery» табылмады'),
                                        ),
                                      ),
                                    )
                                  else
                                    SliverPadding(
                                      padding: const EdgeInsets.fromLTRB(
                                          12, 0, 12, 12),
                                      sliver: SliverGrid(
                                        gridDelegate:
                                            const SliverGridDelegateWithFixedCrossAxisCount(
                                          crossAxisCount: 2,
                                          childAspectRatio: 0.72,
                                          crossAxisSpacing: 12,
                                          mainAxisSpacing: 12,
                                        ),
                                        delegate:
                                            SliverChildBuilderDelegate(
                                          (_, i) {
                                            return ProductGroupCard(
                                              key: ValueKey(cards[i]
                                                  .group
                                                  .variants[cards[i].index]
                                                  .id),
                                              group: cards[i].group,
                                              initialIndex: cards[i].index,
                                              batchesByProductId: batchesById,
                                              storeByProductId: storeById,
                                              tone: i % 5,
                                              onTap: _openProduct,
                                            );
                                          },
                                          childCount: cards.length,
                                        ),
                                      ),
                                    ),
                                  if (_hasMore)
                                    const SliverToBoxAdapter(
                                      child: Center(
                                        child: Padding(
                                          padding: EdgeInsets.all(16),
                                          child: CircularProgressIndicator(
                                              color: cGreen, strokeWidth: 2),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
          ),
        ]),
      ),
    );
  }

  /// Открывает деталь товара; «Купить сейчас» переключает на вкладку корзины.
  /// [variants] — все цветовые варианты группы (для переключателя цвета).
  Future<void> _openProduct(
      ProductModel p, List<ProductModel> variants) async {
    final store = _productStoreMap[p.id];
    if (store == null) return;
    final buyNow = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ClientProductDetail(
            product: p, store: store, allVariants: variants),
      ),
    );
    if (buyNow == true && mounted) {
      final shell = context.findAncestorStateOfType<ClientShellState>();
      if (shell != null) {
        shell.setIndex(2); // Себет — жаңа таб реті бойынша 2-ші
      } else {
        context.findAncestorStateOfType<GuestShellState>()?.setIndex(1);
      }
    }
  }
}

// ── Banner carousel ──────────────────────────────────────────────────────────
/// Самодостаточная авто-прокручиваемая карусель промо-баннеров.
/// Подписывается на BannerRepository().watchActiveBanners() (snapshots) и
/// возвращает SizedBox.shrink(), если активных баннеров нет / ошибка.
class BannerCarousel extends StatefulWidget {
  const BannerCarousel({super.key});

  @override
  State<BannerCarousel> createState() => _BannerCarouselState();
}

class _BannerCarouselState extends State<BannerCarousel> {
  final _ctrl = PageController(viewportFraction: 1.0);
  final _repo = BannerRepository();
  StreamSubscription<List<BannerModel>>? _sub;
  Timer? _timer;
  List<BannerModel> _banners = [];
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _sub = _repo.watchActiveBanners().listen((list) {
      if (!mounted) return;
      setState(() {
        _banners = list;
        if (_currentPage >= _banners.length) _currentPage = 0;
      });
      _restartTimer();
    }, onError: (_) {
      // Қате болса (мыс. рұқсат жоқ) — жай көрсетпейміз.
      if (mounted) setState(() => _banners = []);
    });
  }

  void _restartTimer() {
    _timer?.cancel();
    if (_banners.length <= 1) return;
    _timer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (!_ctrl.hasClients || _banners.length < 2) return;
      final next = (_currentPage + 1) % _banners.length;
      _ctrl.animateToPage(next,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _timer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final banners = _banners;
    if (banners.isEmpty) return const SizedBox.shrink();

    return Column(children: [
      const SizedBox(height: 14),
      SizedBox(
        height: 112,
        child: PageView.builder(
          controller: _ctrl,
          itemCount: banners.length,
          onPageChanged: (i) => setState(() => _currentPage = i),
          itemBuilder: (_, i) {
            final b = banners[i];
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [b.startColor, b.endColor],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: kShadowSm,
                ),
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
                child: Row(children: [
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (b.badge.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.22),
                              borderRadius: BorderRadius.circular(7),
                            ),
                            child: Text(b.badge,
                                style: manrope(10.5, FontWeight.w800,
                                    color: Colors.white)),
                          ),
                        if (b.badge.isNotEmpty) const SizedBox(height: 6),
                        Text(b.title,
                            style: manrope(17, FontWeight.w800,
                                color: Colors.white, letterSpacing: -0.3),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        if (b.subtitle.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(b.subtitle,
                              style: manrope(12.5, FontWeight.w500,
                                  color: Colors.white.withValues(alpha: 0.9)),
                              maxLines: 2, overflow: TextOverflow.ellipsis),
                        ],
                      ],
                    ),
                  ),
                ]),
              ),
            );
          },
        ),
      ),
      if (banners.length > 1) ...[
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(banners.length, (i) {
            final on = i == _currentPage;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: on ? 18 : 5,
              height: 5,
              decoration: BoxDecoration(
                color: on ? cGreen : cInk3.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(3),
              ),
            );
          }),
        ),
      ],
    ]);
  }
}
