import 'dart:html' as html;
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';
import '../../../core/yandex_maps_js_bridge.dart';
import '../../../data/models/warehouse_model.dart';
import '../../../data/services/firestore_service.dart';
import '../../../theme/qoima_design.dart';

import '../../../core/lang.dart';
import '../../../core/error_text.dart';

/// Веб нұсқасы — warehouse_map_picker_screen.dart (Android/iOS, native
/// MapKit) орнына; сол `window.qoimaMaps` JS көпірін қолданады
/// (web/index.html: initPicker — жалғыз жылжымалы белгі, түрту/сүйреу).
class WarehouseMapPickerScreen extends StatefulWidget {
  final WarehouseModel warehouse;
  const WarehouseMapPickerScreen({super.key, required this.warehouse});

  @override
  State<WarehouseMapPickerScreen> createState() =>
      _WarehouseMapPickerScreenState();
}

class _WarehouseMapPickerScreenState extends State<WarehouseMapPickerScreen> {
  final _service = FirestoreService();
  late final String _containerId =
      'qoima-wh-picker-${DateTime.now().microsecondsSinceEpoch}';
  double? _pickedLat;
  double? _pickedLng;
  bool _saving = false;
  bool _mapReady = false;

  @override
  void initState() {
    super.initState();
    ui_web.platformViewRegistry.registerViewFactory(_containerId, (int _) {
      final el = html.DivElement()
        ..id = _containerId
        ..style.width = '100%'
        ..style.height = '100%';
      return el;
    });
    if (widget.warehouse.hasLocation) {
      _pickedLat = widget.warehouse.lat;
      _pickedLng = widget.warehouse.lng;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _initMap());
  }

  @override
  void dispose() {
    jsMapsSetClickHandler(null);
    jsMapsDestroy(_containerId.toJS);
    super.dispose();
  }

  void _initMap() {
    if (_mapReady || !mounted) return;
    final wh = widget.warehouse;
    final lat = wh.lat ?? 43.238293;
    final lng = wh.lng ?? 76.945465;
    jsMapsInitPicker(_containerId.toJS, lat.toJS, lng.toJS,
        (wh.hasLocation ? 16 : 11).toJS, wh.hasLocation.toJS);
    _mapReady = true;
    jsMapsSetClickHandler(((JSString payload) {
      final parts = payload.toDart.split('|');
      if (parts.length != 3) return;
      final lat = double.tryParse(parts[1]);
      final lng = double.tryParse(parts[2]);
      if (lat == null || lng == null || !mounted) return;
      setState(() {
        _pickedLat = lat;
        _pickedLng = lng;
      });
    }).toJS);
  }

  Future<void> _save() async {
    if (_pickedLat == null || _pickedLng == null || _saving) return;
    setState(() => _saving = true);
    try {
      await _service.updateWarehouseLocation(
        warehouseId: widget.warehouse.id,
        lat: _pickedLat!,
        lng: _pickedLng!,
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
            onPressed: (_pickedLat != null && !_saving) ? _save : null,
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
            HtmlElementView(viewType: _containerId),
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
                ]),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}
