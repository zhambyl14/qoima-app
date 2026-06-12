import 'package:flutter/material.dart';
import '../../data/models/product_model.dart';
import '../../data/models/store_model.dart';
import '../../data/services/client_service.dart';
import '../../theme/qoima_design.dart';
import 'client_product_detail.dart';

class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final service = ClientService();
    return Scaffold(
      backgroundColor: cBg,
      body: Column(children: [
        Container(
          decoration: const BoxDecoration(gradient: kGrad),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Row(children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Icon(Icons.chevron_left_rounded,
                      color: Colors.white, size: 28),
                ),
                const SizedBox(width: 10),
                Text('Избранное',
                    style: manrope(20, FontWeight.w800, color: Colors.white)),
              ]),
            ),
          ),
        ),
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: service.watchFavorites(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator(color: cGreen));
              }
              final items = snap.data ?? [];
              if (items.isEmpty) {
                return Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.favorite_border_rounded,
                        size: 60, color: cInk3.withValues(alpha: 0.35)),
                    const SizedBox(height: 14),
                    Text('Список желаний пуст',
                        style: manrope(16, FontWeight.w700, color: cInk2)),
                    const SizedBox(height: 6),
                    Text('Нажмите ♡ на товаре чтобы добавить',
                        style: manrope(13, FontWeight.w500, color: cInk3)),
                  ]),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) => _FavCard(
                    key: ValueKey(items[i]['id']),
                    item: items[i],
                    service: service),
              );
            },
          ),
        ),
      ]),
    );
  }
}

class _FavCard extends StatefulWidget {
  final Map<String, dynamic> item;
  final ClientService service;
  const _FavCard({super.key, required this.item, required this.service});

  @override
  State<_FavCard> createState() => _FavCardState();
}

class _FavCardState extends State<_FavCard> {
  ProductModel? _product;
  StoreModel? _store;
  bool _loading = true;
  bool _available = false;

  String get _adminUid => widget.item['adminUid'] as String? ?? '';
  String get _productId => widget.item['id'] as String? ?? '';

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  // Товардың әлі сатылымда (қолжетімді) екенін тексереміз: статус + бос batch.
  Future<void> _resolve() async {
    try {
      final product = await widget.service.getProductById(_adminUid, _productId);
      final store = product == null
          ? null
          : await widget.service.getStoreByAdminUid(_adminUid);
      var available = false;
      if (product != null &&
          store != null &&
          store.isPublished &&
          !store.isBlocked &&
          product.status == ProductModel.statusInStock) {
        final batches = await widget.service.getProductBatches(
            _adminUid, _productId, store.visibleWarehouseIds,
            onlyAvailable: true);
        available = batches.isNotEmpty;
      }
      if (!mounted) return;
      setState(() {
        _product = product;
        _store = store;
        _available = available;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _open() {
    if (!_available || _product == null || _store == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ClientProductDetail(product: _product!, store: _store!),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.item['productName'] as String? ?? '';
    final store = widget.item['storeName'] as String? ?? '';
    final price = (widget.item['price'] as num?)?.toDouble() ?? 0.0;
    final img = widget.item['imageUrl'] as String? ?? '';
    final dimmed = !_loading && !_available; // сатылымда емес → сұр, басылмайды

    return GestureDetector(
      onTap: dimmed || _loading ? null : _open,
      behavior: HitTestBehavior.opaque,
      child: Opacity(
        opacity: dimmed ? 0.55 : 1,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cLine),
            boxShadow: kShadowSm,
          ),
          child: Row(children: [
            Stack(children: [
              SizedBox(
                width: 72,
                height: 72,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: QShoeImage(
                    imageUrl: img.isNotEmpty ? img : null,
                    height: 72,
                    tone: _productId.hashCode % 5,
                  ),
                ),
              ),
              if (dimmed)
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: cInk.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
            ]),
            const SizedBox(width: 12),
            Expanded(
              child:
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name,
                    style: manrope(14, FontWeight.w700,
                        color: dimmed ? cInk3 : cInk),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(store, style: manrope(12, FontWeight.w500, color: cInk3)),
                const SizedBox(height: 4),
                if (dimmed)
                  Text('Нет в наличии',
                      style: manrope(13, FontWeight.w700, color: cInk3))
                else
                  Text(money(price),
                      style: manrope(15, FontWeight.w800, color: cGreen)),
              ]),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => widget.service.removeFavorite(_productId),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(Icons.favorite_rounded,
                    color: cRed.withValues(alpha: 0.8), size: 22),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
