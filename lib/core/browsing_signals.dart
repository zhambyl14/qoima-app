import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Клиент/гость үшін «не қарады, не іздеді» сигналдарын құрылғыда (серверсіз,
/// CartProvider секілді SharedPreferences арқылы) сақтайды — басты беттегі
/// «Ұсынылады сізге» секциясын жекелендіру үшін. Бекітілген серверлік
/// трекинг инфрақұрылымы жоқ (жоба бойынша тексерілді) — бұл V1 нұсқасы
/// қасбеттен ешбір жаңа кестесіз жұмыс істейді.
class BrowsingSignalsService {
  BrowsingSignalsService._();
  static final BrowsingSignalsService instance = BrowsingSignalsService._();

  static const _kKey = 'browsing_signals_v1';
  static const _kMaxEntries = 40;
  static const _kRecentSearchesKey = 'recent_searches_v1';
  static const _kMaxRecentSearches = 4;

  // {'cat': categoryKey, 'brand': brand-not-required, 'w': weight}
  List<Map<String, dynamic>> _signals = [];
  List<String> _recentSearches = [];
  bool _loaded = false;

  /// Экран initState-інде бір рет шақырылады — синхронды affinity есептеу
  /// үшін жадыда дайын тұруы керек (build() әр рет SharedPreferences оқымайды).
  Future<void> preload() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kKey);
      if (raw != null) {
        final list = jsonDecode(raw) as List<dynamic>;
        _signals = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
      _recentSearches = prefs.getStringList(_kRecentSearchesKey) ?? [];
    } catch (_) {}
    _loaded = true;
  }

  Future<void> _add(Map<String, dynamic> entry) async {
    await preload();
    _signals.add(entry);
    if (_signals.length > _kMaxEntries) {
      _signals = _signals.sublist(_signals.length - _kMaxEntries);
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kKey, jsonEncode(_signals));
    } catch (_) {}
  }

  /// Тауар детальіне кірген сәтте (категория + бренд, салмағы жоғары — нақты
  /// қызығушылық белгісі).
  Future<void> recordView({required String categoryKey, required String brand}) =>
      _add({'cat': categoryKey, 'brand': brand, 'w': 2});

  /// Іздеу нәтижесінің басым категориясы (салмағы төмен — жанама белгі).
  Future<void> recordSearchCategory(String categoryKey) =>
      _add({'cat': categoryKey, 'brand': '', 'w': 1});

  /// Соңғы іздеген сұраныс — басты беттегі іздеу өрісін бассанда «соңғы
  /// іздегендер» ұсынысы үшін (ең соңғысы алдыда, көшірмесіз, макс 4).
  Future<void> recordSearchQuery(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    await preload();
    _recentSearches.removeWhere((e) => e.toLowerCase() == q.toLowerCase());
    _recentSearches.insert(0, q);
    if (_recentSearches.length > _kMaxRecentSearches) {
      _recentSearches = _recentSearches.sublist(0, _kMaxRecentSearches);
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_kRecentSearchesKey, _recentSearches);
    } catch (_) {}
  }

  /// [preload] шақырылғаннан кейін синхронды қолжетімді соңғы іздеу тізімі.
  List<String> get recentSearches => List.unmodifiable(_recentSearches);

  /// Санат бойынша салмақ қосындысы — [preload] шақырылғаннан кейін синхронды.
  Map<String, int> categoryAffinity() {
    final counts = <String, int>{};
    for (final s in _signals) {
      final cat = s['cat'] as String? ?? '';
      if (cat.isEmpty) continue;
      final w = (s['w'] as num?)?.toInt() ?? 1;
      counts[cat] = (counts[cat] ?? 0) + w;
    }
    return counts;
  }

  /// Бренд бойынша салмақ қосындысы (тек view сигналдарынан — іздеуден
  /// бренд алу шуылды болғандықтан қосылмайды).
  Map<String, int> brandAffinity() {
    final counts = <String, int>{};
    for (final s in _signals) {
      final brand = s['brand'] as String? ?? '';
      if (brand.isEmpty) continue;
      final w = (s['w'] as num?)?.toInt() ?? 1;
      counts[brand] = (counts[brand] ?? 0) + w;
    }
    return counts;
  }

  bool get hasSignal => _signals.isNotEmpty;
}
