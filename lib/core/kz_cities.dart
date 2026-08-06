const List<String> kzCities = [
  'Алматы',
  'Астана',
  'Шымкент',
  'Қарағанды',
  'Атырау',
  'Ақтөбе',
  'Тараз',
  'Павлодар',
  'Өскемен',
  'Семей',
  'Ақтау',
  'Қостанай',
  'Орал',
  'Петропавл',
  'Қызылорда',
];

/// Қаланың картадағы орталығы мен рұқсат етілген радиусы.
///
/// [radiusKm] — қойма белгісін қоюға болатын шек: қала + маңы (бутиктер,
/// базарлар қала шетінде де болады). Осыдан тыс нүкте қабылданбайды —
/// админ өз қаласынан басқа жерге қойма белгілей алмайды.
class CityGeo {
  final double lat;
  final double lng;
  final double radiusKm;
  const CityGeo(this.lat, this.lng, {this.radiusKm = 35});
}

/// Қазақстан қалаларының координаттары (kzCities-пен бір тізім).
/// Кілт — kzCities-тегі канондық атау (тек қазақша, `trValue` аудармайды).
const Map<String, CityGeo> kzCityGeo = {
  'Алматы': CityGeo(43.2380, 76.8829, radiusKm: 45),
  'Астана': CityGeo(51.1694, 71.4491, radiusKm: 40),
  'Шымкент': CityGeo(42.3417, 69.5901, radiusKm: 40),
  'Қарағанды': CityGeo(49.8047, 73.1094, radiusKm: 40),
  'Атырау': CityGeo(47.0945, 51.9238),
  'Ақтөбе': CityGeo(50.2839, 57.1670),
  'Тараз': CityGeo(42.9000, 71.3667),
  'Павлодар': CityGeo(52.2873, 76.9674),
  'Өскемен': CityGeo(49.9787, 82.6014),
  'Семей': CityGeo(50.4111, 80.2275),
  'Ақтау': CityGeo(43.6410, 51.1980),
  'Қостанай': CityGeo(53.2144, 63.6246),
  'Орал': CityGeo(51.2333, 51.3667),
  'Петропавл': CityGeo(54.8667, 69.1500),
  'Қызылорда': CityGeo(44.8479, 65.5093),
};

/// Қазақстан шекарасының шамамен алынған тіктөртбұрышы — картаның камерасын
/// ел ішінде ұстау үшін (клиент те, админ де ҚР-дан тыс шыға алмайды).
const double kzMinLat = 40.5;
const double kzMaxLat = 55.6;
const double kzMinLng = 46.2;
const double kzMaxLng = 87.5;

/// Қала атауын kzCityGeo кілтіне келтіреді: бос орын/регистр айырмасын және
/// орысша нұсқаларын (профильде «Караганда» деп сақталуы мүмкін) ескереді.
CityGeo? cityGeoOf(String? city) {
  final key = (city ?? '').trim();
  if (key.isEmpty) return null;
  final direct = kzCityGeo[key];
  if (direct != null) return direct;
  final lower = key.toLowerCase();
  for (final e in kzCityGeo.entries) {
    if (e.key.toLowerCase() == lower) return e.value;
  }
  return _kzCityAliases[lower] == null ? null : kzCityGeo[_kzCityAliases[lower]];
}

/// Орысша/латын жазылымдары → канондық (қазақша) атау.
const Map<String, String> _kzCityAliases = {
  'алма-ата': 'Алматы',
  'almaty': 'Алматы',
  'астана': 'Астана',
  'нур-султан': 'Астана',
  'нұр-сұлтан': 'Астана',
  'astana': 'Астана',
  'shymkent': 'Шымкент',
  'караганда': 'Қарағанды',
  'karaganda': 'Қарағанды',
  'atyrau': 'Атырау',
  'актобе': 'Ақтөбе',
  'aktobe': 'Ақтөбе',
  'taraz': 'Тараз',
  'pavlodar': 'Павлодар',
  'усть-каменогорск': 'Өскемен',
  'oskemen': 'Өскемен',
  'semey': 'Семей',
  'актау': 'Ақтау',
  'aktau': 'Ақтау',
  'костанай': 'Қостанай',
  'kostanay': 'Қостанай',
  'уральск': 'Орал',
  'oral': 'Орал',
  'петропавловск': 'Петропавл',
  'petropavl': 'Петропавл',
  'кызылорда': 'Қызылорда',
  'kyzylorda': 'Қызылорда',
};
