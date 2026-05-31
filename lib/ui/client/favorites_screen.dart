import 'package:flutter/material.dart';
import '../../data/services/client_service.dart';
import '../../theme/qoima_design.dart';

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
                itemBuilder: (_, i) => _FavCard(item: items[i], service: service),
              );
            },
          ),
        ),
      ]),
    );
  }
}

class _FavCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final ClientService service;
  const _FavCard({required this.item, required this.service});

  @override
  Widget build(BuildContext context) {
    final name = item['productName'] as String? ?? '';
    final store = item['storeName'] as String? ?? '';
    final price = (item['price'] as num?)?.toDouble() ?? 0.0;
    final img = item['imageUrl'] as String? ?? '';
    final productId = item['id'] as String;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cLine),
        boxShadow: kShadowSm,
      ),
      child: Row(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: QShoeImage(
            imageUrl: img.isNotEmpty ? img : null,
            height: 64,
            tone: productId.hashCode % 5,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name,
                style: manrope(14, FontWeight.w700, color: cInk),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text(store, style: manrope(12, FontWeight.w500, color: cInk3)),
            const SizedBox(height: 4),
            Text(money(price), style: manrope(15, FontWeight.w800, color: cGreen)),
          ]),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () => service.removeFavorite(productId),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(Icons.favorite_rounded, color: cRed.withValues(alpha: 0.8), size: 22),
          ),
        ),
      ]),
    );
  }
}
