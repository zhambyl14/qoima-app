import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/models/product_model.dart';
import '../../data/models/store_model.dart';
import '../../data/models/batch_model.dart';
import '../../data/models/cart_item_model.dart';
import '../../data/services/client_service.dart';
import '../../theme/qoima_design.dart';
import 'client_shell.dart';

class ClientProductDetail extends StatefulWidget {
  final ProductModel product;
  final StoreModel store;
  const ClientProductDetail(
      {super.key, required this.product, required this.store});

  @override
  State<ClientProductDetail> createState() => _ClientProductDetailState();
}

class _ClientProductDetailState extends State<ClientProductDetail> {
  final _service = ClientService();

  List<BatchModel> _batches = [];
  Map<String, String> _warehouseAddress = {};
  bool _loading = true;
  String? _selectedSize;
  int _pageIndex = 0;

  Map<String, int> get _available {
    final map = <String, int>{};
    for (final b in _batches) {
      b.availableSizes.forEach((size, avail) {
        map[size] = (map[size] ?? 0) + avail;
      });
    }
    return map;
  }

  double get _price =>
      _batches.isNotEmpty ? _batches.first.sellingPrice : 0.0;

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
  }

  Future<void> _loadBatches() async {
    try {
      final batches = await _service.getProductBatches(
        widget.store.adminUid,
        widget.product.id,
        widget.store.visibleWarehouseIds,
      );
      final ids = batches.map((b) => b.warehouseId).toSet().toList();
      final Map<String, String> addresses = {};
      for (final id in ids) {
        if (id.isNotEmpty) {
          final wh = await _service.getWarehouseById(widget.store.adminUid, id);
          if (wh != null && (wh.address ?? '').isNotEmpty) {
            addresses[id] = wh.address!;
          }
        }
      }
      if (mounted) {
        setState(() {
          _batches = batches;
          _warehouseAddress = addresses;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _addToCart() {
    if (_selectedSize == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Выберите размер'),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    context.read<CartProvider>().addItem(CartItemModel(
          productId: widget.product.id,
          productName: widget.product.name,
          batchId: _batchId,
          size: _selectedSize!,
          qty: 1,
          price: _price,
          adminUid: widget.store.adminUid,
          storeName: widget.store.storeName,
          imageUrl: widget.product.images.isNotEmpty
              ? widget.product.images.first
              : '',
          warehouseId: _warehouseId,
          warehouseAddress: _pickupAddress,
        ));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${widget.product.name} добавлен в корзину'),
      backgroundColor: cGreen,
      behavior: SnackBarBehavior.floating,
    ));
    Navigator.pop(context);
  }

  int get _totalAvail =>
      _available.values.fold(0, (s, v) => s + v);

  @override
  Widget build(BuildContext context) {
    final images = widget.product.images;
    final avail = _available;

    return Scaffold(
      backgroundColor: cBg,
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: cGreen))
          : Column(children: [
              // ── Hero image area ───────────────────────────────────────
              Container(
                color: const Color(0xFFE4F7EE),
                child: SafeArea(
                  bottom: false,
                  child: Column(children: [
                    // Back + favourite buttons
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                      child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _RoundBtn(
                              icon: Icons.chevron_left_rounded,
                              onTap: () => Navigator.pop(context),
                            ),
                            _RoundBtn(
                              icon: Icons.favorite_border_rounded,
                              iconColor: cRed,
                              onTap: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Избранное — скоро'),
                                    behavior: SnackBarBehavior.floating,
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              },
                            ),
                          ]),
                    ),
                    // Image / placeholder
                    SizedBox(
                      height: 220,
                      child: images.isNotEmpty
                          ? Stack(children: [
                              PageView.builder(
                                itemCount: images.length,
                                onPageChanged: (i) =>
                                    setState(() => _pageIndex = i),
                                itemBuilder: (_, i) => Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(14),
                                    child: Image.network(images[i],
                                        fit: BoxFit.contain,
                                        errorBuilder: (_, __, ___) =>
                                            _shoePlaceholder()),
                                  ),
                                ),
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
                    const SizedBox(height: 10),
                  ]),
                ),
              ),

              // ── Details ───────────────────────────────────────────────
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 100),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Name + stock pill
                      Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(widget.product.name,
                                        style: manrope(22, FontWeight.w800,
                                            color: cInk,
                                            letterSpacing: -0.4)),
                                    if (widget.product.type.isNotEmpty)
                                      Text(widget.product.type,
                                          style: manrope(13.5, FontWeight.w500,
                                              color: cInk3)),
                                  ]),
                            ),
                            if (_totalAvail > 0)
                              QPill(
                                '$_totalAvail в наличии',
                                tone: 'green',
                                icon: const Icon(Icons.check_rounded,
                                    size: 13, color: cGreenDeep),
                              ),
                          ]),
                      const SizedBox(height: 10),

                      // Price
                      if (_price > 0)
                        Text(money(_price),
                            style: manrope(28, FontWeight.w800, color: cInk)),

                      const SizedBox(height: 16),

                      // Sizes
                      if (avail.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: cRedTint,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(children: [
                            const Icon(Icons.remove_shopping_cart_outlined,
                                color: cRed, size: 20),
                            const SizedBox(width: 10),
                            Text('Нет в наличии',
                                style: manrope(14, FontWeight.w600,
                                    color: cRed)),
                          ]),
                        )
                      else ...[
                        QSecLabel('Размер'),
                        Wrap(
                          spacing: 9,
                          runSpacing: 9,
                          children: avail.entries.map((e) {
                            final available = e.value > 0;
                            final selected = _selectedSize == e.key;
                            return GestureDetector(
                              onTap: available
                                  ? () =>
                                      setState(() => _selectedSize = e.key)
                                  : null,
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                width: 56,
                                height: 50,
                                decoration: BoxDecoration(
                                  color: !available
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
                                      ? [
                                          BoxShadow(
                                              color: cGreenTint,
                                              blurRadius: 0,
                                              spreadRadius: 3)
                                        ]
                                      : null,
                                ),
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    Opacity(
                                      opacity: !available ? 0.45 : 1,
                                      child: Text(e.key,
                                          style: manrope(
                                              15.5, FontWeight.w800,
                                              color: cInk)),
                                    ),
                                    if (!available)
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
                          ? 'Купить · ${money(_price)}'
                          : 'В корзину',
                      onPressed: _addToCart,
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
