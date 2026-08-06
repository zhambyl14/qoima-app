import 'package:flutter/material.dart';
import '../../data/models/batch_model.dart';
import '../../data/models/product_model.dart';
import '../../data/models/store_model.dart';
import '../../data/services/client_service.dart';
import '../../theme/qoima_design.dart';

import '../../core/lang.dart';

typedef _Entry = ({ProductModel product, List<BatchModel> batches});

/// Тауар карточкасының астындағы «Ұқсас тауарлар» блогы — сол дүкендегі
/// ұқсас (бірдей категория/бренд/тип) тауарлар алдымен, содан кейін
/// дүкеннің қалған тауарлары. Клиентті дүкен ішінде ұстап, орташа чекті
/// көтеруге арналған.
///
/// Гость үшін де жұмыс істейді (жүрекше/себет жоқ — тек қарау + өту).
class RelatedProductsSection extends StatefulWidget {
  final ProductModel product;
  final StoreModel store;

  /// Ағымдағы тауардың түс нұсқалары — ұсыныстарда қайталанбауы үшін.
  final Set<String> excludeIds;

  /// Ұсынылған тауарды басқанда шақырылады (ата-экран сол тауардың
  /// карточкасына ауысады — жаңа экран ашпай, стек өспеуі үшін).
  final void Function(ProductModel product) onTap;

  const RelatedProductsSection({
    super.key,
    required this.product,
    required this.store,
    required this.onTap,
    this.excludeIds = const {},
  });

  @override
  State<RelatedProductsSection> createState() => _RelatedProductsSectionState();
}

class _RelatedProductsSectionState extends State<RelatedProductsSection> {
  final _service = ClientService();
  List<_Entry> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await _service.getRelatedProducts(
        adminUid: widget.store.adminUid,
        current: widget.product,
        visibleWarehouseIds: widget.store.visibleWarehouseIds,
        excludeIds: widget.excludeIds,
      );
      if (mounted) setState(() { _items = items; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
            child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(color: cGreen, strokeWidth: 2))),
      );
    }
    if (_items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 22),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Row(children: [
            Expanded(
              child: Text(tr('Похожие товары', 'Ұқсас тауарлар'),
                  style: manrope(16, FontWeight.w800, color: cInk)),
            ),
            Text(widget.store.storeName,
                style: manrope(11.5, FontWeight.w600, color: cInk3),
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 214,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 2),
            itemCount: _items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) => _RelatedCard(
              entry: _items[i],
              tone: i % 5,
              onTap: () => widget.onTap(_items[i].product),
            ),
          ),
        ),
      ],
    );
  }
}

class _RelatedCard extends StatelessWidget {
  final _Entry entry;
  final int tone;
  final VoidCallback onTap;
  const _RelatedCard(
      {required this.entry, required this.tone, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = entry.product;
    final batch = entry.batches.isNotEmpty ? entry.batches.first : null;
    final base = batch?.sellingPrice ?? 0;
    final price = batch != null ? effectivePrice(batch) : 0.0;
    final discounted = batch != null && hasActiveDiscount(batch);

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 142,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Stack(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: QShoeImage(
                imageUrl: p.images.isNotEmpty ? p.images.first : null,
                height: 142,
                tone: tone,
              ),
            ),
            if (discounted)
              Positioned(
                left: 7,
                top: 7,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: cRed,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text('-${discountBadgePercent(batch)}%',
                      style: manrope(10, FontWeight.w800, color: Colors.white)),
                ),
              ),
          ]),
          const SizedBox(height: 7),
          Text(p.name,
              style: manrope(12.5, FontWeight.w700, color: cInk),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          if (discounted)
            Row(children: [
              Text(money(price),
                  style: manrope(13, FontWeight.w800, color: cRed)),
              const SizedBox(width: 5),
              Flexible(
                child: Text(money(base),
                    style: manrope(11, FontWeight.w600, color: cInk3)
                        .copyWith(decoration: TextDecoration.lineThrough),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ])
          else
            Text(money(price),
                style: manrope(13, FontWeight.w800, color: cGreen)),
          if (p.ratingCount > 0) ...[
            const SizedBox(height: 2),
            Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.star_rounded, size: 12, color: Color(0xFFF5A623)),
              const SizedBox(width: 2),
              Text('${p.ratingAvg.toStringAsFixed(1)} (${p.ratingCount})',
                  style: manrope(10.5, FontWeight.w600, color: cInk3)),
            ]),
          ],
        ]),
      ),
    );
  }
}
