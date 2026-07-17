import 'package:flutter/material.dart';
import '../../data/models/product_model.dart';
import '../../data/models/batch_model.dart';
import '../../data/models/store_model.dart';
import '../../data/services/client_service.dart';
import '../../theme/qoima_design.dart';
import '../shared/skeletons.dart';
import '../guest/guest_shell.dart';
import 'client_product_card.dart';
import 'client_product_detail.dart';
import 'client_shell.dart';

import '../../core/lang.dart';
/// Универсальный fashion-каталог, 3 уровня выбора (как маркетплейс):
/// L1 — категория (Обувь / Одежда / …) → L2 — кому → L3 — тип товара → товары.
/// Уровни управляются ЛОКАЛЬНЫМ состоянием (Navigator.push ЕМЕС).
class ClientCatalogScreen extends StatefulWidget {
  const ClientCatalogScreen({super.key});

  @override
  State<ClientCatalogScreen> createState() => _ClientCatalogScreenState();
}

class _ClientCatalogScreenState extends State<ClientCatalogScreen> {
  final _service = ClientService();

  List<({ProductModel product, List<BatchModel> batches})> _pairs = [];
  Map<String, StoreModel> _productStoreMap = {};
  bool _loadingStores = true;
  bool _loadingProducts = false;
  String? _error;

  // Деңгейлер: _cat==null → L1; _aud==null → L2; _type==null → L3; әйтпесе L4.
  _MainCatDef? _cat;
  String? _aud;
  String? _type;

  // L4 ішіндегі іздеу (категория-тип ішінен керегін табу).
  final _searchCtrl = TextEditingController();
  String _query = '';

  // ── L1: негізгі категория. keys → ProductModel.effectiveCategoryKey-пен сай.
  static const List<_MainCatDef> _mainCats = [
    _MainCatDef('Обувь', ['shoes'], '👟', Color(0xFFE3F2FD), Color(0xFF90CAF9)),
    _MainCatDef('Одежда', ['tshirt', 'outer', 'pants', 'dress'], '👕',
        Color(0xFFF3E5F5), Color(0xFFCE93D8)),
    _MainCatDef('Головные уборы', ['caps'], '🧢', Color(0xFFFFF3E0),
        Color(0xFFFFCC80)),
    _MainCatDef('Аксессуары', ['acc'], '🎒', Color(0xFFE8F5E9),
        Color(0xFFA5D6A7)),
    _MainCatDef('Спорт', ['sport'], '🏃', Color(0xFFFFEBEE), Color(0xFFEF9A9A)),
  ];

  // ── L2: кому. value → ProductModel.category-мен сай.
  static const List<_AudienceDef> _audiences = [
    _AudienceDef('Ерлерге', 'Мужские', '👨', Color(0xFFE4EEFE),
        Color(0xFFBBDEFB)),
    _AudienceDef('Әйелдерге', 'Женские', '👩', Color(0xFFFCE4EC),
        Color(0xFFF8BBD9)),
    _AudienceDef('Унисекс', 'Унисекс', '⭐', Color(0xFFE4F7EE),
        Color(0xFFA5D6A7)),
    _AudienceDef('Балаларға', 'Детские', '🧸', Color(0xFFFEF3DC),
        Color(0xFFFFE082)),
  ];

  @override
  void initState() {
    super.initState();
    _loadAll();
    // Дүкен жасырылса/ашылса — каталогты қайта жүктейміз.
    ClientService.hiddenStoresVersion.addListener(_onHiddenStoresChanged);
  }

  void _onHiddenStoresChanged() {
    if (mounted) _loadAll();
  }

  @override
  void dispose() {
    ClientService.hiddenStoresVersion.removeListener(_onHiddenStoresChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    final hasCache = _pairs.isNotEmpty;
    setState(() {
      if (!hasCache) _loadingStores = true;
      _error = null;
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

      // Каталог — бүкіл Қазақстан дүкендерінің товарлары (қала шектеуінсіз).
      final stores = allStores
          .where((s) => !hiddenIds.contains(s.adminUid))
          .toList();

      final storesWithProducts =
          stores.where((s) => s.visibleWarehouseIds.isNotEmpty).toList();

      setState(() {
        _loadingStores = false;
        _pairs = [];
        _productStoreMap = {};
        _loadingProducts = storesWithProducts.isNotEmpty;
      });
      if (storesWithProducts.isEmpty) return;

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
          _error = e.toString();
        });
      }
    }
  }

  // ── Сәйкестік ────────────────────────────────────────────────────────────
  bool _inCat(ProductModel p, _MainCatDef m) =>
      m.keys.contains(p.effectiveCategoryKey);

  // «Детские» — ұл/қыз бөлінісін де қамтиды (легаси товарлар үшін).
  bool _matchAud(ProductModel p, String aud) {
    if (aud == 'Детские') return p.category.startsWith('Детские');
    return p.category == aud;
  }

  List<ProductGroup> get _allGroups =>
      groupProducts(_pairs.map((e) => e.product).toList());

  int _catCount(_MainCatDef m) =>
      _allGroups.where((g) => _inCat(g.main, m)).length;

  int _audCount(_MainCatDef m, String aud) => _allGroups
      .where((g) => _inCat(g.main, m) && _matchAud(g.main, aud))
      .length;

  /// Тип товара тізімі — нақты тауарлардан динамикалық жинаймыз (админ не қосса,
  /// сол көрінеді). Бос тип «Другое» деп көрсетіледі.
  List<String> _typesFor(_MainCatDef m, String aud) {
    final seen = <String>{};
    final out = <String>[];
    for (final g in _allGroups) {
      if (_inCat(g.main, m) && _matchAud(g.main, aud)) {
        final t = g.main.type.trim();
        if (seen.add(t)) out.add(t);
      }
    }
    out.sort();
    return out;
  }

  int _typeCount(_MainCatDef m, String aud, String type) => _allGroups
      .where((g) =>
          _inCat(g.main, m) &&
          _matchAud(g.main, aud) &&
          g.main.type.trim() == type)
      .length;

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
        shell.setIndex(2); // Себет
      } else {
        context.findAncestorStateOfType<GuestShellState>()?.setIndex(2);
      }
    }
  }

  void _clearSearch() {
    _searchCtrl.clear();
    _query = '';
  }

  void _back() {
    setState(() {
      if (_type != null) {
        _type = null; // L4 → L3
        _clearSearch();
      } else if (_aud != null) {
        _aud = null; // L3 → L2
      } else if (_cat != null) {
        _cat = null; // L2 → L1
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isL1 = _cat == null;
    final isL2 = _cat != null && _aud == null;
    final isL3 = _aud != null && _type == null;

    final title = isL1
        ? 'Каталог'
        : isL2
            ? trValue(_cat!.label)
            : isL3
                ? _audLabel(_aud!)
                : (_type!.isEmpty ? tr('Другое', 'Басқа') : trValue(_type!));

    return Scaffold(
      backgroundColor: cBg,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          // ── Gradient header ─────────────────────────────────────────────
          Container(
            decoration: const BoxDecoration(gradient: kGrad),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 20, 16),
              child: Row(children: [
                if (!isL1)
                  GestureDetector(
                    onTap: _back,
                    child: Container(
                      width: 38,
                      height: 38,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.chevron_left_rounded,
                          color: Colors.white, size: 24),
                    ),
                  )
                else
                  const SizedBox(width: 4),
                Expanded(
                  child: Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: manrope(23, FontWeight.w800,
                          color: Colors.white, letterSpacing: -0.5)),
                ),
              ]),
            ),
          ),

          // ── Body ────────────────────────────────────────────────────────
          Expanded(
            child: _loadingStores
                ? const CatalogGridSkeleton()
                : _error != null
                    ? ClientEmptyState(
                        icon: Icons.error_outline_rounded, message: _error!)
                    : isL1
                        ? _buildCategoryGrid()
                        : isL2
                            ? _buildAudienceGrid()
                            : isL3
                                ? _buildTypeList()
                                : _buildProductGrid(),
          ),
        ]),
      ),
    );
  }

  // ru режимде канондық мәні (value), kk режимде — қазақша label.
  String _audLabel(String value) {
    final a = _audiences.firstWhere((a) => a.value == value);
    return tr(a.value, a.label);
  }

  // ── LEVEL 1: категория grid ─────────────────────────────────────────────
  Widget _buildCategoryGrid() {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.92,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
      ),
      itemCount: _mainCats.length,
      itemBuilder: (_, i) {
        final c = _mainCats[i];
        final count = _catCount(c);
        return _GradientTile(
          emoji: c.emoji,
          label: trValue(c.label),
          subtitle: _loadingProducts && count == 0 ? '...' : tr('$count товаров', '$count тауар'),
          g1: c.g1,
          g2: c.g2,
          onTap: () => setState(() => _cat = c),
        );
      },
    );
  }

  // ── LEVEL 2: кому grid ──────────────────────────────────────────────────
  Widget _buildAudienceGrid() {
    final cat = _cat!;
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.92,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
      ),
      itemCount: _audiences.length,
      itemBuilder: (_, i) {
        final a = _audiences[i];
        final count = _audCount(cat, a.value);
        final enabled = count > 0;
        return Opacity(
          opacity: enabled ? 1 : 0.4,
          child: _GradientTile(
            emoji: a.emoji,
            label: tr(a.value, a.label),
            subtitle: _loadingProducts && count == 0 ? '...' : tr('$count товаров', '$count тауар'),
            g1: a.g1,
            g2: a.g2,
            onTap: enabled ? () => setState(() => _aud = a.value) : null,
          ),
        );
      },
    );
  }

  // ── LEVEL 3: тип товара тізімі ──────────────────────────────────────────
  Widget _buildTypeList() {
    final cat = _cat!;
    final aud = _aud!;
    final types = _typesFor(cat, aud);

    if (types.isEmpty) {
      return ClientEmptyState(
          icon: Icons.search_off_rounded, message: tr('Товары не найдены', 'Тауарлар табылмады'));
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: types.length,
      separatorBuilder: (_, __) =>
          const Divider(height: 1, color: cLine2, indent: 76),
      itemBuilder: (_, i) {
        final t = types[i];
        final count = _typeCount(cat, aud, t);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() {
            _type = t;
            _clearSearch();
          }),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: cBg,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Center(
                    child: Text(cat.emoji,
                        style: const TextStyle(fontSize: 26))),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.isEmpty ? tr('Другое', 'Басқа') : trValue(t),
                        style: manrope(15, FontWeight.w600, color: cInk)),
                    const SizedBox(height: 2),
                    Text(tr('$count товаров', '$count тауар'),
                        style: manrope(12.5, FontWeight.w500, color: cInk3)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: cInk3, size: 22),
            ]),
          ),
        );
      },
    );
  }

  // ── LEVEL 4: тауарлар grid ──────────────────────────────────────────────
  Widget _buildProductGrid() {
    final cat = _cat!;
    final aud = _aud!;
    final type = _type!;
    final base = _allGroups
        .where((g) =>
            _inCat(g.main, cat) &&
            _matchAud(g.main, aud) &&
            g.main.type.trim() == type)
        .toList();
    final groups = _query.isEmpty
        ? base
        : base.where((g) => productGroupMatches(g, _query)).toList();
    // Әр түс — жеке карточка.
    final cards = expandVariantCards(groups);
    final batchesById = {for (final pr in _pairs) pr.product.id: pr.batches};
    final storeById = {
      for (final pr in _pairs) pr.product.id: _productStoreMap[pr.product.id]
    };

    return Column(children: [
      _buildSearchField(),
      if (cards.isEmpty)
        Expanded(
          child: ClientEmptyState(
            icon: Icons.search_off_rounded,
            message:
                _query.isEmpty ? tr('Товары не найдены', 'Тауарлар табылмады') : tr('«$_query» не найдено', '«$_query» табылмады'),
          ),
        )
      else ...[
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text(tr('${cards.length} товаров', '${cards.length} тауар'),
                style: manrope(13.5, FontWeight.w700, color: cInk2)),
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.72,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: cards.length,
            itemBuilder: (_, i) => ProductGroupCard(
              key: ValueKey(cards[i].group.variants[cards[i].index].id),
              group: cards[i].group,
              initialIndex: cards[i].index,
              batchesByProductId: batchesById,
              storeByProductId: storeById,
              tone: i % 5,
              onTap: _openProduct,
            ),
          ),
        ),
      ],
    ]);
  }

  // L4 ішіндегі іздеу өрісі.
  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: cSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cLine),
        ),
        child: Row(children: [
          const SizedBox(width: 12),
          const Icon(Icons.search_rounded, color: cInk3, size: 19),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              cursorColor: cGreen,
              textAlignVertical: TextAlignVertical.center,
              onChanged: (q) => setState(() => _query = q.trim()),
              style: manrope(14.5, FontWeight.w600, color: cInk),
              decoration: InputDecoration(
                hintText: tr('Поиск в этом разделе...', 'Осы бөлімнен іздеу...'),
                hintStyle: manrope(14.5, FontWeight.w500, color: cInk3),
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
                suffixIcon: _query.isNotEmpty
                    ? GestureDetector(
                        onTap: () => setState(_clearSearch),
                        child: const Icon(Icons.close_rounded,
                            color: cInk3, size: 18))
                    : null,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ]),
      ),
    );
  }
}

// ── Reusable gradient tile (L1/L2) ─────────────────────────────────────────────
class _GradientTile extends StatelessWidget {
  final String emoji, label, subtitle;
  final Color g1, g2;
  final VoidCallback? onTap;
  const _GradientTile({
    required this.emoji,
    required this.label,
    required this.subtitle,
    required this.g1,
    required this.g2,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [g1, g2],
          ),
          borderRadius: BorderRadius.circular(18),
          boxShadow: kShadowSm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 18),
            Expanded(
              child: Center(
                child: Text(emoji, style: const TextStyle(fontSize: 54)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: manrope(15, FontWeight.w800, color: cInk)),
                  const SizedBox(height: 1),
                  Text(subtitle,
                      style: manrope(12, FontWeight.w600,
                          color: cInk2.withValues(alpha: 0.7))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Tile data ──────────────────────────────────────────────────────────────────
class _MainCatDef {
  final String label;
  final List<String> keys; // ProductModel.effectiveCategoryKey-пен сай
  final String emoji;
  final Color g1, g2;
  const _MainCatDef(this.label, this.keys, this.emoji, this.g1, this.g2);
}

class _AudienceDef {
  final String label;
  final String value; // ProductModel.category-мен сай
  final String emoji;
  final Color g1, g2;
  const _AudienceDef(this.label, this.value, this.emoji, this.g1, this.g2);
}
