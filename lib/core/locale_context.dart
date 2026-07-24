import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocaleContext extends ChangeNotifier {
  static const _prefKey = 'app_locale';
  static const _supported = {'kk', 'ru'};

  /// Ағымдағы тіл коды — tr() сияқты BuildContext жоқ жерлерде оқылады.
  /// Тіл ауысқанда MaterialApp толық қайта құрылатындықтан (key: locale),
  /// статикалық оқу UI-мен синхронды.
  static String currentLang = 'ru';

  Locale _locale;
  Locale get locale => _locale;

  /// [initial] — main()-те [loadSaved] арқылы алдын ала жүктелген тіл.
  /// Бастапқы Locale-ды конструкторда орнату алғашқы кадрдан-ақ дұрыс тілді
  /// береді (сақталған тіл kk болса да жыпылық/қосымша rebuild болмайды).
  LocaleContext([Locale? initial])
      : _locale = initial ?? const Locale('ru') {
    currentLang = _locale.languageCode;
  }

  /// runApp алдында шақырылады: SharedPreferences-тен сақталған тілді оқып,
  /// бастапқы Locale-ды қайтарады. Белгісіз/жоқ мән → ru.
  static Future<Locale> loadSaved() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefKey);
      if (saved != null && _supported.contains(saved)) return Locale(saved);
    } catch (_) {
      // SharedPreferences қолжетімсіз болса — әдепкі тіл.
    }
    return const Locale('ru');
  }

  Future<void> setLocale(Locale locale) async {
    if (_locale.languageCode == locale.languageCode) return;
    _locale = locale;
    currentLang = locale.languageCode;
    // notifyListeners → QoimaApp rebuild → MaterialApp key өзгереді → бүкіл
    // интерфейс сол сәтте жаңа тілде қайта құрылады.
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, locale.languageCode);
    } catch (_) {
      // Сақтау сәтсіз болса да ағымдағы сессияда тіл ауысады.
    }
  }
}
