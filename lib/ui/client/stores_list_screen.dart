import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import '../../core/app_user.dart';
import '../../core/lang.dart';
import '../../data/models/store_model.dart';
import '../../data/models/warehouse_model.dart';
import '../../data/services/client_service.dart';
import '../../theme/qoima_design.dart';
import 'addresses_screen.dart';
import 'store_public_screen.dart';
import 'stores_map_screen.dart';
import '../shared/error_view.dart';

enum _SortMode { distance, rating, alpha }

/// Дүкендер тізімі — бүкіл Қазақстан бойынша, қала бойынша сүзгімен.
/// Клиент өз қаласындағы (немесе кез келген қаладағы) дүкендерді көріп,
/// әрқайсысының товарларын аша алады (StorePublicScreen).
///
/// Клиенттің «Мой адрес» (профиль → мекенжайлар) бөлімінде картадан
/// белгіленген нүктесі болса — тізім ЕҢ ЖАҚЫННАН бастап сұрыпталады, әр
/// карточкада нақты қашықтығы көрінеді (1 км, 1.2 км, ...). Рейтинг бойынша
/// сұрыптауға да ауыстыруға болады. Мекенжай әлі жоқ болса — қосудың
/// пайдасын түсіндіретін кішкентай карточка көрсетеміз.
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
  // Жүктеу қатесі (көбіне интернет жоқ) — бұрын тізім жай «бос» көрінетін.
  Object? _error;
  String? _city;

  // Клиенттің сақталған мекенжай нүктесі (бар болса) + сол дүкендердің
  // қойма координаттары — «ең жақын дүкен» ұсынысы үшін.
  ({double lat, double lng})? _myPoint;
  Map<String, WarehouseModel> _warehouseByAdmin = {};
  bool _nudgeDismissed = false;
  _SortMode? _manualSort;

  @override
  void initState() {
    super.initState();
    _city = widget.initialCity;
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait([
        _service.getPublishedStores(),
        _service.getHiddenStoreIds(),
        _service.watchAddresses().first,
      ]);
      if (!mounted) return;
      final all = results[0] as List<StoreModel>;
      final hidden = results[1] as Set<String>;
      final addresses = results[2] as List<Map<String, dynamic>>;
      final stores = all
          .where((s) =>
              !hidden.contains(s.adminUid) && s.visibleWarehouseIds.isNotEmpty)
          .toList()
        ..sort((a, b) =>
            a.storeName.toLowerCase().compareTo(b.storeName.toLowerCase()));

      // Ең соңғы қосылған (бірінші, watchAddresses desc сұрыпталған)
      // координатасы бар мекенжай — «ең жақын дүкен» есептеуі үшін.
      Map<String, dynamic>? withGeo;
      for (final a in addresses) {
        if (a['lat'] != null && a['lng'] != null) {
          withGeo = a;
          break;
        }
      }
      final myPoint = withGeo == null
          ? null
          : (lat: withGeo['lat'] as double, lng: withGeo['lng'] as double);

      Map<String, WarehouseModel> warehouseByAdmin = {};
      if (myPoint != null && stores.isNotEmpty) {
        final adminUids = stores.map((s) => s.adminUid).toSet().toList();
        final whs = await _service.getMappableWarehouses(adminUids);
        for (final e in whs) {
          // Бір дүкенде бірнеше көрінетін қойма болуы мүмкін — біріншісі
          // жеткілікті (карта экранындағыдай, дәл орталықтандыру емес,
          // жақындықты БАҒАЛАУ үшін ғана).
          warehouseByAdmin.putIfAbsent(e.ownerUid, () => e.warehouse);
        }
      }

      setState(() {
        // Онлайн-витрина қосулы (isPublished) болса да, барлық қоймасы
        // витринадан өшірулі («Склады витрины») дүкенде көрсетер тауар
        // жоқ — басты беттегі рекомендация тізімі сияқты осындай дүкенді
        // жасырамыз (әйтпесе бос дүкенге кіруге болатын сәйкессіздік болады).
        _stores = stores;
        _myPoint = myPoint;
        _warehouseByAdmin = warehouseByAdmin;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e;
        });
      }
    }
  }

  /// Дүкенге дейінгі қашықтық (метр) — мекенжай нүктесі немесе дүкеннің
  /// координатасы жоқ болса null.
  double? _distanceFor(StoreModel s) {
    final my = _myPoint;
    final wh = _warehouseByAdmin[s.adminUid];
    if (my == null || wh == null || !wh.hasLocation) return null;
    return Geolocator.distanceBetween(my.lat, my.lng, wh.lat!, wh.lng!);
  }

  _SortMode get _effectiveSort =>
      _manualSort ?? (_myPoint != null ? _SortMode.distance : _SortMode.alpha);

  /// [filtered] (қала бойынша сүзілген, әліпби бойынша сұрыпталған тізім)
  /// ағымдағы сұрыптау режиміне сай қайта реттеледі. Координатасы/рейтингі
  /// жоқ дүкендер тізімнің соңына түседі (жойылмайды).
  List<StoreModel> _applySort(List<StoreModel> filtered) {
    final sort = _effectiveSort;
    if (sort == _SortMode.alpha) return filtered;
    final list = [...filtered];
    if (sort == _SortMode.distance) {
      list.sort((a, b) {
        final da = _distanceFor(a), db = _distanceFor(b);
        if (da == null && db == null) return 0;
        if (da == null) return 1;
        if (db == null) return -1;
        return da.compareTo(db);
      });
    } else if (sort == _SortMode.rating) {
      list.sort((a, b) {
        if (a.ratingCount == 0 && b.ratingCount == 0) return 0;
        if (a.ratingCount == 0) return 1;
        if (b.ratingCount == 0) return -1;
        return b.ratingAvg.compareTo(a.ratingAvg);
      });
    }
    return list;
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
    final sorted = _applySort(filtered);
    final showNudge = !_loading && _myPoint == null && !_nudgeDismissed;
    final canSortByRating = _stores.any((s) => s.ratingCount > 0);
    final showSortRow = _myPoint != null || canSortByRating;

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
          action: filtered.isEmpty
              ? null
              : QHeaderBtn(Icons.map_outlined,
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => StoresMapScreen(
                              stores: filtered, city: _city)))),
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
            if (showSortRow) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 32,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    if (_myPoint != null)
                      _SortChip(
                        icon: Icons.near_me_rounded,
                        label: tr('Ближе всего', 'Ең жақын'),
                        selected: _effectiveSort == _SortMode.distance,
                        onTap: () =>
                            setState(() => _manualSort = _SortMode.distance),
                      ),
                    if (_myPoint != null) const SizedBox(width: 8),
                    if (canSortByRating)
                      _SortChip(
                        icon: Icons.star_rounded,
                        label: tr('По рейтингу', 'Рейтинг бойынша'),
                        selected: _effectiveSort == _SortMode.rating,
                        onTap: () =>
                            setState(() => _manualSort = _SortMode.rating),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
        Expanded(
          child: _loading
              ? const Center(
                  child:
                      CircularProgressIndicator(color: cGreen, strokeWidth: 2))
              : _error != null
                  ? AppErrorView(error: _error, onRetry: _load)
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
                      itemCount: sorted.length + (showNudge ? 1 : 0),
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) {
                        if (showNudge && i == 0) {
                          return _AddressNudgeCard(
                            onAdd: () async {
                              await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) => const AddressesScreen()));
                              _load();
                            },
                            onDismiss: () =>
                                setState(() => _nudgeDismissed = true),
                          );
                        }
                        final idx = showNudge ? i - 1 : i;
                        final store = sorted[idx];
                        return _StoreCard(
                          store: store,
                          distanceMeters: _distanceFor(store),
                          warehouseAddress:
                              _warehouseByAdmin[store.adminUid]?.address,
                        );
                      },
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

String _distanceLabel(double meters) => meters < 1000
    ? '${meters.round()} м'
    : '${(meters / 1000).toStringAsFixed(1)} км';

class _SortChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _SortChip(
      {required this.icon,
      required this.label,
      required this.selected,
      required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.white.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 13, color: selected ? cGreen : Colors.white),
            const SizedBox(width: 4),
            Text(label,
                style: manrope(11.5, FontWeight.w700,
                    color: selected ? cGreen : Colors.white.withValues(alpha: 0.92))),
          ]),
        ),
      );
}

/// Мекенжай нүктесі әлі жоқ болғанда — қосудың пайдасын түсіндіретін
/// кішкентай ұсыныс карточкасы (жабылады, талап етпейді).
class _AddressNudgeCard extends StatelessWidget {
  final VoidCallback onAdd;
  final VoidCallback onDismiss;
  const _AddressNudgeCard({required this.onAdd, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: cGreenTint,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cGreen.withValues(alpha: 0.25)),
      ),
      child: Row(children: [
        const Icon(Icons.near_me_outlined, color: cGreen, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('Добавьте адрес', 'Мекенжай қосыңыз'),
                style: manrope(13.5, FontWeight.w700, color: cGreenDeep)),
            const SizedBox(height: 2),
            Text(
                tr('Покажем, какой магазин ближе всего к вам',
                    'Сізге ең жақын дүкенді көрсетеміз'),
                style: manrope(11.5, FontWeight.w500, color: cGreen)),
          ]),
        ),
        TextButton(
          onPressed: onAdd,
          style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              backgroundColor: cGreen,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
          child: Text(tr('Добавить', 'Қосу'),
              style: manrope(12.5, FontWeight.w700, color: Colors.white)),
        ),
        GestureDetector(
          onTap: onDismiss,
          child: const Padding(
            padding: EdgeInsets.only(left: 6),
            child: Icon(Icons.close_rounded, size: 17, color: cGreen),
          ),
        ),
      ]),
    );
  }
}

class _StoreCard extends StatelessWidget {
  final StoreModel store;
  final double? distanceMeters;
  final String? warehouseAddress;
  const _StoreCard(
      {required this.store, this.distanceMeters, this.warehouseAddress});

  /// Қашықтық есептелген нақты қойма мекенжайы басым (дәл сол жерге дейін
  /// өлшенген) — жоқ болса дүкеннің жалпы мекенжайына түседі.
  String get _addressText {
    final wh = warehouseAddress?.trim() ?? '';
    if (wh.isNotEmpty) return wh;
    return store.address.trim();
  }

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
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
                  Row(children: [
                    Expanded(
                      child: Text(store.storeName,
                          style: manrope(14.5, FontWeight.w700, color: cInk),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                    if (store.ratingCount > 0) ...[
                      const SizedBox(width: 6),
                      const Icon(Icons.star_rounded, size: 14, color: Color(0xFFF5A623)),
                      const SizedBox(width: 1),
                      Text(store.ratingAvg.toStringAsFixed(1),
                          style: manrope(12, FontWeight.w700, color: cInk)),
                    ],
                  ]),
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
                    if (distanceMeters != null) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: cGreenTint,
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Text(_distanceLabel(distanceMeters!),
                            style: manrope(10.5, FontWeight.w700, color: cGreenDeep)),
                      ),
                    ],
                  ]),
                  if (_addressText.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(_addressText,
                        style: manrope(11.5, FontWeight.w500, color: cInk3),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ],
                ]),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right_rounded, color: cInk3, size: 22),
        ]),
      ),
    );
  }
}
