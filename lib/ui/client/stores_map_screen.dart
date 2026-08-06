import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart' as launcher;
import '../../data/models/store_model.dart';
import '../../data/models/warehouse_model.dart';
import '../../data/services/client_service.dart';
import '../../theme/qoima_design.dart';
import 'store_public_screen.dart';

import '../../core/lang.dart';

const _kDefaultCenter = LatLng(48.0196, 66.9237); // ҚР ортасы
const _kCardWidth = 268.0;

typedef _Pin = ({StoreModel store, WarehouseModel warehouse});

/// Клиентке жақын дүкендерді картадан көрсетеді (OpenStreetMap + flutter_map,
/// API кілтсіз, барлық платформада — mobile/web — бірдей жұмыс істейді):
/// тек интернет-витринасы қосулы (жарияланған дүкен + видимый қойма) белгілер
/// шығады. Белгіні түрткенде пиннің үстінде қалқымалы карточка ашылады
/// (2GIS/Yandex стилі), геолокация — толық опционал (рұқсат берілмесе де
/// карта ашыла береді, тек «менің орным» батырмасы жұмыс істемейді).
class StoresMapScreen extends StatefulWidget {
  final List<StoreModel> stores;
  const StoresMapScreen({super.key, required this.stores});

  @override
  State<StoresMapScreen> createState() => _StoresMapScreenState();
}

class _StoresMapScreenState extends State<StoresMapScreen> {
  final _service = ClientService();
  final _mapController = MapController();
  StreamSubscription<MapEvent>? _mapEventSub;
  bool _loading = true;
  List<_Pin> _entries = [];
  _Pin? _selected;
  Offset? _selectedOffset;
  LatLng? _myPos;
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    _mapEventSub =
        _mapController.mapEventStream.listen((_) => _updateSelectedOffset());
    _load();
  }

  @override
  void dispose() {
    _mapEventSub?.cancel();
    super.dispose();
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
      if (entries.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _fitBounds());
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _fitBounds() {
    if (_entries.length == 1) {
      final wh = _entries.first.warehouse;
      _mapController.move(LatLng(wh.lat!, wh.lng!), 14);
      return;
    }
    final bounds = LatLngBounds.fromPoints(
      _entries.map((e) => LatLng(e.warehouse.lat!, e.warehouse.lng!)).toList(),
    );
    _mapController.fitCamera(
      CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(48)),
    );
  }

  void _selectPin(_Pin pin) {
    setState(() => _selected = pin);
    _updateSelectedOffset();
  }

  void _updateSelectedOffset() {
    final pin = _selected;
    if (pin == null || !mounted) return;
    setState(() {
      _selectedOffset = _mapController.camera.latLngToScreenOffset(
          LatLng(pin.warehouse.lat!, pin.warehouse.lng!));
    });
  }

  Future<void> _locateMe() async {
    if (_locating) return;
    setState(() => _locating = true);
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(tr('Доступ к геолокации не разрешён',
                'Геолокацияға рұқсат берілмеді')),
            behavior: SnackBarBehavior.floating,
          ));
        }
        return;
      }
      if (!await Geolocator.isLocationServiceEnabled()) return;
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 8)),
      );
      if (!mounted) return;
      final me = LatLng(pos.latitude, pos.longitude);
      setState(() => _myPos = me);
      _mapController.move(me, 14);
    } catch (_) {
      // Геолокация міндетті емес — сәтсіз болса да карта қалыпты жұмыс істейді.
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  String? _distanceLabel(WarehouseModel wh) {
    final my = _myPos;
    if (my == null) return null;
    final meters =
        Geolocator.distanceBetween(my.latitude, my.longitude, wh.lat!, wh.lng!);
    return meters < 1000
        ? tr('${meters.round()} м', '${meters.round()} м')
        : '${(meters / 1000).toStringAsFixed(1)} км';
  }

  Future<void> _openInYandexMaps(WarehouseModel wh) async {
    final uri = Uri.parse(
        'https://yandex.ru/maps/?pt=${wh.lng},${wh.lat}&z=17&l=map');
    try {
      await launcher.launchUrl(uri, mode: launcher.LaunchMode.externalApplication);
    } catch (_) {}
  }

  void _deselect() => setState(() {
        _selected = null;
        _selectedOffset = null;
      });

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
          child: Stack(clipBehavior: Clip.none, children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _kDefaultCenter,
                initialZoom: 4.5,
                onTap: (_, __) => _deselect(),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'kz.qoima.app',
                ),
                MarkerLayer(markers: [
                  ..._entries.map((e) => Marker(
                        point: LatLng(e.warehouse.lat!, e.warehouse.lng!),
                        width: 38,
                        height: 38,
                        child: GestureDetector(
                          onTap: () => _selectPin(e),
                          child: _PinIcon(
                              selected:
                                  _selected?.warehouse.id == e.warehouse.id),
                        ),
                      )),
                  if (_myPos != null)
                    Marker(
                      point: _myPos!,
                      width: 20,
                      height: 20,
                      child: const _MyLocationDot(),
                    ),
                ]),
              ],
            ),
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
            if (_selected != null && _selectedOffset != null)
              LayoutBuilder(builder: (context, constraints) {
                return _StoreFloatingCard(
                  pin: _selected!,
                  anchor: _selectedOffset!,
                  maxWidth: constraints.maxWidth,
                  distanceLabel: _distanceLabel(_selected!.warehouse),
                  onOpenMaps: () => _openInYandexMaps(_selected!.warehouse),
                  onViewStore: () {
                    final store = _selected!.store;
                    _deselect();
                    Navigator.push(context,
                        MaterialPageRoute(builder: (_) => StorePublicScreen(store: store)));
                  },
                  onClose: _deselect,
                );
              }),
            Positioned(
              right: 14,
              bottom: 14,
              child: FloatingActionButton.small(
                heroTag: 'stores-map-locate',
                onPressed: _locateMe,
                backgroundColor: cSurface,
                foregroundColor: cGreen,
                elevation: 2,
                child: _locating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(color: cGreen, strokeWidth: 2))
                    : const Icon(Icons.my_location_rounded, size: 20),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _PinIcon extends StatelessWidget {
  final bool selected;
  const _PinIcon({required this.selected});

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: selected ? 1.15 : 1,
      duration: const Duration(milliseconds: 150),
      child: Container(
        decoration: BoxDecoration(
          color: selected ? cGreenDeep : cGreen,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2.5),
          boxShadow: kShadowSm,
        ),
        child: const Icon(Icons.storefront_rounded, color: Colors.white, size: 18),
      ),
    );
  }
}

class _MyLocationDot extends StatelessWidget {
  const _MyLocationDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF2C7BE5),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: kShadowSm,
      ),
    );
  }
}

/// Пиннің үстінде қалқымалы карточка (2GIS/Yandex стилі) — anchor нүктесіне
/// (marker-дің экрандағы координатасы) бекітіліп, картаны жылжытқан/
/// масштабтаған сайын қайта орналасады (StoresMapScreen._updateSelectedOffset).
class _StoreFloatingCard extends StatelessWidget {
  final _Pin pin;
  final Offset anchor;
  final double maxWidth;
  final String? distanceLabel;
  final VoidCallback onOpenMaps;
  final VoidCallback onViewStore;
  final VoidCallback onClose;

  const _StoreFloatingCard({
    required this.pin,
    required this.anchor,
    required this.maxWidth,
    required this.distanceLabel,
    required this.onOpenMaps,
    required this.onViewStore,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final store = pin.store;
    final wh = pin.warehouse;
    const cardHeight = 176.0;
    const arrowGap = 12.0;
    var left = anchor.dx - _kCardWidth / 2;
    left = left.clamp(8.0, (maxWidth - _kCardWidth - 8).clamp(8.0, double.infinity));
    var top = anchor.dy - cardHeight - arrowGap;
    final showBelow = top < 8;
    if (showBelow) top = anchor.dy + arrowGap + 20;

    return Positioned(
      left: left,
      top: top,
      width: _kCardWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (showBelow) _CardArrow(pointUp: true),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cSurface,
              borderRadius: BorderRadius.circular(16),
              boxShadow: kShadowMd,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: cGreenTint,
                      borderRadius: BorderRadius.circular(12),
                      image: store.logoUrl.isNotEmpty
                          ? DecorationImage(
                              image: NetworkImage(store.logoUrl), fit: BoxFit.cover)
                          : null,
                    ),
                    child: store.logoUrl.isEmpty
                        ? const Icon(Icons.storefront_rounded, color: cGreenDeep, size: 22)
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(store.storeName,
                            style: manrope(14.5, FontWeight.w800, color: cInk),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        if (store.category.isNotEmpty)
                          Text(trValue(store.category),
                              style: manrope(11.5, FontWeight.w600, color: cInk3),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: onClose,
                    child: const Padding(
                      padding: EdgeInsets.only(left: 4),
                      child: Icon(Icons.close_rounded, size: 18, color: cInk3),
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  if (store.ratingCount > 0) ...[
                    const Icon(Icons.star_rounded, size: 15, color: Color(0xFFF5A623)),
                    const SizedBox(width: 2),
                    Text(store.ratingAvg.toStringAsFixed(1),
                        style: manrope(12, FontWeight.w700, color: cInk)),
                    Text(' (${store.ratingCount})',
                        style: manrope(11.5, FontWeight.w500, color: cInk3)),
                    if (distanceLabel != null) const SizedBox(width: 8),
                  ],
                  if (distanceLabel != null) ...[
                    const Icon(Icons.directions_walk_rounded, size: 14, color: cInk3),
                    const SizedBox(width: 2),
                    Text(distanceLabel!,
                        style: manrope(11.5, FontWeight.w600, color: cInk3)),
                  ],
                ]),
                if ((wh.address ?? '').isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(wh.address!,
                      style: manrope(11.5, FontWeight.w500, color: cInk3),
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: SizedBox(
                      height: 38,
                      child: ElevatedButton(
                        onPressed: onViewStore,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: cGreen,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(11)),
                        ),
                        child: Text(tr('Смотреть товары', 'Тауарларды көру'),
                            style: manrope(12.5, FontWeight.w700, color: Colors.white)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 38,
                    height: 38,
                    child: OutlinedButton(
                      onPressed: onOpenMaps,
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.zero,
                        side: const BorderSide(color: cLine),
                        shape:
                            RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
                      ),
                      child: const Icon(Icons.open_in_new_rounded, size: 16, color: cInk2),
                    ),
                  ),
                ]),
              ],
            ),
          ),
          if (!showBelow) _CardArrow(pointUp: false),
        ],
      ),
    );
  }
}

class _CardArrow extends StatelessWidget {
  final bool pointUp;
  const _CardArrow({required this.pointUp});

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: pointUp ? 3.14159 : 0,
      child: CustomPaint(size: const Size(16, 8), painter: _ArrowPainter()),
    );
  }
}

class _ArrowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = cSurface;
    final path = ui.Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
