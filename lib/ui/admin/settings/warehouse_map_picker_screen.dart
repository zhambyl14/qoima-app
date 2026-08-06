import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../data/models/warehouse_model.dart';
import '../../../data/services/firestore_service.dart';
import '../../../theme/qoima_design.dart';

import '../../../core/lang.dart';
import '../../../core/error_text.dart';

/// Алматы орталығы — қойманың координатасы әлі белгіленбегенде картаның
/// бастапқы центрі.
const _kDefaultCenter = LatLng(43.238293, 76.945465);

/// Админ қойма орнын картадан белгілейді (түртіп): таңдалған нүкте
/// warehouses.lat/lng-ге сақталады — клиенттің «Магазины» картасында
/// осы қойма (витринада көрінсе) белгі ретінде шығады.
/// OpenStreetMap + flutter_map — API кілтсіз, барлық платформада бірдей.
class WarehouseMapPickerScreen extends StatefulWidget {
  final WarehouseModel warehouse;
  const WarehouseMapPickerScreen({super.key, required this.warehouse});

  @override
  State<WarehouseMapPickerScreen> createState() =>
      _WarehouseMapPickerScreenState();
}

class _WarehouseMapPickerScreenState extends State<WarehouseMapPickerScreen> {
  final _service = FirestoreService();
  LatLng? _picked;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final wh = widget.warehouse;
    if (wh.hasLocation) _picked = LatLng(wh.lat!, wh.lng!);
  }

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
    final wh = widget.warehouse;
    return Scaffold(
      backgroundColor: cBg,
      body: Column(children: [
        QGradientHeader(
          title: tr('Место на карте', 'Картадағы орын'),
          subtitle: wh.name,
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
            FlutterMap(
              options: MapOptions(
                initialCenter: _picked ?? (wh.hasLocation
                    ? LatLng(wh.lat!, wh.lng!)
                    : _kDefaultCenter),
                initialZoom: wh.hasLocation ? 16 : 11,
                onTap: (_, point) => setState(() => _picked = point),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'kz.qoima.app',
                ),
                if (_picked != null)
                  MarkerLayer(markers: [
                    Marker(
                      point: _picked!,
                      width: 34,
                      height: 34,
                      child: const Icon(Icons.location_on_rounded,
                          color: cRed, size: 34),
                    ),
                  ]),
              ],
            ),
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
