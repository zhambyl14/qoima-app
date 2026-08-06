import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../../core/kz_cities.dart';
import '../../theme/qoima_design.dart';

import '../../core/lang.dart';

/// Клиент өз мекенжайының нүктесін картадан белгілейді — OpenStreetMap +
/// flutter_map, API кілтсіз. Тек Қазақстан аумағымен шектеледі (қала
/// бойынша қатаң шектеу жоқ — клиент кез келген қалада өмір сүруі мүмкін),
/// бастапқы центр — профильдегі қала болса сол, әйтпесе ҚР ортасы.
///
/// Нәтиже: таңдалған [LatLng] `Navigator.pop`-пен қайтарылады (болмаса null).
class AddressMapPickerScreen extends StatefulWidget {
  final String? initialCity;
  final LatLng? initialPoint;
  const AddressMapPickerScreen({super.key, this.initialCity, this.initialPoint});

  @override
  State<AddressMapPickerScreen> createState() => _AddressMapPickerScreenState();
}

class _AddressMapPickerScreenState extends State<AddressMapPickerScreen> {
  final _mapController = MapController();
  LatLng? _picked;
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    _picked = widget.initialPoint;
  }

  LatLng get _initialCenter {
    if (_picked != null) return _picked!;
    final geo = cityGeoOf(widget.initialCity);
    if (geo != null) return LatLng(geo.lat, geo.lng);
    return const LatLng(48.0196, 66.9237); // ҚР ортасы
  }

  double get _initialZoom {
    if (_picked != null) return 16;
    return cityGeoOf(widget.initialCity) != null ? 12 : 4.5;
  }

  bool _isAllowed(LatLng p) =>
      p.latitude >= kzMinLat &&
      p.latitude <= kzMaxLat &&
      p.longitude >= kzMinLng &&
      p.longitude <= kzMaxLng;

  void _tryPick(LatLng point) {
    if (!_isAllowed(point)) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(tr('Точку можно поставить только на территории Казахстана',
              'Нүктені тек Қазақстан аумағында қоюға болады')),
          backgroundColor: cRed,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ));
      return;
    }
    setState(() => _picked = point);
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
            accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 10)),
      );
      if (!mounted) return;
      final me = LatLng(pos.latitude, pos.longitude);
      if (!_isAllowed(me)) return;
      setState(() => _picked = me);
      _mapController.move(me, 16);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _zoom(double delta) {
    final c = _mapController.camera;
    _mapController.move(c.center, (c.zoom + delta).clamp(3.0, 18.0));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cBg,
      body: Column(children: [
        QGradientHeader(
          title: tr('Точка на карте', 'Картадағы нүкте'),
          subtitle: tr('Отметьте, где вы находитесь', 'Тұрған жеріңізді белгілеңіз'),
          showBack: true,
          action: TextButton(
            onPressed: _picked != null
                ? () => Navigator.pop(context, _picked)
                : null,
            child: Text(tr('Готово', 'Дайын'),
                style: manrope(14.5, FontWeight.w700,
                    color: _picked != null
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.45))),
          ),
        ),
        Expanded(
          child: Stack(children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _initialCenter,
                initialZoom: _initialZoom,
                minZoom: 3.5,
                maxZoom: 18,
                cameraConstraint: CameraConstraint.containCenter(
                  bounds: LatLngBounds(
                    const LatLng(kzMinLat, kzMinLng),
                    const LatLng(kzMaxLat, kzMaxLng),
                  ),
                ),
                onTap: (_, point) => _tryPick(point),
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
                      width: 42,
                      height: 42,
                      alignment: Alignment.topCenter,
                      child: const _PickedPin(),
                    ),
                  ]),
              ],
            ),
            Positioned(
              right: 12,
              top: 12,
              child: Column(children: [
                _MapBtn(icon: Icons.add_rounded, onTap: () => _zoom(1)),
                const SizedBox(height: 8),
                _MapBtn(icon: Icons.remove_rounded, onTap: () => _zoom(-1)),
                const SizedBox(height: 8),
                _MapBtn(
                  icon: Icons.my_location_rounded,
                  loading: _locating,
                  onTap: _locateMe,
                ),
              ]),
            ),
            Positioned(
              left: 14,
              right: 14,
              bottom: 14,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: cSurface,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: kShadowMd,
                ),
                child: Row(children: [
                  Icon(
                      _picked != null
                          ? Icons.check_circle_rounded
                          : Icons.touch_app_outlined,
                      color: _picked != null ? cGreen : cInk2,
                      size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                        _picked != null
                            ? tr('Точка выбрана — нажмите «Готово»',
                                'Нүкте таңдалды — «Дайын» басыңыз')
                            : tr('Нажмите на карту или используйте «моё местоположение»',
                                'Картаны түртіңіз немесе «менің орным» батырмасын қолданыңыз'),
                        style: manrope(12.5, FontWeight.w600,
                            color: _picked != null ? cGreen : cInk2)),
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

class _PickedPin extends StatelessWidget {
  const _PickedPin();

  @override
  Widget build(BuildContext context) => const Stack(
        alignment: Alignment.topCenter,
        children: [
          Icon(Icons.location_on_rounded, color: cGreen, size: 42),
          Positioned(
            top: 8,
            child: Icon(Icons.circle, color: Colors.white, size: 12),
          ),
        ],
      );
}

class _MapBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool loading;
  const _MapBtn({required this.icon, required this.onTap, this.loading = false});

  @override
  Widget build(BuildContext context) => Material(
        color: cSurface,
        borderRadius: BorderRadius.circular(12),
        elevation: 2,
        child: InkWell(
          onTap: loading ? null : onTap,
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: 40,
            height: 40,
            child: loading
                ? const Center(
                    child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            color: cGreen, strokeWidth: 2)))
                : Icon(icon, size: 20, color: cInk2),
          ),
        ),
      );
}
