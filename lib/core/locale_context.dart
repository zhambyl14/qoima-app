import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocaleContext extends ChangeNotifier {
  static const _prefKey = 'app_locale';

  /// Ағымдағы тіл коды — tr() сияқты BuildContext жоқ жерлерде оқылады.
  /// Тіл ауысқанда MaterialApp толық қайта құрылатындықтан, статикалық
  /// оқу UI-мен синхронды.
  static String currentLang = 'ru';

  Locale _locale = const Locale('ru');
  Locale get locale => _locale;

  LocaleContext() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefKey);
    if (saved != null) {
      _locale = Locale(saved);
      currentLang = saved;
      notifyListeners();
    }
  }

  Future<void> setLocale(Locale locale) async {
    if (_locale == locale) return;
    _locale = locale;
    currentLang = locale.languageCode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, locale.languageCode);
  }
}
