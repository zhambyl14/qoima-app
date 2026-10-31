import '../../core/lang.dart';
import 'category_data.dart' show kSeasons;

/// Тауар маусымы (`products.season`) — ЖАЛҒЫЗ канондық пішім:
/// канондық мәндер ([kSeasons]) үтірмен, бос орынсыз, [kSeasons] ретімен:
/// `Лето,Зима`. Бір мәнді ескі жазба (`Лето`) — тізімнің дербес жағдайы,
/// сондықтан өзгеріссіз жұмыс істейді. Бос жол = маусым көрсетілмеген.
///
/// Бұл файл ProductModel-ге де, иесінің формасына да, клиент UI-ына да ортақ
/// болу үшін бөлек: ProductModel-ді импорттамайды (циклдік тәуелділік жоқ).
const String kSeasonSeparator = ',';

/// Жолды маусымдар тізіміне бөледі. Қайталанбайды; белгілі мәндер [kSeasons]
/// ретімен, белгісіздер (болашақ/қолмен жазылған) соңында — деректі жоғалтпаймыз.
List<String> parseSeasons(String? raw) {
  if (raw == null) return const [];
  final seen = <String>{};
  for (final part in raw.split(kSeasonSeparator)) {
    final s = part.trim();
    if (s.isNotEmpty) seen.add(s);
  }
  final known = [
    for (final s in kSeasons)
      if (seen.contains(s)) s
  ];
  final unknown = [
    for (final s in seen)
      if (!kSeasons.contains(s)) s
  ];
  return [...known, ...unknown];
}

/// Таңдалған маусымдарды DB-ге жазылатын жолға айналдырады (канондық ретпен,
/// қайталанбай). Бос тізім → ''.
String joinSeasons(Iterable<String> seasons) =>
    parseSeasons(seasons.join(kSeasonSeparator)).join(kSeasonSeparator);

/// [raw] ішінде [season] бар ма (ескі бір мәнді жазба да дұрыс жұмыс істейді).
bool seasonsContain(String? raw, String season) =>
    parseSeasons(raw).contains(season.trim());

/// Клиент сүзгісі: [selected] бос болса — сүзгі жоқ (бәрі өтеді). Әйтпесе
/// тауардың КЕЗ КЕЛГЕН маусымы таңдалғандардың бірімен сәйкессе — өтеді.
/// [includeUnspecified] — маусымы көрсетілмеген тауарды да өткізу
/// (search_catalog RPC-дағы мінез: «сол маусым НЕМЕСЕ көрсетілмеген»).
bool seasonsMatchFilter(String? raw, Iterable<String> selected,
    {bool includeUnspecified = false}) {
  final want = selected.map((s) => s.trim()).where((s) => s.isNotEmpty).toSet();
  if (want.isEmpty) return true;
  final have = parseSeasons(raw);
  if (have.isEmpty) return includeUnspecified;
  return have.any(want.contains);
}

/// Көрсетілім: ағымдағы тіл бойынша «Жаз, Қыс» / «Лето, Зима».
/// Бос болса — ''. (trValue әр канондық мәнге жеке қолданылады.)
String seasonsLabel(String? raw, {String separator = ', '}) =>
    parseSeasons(raw).map(trValue).join(separator);
