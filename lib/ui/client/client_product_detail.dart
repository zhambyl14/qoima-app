import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/models/product_model.dart';
import '../../data/models/store_model.dart';
import '../../data/models/batch_model.dart';
import '../../data/models/cart_item_model.dart';
import '../../data/services/client_service.dart';
import '../../theme/app_theme.dart';
import 'client_shell.dart';

class ClientProductDetail extends StatefulWidget {
  final ProductModel product;
  final StoreModel   store;
  const ClientProductDetail({super.key, required this.product, required this.store});

  @override
  State<ClientProductDetail> createState() => _ClientProductDetailState();
}

class _ClientProductDetailState extends State<ClientProductDetail> {
  final _service = ClientService();

  List<BatchModel>           _batches          = [];
  Map<String, String>        _warehouseAddress = {}; // warehouseId → address
  bool                       _loading          = true;
  String?                    _selectedSize;
  int                        _pageIndex        = 0;

  // Aggregated: size → total *available* (unreserved) qty across batches
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

  // Find batch with available (unreserved) stock for the selected size
  BatchModel? get _batchForSize {
    for (final b in _batches) {
      if (b.availableForSize(_selectedSize ?? '') > 0) return b;
    }
    return null;
  }

  String get _batchId      => _batchForSize?.id          ?? '';
  String get _warehouseId  => _batchForSize?.warehouseId ?? '';
  String get _pickupAddress =>
      _batchForSize != null ? (_warehouseAddress[_batchForSize!.warehouseId] ?? '') : '';

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
      // Load warehouse addresses for all unique warehouse IDs in these batches
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
          _batches          = batches;
          _warehouseAddress = addresses;
          _loading          = false;
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
      productId:        widget.product.id,
      productName:      widget.product.name,
      batchId:          _batchId,
      size:             _selectedSize!,
      qty:              1,
      price:            _price,
      adminUid:         widget.store.adminUid,
      storeName:        widget.store.storeName,
      imageUrl:         widget.product.images.isNotEmpty ? widget.product.images.first : '',
      warehouseId:      _warehouseId,
      warehouseAddress: _pickupAddress,
    ));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${widget.product.name} добавлен в корзину'),
      backgroundColor: AppTheme.success,
      behavior: SnackBarBehavior.floating,
    ));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final images = widget.product.images;
    final avail  = _available;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(widget.product.name),
        backgroundColor: AppTheme.primary,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Images
                    if (images.isNotEmpty)
                      SizedBox(
                        height: 300,
                        child: Stack(children: [
                          PageView.builder(
                            itemCount: images.length,
                            onPageChanged: (i) => setState(() => _pageIndex = i),
                            itemBuilder: (_, i) => Image.network(
                              images[i], fit: BoxFit.cover, width: double.infinity,
                              errorBuilder: (_, __, ___) => Container(
                                color: AppTheme.primary.withValues(alpha: 0.06),
                                child: const Center(child: Icon(
                                    Icons.image_outlined,
                                    color: AppTheme.textHint, size: 60)),
                              ),
                            ),
                          ),
                          if (images.length > 1)
                            Positioned(
                              bottom: 12, left: 0, right: 0,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: List.generate(images.length, (i) =>
                                  AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    width: i == _pageIndex ? 20 : 6,
                                    height: 6,
                                    margin: const EdgeInsets.symmetric(horizontal: 2),
                                    decoration: BoxDecoration(
                                      color: i == _pageIndex
                                          ? AppTheme.primary
                                          : Colors.white.withValues(alpha: 0.6),
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                  )),
                              ),
                            ),
                        ]),
                      )
                    else
                      Container(
                        height: 200,
                        color: AppTheme.primary.withValues(alpha: 0.06),
                        child: const Center(child: Icon(
                            Icons.image_outlined,
                            color: AppTheme.textHint, size: 60)),
                      ),

                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Brand + name
                          Text(widget.product.brand,
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w600,
                                  color: AppTheme.primary)),
                          const SizedBox(height: 4),
                          Text(widget.product.name,
                              style: const TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.w800,
                                  color: AppTheme.textPrimary, letterSpacing: -0.3)),
                          const SizedBox(height: 8),

                          // Price
                          if (_price > 0)
                            Text(
                              '${_price.toStringAsFixed(0)} ₸',
                              style: const TextStyle(
                                  fontSize: 22, fontWeight: FontWeight.w800,
                                  color: AppTheme.primary),
                            ),
                          const SizedBox(height: 16),

                          // Details row
                          Wrap(spacing: 8, runSpacing: 8, children: [
                            _Chip(label: widget.product.type),
                            _Chip(label: widget.product.category),
                            _Chip(label: widget.product.color),
                            if (widget.product.material.isNotEmpty)
                              _Chip(label: widget.product.material),
                          ]),
                          const SizedBox(height: 20),

                          // Sizes
                          if (avail.isEmpty)
                            const Text('Нет в наличии',
                                style: TextStyle(color: AppTheme.textSecondary))
                          else ...[
                            const Text('Выберите размер',
                                style: TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.w700,
                                    color: AppTheme.textPrimary)),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8, runSpacing: 8,
                              children: avail.entries.map((e) {
                                final available = e.value > 0;
                                final selected  = _selectedSize == e.key;
                                return GestureDetector(
                                  onTap: available
                                      ? () => setState(() => _selectedSize = e.key)
                                      : null,
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 150),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: !available
                                          ? const Color(0xFFF3F4F6)
                                          : selected
                                              ? AppTheme.primary
                                              : Colors.white,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: !available
                                            ? AppTheme.border
                                            : selected
                                                ? AppTheme.primary
                                                : AppTheme.border,
                                        width: selected ? 2 : 1,
                                      ),
                                    ),
                                    child: Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        Text(e.key,
                                            style: TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w700,
                                                color: !available
                                                    ? AppTheme.textHint
                                                    : selected
                                                        ? Colors.white
                                                        : AppTheme.textPrimary)),
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
                          const SizedBox(height: 100),
                        ],
                      ),
                    ),
                  ],
                )),
              ],
            ),
      bottomNavigationBar: avail.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: SizedBox(
                  width: double.infinity, height: 52,
                  child: ElevatedButton.icon(
                    onPressed: _addToCart,
                    icon: const Icon(Icons.shopping_cart_outlined),
                    label: const Text('В корзину',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  const _Chip({required this.label});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: AppTheme.primary.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(label,
        style: const TextStyle(
            fontSize: 12, fontWeight: FontWeight.w500, color: AppTheme.primary)),
  );
}

class _StrikePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(
      Offset(0, size.height),
      Offset(size.width, 0),
      Paint()
        ..color = AppTheme.textHint.withValues(alpha: 0.5)
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
