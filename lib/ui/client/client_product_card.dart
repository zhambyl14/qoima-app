import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/models/product_model.dart';
import '../../data/models/batch_model.dart';
import '../../data/models/store_model.dart';
import '../../data/models/cart_item_model.dart';
import '../../data/models/category_data.dart';
import '../../data/services/client_service.dart';
import '../../theme/qoima_design.dart';
import '../../theme/qoima_v2.dart';
import 'client_shell.dart';

import '../../core/lang.dart';
/// Wildberries-стиль карточка группы: одна карточка на товар, цветовые
/// варианты (same name+brand+type) переключаются точками под названием.
class ProductGroupCard extends StatefulWidget {
  final ProductGroup group;
  final Map<String, List<BatchModel>> batchesByProductId;
  final Map<String, StoreModel?> storeByProductId;
  final int tone;
  // Карточка осы нұсқадан басталады (әр түс — жеке карточка).
  final int initialIndex;
  // selected — текущий выбранный вариант; variants — все варианты группы.
  final void Function(ProductModel selected, List<ProductModel> variants) onTap;
  // false — жылдам «+» (себетке қосу) батырмасы жасырылады (иесінің preview-і).
  final bool quickAddEnabled;

  const ProductGroupCard({
    super.key,
    required this.group,
    required this.batchesByProductId,
    required this.storeByProductId,
    required this.tone,
    required this.onTap,
    this.initialIndex = 0,
    this.quickAddEnabled = true,
  });

  @override
  State<ProductGroupCard> createState() => _ProductGroupCardState();
}

class _ProductGroupCardState extends State<ProductGroupCard> {
  // Карточка өз түсінен (initialIndex) басталады. Қолмен ауыстырған түс
  // қайта құру (іздеу/жүктелу) кезінде сақталуы үшін — шақырушы тұрақты
  // ValueKey береді (нұсқаның product id-і), сол арқылы State жоғалмайды.
  late int _selectedIndex = widget.initialIndex.clamp(
      0, widget.group.variants.length - 1);

  List<ProductModel> get _variants => widget.group.variants;
  ProductModel get _product => _variants[_selectedIndex];
  List<BatchModel> get _batches =>
      widget.batchesByProductId[_product.id] ?? const [];
  StoreModel? get _store => widget.storeByProductId[_product.id];

  BatchModel? get _priceBatch => _batches.isNotEmpty ? _batches.first : null;
  double get _basePrice => _priceBatch?.sellingPrice ?? 0.0;
  double get _price => _priceBatch != null ? effectivePrice(_priceBatch!) : 0.0;
  bool get _hasDiscount =>
      _priceBatch != null && hasActiveDiscount(_priceBatch!);
  int get _discountPct =>
      _priceBatch != null ? discountBadgePercent(_priceBatch!) : 0;

  void _quickAdd() {
    final store = _store;
    if (store == null) {
      widget.onTap(_product, _variants);
      return;
    }
    final Map<String, ({int qty, BatchModel batch})> available = {};
    for (final b in _batches) {
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
      widget.onTap(_product, _variants);
      return;
    }
    final sortedSizes = available.keys.toList()
      ..sort((a, b) => (int.tryParse(a) ?? 0).compareTo(int.tryParse(b) ?? 0));

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _SizePickerSheet(
        product: _product,
        store: store,
        price: _price,
        sortedSizes: sortedSizes,
        available: {for (final e in available.entries) e.key: e.value},
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final variantCount = _variants.length;
    return GestureDetector(
      onTap: () => widget.onTap(_product, _variants),
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
          mainAxisSize: MainAxisSize.max,
          children: [
            // Image area — category tag, discount badge, favorite, variant count.
            // Expanded: атау 2 жол + цвет-нүктелер + сызылған баға қосылғанда
            // мәтін блогы ұзарса, сурет өзі кішірейеді — баға карточкадан
            // ШЫҚПАЙДЫ (бұрын height:130 бекітулі болып, контент тасып кететін).
            Expanded(
              child: Stack(children: [
              QShoeImage(
                imageUrl:
                    _product.images.isNotEmpty ? _product.images.first : null,
                height: double.infinity,
                tone: widget.tone,
              ),
              Positioned(
                bottom: 7,
                left: 7,
                child: QCategoryTag(
                  category: categoryByKey(_product.effectiveCategoryKey),
                  fontSize: 10,
                ),
              ),
              if (_hasDiscount)
                Positioned(
                  top: 7,
                  left: 7,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: cRed,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('−$_discountPct%',
                        style: manrope(11.5, FontWeight.w800,
                            color: Colors.white)),
                  ),
                ),
              Positioned(
                top: 7,
                right: 7,
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.9),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.favorite_border_rounded,
                      size: 14, color: cInk3),
                ),
              ),
              // 3+ нұсқа болса — «{n} түс» бейджі (суреттің астыңғы оң бұрышы)
              if (variantCount >= 3)
                Positioned(
                  bottom: 7,
                  right: 7,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: cInk.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(tr('$variantCount цв.', '$variantCount түс'),
                        style:
                            manrope(10, FontWeight.w800, color: Colors.white)),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 8),
            // Product name
            Text(_product.name,
                style: manrope(13, FontWeight.w700, color: cInk),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
            // Рейтинг (денормализацияланған — N+1 сұраныссыз)
            if (_product.ratingCount > 0) ...[
              const SizedBox(height: 3),
              Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.star_rounded,
                    size: 13, color: Color(0xFFF6A609)),
                const SizedBox(width: 2),
                Text(
                  '${_product.ratingAvg.toStringAsFixed(1)} (${_product.ratingCount})',
                  style: manrope(11, FontWeight.w700, color: cInk2),
                ),
              ]),
            ],
            // Color variant dots (only when >1 variant)
            if (variantCount > 1) ...[
              const SizedBox(height: 9),
              Wrap(
                spacing: 11,
                runSpacing: 8,
                children: List.generate(variantCount, (i) {
                  return _ColorDot(
                    color: ProductModel.colorHex(_variants[i].color),
                    selected: i == _selectedIndex,
                    onTap: () => setState(() => _selectedIndex = i),
                  );
                }),
              ),
            ],
            // Spacer ЕМЕС: бос орынды түгел жоғарыдағы Expanded (сурет) алады.
            const SizedBox(height: 8),
            // Price + add button
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_hasDiscount)
                        Text(
                          money(_basePrice),
                          style: manrope(10.5, FontWeight.w600, color: cInk3)
                              .copyWith(decoration: TextDecoration.lineThrough),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      Text(
                        _price > 0 ? money(_price) : '—',
                        style: manrope(14, FontWeight.w800,
                            color: _hasDiscount ? cRed : cInk),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (widget.quickAddEnabled)
                  GestureDetector(
                    onTap: _quickAdd,
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

// ── Color dot ────────────────────────────────────────────────────────────────
class _ColorDot extends StatelessWidget {
  final Color? color;
  final bool selected;
  final VoidCallback onTap;
  const _ColorDot(
      {required this.color, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = color ?? const Color(0xFFBDBDBD);
    // Светлые цвета (белый) — нужна серая обводка, иначе сольётся с фоном.
    final isLight = c.computeLuminance() > 0.82;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          color: c,
          shape: BoxShape.circle,
          border: isLight
              ? Border.all(color: const Color(0xFFE0E0E0), width: 1.2)
              : null,
          // Выбранный: белое кольцо 2px + зелёное кольцо 3.5px
          boxShadow: selected
              ? const [
                  BoxShadow(color: cGreen, spreadRadius: 3),
                  BoxShadow(color: Colors.white, spreadRadius: 1.8),
                ]
              : null,
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
  final _service = ClientService();
  String? _selected;
  bool _saving = false;

  Future<void> _confirm() async {
    if (_selected == null || _saving) return;
    final entry = widget.available[_selected!]!;
    final eff = effectivePrice(entry.batch);
    final size = _selected!;
    // Контекстті async-тен бұрын ұстап аламыз.
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final cart = context.read<CartProvider>();

    setState(() => _saving = true);
    // Получение адресін жүктейміз (детальдегі секілді) — себетте/брон/төлемде
    // адрес көрінсін. Guest үшін permission-denied болуы мүмкін → бос қалады.
    String address = '';
    if (entry.batch.warehouseId.isNotEmpty) {
      try {
        final wh = await _service.getWarehouseById(
            widget.store.adminUid, entry.batch.warehouseId);
        if (wh != null && (wh.address ?? '').isNotEmpty) address = wh.address!;
      } catch (_) {}
    }

    cart.addItem(CartItemModel(
      productId: widget.product.id,
      productName: widget.product.name,
      batchId: entry.batch.id,
      size: size,
      qty: 1,
      price: eff,
      originalPrice:
          hasActiveDiscount(entry.batch) ? entry.batch.sellingPrice : 0,
      adminUid: widget.store.adminUid,
      storeName: widget.store.storeName,
      imageUrl:
          widget.product.images.isNotEmpty ? widget.product.images.first : '',
      warehouseId: entry.batch.warehouseId,
      warehouseAddress: address,
    ));
    navigator.pop();
    messenger.showSnackBar(SnackBar(
      content: Text(tr('${widget.product.name} ($size) добавлен в корзину', '${widget.product.name} ($size) себетке қосылды')),
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
        QSecLabel(tr('Выберите размер', 'Өлшемді таңдаңыз')),
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
          label: tr('Добавить в корзину', 'Себетке қосу'),
          onPressed: (_selected != null && !_saving) ? _confirm : null,
          height: 52,
          icon: const Icon(Icons.shopping_cart_outlined,
              color: Colors.white, size: 18),
        ),
      ]),
    );
  }
}

// ── Empty state ────────────────────────────────────────────────────────────────
class ClientEmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  const ClientEmptyState({super.key, required this.icon, required this.message});

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
