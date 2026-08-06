import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:yandex_maps_mapkit_lite/mapkit.dart' hide Icon, Uri;
import 'package:yandex_maps_mapkit_lite/yandex_map.dart';
import '../../../data/models/warehouse_model.dart';
import '../../../data/services/firestore_service.dart';
import '../../../theme/qoima_design.dart';

import '../../../core/lang.dart';
import '../../../core/error_text.dart';

/// Алматы орталығы — қойманың координатасы әлі белгіленбегенде картаның
/// бастапқы центрі.
const _kDefaultCenter = Point(latitude: 43.238293, longitude: 76.945465);

/// Админ қойма орнын картадан белгілейді (түртіп): таңдалған нүкте
/// warehouses.lat/lng-ге сақталады — клиенттің «Магазины» картасында
/// осы қойма (витринада көрінсе) белгі ретінде шығады.
class WarehouseMapPickerScreen extends StatefulWidget {
  final WarehouseModel warehouse;
  const WarehouseMapPickerScreen({super.key, required this.warehouse});

  @override
  State<WarehouseMapPickerScreen> createState() =>
      _WarehouseMapPickerScreenState();
}

class _WarehouseMapPickerScreenState extends State<WarehouseMapPickerScreen>
    implements MapInputListener {
  final _service = FirestoreService();
  MapWindow? _mapWindow;
  PlacemarkMapObject? _pin;
  Point? _picked;
  bool _saving = false;

  @override
  void dispose() {
    _mapWindow?.map.removeInputListener(this);
    super.dispose();
  }

  void _onMapCreated(MapWindow mapWindow) {
    _mapWindow = mapWindow;
    final wh = widget.warehouse;
    final start = wh.hasLocation
        ? Point(latitude: wh.lat!, longitude: wh.lng!)
        : _kDefaultCenter;
    mapWindow.map.move(
      CameraPosition(start, zoom: wh.hasLocation ? 16 : 11, azimuth: 0, tilt: 0),
    );
    mapWindow.map.addInputListener(this);
    if (wh.hasLocation) {
      _placePin(start);
    }
  }

  void _placePin(Point point) {
    _pin?.geometry = point;
    _pin ??= _mapWindow!.map.mapObjects.addPlacemarkWithPoint(point);
    setState(() => _picked = point);
  }

  @override
  void onMapTap(Map map, Point point) => _placePin(point);

  @override
  void onMapLongTap(Map map, Point point) => _placePin(point);

  Future<void> _save() async {
    final p = _picked;
    if (p == null || _saving) return;
    setState(() => _saving = true);
    try {
      await _service.updateWarehouseLocation(
        warehouseId: widget.warehouse.id,
        lat: p.latitude,
        lng: p.longitude,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(friendlyError(e)),
          backgroundColor: cRed,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  Future<void> _openInYandexMaps() async {
    final p = _picked;
    if (p == null) return;
    final uri = Uri.parse(
        'https://yandex.ru/maps/?pt=${p.longitude},${p.latitude}&z=17&l=map');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cBg,
      body: Column(children: [
        QGradientHeader(
          title: tr('Место на карте', 'Картадағы орын'),
          subtitle: widget.warehouse.name,
          showBack: true,
          action: TextButton(
            onPressed: (_picked != null && !_saving) ? _save : null,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : Text(tr('Сохранить', 'Сақтау'),
                    style: manrope(14.5, FontWeight.w700, color: Colors.white)),
          ),
        ),
        Expanded(
          child: Stack(children: [
            YandexMap(onMapCreated: _onMapCreated),
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: cSurface,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: kShadowSm,
                ),
                child: Row(children: [
                  const Icon(Icons.touch_app_outlined, color: cGreen, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                        tr('Нажмите на карту, чтобы указать точное место склада',
                            'Қойманың дәл орнын белгілеу үшін картаны түртіңіз'),
                        style: manrope(12.5, FontWeight.w500, color: cInk2)),
                  ),
                  if (_picked != null)
                    GestureDetector(
                      onTap: _openInYandexMaps,
                      child: const Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: Icon(Icons.open_in_new_rounded,
                            color: cGreen, size: 18),
                      ),
                    ),
                ]),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}
