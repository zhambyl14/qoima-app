import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/app_user.dart';
import '../../core/browsing_signals.dart';
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
import 'home_filters_sheet.dart';
import 'store_public_screen.dart';
import 'stores_list_screen.dart';

import '../../core/lang.dart';
import '../shared/error_view.dart';

// ── Filters state ──────────────────────────────────────────────────────────────
class ClientFilters {
  final String search;
  final String? storeId;
  final Set<String> categoryKeys; // тип товара v2 (shoes|tshirt|...)
  final Set<String> types;
  final Set<String> brands;
  final Set<String> sizes;
  final Set<String> colors;
  final Set<String> categories; // кому: Мужские|Женские|Унисекс|Детские
  final double? minPrice;
  final double? maxPrice;
  final bool onSale; // only show products with active discount
  final String sort; // default|price_asc|price_desc|rating

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
    this.sort = 'default',
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

  bool get hasAny => activeCount > 0 || sort != 'default';

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
    String? sort,
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
        sort: sort ?? this.sort,
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
  final _searchFocus = FocusNode();
  bool _searchFocused = false;

  List<StoreModel> _stores = [];
  // Барлық жарияланған дүкендер (қала сүзгісінсіз) — қала тізімін көрсету үшін.
  List<StoreModel> _allStores = [];
  List<({ProductModel product, List<BatchModel> batches})> _pairs = [];
  Map<String, StoreModel> _productStoreMap = {};
  bool _loadingStores = true;
  bool _loadingProducts = false;
  // Шикі қате нысаны — AppErrorView оны түсінікті мәтінге айналдырады
  // әрі желі қатесін бөлек (Wi-Fi иконкасымен) көрсетеді.
  Object? _errorMessage;
  int _displayCount = 20;
  String _searchQuery = '';
  // Соңғы іздеу дәл сәйкестік таппай, «ұқсас» fallback-қа көшкенін білдіреді.
  bool _lastSearchFallback = false;
  ClientFilters _filters = const ClientFilters();
  // Соңғы build-тегі сүзілген топ саны — _hasMore үшін (қайта есептемей).
  int _filteredCount = 0;

  // Таңдаулылар — бір ортақ жазылым (әр карточка өз жазылымын ашпайды).
  List<String> _favoriteIds = [];
  StreamSubscription<List<String>>? _favSub;

  // «Ұсынылады сізге» негізгі реті: сессия сайын бір рет араластырылады
  // (ешқашан «жаңасы үстінде» болмайды) — build() сайын өзгермеу үшін мұнда
  // бір рет сақталады. Жеке қалау сигналы болса — үстіне ілінеді.
  final int _shuffleSeed = DateTime.now().millisecondsSinceEpoch;
  Timer? _searchSignalDebounce;

  // Қала сүзгісі: null = бүкіл Қазақстан (әдепкі). Таңдау сақталады.
  static const _kCityPrefKey = 'client_home_city_filter';
  String? _cityFilter;

  // Все группы — цветовые варианты (same name+brand+type) схлопнуты в одну.
  List<ProductGroup> get _allGroups =>
      groupProducts(_pairs.map((e) => e.product).toList());

  /// Фильтр + сорт қолданылған ТОЛЫҚ тізім (пагинациясыз).
  List<ProductGroup> _filteredSortedGroups() {
    var groups = _allGroups;
    final f = _filters;

    if (f.activeCount > 0) {
      final batchesById = {for (final pr in _pairs) pr.product.id: pr.batches};
      bool priceOk(ProductModel v) {
        final bs = batchesById[v.id] ?? const <BatchModel>[];
        if (bs.isEmpty) return false;
        final price = effectivePrice(bs.first);
        if (f.minPrice != null && price < f.minPrice!) return false;
        if (f.maxPrice != null && price > f.maxPrice!) return false;
        if (f.onSale && !hasActiveDiscount(bs.first)) return false;
        return true;
      }

      groups = groups.where((g) {
        if (f.categoryKeys.isNotEmpty &&
            !f.categoryKeys.contains(g.main.effectiveCategoryKey)) {
          return false;
        }
        if (f.categories.isNotEmpty &&
            !f.categories.any((aud) => aud == 'Детские'
                ? g.main.category.startsWith('Детские')
                : g.main.category == aud)) {
          return false;
        }
        if (f.storeId != null &&
            _productStoreMap[g.main.id]?.adminUid != f.storeId) {
          return false;
        }
        if ((f.minPrice != null || f.maxPrice != null || f.onSale) &&
            !g.variants.any(priceOk)) {
          return false;
        }
        return true;
      }).toList();
    }

    if (_searchQuery.isNotEmpty) {
      final result = searchProductGroups(groups, _searchQuery);
      groups = result.results;
      _lastSearchFallback = result.isFallback;
      // Іздеуде relevance-сорт басым; таңдалған сорт болса — қайта сорттаймыз.
    } else {
      _lastSearchFallback = false;
    }

    if (f.sort != 'default') {
      final batchesById = {for (final pr in _pairs) pr.product.id: pr.batches};
      double priceOf(ProductGroup g) {
        double best = double.infinity;
        for (final v in g.variants) {
          final bs = batchesById[v.id] ?? const <BatchModel>[];
          if (bs.isEmpty) continue;
          final p = effectivePrice(bs.first);
          if (p < best) best = p;
        }
        return best;
      }

      switch (f.sort) {
        case 'price_asc':
          groups.sort((a, b) => priceOf(a).compareTo(priceOf(b)));
        case 'price_desc':
          groups.sort((a, b) => priceOf(b).compareTo(priceOf(a)));
        case 'rating':
          groups.sort((a, b) {
            final c = b.main.ratingAvg.compareTo(a.main.ratingAvg);
            return c != 0
                ? c
                : b.main.ratingCount.compareTo(a.main.ratingCount);
          });
      }
    } else if (_searchQuery.isEmpty) {
      // Әдепкі («Ұсынылады сізге»): дүкендер/желі ретімен АРАЛАСПАЙДЫ —
      // сессия сайын бір рет араластырылады (ешқашан «жаңасы үстінде» емес),
      // содан кейін клиенттің қарау/іздеу тарихына сай санат/бренд
      // басымдығы бар топтар алдыға шығады.
      groups = _personalizedOrder(groups);
    }
    return groups;
  }

  List<ProductGroup> _personalizedOrder(List<ProductGroup> groups) {
    final shuffled = List<ProductGroup>.from(groups)
      ..shuffle(Random(_shuffleSeed));
    final catAffinity = BrowsingSignalsService.instance.categoryAffinity();
    final brandAffinity = BrowsingSignalsService.instance.brandAffinity();
    if (catAffinity.isEmpty && brandAffinity.isEmpty) return shuffled;

    int score(ProductGroup g) =>
        (catAffinity[g.main.effectiveCategoryKey] ?? 0) * 2 +
        (brandAffinity[g.main.brand] ?? 0);

    // Индекспен байланыстырып сорттаймыз — List.sort тұрақты (stable) емес,
    // тең ұпайлылар араластырылған реттен шықпауы керек.
    final indexed = List.generate(shuffled.length, (i) => i);
    indexed.sort((ai, bi) {
      final c = score(shuffled[bi]).compareTo(score(shuffled[ai]));
      return c != 0 ? c : ai.compareTo(bi);
    });
    return indexed.map((i) => shuffled[i]).toList();
  }

  bool get _hasMore => _searchQuery.isEmpty && _displayCount < _filteredCount;

  @override
  void initState() {
    super.initState();
    _restoreCityFilter();
    _scrollCtrl.addListener(_onScroll);
    // Дүкен жасырылса/ашылса — тізімді қайта жүктейміз.
    ClientService.hiddenStoresVersion.addListener(_onHiddenStoresChanged);
    _favSub = _service.watchFavoriteIds().listen((ids) {
      if (mounted) setState(() => _favoriteIds = ids);
    });
    BrowsingSignalsService.instance.preload().then((_) {
      if (mounted) setState(() {});
    });
    _searchFocus.addListener(() {
      if (mounted) setState(() => _searchFocused = _searchFocus.hasFocus);
    });
  }

  void _toggleFavorite(ProductModel p) async {
    final user = context.read<AppUser>();
    if (user.uid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(tr('Войдите, чтобы добавить в избранное',
            'Таңдаулыға қосу үшін кіріңіз')),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    final isFav = _favoriteIds.contains(p.id);
    // Оптимистикалық жаңарту — желі/realtime жауабын күтпей иконка бірден
    // ауысады, растау кейін watchFavoriteIds() арқылы келеді.
    setState(() {
      _favoriteIds = isFav
          ? (List.of(_favoriteIds)..remove(p.id))
          : (List.of(_favoriteIds)..add(p.id));
    });
    try {
      if (isFav) {
        await _service.removeFavorite(p.id);
      } else {
        final store = _productStoreMap[p.id];
        final batches = _pairs
            .firstWhere((pr) => pr.product.id == p.id,
                orElse: () => (product: p, batches: const <BatchModel>[]))
            .batches;
        final price = batches.isNotEmpty ? batches.first.sellingPrice : 0.0;
        await _service.addFavorite(
          productId: p.id,
          productName: p.name,
          imageUrl: p.images.isNotEmpty ? p.images.first : '',
          adminUid: store?.adminUid ?? '',
          storeName: store?.storeName ?? '',
          price: price,
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _favoriteIds = isFav
              ? (List.of(_favoriteIds)..add(p.id))
              : (List.of(_favoriteIds)..remove(p.id));
        });
      }
    }
  }

  Future<void> _restoreCityFilter() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_kCityPrefKey);
      if (mounted && saved != null && saved.isNotEmpty) {
        _cityFilter = saved;
      }
    } catch (_) {}
    if (mounted) _loadAllProducts();
  }

  Future<void> _setCityFilter(String? city) async {
    setState(() {
      _cityFilter = city;
      _displayCount = 20;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      if (city == null || city.isEmpty) {
        await prefs.remove(_kCityPrefKey);
      } else {
        await prefs.setString(_kCityPrefKey, city);
      }
    } catch (_) {}
    _loadAllProducts();
  }

  void _onHiddenStoresChanged() {
    if (mounted) _loadAllProducts();
  }

  @override
  void dispose() {
    ClientService.hiddenStoresVersion.removeListener(_onHiddenStoresChanged);
    _favSub?.cancel();
    _searchSignalDebounce?.cancel();
    _scrollCtrl.dispose();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  // Іздеу тоқтағаннан кейін (жазу аяқталған сәтте) — нәтиженің басым
  // категориясын жеңіл сигнал ретінде жазамыз. build() ішінде емес, осында —
  // әр rebuild-те емес, пайдаланушы шынымен іздегенде ғана жазылады.
  void _onSearchChanged(String q) {
    setState(() {
      _searchQuery = q.trim();
      _displayCount = 20;
    });
    _searchSignalDebounce?.cancel();
    if (_searchQuery.isEmpty) return;
    _searchSignalDebounce = Timer(const Duration(milliseconds: 700), () {
      final matches = _allGroups
          .where((g) => productGroupMatches(g, _searchQuery))
          .toList();
      if (matches.isEmpty) return;
      final counts = <String, int>{};
      for (final g in matches) {
        final k = g.main.effectiveCategoryKey;
        counts[k] = (counts[k] ?? 0) + 1;
      }
      final top = counts.entries.reduce((a, b) => a.value >= b.value ? a : b);
      BrowsingSignalsService.instance.recordSearchCategory(top.key);
      BrowsingSignalsService.instance.recordSearchQuery(_searchQuery);
    });
  }

  void _applyRecentSearch(String q) {
    _searchCtrl.text = q;
    _searchCtrl.selection =
        TextSelection.collapsed(offset: _searchCtrl.text.length);
    _onSearchChanged(q);
    _searchFocus.unfocus();
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
      // Дүкендер + клиент жасырған дүкендер (параллель).
      final results = await Future.wait([
        _service.getPublishedStores(),
        _service.getHiddenStoreIds(),
      ]);
      if (!mounted) return;
      final allStores = results[0] as List<StoreModel>;
      final hiddenIds = results[1] as Set<String>;

      // Әдепкі — бүкіл Қазақстан дүкендері; _cityFilter таңдалса — сол қала.
      final visible =
          allStores.where((s) => !hiddenIds.contains(s.adminUid)).toList();
      _allStores = visible;
      final stores = visible
          .where((s) => _cityFilter == null || s.city.trim() == _cityFilter)
          .toList();

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
          _errorMessage = e;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final userName = context.watch<AppUser>().name.trim();
    final firstName = userName.isEmpty ? '' : userName.split(' ').first;

    // Группы к показу + карты «вариант → батчи/магазин» (для всех вариантов).
    final allFiltered = _filteredSortedGroups();
    _filteredCount = allFiltered.length;
    final groups = _searchQuery.isEmpty
        ? allFiltered.take(_displayCount).toList()
        : allFiltered;
    // Әр түс — жеке карточка.
    final cards = expandVariantCards(groups);
    final batchesById = {for (final pr in _pairs) pr.product.id: pr.batches};
    final storeById = {
      for (final pr in _pairs) pr.product.id: _productStoreMap[pr.product.id]
    };

    return Scaffold(
      backgroundColor: cBg,
      // top: false — жасыл хедер статус-бардың АСТЫНА дейін созылады
      // (қалған экрандардағы QGradientHeader сияқты); жоғарғы шегініс
      // хедердің өз ішіндегі SafeArea-мен беріледі.
      body: SafeArea(
        top: false,
        child: Column(children: [
          // ── Gradient header: greeting + bell + search ───────────────────
          Container(
            decoration: const BoxDecoration(
              gradient: kGrad,
              borderRadius:
                  BorderRadius.vertical(bottom: Radius.circular(kR24)),
              boxShadow: [
                BoxShadow(
                    color: Color(0x2600713F),
                    blurRadius: 20,
                    offset: Offset(0, 8)),
              ],
            ),
            child: SafeArea(
              bottom: false,
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
                                : tr('Привет, $firstName 👋',
                                    'Сәлем, $firstName 👋'),
                            style: manrope(13.5, FontWeight.w600,
                                color: Colors.white.withValues(alpha: 0.85)),
                          ),
                          Text('Qoima',
                              style: manrope(24, FontWeight.w800,
                                  color: Colors.white, letterSpacing: -0.5)),
                        ],
                      ),
                    ),
                  ]),
                ),
                // Search row + фильтр батырмасы
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
                  child: Row(children: [
                    Expanded(
                      child: Container(
                        height: 46,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(kR14),
                          boxShadow: const [
                            BoxShadow(
                                color: Color(0x1A004025),
                                blurRadius: 10,
                                offset: Offset(0, 3)),
                          ],
                        ),
                        child: Row(children: [
                          const SizedBox(width: 12),
                          const Icon(Icons.search_rounded,
                              color: cInk3, size: 19),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _searchCtrl,
                              focusNode: _searchFocus,
                              cursorColor: cGreen,
                              textAlignVertical: TextAlignVertical.center,
                              onChanged: _onSearchChanged,
                              style:
                                  manrope(14.5, FontWeight.w600, color: cInk),
                              decoration: InputDecoration(
                                hintText: tr(
                                    'Поиск товаров...', 'Тауарларды іздеу...'),
                                hintStyle: manrope(14.5, FontWeight.w500,
                                    color: cInk3),
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
                    const SizedBox(width: 10),
                    // Фильтр (санат, кому, баға, скидка, дүкен, сорт)
                    GestureDetector(
                      onTap: _openFilters,
                      child: Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(kR14),
                          boxShadow: const [
                            BoxShadow(
                                color: Color(0x1A004025),
                                blurRadius: 10,
                                offset: Offset(0, 3)),
                          ],
                        ),
                        child: Stack(clipBehavior: Clip.none, children: [
                          const Center(
                              child: Icon(Icons.tune_rounded,
                                  color: cInk, size: 20)),
                          if (_filters.activeCount > 0)
                            Positioned(
                              top: 7,
                              right: 7,
                              child: Container(
                                width: 16,
                                height: 16,
                                decoration: const BoxDecoration(
                                    color: cGreen, shape: BoxShape.circle),
                                child: Center(
                                  child: Text('${_filters.activeCount}',
                                      style: manrope(9.5, FontWeight.w800,
                                          color: Colors.white)),
                                ),
                              ),
                            ),
                        ]),
                      ),
                    ),
                  ]),
                ),

                // Соңғы іздегендер — іздеу өрісі бассалғанда әрі бос болғанда
                // ғана («осыны қарамайсыз ба?» ұсынысы, макс 4, чип басылса
                // сол сұраныс бірден қолданылады).
                if (_searchFocused &&
                    _searchQuery.isEmpty &&
                    BrowsingSignalsService.instance.recentSearches.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            tr('Недавние:', 'Соңғы іздегендер:'),
                            style: manrope(12, FontWeight.w600,
                                color: Colors.white.withValues(alpha: 0.85)),
                          ),
                          for (final q
                              in BrowsingSignalsService.instance.recentSearches)
                            GestureDetector(
                              onTap: () => _applyRecentSearch(q),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 11, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                      color:
                                          Colors.white.withValues(alpha: 0.22)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.history_rounded,
                                        size: 13, color: Colors.white),
                                    const SizedBox(width: 5),
                                    Text(q,
                                        style: manrope(12, FontWeight.w600,
                                            color: Colors.white)),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),

                // ── Қала таңдау + Дүкендер қатары ───────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                  child: Row(children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: _openCitySheet,
                        child: Container(
                          height: 36,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(kRPill),
                            border: Border.all(
                                color: Colors.white.withValues(alpha: 0.22)),
                          ),
                          child: Row(children: [
                            const Icon(Icons.location_on_outlined,
                                color: Colors.white, size: 16),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                _cityFilter ??
                                    tr('Все города', 'Барлық қалалар'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: manrope(12.5, FontWeight.w700,
                                    color: Colors.white),
                              ),
                            ),
                            const Icon(Icons.expand_more_rounded,
                                color: Colors.white, size: 18),
                          ]),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) =>
                                StoresListScreen(initialCity: _cityFilter)),
                      ),
                      child: Container(
                        height: 36,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(kRPill),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.22)),
                        ),
                        child: Row(children: [
                          const Icon(Icons.storefront_outlined,
                              color: Colors.white, size: 16),
                          const SizedBox(width: 6),
                          Text(tr('Магазины', 'Дүкендер'),
                              style: manrope(12.5, FontWeight.w700,
                                  color: Colors.white)),
                        ]),
                      ),
                    ),
                  ]),
                ),
              ]),
            ),
          ),

          // ── Body: banner carousel + recommendations grid ────────────────
          Expanded(
            child: _loadingStores
                ? const CatalogGridSkeleton()
                : _errorMessage != null
                    ? AppErrorView(
                        error: _errorMessage, onRetry: _loadAllProducts)
                    : _stores.isEmpty
                        ? ClientEmptyState(
                            icon: Icons.storefront_outlined,
                            message: _cityFilter != null
                                ? tr('В городе $_cityFilter пока нет магазинов',
                                    '$_cityFilter қаласында әзірге дүкен жоқ')
                                : tr('Активных магазинов нет',
                                    'Белсенді дүкендер жоқ'))
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
                                      child: Text(
                                          tr('Рекомендуем вам',
                                              'Ұсынылады сізге'),
                                          style: manrope(17, FontWeight.w800,
                                              color: cInk)),
                                    ),
                                  ),
                                  if (groups.isEmpty)
                                    SliverToBoxAdapter(
                                      child: Padding(
                                        padding: const EdgeInsets.only(top: 60),
                                        child: ClientEmptyState(
                                          icon: Icons.search_off_rounded,
                                          message: _searchQuery.isNotEmpty
                                              ? tr('«$_searchQuery» не найдено',
                                                  '«$_searchQuery» табылмады')
                                              : _filters.activeCount > 0
                                                  ? tr(
                                                      'По выбранным фильтрам ничего не найдено',
                                                      'Таңдалған сүзгілер бойынша ештеңе табылмады')
                                                  : tr('Товаров нет',
                                                      'Тауарлар жоқ'),
                                        ),
                                      ),
                                    )
                                  else ...[
                                    if (_lastSearchFallback)
                                      SliverToBoxAdapter(
                                        child: Padding(
                                          padding: const EdgeInsets.fromLTRB(
                                              16, 0, 16, 4),
                                          child: Text(
                                              tr('Точных совпадений нет — вот похожие товары',
                                                  'Дәл сәйкестік табылмады — міне ұқсас тауарлар'),
                                              style: manrope(
                                                  12.5, FontWeight.w600,
                                                  color: cInk3)),
                                        ),
                                      ),
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
                                        delegate: SliverChildBuilderDelegate(
                                          (_, i) {
                                            final variantId = cards[i]
                                                .group
                                                .variants[cards[i].index]
                                                .id;
                                            return ProductGroupCard(
                                              key: ValueKey(variantId),
                                              group: cards[i].group,
                                              initialIndex: cards[i].index,
                                              batchesByProductId: batchesById,
                                              storeByProductId: storeById,
                                              tone: i % 5,
                                              onTap: _openProduct,
                                              isFavorite: _favoriteIds
                                                  .contains(variantId),
                                              onToggleFavorite: _toggleFavorite,
                                            );
                                          },
                                          childCount: cards.length,
                                        ),
                                      ),
                                    ),
                                  ],
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

  /// Қала таңдау: Барлық қалалар / өз қалаңыз / дүкені бар қалалар.
  Future<void> _openCitySheet() async {
    final myCity = context.read<AppUser>().city.trim();
    // Дүкені бар қалалар (санымен) — өз қала бірінші, қалғаны дүкен санына
    // қарай кему ретімен.
    final counts = <String, int>{};
    for (final s in _allStores) {
      final c = s.city.trim();
      if (c.isNotEmpty) counts[c] = (counts[c] ?? 0) + 1;
    }
    final cities = counts.entries.toList()
      ..sort((a, b) {
        if (a.key == myCity) return -1;
        if (b.key == myCity) return 1;
        return b.value.compareTo(a.value);
      });

    final selected = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(top: 12, bottom: 6),
            decoration: BoxDecoration(
                color: cLine, borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(tr('Выберите город', 'Қала таңдаңыз'),
                  style: manrope(17, FontWeight.w800, color: cInk)),
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
              children: [
                ListTile(
                  leading: const Icon(Icons.public_rounded, color: cGreen),
                  title: Text(
                      tr('Все города Казахстана', 'Қазақстанның барлық қаласы'),
                      style: manrope(14.5, FontWeight.w600, color: cInk)),
                  trailing: _cityFilter == null
                      ? const Icon(Icons.check_rounded, color: cGreen)
                      : null,
                  onTap: () => Navigator.pop(ctx, ''),
                ),
                ...cities.map((e) => ListTile(
                      leading: Icon(
                          e.key == myCity
                              ? Icons.my_location_rounded
                              : Icons.location_city_rounded,
                          color: e.key == myCity ? cGreen : cInk3),
                      title: Text(
                          e.key == myCity
                              ? tr('${e.key} (мой город)',
                                  '${e.key} (менің қалам)')
                              : e.key,
                          style: manrope(14.5, FontWeight.w600, color: cInk)),
                      subtitle: Text(
                          tr('${e.value} магазинов', '${e.value} дүкен'),
                          style: manrope(12, FontWeight.w500, color: cInk3)),
                      trailing: _cityFilter == e.key
                          ? const Icon(Icons.check_rounded, color: cGreen)
                          : null,
                      onTap: () => Navigator.pop(ctx, e.key),
                    )),
              ],
            ),
          ),
        ]),
      ),
    );
    if (selected == null || !mounted) return;
    _setCityFilter(selected.isEmpty ? null : selected);
  }

  /// Фильтр sheet-і: санат, кому, баға аралығы, скидка, дүкен, сорттау.
  Future<void> _openFilters() async {
    final result = await showHomeFiltersSheet(
      context,
      current: _filters,
      stores: _stores,
    );
    if (result != null && mounted) {
      setState(() {
        _filters = result;
        _displayCount = 20;
      });
    }
  }

  /// Открывает деталь товара; «Купить сейчас» переключает на вкладку корзины.
  /// [variants] — все цветовые варианты группы (для переключателя цвета).
  Future<void> _openProduct(ProductModel p, List<ProductModel> variants) async {
    final store = _productStoreMap[p.id];
    if (store == null) return;
    BrowsingSignalsService.instance
        .recordView(categoryKey: p.effectiveCategoryKey, brand: p.brand);
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
        // GuestShell табтары: 0=Басты, 1=Каталог, 2=Себет. Бұрын қате 1 (Каталог)
        // қойылып, «купить» басқанда клиент каталогқа өтіп кететін — енді Себет.
        context.findAncestorStateOfType<GuestShellState>()?.setIndex(2);
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

  /// Дүкен(дер)ге сілтелген баннер: біреу болса — тікелей ашады, бірнешеу
  /// болса — таңдау парағын көрсетеді. Дүкен жабық/блокталған/жарияланбаған
  /// болса — үнсіз ештеңе істемейміз.
  Future<void> _openStore(BuildContext context, BannerModel b) async {
    if (b.storeAdminUids.isEmpty) return;
    if (b.storeAdminUids.length == 1) {
      await _openSingleStore(context, b.storeAdminUids.first);
      return;
    }
    final chosenUid = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: cSurface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
                color: cLine, borderRadius: BorderRadius.circular(2)),
          ),
          Text(tr('Выберите магазин', 'Дүкенді таңдаңыз'),
              style: manrope(17, FontWeight.w800, color: cInk)),
          const SizedBox(height: 12),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (var i = 0; i < b.storeAdminUids.length; i++)
                  ListTile(
                    leading:
                        const Icon(Icons.storefront_rounded, color: cGreen),
                    title: Text(i < b.storeNames.length ? b.storeNames[i] : '',
                        style: manrope(14.5, FontWeight.w600, color: cInk)),
                    onTap: () => Navigator.pop(ctx, b.storeAdminUids[i]),
                  ),
              ],
            ),
          ),
        ]),
      ),
    );
    if (chosenUid != null && context.mounted) {
      await _openSingleStore(context, chosenUid);
    }
  }

  Future<void> _openSingleStore(BuildContext context, String uid) async {
    try {
      final store = await ClientService().getStoreByAdminUid(uid);
      if (store == null ||
          !store.isPublished ||
          store.isBlocked ||
          !context.mounted) {
        return;
      }
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => StorePublicScreen(store: store)),
      );
    } catch (_) {}
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
              child: GestureDetector(
                // Дүкенге сілтелген баннер — басқанда сол дүкеннің каталогы.
                onTap: b.hasStoreLink ? () => _openStore(context, b) : null,
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    gradient: b.hasImage
                        ? null
                        : LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [b.startColor, b.endColor],
                          ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: kShadowSm,
                  ),
                  child: b.hasImage
                      ? Stack(fit: StackFit.expand, children: [
                          Image.network(b.imageUrl, fit: BoxFit.cover),
                          if (b.hasStoreLink)
                            Positioned(
                              right: 10,
                              bottom: 10,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 9, vertical: 5),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.45),
                                  borderRadius: BorderRadius.circular(9),
                                ),
                                child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(tr('В магазин', 'Дүкенге'),
                                          style: manrope(11, FontWeight.w800,
                                              color: Colors.white)),
                                      const Icon(Icons.chevron_right_rounded,
                                          color: Colors.white, size: 15),
                                    ]),
                              ),
                            ),
                        ])
                      : Padding(
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
                                        color: Colors.white
                                            .withValues(alpha: 0.22),
                                        borderRadius: BorderRadius.circular(7),
                                      ),
                                      child: Text(b.badge,
                                          style: manrope(10.5, FontWeight.w800,
                                              color: Colors.white)),
                                    ),
                                  if (b.badge.isNotEmpty)
                                    const SizedBox(height: 6),
                                  Text(b.title,
                                      style: manrope(17, FontWeight.w800,
                                          color: Colors.white,
                                          letterSpacing: -0.3),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                  if (b.subtitle.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(b.subtitle,
                                        style: manrope(12.5, FontWeight.w500,
                                            color: Colors.white
                                                .withValues(alpha: 0.9)),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis),
                                  ],
                                ],
                              ),
                            ),
                            if (b.hasStoreLink)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 9, vertical: 5),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.22),
                                  borderRadius: BorderRadius.circular(9),
                                ),
                                child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(tr('В магазин', 'Дүкенге'),
                                          style: manrope(11, FontWeight.w800,
                                              color: Colors.white)),
                                      const Icon(Icons.chevron_right_rounded,
                                          color: Colors.white, size: 15),
                                    ]),
                              ),
                          ]),
                        ),
                ),
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
