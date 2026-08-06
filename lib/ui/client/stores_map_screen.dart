import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart' as launcher;
import 'package:yandex_maps_mapkit_lite/mapkit.dart' hide Icon, Uri, Map;
import 'package:yandex_maps_mapkit_lite/yandex_map.dart';
import '../../data/models/store_model.dart';
import '../../data/models/warehouse_model.dart';
import '../../data/services/client_service.dart';
import '../../theme/qoima_design.dart';
import 'store_public_screen.dart';

import '../../core/lang.dart';

const _kDefaultCenter = Point(latitude: 48.0196, longitude: 66.9237); // ҚР ортасы

typedef _Pin = ({StoreModel store, WarehouseModel warehouse});

/// Клиентке жақын дүкендерді картадан көрсетеді: тек интернет-витринасы
/// қосулы (жарияланған дүкен + видимый қойма) белгілер шығады.
class StoresMapScreen extends StatefulWidget {
  final List<StoreModel> stores;
  const StoresMapScreen({super.key, required this.stores});

  @override
  State<StoresMapScreen> createState() => _StoresMapScreenState();
}

class _StoresMapScreenState extends State<StoresMapScreen>
    implements MapObjectTapListener {
  final _service = ClientService();
  MapWindow? _mapWindow;
  bool _loading = true;
  List<_Pin> _entries = [];
  final Map<String, _Pin> _byWarehouseId = {};
  final Map<PlacemarkMapObject, String> _placemarkToId = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final adminUids = widget.stores.map((s) => s.adminUid).toSet().toList();
      final whs = await _service.getMappableWarehouses(adminUids);
      final byOwner = {for (final s in widget.stores) s.adminUid: s};
      final entries = <_Pin>[];
      for (final e in whs) {
        final store = byOwner[e.ownerUid];
        if (store == null) continue;
        entries.add((store: store, warehouse: e.warehouse));
      }
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _loading = false;
      });
      _renderPins();
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _renderPins() {
    final map = _mapWindow?.map;
    if (map == null || _entries.isEmpty) return;
    map.mapObjects.clear();
    _byWarehouseId.clear();
    _placemarkToId.clear();
    for (final e in _entries) {
      final wh = e.warehouse;
      final placemark = map.mapObjects.addPlacemarkWithPoint(
        Point(latitude: wh.lat!, longitude: wh.lng!),
      );
      placemark.addTapListener(this);
      _byWarehouseId[wh.id] = e;
      _placemarkToId[placemark] = wh.id;
    }
    _fitCamera(_entries.map((e) => e.warehouse).toList());
  }

  void _fitCamera(List<WarehouseModel> whs) {
    final map = _mapWindow?.map;
    if (map == null) return;
    if (whs.length == 1) {
      map.move(CameraPosition(
          Point(latitude: whs.first.lat!, longitude: whs.first.lng!),
          zoom: 14, azimuth: 0, tilt: 0));
      return;
    }
    double minLat = whs.first.lat!, maxLat = whs.first.lat!;
    double minLng = whs.first.lng!, maxLng = whs.first.lng!;
    for (final w in whs) {
      minLat = minLat < w.lat! ? minLat : w.lat!;
      maxLat = maxLat > w.lat! ? maxLat : w.lat!;
      minLng = minLng < w.lng! ? minLng : w.lng!;
      maxLng = maxLng > w.lng! ? maxLng : w.lng!;
    }
    final geometry = Geometry.fromBoundingBox(
      BoundingBox(
        Point(latitude: minLat, longitude: minLng),
        Point(latitude: maxLat, longitude: maxLng),
      ),
    );
    final camera = map.cameraPositionForGeometry(geometry);
    map.move(CameraPosition(camera.target,
        zoom: camera.zoom - 0.4, azimuth: 0, tilt: 0));
  }

  void _onMapCreated(MapWindow mapWindow) {
    _mapWindow = mapWindow;
    mapWindow.map.move(
        const CameraPosition(_kDefaultCenter, zoom: 4.5, azimuth: 0, tilt: 0));
    if (!_loading) _renderPins();
  }

  @override
  bool onMapObjectTap(MapObject mapObject, Point point) {
    if (mapObject is! PlacemarkMapObject) return false;
    final id = _placemarkToId[mapObject];
    final entry = id == null ? null : _byWarehouseId[id];
    if (entry == null) return false;
    _showStoreSheet(entry.store, entry.warehouse);
    return true;
  }

  Future<void> _openInYandexMaps(WarehouseModel wh) async {
    final uri = Uri.parse(
        'https://yandex.ru/maps/?pt=${wh.lng},${wh.lat}&z=17&l=map');
    try {
      await launcher.launchUrl(uri, mode: launcher.LaunchMode.externalApplication);
    } catch (_) {}
  }

  void _showStoreSheet(StoreModel store, WarehouseModel wh) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            Row(children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: cGreenTint,
                  borderRadius: BorderRadius.circular(13),
                  image: store.logoUrl.isNotEmpty
                      ? DecorationImage(
                          image: NetworkImage(store.logoUrl), fit: BoxFit.cover)
                      : null,
                ),
                child: store.logoUrl.isEmpty
                    ? const Icon(Icons.storefront_rounded, color: cGreenDeep, size: 24)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(store.storeName,
                        style: manrope(15.5, FontWeight.w800, color: cInk),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(wh.name,
                        style: manrope(12.5, FontWeight.w600, color: cGreen),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    if ((wh.address ?? '').isNotEmpty)
                      Text(wh.address!,
                          style: manrope(12, FontWeight.w500, color: cInk3),
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: 18),
            Row(children: [
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: () => _openInYandexMaps(wh),
                    icon: const Icon(Icons.open_in_new_rounded, size: 17, color: cInk2),
                    label: Text(tr('Открыть в Картах', 'Картада ашу'),
                        style: manrope(13.5, FontWeight.w700, color: cInk2)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: cLine),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.push(context,
                          MaterialPageRoute(builder: (_) => StorePublicScreen(store: store)));
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: cGreen,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Text(tr('Смотреть товары', 'Тауарларды көру'),
                        style: manrope(13.5, FontWeight.w700, color: Colors.white)),
                  ),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cBg,
      body: Column(children: [
        QGradientHeader(
          title: tr('Магазины на карте', 'Дүкендер картада'),
          subtitle: _loading
              ? tr('Загрузка…', 'Жүктелуде…')
              : tr('${_entries.length} на карте', '${_entries.length} картада'),
          compact: true,
          showBack: true,
        ),
        Expanded(
          child: Stack(children: [
            YandexMap(onMapCreated: _onMapCreated),
            if (_loading)
              const Positioned.fill(
                child: ColoredBox(
                  color: Color(0x33000000),
                  child: Center(
                      child: CircularProgressIndicator(color: cGreen, strokeWidth: 2)),
                ),
              ),
            if (!_loading && _entries.isEmpty)
              Center(
                child: Container(
                  margin: const EdgeInsets.all(24),
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: cSurface,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: kShadowSm,
                  ),
                  child: Text(
                      tr('Для этих магазинов ещё не указано место на карте',
                          'Бұл дүкендер үшін картадағы орын әлі көрсетілмеген'),
                      textAlign: TextAlign.center,
                      style: manrope(13.5, FontWeight.w600, color: cInk2)),
                ),
              ),
          ]),
        ),
      ]),
    );
  }
}
