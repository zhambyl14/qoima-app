import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/kz_cities.dart';
import '../../../data/models/warehouse_model.dart';
import '../../../data/services/firestore_service.dart';
import '../../../theme/qoima_design.dart';

import '../../../core/lang.dart';
import '../../../core/error_text.dart';

/// Қала белгісіз болғанда (дүкенде city толтырылмаған) — Қазақстан ортасы.
const _kKzCenter = LatLng(48.0196, 66.9237);
const _kDistance = Distance();

/// Админ қойма орнын картадан белгілейді (түртіп): таңдалған нүкте
/// warehouses.lat/lng-ге сақталады — клиенттің «Дүкендер картада» экранында
/// осы қойма (витринада көрінсе) белгі ретінде шығады.
///
/// Карта дүкеннің ӨЗ ҚАЛАСЫНА бекітілген: камера сол қаланың айналасынан
/// шықпайды және рұқсат етілген шеңберден (kzCityGeo.radiusKm) тыс нүкте
/// қабылданбайды — админ басқа қалаға қойма қоя алмайды. Қала белгісіз
/// болса, бүкіл ҚР бойынша рұқсат етіледі (әйтпесе админ бұғатталып қалар
/// еді). OpenStreetMap + flutter_map — API кілтсіз, платформааралық.
class WarehouseMapPickerScreen extends StatefulWidget {
  final WarehouseModel warehouse;

  /// Дүкеннің қаласы (stores.city) — картаны шектеу үшін. Бос болса шектеу
  /// бүкіл Қазақстан бойынша қолданылады.
  final String? city;

  const WarehouseMapPickerScreen({
    super.key,
    required this.warehouse,
    this.city,
  });

  @override
  State<WarehouseMapPickerScreen> createState() =>
      _WarehouseMapPickerScreenState();
}

class _WarehouseMapPickerScreenState extends State<WarehouseMapPickerScreen> {
  final _service = FirestoreService();
  final _mapController = MapController();
  LatLng? _picked;
  bool _saving = false;
  bool _locating = false;

  CityGeo? get _geo => cityGeoOf(widget.city);
  bool get _cityKnown => _geo != null;

  /// Рұқсат етілген аймақтың центрі мен радиусы (метрмен).
  LatLng get _allowedCenter =>
      _cityKnown ? LatLng(_geo!.lat, _geo!.lng) : _kKzCenter;
  double get _allowedRadiusM => (_geo?.radiusKm ?? 0) * 1000;

  @override
  void initState() {
    super.initState();
    final wh = widget.warehouse;
    if (wh.hasLocation) _picked = LatLng(wh.lat!, wh.lng!);
  }

  /// Бастапқы центр: бар белгі (рұқсат аймағында болса) → қала → ҚР ортасы.
  LatLng get _initialCenter {
    final p = _picked;
    if (p != null && _isAllowed(p)) return p;
    return _allowedCenter;
  }

  double get _initialZoom {
    final p = _picked;
    if (p != null && _isAllowed(p)) return 16;
    return _cityKnown ? 12 : 4.5;
  }

  bool _isAllowed(LatLng p) {
    if (!_cityKnown) {
      // Қала белгісіз — тек ҚР шекарасымен шектейміз.
      return p.latitude >= kzMinLat &&
          p.latitude <= kzMaxLat &&
          p.longitude >= kzMinLng &&
          p.longitude <= kzMaxLng;
    }
    return _kDistance.as(LengthUnit.Meter, _allowedCenter, p) <=
        _allowedRadiusM;
  }

  /// Камераны қала маңында ұстайтын шек (шеңберден сәл кеңірек, әйтпесе
  /// шеттегі нүктені қою ыңғайсыз болады).
  LatLngBounds get _cameraBounds {
    if (!_cityKnown) {
      return LatLngBounds(
        const LatLng(kzMinLat, kzMinLng),
        const LatLng(kzMaxLat, kzMaxLng),
      );
    }
    // 1° ендік ≈ 111 км; бойлық градусы ендікке қарай cos(lat) есе сығылады.
    final padKm = _geo!.radiusKm * 1.4;
    final dLat = padKm / 111.0;
    final cosLat =
        math.cos(_allowedCenter.latitude * math.pi / 180).abs().clamp(0.1, 1.0);
    final dLng = padKm / (111.0 * cosLat);
    return LatLngBounds(
      LatLng(_allowedCenter.latitude - dLat, _allowedCenter.longitude - dLng),
      LatLng(_allowedCenter.latitude + dLat, _allowedCenter.longitude + dLng),
    );
  }

  void _tryPick(LatLng point) {
    if (!_isAllowed(point)) {
      _warnOutside();
      return;
    }
    setState(() => _picked = point);
  }

  void _warnOutside() {
    final city = widget.city?.trim();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(
          _cityKnown
              ? tr('Точку можно поставить только в городе $city',
                  'Нүктені тек $city қаласының шегінде қоюға болады')
              : tr('Точку можно поставить только на территории Казахстана',
                  'Нүктені тек Қазақстан аумағында қоюға болады'),
        ),
        backgroundColor: cRed,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ));
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
      if (!_isAllowed(me)) {
        _warnOutside();
        return;
      }
      setState(() => _picked = me);
      _mapController.move(me, 17);
    } catch (_) {
      // Геолокация міндетті емес — сәтсіз болса қолмен түртуге болады.
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _save() async {
    final p = _picked;
    if (p == null || _saving) return;
    if (!_isAllowed(p)) {
      _warnOutside();
      return;
    }
    setState(() => _saving = true);
    try {
      await _service.updateWarehouseLocation(
        warehouseId: widget.warehouse.id,
        lat: p.latitude,
        lng: p.longitude,
      );
      if (mounted) Navigator.pop(context, true);
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

  /// Таңдалған нүктені сыртқы картада ашып тексеру (әмбебап Google Maps
  /// сілтемесі — API кілт қажет емес, құрылғының карта қосымшасын ашады).
  Future<void> _openInMaps() async {
    final p = _picked;
    if (p == null) return;
    final uri = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=${p.latitude},${p.longitude}');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  void _zoom(double delta) {
    final c = _mapController.camera;
    _mapController.move(c.center, (c.zoom + delta).clamp(3.0, 18.0));
  }

  @override
  Widget build(BuildContext context) {
    final wh = widget.warehouse;
    final city = widget.city?.trim() ?? '';
    return Scaffold(
      backgroundColor: cBg,
      body: Column(children: [
        QGradientHeader(
          title: tr('Место на карте', 'Картадағы орын'),
          subtitle: city.isNotEmpty ? '${wh.name} · $city' : wh.name,
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
                minZoom: _cityKnown ? 9 : 3.5,
                maxZoom: 18,
                cameraConstraint:
                    CameraConstraint.containCenter(bounds: _cameraBounds),
                onTap: (_, point) => _tryPick(point),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'kz.qoima.app',
                ),
                if (_cityKnown)
                  CircleLayer(circles: [
                    CircleMarker(
                      point: _allowedCenter,
                      radius: _allowedRadiusM,
                      useRadiusInMeter: true,
                      color: cGreen.withValues(alpha: 0.07),
                      borderColor: cGreen.withValues(alpha: 0.55),
                      borderStrokeWidth: 2,
                    ),
                  ]),
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

            // ── Оң жақтағы басқару батырмалары ─────────────────────────────
            Positioned(
              right: 12,
              top: 12,
              child: Column(children: [
                _MapBtn(
                  icon: Icons.add_rounded,
                  onTap: () => _zoom(1),
                ),
                const SizedBox(height: 8),
                _MapBtn(
                  icon: Icons.remove_rounded,
                  onTap: () => _zoom(-1),
                ),
                const SizedBox(height: 8),
                _MapBtn(
                  icon: Icons.my_location_rounded,
                  loading: _locating,
                  onTap: _locateMe,
                ),
                if (_cityKnown) ...[
                  const SizedBox(height: 8),
                  _MapBtn(
                    icon: Icons.location_city_rounded,
                    onTap: () => _mapController.move(_allowedCenter, 12),
                  ),
                ],
              ]),
            ),

            // ── Төмендегі нұсқау/күй панелі ────────────────────────────────
            Positioned(
              left: 14,
              right: 14,
              bottom: 14,
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                decoration: BoxDecoration(
                  color: cSurface,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: kShadowMd,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(children: [
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
                              ? tr('Точка выбрана — нажмите «Сохранить»',
                                  'Нүкте таңдалды — «Сақтау» батырмасын басыңыз')
                              : tr('Нажмите на карту, чтобы указать место склада',
                                  'Қойманың орнын белгілеу үшін картаны түртіңіз'),
                          style: manrope(12.5, FontWeight.w600,
                              color: _picked != null ? cGreen : cInk2),
                        ),
                      ),
                      if (_picked != null)
                        GestureDetector(
                          onTap: _openInMaps,
                          child: const Padding(
                            padding: EdgeInsets.only(left: 8),
                            child: Icon(Icons.open_in_new_rounded,
                                color: cGreen, size: 18),
                          ),
                        ),
                    ]),
                    if (_cityKnown) ...[
                      const SizedBox(height: 7),
                      Row(children: [
                        const Icon(Icons.info_outline_rounded,
                            size: 14, color: cInk3),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            tr('Доступна только территория города $city (зелёная зона)',
                                'Тек $city қаласының аумағы қолжетімді (жасыл аймақ)'),
                            style: manrope(11.5, FontWeight.w500, color: cInk3),
                          ),
                        ),
                      ]),
                    ] else ...[
                      const SizedBox(height: 7),
                      Row(children: [
                        const Icon(Icons.warning_amber_rounded,
                            size: 14, color: cAmber),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            tr('Город магазина не указан — доступен весь Казахстан',
                                'Дүкен қаласы көрсетілмеген — бүкіл Қазақстан қолжетімді'),
                            style: manrope(11.5, FontWeight.w500, color: cInk3),
                          ),
                        ),
                      ]),
                    ],
                  ],
                ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

/// Таңдалған нүкте белгісі — ұшы дәл координатада тұратындай (alignment
/// topCenter + ішінде төмен қараған pin) жасалған.
class _PickedPin extends StatelessWidget {
  const _PickedPin();

  @override
  Widget build(BuildContext context) => const Stack(
        alignment: Alignment.topCenter,
        children: [
          Icon(Icons.location_on_rounded, color: cRed, size: 42),
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
