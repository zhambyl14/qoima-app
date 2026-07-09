import 'package:flutter/material.dart';
import '../../data/models/product_model.dart';
import '../../data/repositories/store_moderation_repository.dart';
import '../../theme/qoima_design.dart';

import '../../core/lang.dart';

/// Superadmin (модератор) — дүкен иесінің барлық товарларын көреді.
/// Мақсаты: заңсыз/тыйым салынған тауар жоқ па екенін тексеру.
class OwnerProductsScreen extends StatelessWidget {
  final String ownerUid;
  final String ownerName;
  final String storeName;
  const OwnerProductsScreen({
    super.key,
    required this.ownerUid,
    required this.ownerName,
    this.storeName = '',
  });

  @override
  Widget build(BuildContext context) {
    final repo = StoreModerationRepository();
    return Scaffold(
      backgroundColor: cBg,
      body: StreamBuilder<List<ProductModel>>(
        stream: repo.watchOwnerProducts(ownerUid),
        builder: (context, snap) {
          final all = snap.data ?? [];
          final inStock =
              all.where((p) => p.status == ProductModel.statusInStock).length;

          return Column(children: [
            QGradientHeader(
              title: storeName.isNotEmpty ? storeName : ownerName,
              subtitle: tr('Товары · всего ${all.length} · в наличии $inStock',
                  'Товарлар · барлығы ${all.length} · қоймада $inStock'),
              compact: true,
              showBack: true,
            ),
            Expanded(
              child: snap.connectionState == ConnectionState.waiting
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: cGreen, strokeWidth: 2))
                  : all.isEmpty
                      ? _empty()
                      : GridView.builder(
                          padding: const EdgeInsets.fromLTRB(14, 16, 14, 28),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            childAspectRatio: 0.72,
                          ),
                          itemCount: all.length,
                          itemBuilder: (_, i) => _ProductCard(product: all[i]),
                        ),
            ),
          ]);
        },
      ),
    );
  }

  Widget _empty() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                  color: cGreenTint, shape: BoxShape.circle),
              child: const Icon(Icons.inventory_2_outlined,
                  color: cGreen, size: 34),
            ),
            const SizedBox(height: 14),
            Text(tr('Нет товаров', 'Товар жоқ'),
                style: manrope(16, FontWeight.w700, color: cInk)),
          ],
        ),
      );
}

class _ProductCard extends StatelessWidget {
  final ProductModel product;
  const _ProductCard({required this.product});

  @override
  Widget build(BuildContext context) {
    final sold = product.status == ProductModel.statusSold;
    final img = product.images.isNotEmpty ? product.images.first : '';
    final sub = [
      if (product.brand.isNotEmpty) product.brand,
      if (product.category.isNotEmpty) trValue(product.category),
    ].join(' · ');

    return GestureDetector(
      onTap: () => _showDetail(context),
      child: Container(
        decoration: BoxDecoration(
          color: cSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cLine),
          boxShadow: kShadowSm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
                child: Stack(fit: StackFit.expand, children: [
                  img.isEmpty
                      ? Container(
                          color: cGreenTint,
                          child: const Icon(Icons.image_outlined,
                              color: cGreen, size: 30))
                      : Image.network(img,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                              color: cGreenTint,
                              child: const Icon(Icons.broken_image_outlined,
                                  color: cGreen, size: 30))),
                  Positioned(
                    top: 8,
                    left: 8,
                    child: QPill(
                        sold ? tr('Продано', 'Сатылды') : tr('В наличии', 'Қоймада'),
                        tone: sold ? 'ink' : 'green'),
                  ),
                ]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 9, 10, 11),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(product.name.isNotEmpty ? product.name : tr('Без названия', 'Атаусыз'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: manrope(13.5, FontWeight.w700, color: cInk)),
                  if (sub.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: manrope(11.5, FontWeight.w500, color: cInk3)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDetail(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ProductDetailSheet(product: product),
    );
  }
}

class _ProductDetailSheet extends StatelessWidget {
  final ProductModel product;
  const _ProductDetailSheet({required this.product});

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    final rows = <(String, String)>[
      (tr('Название', 'Атауы'), product.name),
      (tr('Бренд', 'Бренд'), product.brand),
      (tr('Категория', 'Санат'), trValue(product.category)),
      (tr('Тип', 'Түрі'), trValue(product.type)),
      (tr('Материал', 'Материал'), product.material),
      (tr('Цвет', 'Түс'), trValue(product.color)),
      (tr('Артикул', 'Артикул'), product.articul),
      (tr('Страна', 'Ел'), product.country),
      (tr('Сезон', 'Маусым'), trValue(product.season)),
    ].where((r) => r.$2.trim().isNotEmpty).toList();

    return Container(
      constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85),
      padding: EdgeInsets.fromLTRB(18, 10, 18, 18 + bottom),
      decoration: const BoxDecoration(
        color: cSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                    color: cLine, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            if (product.images.isNotEmpty)
              SizedBox(
                height: 220,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: product.images.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (_, i) => ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.network(product.images[i],
                        width: 180,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                            width: 180,
                            color: cGreenTint,
                            child: const Icon(Icons.broken_image_outlined,
                                color: cGreen))),
                  ),
                ),
              ),
            const SizedBox(height: 16),
            ...rows.map((r) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 110,
                        child: Text(r.$1,
                            style: manrope(12.5, FontWeight.w600, color: cInk3)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(r.$2,
                            style:
                                manrope(13.5, FontWeight.w600, color: cInk)),
                      ),
                    ],
                  ),
                )),
            if (product.description.trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              QSecLabel(tr('Описание', 'Сипаттама')),
              const SizedBox(height: 6),
              Text(product.description,
                  style: manrope(13.5, FontWeight.w500, color: cInk2, height: 1.4)),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
