import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';

extension L10nContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this)!;

  List<String> get monthAbbreviations {
    final isKk = Localizations.localeOf(this).languageCode == 'kk';
    return isKk
        ? ['Қаң', 'Ақп', 'Нау', 'Сәу', 'Мам', 'Мау', 'Шіл', 'Там', 'Қыр', 'Қаз', 'Қар', 'Жел']
        : ['Янв', 'Фев', 'Мар', 'Апр', 'Май', 'Июн', 'Июл', 'Авг', 'Сен', 'Окт', 'Ноя', 'Дек'];
  }

  List<String> get monthNames {
    final isKk = Localizations.localeOf(this).languageCode == 'kk';
    return isKk
        ? ['Қаңтар', 'Ақпан', 'Наурыз', 'Сәуір', 'Мамыр', 'Маусым', 'Шілде', 'Тамыз', 'Қыркүйек', 'Қазан', 'Қараша', 'Желтоқсан']
        : ['Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь', 'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь'];
  }

  String monthShort(DateTime d) => '${monthAbbreviations[d.month - 1]} ${d.year}';

  String monthLong(DateTime d) => '${monthNames[d.month - 1]} ${d.year}';

  String forMonth(DateTime d) {
    final isKk = Localizations.localeOf(this).languageCode == 'kk';
    return isKk
        ? '${monthNames[d.month - 1]} айы үшін'
        : 'За ${monthNames[d.month - 1]}';
  }
}
