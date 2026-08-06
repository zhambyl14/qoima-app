import 'dart:async';
import 'dart:html' as html;
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';
import '../../core/yandex_maps_js_bridge.dart';
import '../../data/models/store_model.dart';
import '../../data/models/warehouse_model.dart';
import '../../data/services/client_service.dart';
import '../../theme/qoima_design.dart';
import 'store_public_screen.dart';

import '../../core/lang.dart';

typedef _Pin = ({StoreModel store, WarehouseModel warehouse});

/// Веб нұсқасы — Yandex Maps JavaScript API (web/index.html-дегі
/// `window.qoimaMaps` көпірі арқылы). Android/iOS нұсқасы — stores_map_
/// screen.dart (Yandex MapKit native SDK); екеуін stores_map_launcher.dart
/// платформаға қарай таңдайды.
class StoresMapScreen extends StatefulWidget {
  final List<StoreModel> stores;
  const StoresMapScreen({super.key, required this.stores});

  @override
  State<StoresMapScreen> createState() => _StoresMapScreenState();
}

class _StoresMapScreenState extends State<StoresMapScreen> {
  final _service = ClientService();
  late final String _containerId =
      'qoima-store-map-${DateTime.now().microsecondsSinceEpoch}';
  bool _loading = true;
  bool _mapReady = false;
  List<_Pin> _entries = [];
  final Map<String, _Pin> _byId = {};

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
    _boot();
  }

  @override
  void dispose() {
    jsMapsSetClickHandler(null);
    jsMapsDestroy(_containerId.toJS);
    super.dispose();
  }

  void _setClickHandler(void Function(String id)? handler) {
    if (handler == null) {
      jsMapsSetClickHandler(null);
    } else {
      jsMapsSetClickHandler(
          ((JSString id) => handler(id.toDart)).toJS);
    }
  }

  Future<void> _boot() async {
    try {
      final ok = (await jsMapsReady().toDart).toDart;
      if (!ok) throw Exception('ymaps not loaded');

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
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // HtmlElementView өз DOM элементін орналастырғанша бір кадр күтеміз.
  void _initMapWhenMounted() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_mapReady || !mounted) return;
      final center = _entries.isNotEmpty
          ? [_entries.first.warehouse.lat!, _entries.first.warehouse.lng!]
          : [48.0196, 66.9237];
      final started = jsMapsInit(
              _containerId.toJS, center[0].toJS, center[1].toJS, 4.5.toJS)
          .toDart;
      if (!started) return;
      _mapReady = true;
      _setClickHandler((id) {
        final entry = _byId[id];
        if (entry != null) _showStoreSheet(entry.store, entry.warehouse);
      });
      final pointsFlat = <double>[];
      for (final e in _entries) {
        final wh = e.warehouse;
        _byId[wh.id] = e;
        jsMapsAddPlacemark(
            _containerId.toJS, wh.id.toJS, wh.lat!.toJS, wh.lng!.toJS);
        pointsFlat.addAll([wh.lat!, wh.lng!]);
      }
      if (pointsFlat.isNotEmpty) {
        jsMapsFitBounds(_containerId.toJS, pointsFlat.toJSNumbers);
      }
    });
  }

  void _openInYandexMaps(WarehouseModel wh) {
    html.window.open(
        'https://yandex.ru/maps/?pt=${wh.lng},${wh.lat}&z=17&l=map', '_blank');
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
    if (!_loading && !_mapReady) _initMapWhenMounted();
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
            if (!_loading) HtmlElementView(viewType: _containerId),
            if (_loading)
              const Center(child: CircularProgressIndicator(color: cGreen, strokeWidth: 2)),
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
