import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/models/product_model.dart';
import '../../data/models/store_model.dart';
import '../../data/models/batch_model.dart';
import '../../data/models/cart_item_model.dart';
import '../../data/services/client_service.dart';
import '../../theme/qoima_design.dart';
import 'client_shell.dart';

import '../../core/lang.dart';
class ClientProductDetail extends StatefulWidget {
  final ProductModel product;
  final StoreModel store;
  // Все цветовые варианты группы (для переключателя цвета). По умолчанию — сам товар.
  final List<ProductModel> allVariants;
  const ClientProductDetail({
    super.key,
    required this.product,
    required this.store,
    this.allVariants = const [],
  });

  @override
  State<ClientProductDetail> createState() => _ClientProductDetailState();
}

class _ClientProductDetailState extends State<ClientProductDetail> {
  final _service = ClientService();

  // Цветовые варианты + текущий выбранный.
  late final List<ProductModel> _variants =
      widget.allVariants.isEmpty ? [widget.product] : widget.allVariants;
  late int _variantIndex = () {
    final i = _variants.indexWhere((v) => v.id == widget.product.id);
    return i < 0 ? 0 : i;
  }();
  ProductModel get _currentProduct => _variants[_variantIndex];

  List<BatchModel> _batches = [];
  Map<String, String> _warehouseAddress = {};
  bool _loading = true;
  String? _selectedSize;
  int _pageIndex = 0;
  Set<String> _favIds = {};
  bool _togglingFav = false;
  StreamSubscription<List<String>>? _favSub;

  bool get _isFavorite => _favIds.contains(_currentProduct.id);

  // Тек қолжетімді размерлер — «В корзину» батырмасы мен _totalAvail үшін.
  Map<String, int> get _available {
    final map = <String, int>{};
    for (final b in _batches) {
      b.availableSizes.forEach((size, avail) {
        map[size] = (map[size] ?? 0) + avail;
      });
    }
    return map;
  }

  // Барлық анықталған размерлер (0-дылар сызылған күйде UI-да көрсетіледі).
  Map<String, int> get _allSizes {
    final map = <String, int>{};
    for (final b in _batches) {
      for (final size in b.sizesQuantity.keys) {
        map[size] = (map[size] ?? 0) + b.availableForSize(size);
      }
    }
    return map;
  }

  BatchModel? get _priceBatch {
    final sized = _batchForSize;
    if (sized != null) return sized;
    return _batches.isNotEmpty ? _batches.first : null;
  }

  // Базовая (зачёркнутая) цена и итоговая цена со скидкой товара
  double get _basePrice => _priceBatch?.sellingPrice ?? 0.0;
  double get _price =>
      _priceBatch != null ? effectivePrice(_priceBatch!) : 0.0;
  bool get _hasDiscount =>
      _priceBatch != null && hasActiveDiscount(_priceBatch!);
  int get _discountPct =>
      _priceBatch != null ? discountBadgePercent(_priceBatch!) : 0;

  BatchModel? get _batchForSize {
    for (final b in _batches) {
      if (b.availableForSize(_selectedSize ?? '') > 0) return b;
    }
    return null;
  }

  String get _batchId => _batchForSize?.id ?? '';
  String get _warehouseId => _batchForSize?.warehouseId ?? '';
  String get _pickupAddress => _batchForSize != null
      ? (_warehouseAddress[_batchForSize!.warehouseId] ?? '')
      : '';

  @override
  void initState() {
    super.initState();
    _loadBatches();
    _favSub = _service.watchFavoriteIds().listen((ids) {
      if (mounted) setState(() => _favIds = ids.toSet());
    });
  }

  @override
  void dispose() {
    _favSub?.cancel();
    super.dispose();
  }

  /// Переключение цветового варианта: меняем товар и перезагружаем батчи.
  void _onSelectVariant(int i) {
    if (i == _variantIndex) return;
    setState(() {
      _variantIndex = i;
      _selectedSize = null;
      _pageIndex = 0;
      _batches = [];
      _warehouseAddress = {};
      _loading = true;
    });
    _loadBatches();
  }

  Future<void> _toggleFavorite() async {
    if (_togglingFav) return;
    setState(() => _togglingFav = true);
    final p = _currentProduct;
    try {
      if (_isFavorite) {
        await _service.removeFavorite(p.id);
      } else {
        final price = _batches.isNotEmpty ? _batches.first.sellingPrice : 0.0;
        final img = p.images.isNotEmpty ? p.images.first : '';
        await _service.addFavorite(
          productId: p.id,
          productName: p.name,
          imageUrl: img,
          adminUid: widget.store.adminUid,
          storeName: widget.store.storeName,
          price: price,
        );
      }
    } catch (_) {} finally {
      if (mounted) setState(() => _togglingFav = false);
    }
  }

  Future<void> _loadBatches() async {
    try {
      // Detail-де барлық batch-тарды жүктейміз (OOS да) — пайдаланушы
      // қандай размерлер бар екенін, қайсысы бітіп кеткенін көру үшін.
      final batches = await _service.getProductBatches(
        widget.store.adminUid,
        _currentProduct.id,
        widget.store.visibleWarehouseIds,
        onlyAvailable: false,
      );

      // Батч-тарды бірінші орнатамыз — размерлер бірден көрінеді.
      // Мекенжай жүктеуі guest үшін permission-denied бере алады (warehouses
      // тек авторизацияланған үшін), сол себепті try-catch-пен жеке жасаймыз.
      if (mounted) {
        setState(() {
          _batches = batches;
          _loading = false;
        });
      }

      // Мекенжайларды жеке жүктейміз — сәтсіз болса да размерлерге әсер жоқ.
      final ids = batches.map((b) => b.warehouseId).toSet();
      final Map<String, String> addresses = {};
      for (final id in ids) {
        if (id.isEmpty) continue;
        try {
          final wh = await _service.getWarehouseById(widget.store.adminUid, id);
          if (wh != null && (wh.address ?? '').isNotEmpty) {
            addresses[id] = wh.address!;
          }
        } catch (_) {}
      }
      if (addresses.isNotEmpty && mounted) {
        setState(() => _warehouseAddress = addresses);
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  CartItemModel? _buildCartItem() {
    if (_selectedSize == null) return null;
    final p = _currentProduct;
    return CartItemModel(
      productId: p.id,
      productName: p.name,
      batchId: _batchId,
      size: _selectedSize!,
      qty: 1,
      price: _price,
      originalPrice: _hasDiscount ? _basePrice : 0,
      adminUid: widget.store.adminUid,
      storeName: widget.store.storeName,
      imageUrl: p.images.isNotEmpty ? p.images.first : '',
      warehouseId: _warehouseId,
      warehouseAddress: _pickupAddress,
    );
  }

  void _addToCart() {
    if (_selectedSize == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(tr('Выберите размер', 'Өлшемді таңдаңыз')),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    context.read<CartProvider>().addItem(_buildCartItem()!);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(tr('${_currentProduct.name} добавлен в корзину', '${_currentProduct.name} себетке қосылды')),
      backgroundColor: cGreen,
      behavior: SnackBarBehavior.floating,
    ));
    Navigator.pop(context);
  }

  void _buyNow() {
    if (_selectedSize == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(tr('Выберите размер', 'Өлшемді таңдаңыз')),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    context.read<CartProvider>().addItem(_buildCartItem()!);
    // true-ны сигнал ретінде жіберіп, шақырушы cart-табқа ауысады
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final images = _currentProduct.images;
    final allSizes = _allSizes; // барлық размерлер (0-дылар сызылған)
    final avail = _available;  // тек қолжетімді (корзина/батырма үшін)

    return Scaffold(
      backgroundColor: cBg,
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: cGreen))
          : Stack(children: [
              // ── Бәрі бірге скролл болады (сурет + сипаттама) ──────────
              SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 100),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Hero image — контентпен бірге скролл, фонсыз 1:1 cover.
                    Container(
                      color: const Color(0xFFE4F7EE),
                      child: AspectRatio(
                      aspectRatio: 1.1,
                      child: images.isNotEmpty
                          ? Stack(children: [
                              PageView.builder(
                                itemCount: images.length,
                                onPageChanged: (i) =>
                                    setState(() => _pageIndex = i),
                                itemBuilder: (_, i) => Image.network(images[i],
                                    fit: BoxFit.cover,
                                    width: double.infinity,
                                    height: double.infinity,
                                    errorBuilder: (_, __, ___) =>
                                        _shoePlaceholder()),
                              ),
                              if (images.length > 1)
                                Positioned(
                                  bottom: 12,
                                  left: 0,
                                  right: 0,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: List.generate(
                                        images.length,
                                        (i) => AnimatedContainer(
                                              duration: const Duration(
                                                  milliseconds: 200),
                                              width: i == _pageIndex ? 20 : 7,
                                              height: 7,
                                              margin:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 2),
                                              decoration: BoxDecoration(
                                                color: i == _pageIndex
                                                    ? cGreen
                                                    : cInk.withValues(
                                                        alpha: 0.18),
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                            )),
                                  ),
                                ),
                            ])
                          : _shoePlaceholder(),
                    ),
                    ),

                    // ── Details ───────────────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      // Name
                      Text(_currentProduct.name,
                          style: manrope(22, FontWeight.w800,
                              color: cInk, letterSpacing: -0.4)),
                      if (_currentProduct.type.isNotEmpty)
                        Text(_currentProduct.type,
                            style: manrope(13.5, FontWeight.w500,
                                color: cInk3)),
                      const SizedBox(height: 10),

                      // Price (со скидкой товара — зачёркнутая старая + новая + бейдж)
                      if (_price > 0)
                        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Text(money(_price),
                              style: manrope(28, FontWeight.w800,
                                  color: _hasDiscount ? cRed : cInk)),
                          if (_hasDiscount) ...[
                            const SizedBox(width: 10),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 5),
                              child: Text(money(_basePrice),
                                  style: manrope(16, FontWeight.w600, color: cInk3)
                                      .copyWith(
                                          decoration:
                                              TextDecoration.lineThrough)),
                            ),
                            const SizedBox(width: 8),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: cRed,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text('−$_discountPct%',
                                    style: manrope(12.5, FontWeight.w800,
                                        color: Colors.white)),
                              ),
                            ),
                          ],
                        ]),

                      const SizedBox(height: 16),

                      // ── Түсі (color variants) ───────────────────────
                      if (_variants.length > 1) ...[
                        QSecLabel(tr('Цвет', 'Түсі')),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: List.generate(_variants.length, (i) {
                            final v = _variants[i];
                            final selected = i == _variantIndex;
                            final dot = ProductModel.colorHex(v.color) ??
                                const Color(0xFFBDBDBD);
                            return GestureDetector(
                              onTap: () => _onSelectVariant(i),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 11, vertical: 8),
                                decoration: BoxDecoration(
                                  color: selected ? cGreenTint : cSurface,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                      color: selected ? cGreen : cLine,
                                      width: 1.5),
                                ),
                                child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 16,
                                        height: 16,
                                        decoration: BoxDecoration(
                                          color: dot,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                              color: const Color(0xFFE0E0E0),
                                              width: 1),
                                        ),
                                      ),
                                      const SizedBox(width: 7),
                                      Text(
                                          v.color.isNotEmpty
                                              ? trValue(v.color)
                                              : tr('Цвет ${i + 1}', 'Түс ${i + 1}'),
                                          style: manrope(13, FontWeight.w700,
                                              color: selected
                                                  ? cGreenDeep
                                                  : cInk)),
                                    ]),
                              ),
                            );
                          }),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Sizes — барлық анықталған размерлер; қолжетімді
                      // емес болса үсті сызылған күйде көрінеді.
                      if (allSizes.isNotEmpty) ...[
                        QSecLabel(tr('Размер', 'Өлшем')),
                        Wrap(
                          spacing: 9,
                          runSpacing: 9,
                          children: (allSizes.entries.toList()
                                ..sort((a, b) =>
                                    (double.tryParse(a.key) ?? 0)
                                        .compareTo(double.tryParse(b.key) ?? 0)))
                              .map((e) {
                            final isAvailable = e.value > 0;
                            final selected = _selectedSize == e.key;
                            return GestureDetector(
                              onTap: isAvailable
                                  ? () => setState(() => _selectedSize = e.key)
                                  : null,
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                width: 56,
                                height: 50,
                                decoration: BoxDecoration(
                                  color: !isAvailable
                                      ? cLine2
                                      : selected
                                          ? cGreenTint
                                          : cSurface,
                                  borderRadius: BorderRadius.circular(13),
                                  border: Border.all(
                                    color: selected ? cGreen : cLine,
                                    width: 1.5,
                                  ),
                                  boxShadow: selected
                                      ? [BoxShadow(
                                          color: cGreenTint,
                                          blurRadius: 0,
                                          spreadRadius: 3)]
                                      : null,
                                ),
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    Opacity(
                                      opacity: isAvailable ? 1.0 : 0.38,
                                      child: Text(e.key,
                                          style: manrope(15.5, FontWeight.w800,
                                              color: cInk)),
                                    ),
                                    if (!isAvailable)
                                      Positioned.fill(
                                        child: CustomPaint(
                                            painter: _StrikePainter()),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],

                      // ── Описание (маркетплейс-стиль, жайылмалы) ─────
                      if (_currentProduct.description.isNotEmpty)
                        _DescriptionSection(text: _currentProduct.description),

                      // ── Характеристики ──────────────────────────────
                      _SpecSection(product: _currentProduct),

                      const SizedBox(height: 16),

                      // Store card
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: cGreenTint,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Row(children: [
                          const Icon(Icons.storefront_outlined,
                              color: cGreenDeep, size: 22),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(widget.store.storeName,
                                      style: manrope(13.5, FontWeight.w700,
                                          color: cGreenDeep)),
                                  if (widget.store.address.isNotEmpty)
                                    Text(widget.store.address,
                                        style: manrope(12, FontWeight.w500,
                                            color: cGreenDeep.withValues(
                                                alpha: 0.8))),
                                ]),
                          ),
                          const Icon(Icons.chevron_right_rounded,
                              color: cGreenDeep, size: 18),
                        ]),
                      ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // ── Бекітілген артқа/таңдаулы батырмалар (скроллда қозғалмайды)
              SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                  child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _RoundBtn(
                          icon: Icons.chevron_left_rounded,
                          onTap: () => Navigator.pop(context),
                        ),
                        _RoundBtn(
                          icon: _isFavorite
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          iconColor: cRed,
                          onTap: _toggleFavorite,
                        ),
                      ]),
                ),
              ),
            ]),
      bottomNavigationBar: avail.isEmpty
          ? null
          : SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
                decoration: const BoxDecoration(
                  color: cSurface,
                  border: Border(top: BorderSide(color: cLine)),
                ),
                child: Row(children: [
                  // Cart icon button
                  GestureDetector(
                    onTap: _addToCart,
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: cGreenTint,
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: const Icon(Icons.shopping_cart_outlined,
                          color: cGreenDeep, size: 22),
                    ),
                  ),
                  const SizedBox(width: 11),
                  // Buy button
                  Expanded(
                    child: QPrimaryButton(
                      label: _price > 0
                          ? tr('Купить · ${money(_price)}', 'Сатып алу · ${money(_price)}')
                          : tr('В корзину', 'Себетке'),
                      onPressed: _buyNow,
                      height: 52,
                    ),
                  ),
                ]),
              ),
            ),
    );
  }

  Widget _shoePlaceholder() => Container(
        height: 180,
        margin: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFE4F7EE), Color(0xFFC8EEDB)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Center(
          child: Icon(Icons.inventory_2_outlined,
              size: 64, color: Color(0x380C120F)),
        ),
      );
}

class _RoundBtn extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final VoidCallback onTap;
  const _RoundBtn(
      {required this.icon,
      this.iconColor = cInk,
      required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(icon, color: iconColor, size: 20),
        ),
      );
}

// ── Spec row data ─────────────────────────────────────────────────────────────
class _SpecRow {
  final String label;
  final String value;
  const _SpecRow(this.label, this.value);
}

// ── Описание секциясы (ұзын мәтін жиналып тұрады — «Читать далее») ───────────
class _DescriptionSection extends StatefulWidget {
  final String text;
  const _DescriptionSection({required this.text});

  @override
  State<_DescriptionSection> createState() => _DescriptionSectionState();
}

class _DescriptionSectionState extends State<_DescriptionSection> {
  static const int _collapsedLines = 5;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final style =
        manrope(13.5, FontWeight.w500, color: cInk2).copyWith(height: 1.5);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        QSecLabel(tr('Описание', 'Сипаттама')),
        LayoutBuilder(builder: (ctx, constraints) {
          // Мәтін 5 жолдан асатынын өлшеп, «Читать далее» керек пе — соны
          // анықтаймыз (қысқа сипаттамаға артық батырма көрсетпейміз).
          final painter = TextPainter(
            text: TextSpan(text: widget.text, style: style),
            maxLines: _collapsedLines,
            textDirection: TextDirection.ltr,
          )..layout(maxWidth: constraints.maxWidth);
          final needsToggle = painter.didExceedMaxLines;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                alignment: Alignment.topCenter,
                child: Text(
                  widget.text,
                  style: style,
                  maxLines: _expanded ? null : _collapsedLines,
                  overflow: _expanded
                      ? TextOverflow.visible
                      : TextOverflow.ellipsis,
                ),
              ),
              if (needsToggle)
                GestureDetector(
                  onTap: () => setState(() => _expanded = !_expanded),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(
                          _expanded
                              ? tr('Свернуть', 'Жасыру')
                              : tr('Читать далее', 'Толығырақ оқу'),
                          style: manrope(13.5, FontWeight.w700,
                              color: cGreenDeep)),
                      Icon(
                          _expanded
                              ? Icons.keyboard_arrow_up_rounded
                              : Icons.keyboard_arrow_down_rounded,
                          size: 18,
                          color: cGreenDeep),
                    ]),
                  ),
                ),
            ],
          );
        }),
      ],
    );
  }
}

// ── Характеристики секциясы ───────────────────────────────────────────────────
class _SpecSection extends StatelessWidget {
  final ProductModel product;
  const _SpecSection({required this.product});

  @override
  Widget build(BuildContext context) {
    final rows = <_SpecRow>[
      if (product.category.isNotEmpty) _SpecRow(tr('Для кого', 'Кімге'), trValue(product.category)),
      if (product.material.isNotEmpty) _SpecRow('Материал', trValue(product.material)),
      if (product.brand.isNotEmpty)    _SpecRow('Бренд', product.brand),
      if (product.color.isNotEmpty)    _SpecRow(tr('Цвет', 'Түсі'), trValue(product.color)),
      if (product.type.isNotEmpty)     _SpecRow(tr('Тип', 'Түрі'), trValue(product.type)),
      if (product.season.isNotEmpty)   _SpecRow(tr('Сезон', 'Маусым'), trValue(product.season)),
      if (product.country.isNotEmpty)  _SpecRow(tr('Страна', 'Өндірілген ел'), product.country),
      if (product.articul.isNotEmpty)  _SpecRow('Артикул', product.articul),
    ];
    if (rows.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        QSecLabel(tr('Характеристики', 'Сипаттамалар')),
        QCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          child: Column(
            children: [
              for (int i = 0; i < rows.length; i++) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  child: Row(children: [
                    SizedBox(
                      width: 96,
                      child: Text(rows[i].label,
                          style: manrope(13, FontWeight.w500, color: cInk3)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(rows[i].value,
                          style: manrope(13.5, FontWeight.w700, color: cInk)),
                    ),
                  ]),
                ),
                if (i < rows.length - 1)
                  Container(height: 1, color: cLine),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _StrikePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(
      Offset(0, size.height),
      Offset(size.width, 0),
      Paint()
        ..color = cInk3.withValues(alpha: 0.5)
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
