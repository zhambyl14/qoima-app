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

typedef _Nearest = ({StoreModel store, WarehouseModel warehouse, double meters});

/// Дүкендер тізімі — бүкіл Қазақстан бойынша, қала бойынша сүзгімен.
/// Клиент өз қаласындағы (немесе кез келген қаладағы) дүкендерді көріп,
/// әрқайсысының товарларын аша алады (StorePublicScreen).
///
/// Клиенттің «Мой адрес» (профиль → мекенжайлар) бөлімінде картадан
/// белгіленген нүктесі болса — қазір көрсетіліп тұрған (сүзілген) дүкендер
/// арасынан ЕҢ ЖАҚЫНын ұсынамыз. Мекенжай/нүкте әлі жоқ болса — қосудың
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

  /// Ағымдағы (қала бойынша сүзілген) тізімнен клиентке ең жақын дүкенді
  /// табады. Мекенжай нүктесі жоқ болса немесе ешбір дүкенде координата
  /// табылмаса — null.
  _Nearest? _findNearest(List<StoreModel> filtered) {
    final my = _myPoint;
    if (my == null) return null;
    _Nearest? best;
    for (final s in filtered) {
      final wh = _warehouseByAdmin[s.adminUid];
      if (wh == null || !wh.hasLocation) continue;
      final meters =
          Geolocator.distanceBetween(my.lat, my.lng, wh.lat!, wh.lng!);
      if (best == null || meters < best.meters) {
        best = (store: s, warehouse: wh, meters: meters);
      }
    }
    return best;
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
    final nearest = _findNearest(filtered);
    final showNudge = !_loading && _myPoint == null && !_nudgeDismissed;

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
                      itemCount: filtered.length + (nearest != null || showNudge ? 1 : 0),
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) {
                        final hasBanner = nearest != null || showNudge;
                        if (hasBanner && i == 0) {
                          return nearest != null
                              ? _NearestStoreCard(
                                  nearest: nearest,
                                  onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                          builder: (_) => StorePublicScreen(
                                              store: nearest.store))),
                                )
                              : _AddressNudgeCard(
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
                        final idx = hasBanner ? i - 1 : i;
                        return _StoreCard(store: filtered[idx]);
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

/// Клиентке ең жақын дүкен ұсынысы — тізімнің басында, «Мой адрес»
/// нүктесі белгіленген болса ғана шығады.
class _NearestStoreCard extends StatelessWidget {
  final _Nearest nearest;
  final VoidCallback onTap;
  const _NearestStoreCard({required this.nearest, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final store = nearest.store;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [cGreen, cGreenDeep],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(18),
          boxShadow: kShadowSm,
        ),
        child: Row(children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(13),
              image: store.logoUrl.isNotEmpty
                  ? DecorationImage(
                      image: NetworkImage(store.logoUrl), fit: BoxFit.cover)
                  : null,
            ),
            child: store.logoUrl.isEmpty
                ? const Icon(Icons.storefront_rounded, color: Colors.white, size: 22)
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.near_me_rounded, size: 13, color: Colors.white),
                const SizedBox(width: 4),
                Text(tr('Ближе всего от вас', 'Сізге ең жақыны'),
                    style: manrope(11.5, FontWeight.w700,
                        color: Colors.white.withValues(alpha: 0.9))),
              ]),
              const SizedBox(height: 2),
              Text(store.storeName,
                  style: manrope(15, FontWeight.w800, color: Colors.white),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              if (nearest.warehouse.address?.trim().isNotEmpty ?? false)
                Text(nearest.warehouse.address!.trim(),
                    style: manrope(11.5, FontWeight.w500,
                        color: Colors.white.withValues(alpha: 0.85)),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(_distanceLabel(nearest.meters),
                style: manrope(12, FontWeight.w800, color: Colors.white)),
          ),
        ]),
      ),
    );
  }
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
                  if (store.address.trim().isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(store.address.trim(),
                        style: manrope(11.5, FontWeight.w500, color: cInk3),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ],
                ]),
          ),
          const Icon(Icons.chevron_right_rounded, color: cInk3, size: 22),
        ]),
      ),
    );
  }
}
