import 'package:yandex_maps_mapkit_lite/init.dart' as ymk;
import 'yandex_maps_config.dart';

/// Мобильді (Android/iOS) — Yandex MapKit native SDK. Веб-те бұл файл
/// МҮЛДЕ импортталмайды (map_init_web.dart қолданылады) — MapKit dart:ffi
/// қолданады, ол веб-компиляцияда мүлде жұмыс істемейді/derlemейді.
Future<void> initMapsSdk() => ymk.initMapkit(apiKey: YandexMapsConfig.mapKitApiKey);
