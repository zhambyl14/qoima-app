import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_user.dart';
import '../../core/lang.dart';
import '../../data/models/store_model.dart';
import '../../data/services/client_service.dart';
import '../../theme/qoima_design.dart';
import 'store_public_screen.dart';

/// Дүкендер тізімі — бүкіл Қазақстан бойынша, қала бойынша сүзгімен.
/// Клиент өз қаласындағы (немесе кез келген қаладағы) дүкендерді көріп,
/// әрқайсысының товарларын аша алады (StorePublicScreen).
class StoresListScreen extends StatefulWidget {
  /// Бастапқы қала сүзгісі (null — барлық қалалар).
  final String? initialCity;
  const StoresListScreen({super.key, this.initialCity});

  @override
  State<StoresListScreen> createState() => _StoresListScreenState();
}

class _StoresListScreenState extends State<StoresListScreen> {
  final _service = ClientService();
  List<StoreModel> _stores = [];
  bool _loading = true;
  String? _city;

  @override
  void initState() {
    super.initState();
    _city = widget.initialCity;
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        _service.getPublishedStores(),
        _service.getHiddenStoreIds(),
      ]);
      if (!mounted) return;
      final all = results[0] as List<StoreModel>;
      final hidden = results[1] as Set<String>;
      setState(() {
        _stores = all.where((s) => !hidden.contains(s.adminUid)).toList()
          ..sort((a, b) => a.storeName.toLowerCase().compareTo(
              b.storeName.toLowerCase()));
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Дүкені бар қалалар (санымен), клиент қаласы бірінші.
  List<MapEntry<String, int>> get _cityCounts {
    final counts = <String, int>{};
    for (final s in _stores) {
      final c = s.city.trim();
      if (c.isEmpty) continue;
      counts[c] = (counts[c] ?? 0) + 1;
    }
    final myCity = context.read<AppUser>().city.trim();
    final entries = counts.entries.toList()
      ..sort((a, b) {
        if (a.key == myCity) return -1;
        if (b.key == myCity) return 1;
        return b.value.compareTo(a.value);
      });
    return entries;
  }

  @override
  Widget build(BuildContext context) {
    final myCity = context.watch<AppUser>().city.trim();
    final filtered = _city == null
        ? _stores
        : _stores.where((s) => s.city.trim() == _city).toList();

    return Scaffold(
      backgroundColor: cBg,
      body: Column(children: [
        QGradientHeader(
          title: tr('Магазины', 'Дүкендер'),
          subtitle: _city == null
              ? tr('Все города Казахстана', 'Қазақстанның барлық қаласы')
              : _city!,
          compact: true,
          showBack: true,
          bottom: [
            const SizedBox(height: 12),
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _CityChip(
                    label: tr('Все города', 'Барлық қалалар'),
                    selected: _city == null,
                    onTap: () => setState(() => _city = null),
                  ),
                  ..._cityCounts.map((e) => _CityChip(
                        label: e.key == myCity
                            ? tr('📍 ${e.key} · ${e.value}', '📍 ${e.key} · ${e.value}')
                            : '${e.key} · ${e.value}',
                        selected: _city == e.key,
                        onTap: () => setState(() => _city = e.key),
                      )),
                ],
              ),
            ),
          ],
        ),
        Expanded(
          child: _loading
              ? const Center(
                  child:
                      CircularProgressIndicator(color: cGreen, strokeWidth: 2))
              : filtered.isEmpty
                  ? Center(
                      child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                          const Icon(Icons.storefront_outlined,
                              size: 56, color: cInk3),
                          const SizedBox(height: 12),
                          Text(
                              _city == null
                                  ? tr('Магазинов пока нет', 'Дүкендер әзірге жоқ')
                                  : tr('В городе $_city пока нет магазинов',
                                      '$_city қаласында әзірге дүкен жоқ'),
                              style: manrope(15, FontWeight.w500,
                                  color: cInk2)),
                        ]))
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) =>
                          _StoreCard(store: filtered[i]),
                    ),
        ),
      ]),
    );
  }
}

class _CityChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _CityChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? Colors.white
                : Colors.white.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Text(label,
              style: manrope(12.5, FontWeight.w700,
                  color: selected
                      ? cGreen
                      : Colors.white.withValues(alpha: 0.92))),
        ),
      );
}

class _StoreCard extends StatelessWidget {
  final StoreModel store;
  const _StoreCard({required this.store});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => StorePublicScreen(store: store)),
      ),
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: cSurface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: cLine),
          boxShadow: kShadowSm,
        ),
        child: Row(children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: cGreenTint,
              borderRadius: BorderRadius.circular(14),
              image: store.logoUrl.isNotEmpty
                  ? DecorationImage(
                      image: NetworkImage(store.logoUrl), fit: BoxFit.cover)
                  : null,
            ),
            child: store.logoUrl.isEmpty
                ? const Icon(Icons.storefront_rounded,
                    color: cGreenDeep, size: 26)
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(store.storeName,
                      style: manrope(14.5, FontWeight.w700, color: cInk),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 3),
                  Row(children: [
                    const Icon(Icons.location_on_outlined,
                        size: 13, color: cInk3),
                    const SizedBox(width: 3),
                    Flexible(
                      child: Text(
                        [
                          if (store.city.trim().isNotEmpty) store.city.trim(),
                          if (store.category.trim().isNotEmpty)
                            trValue(store.category.trim()),
                        ].join(' · '),
                        style: manrope(12, FontWeight.w500, color: cInk3),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ]),
                ]),
          ),
          const Icon(Icons.chevron_right_rounded, color: cInk3, size: 22),
        ]),
      ),
    );
  }
}
