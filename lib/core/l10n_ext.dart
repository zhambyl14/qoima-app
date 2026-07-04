import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../l10n/app_localizations.dart';
import 'lang.dart';

extension MoneyFmt on num {
  String get money =>
      '${NumberFormat('#,###', 'ru').format(this).replaceAll(',', ' ')} ₸';
}

extension L10nContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this)!;

  String money(num amount) =>
      '${NumberFormat('#,##0', 'ru').format(amount.round())} ₸';

  String date(DateTime d) => DateFormat('dd.MM.yyyy').format(d);

  List<String> get monthAbbreviations => [
        tr('Янв', 'Қаң'),
        tr('Фев', 'Ақп'),
        tr('Мар', 'Нау'),
        tr('Апр', 'Сәу'),
        tr('Май', 'Мам'),
        tr('Июн', 'Мау'),
        tr('Июл', 'Шіл'),
        tr('Авг', 'Там'),
        tr('Сен', 'Қыр'),
        tr('Окт', 'Қаз'),
        tr('Ноя', 'Қар'),
        tr('Дек', 'Жел')
      ];

  List<String> get monthNames => [
        tr('Январь', 'Қаңтар'),
        tr('Февраль', 'Ақпан'),
        tr('Март', 'Наурыз'),
        tr('Апрель', 'Сәуір'),
        tr('Май', 'Мамыр'),
        tr('Июнь', 'Маусым'),
        tr('Июль', 'Шілде'),
        tr('Август', 'Тамыз'),
        tr('Сентябрь', 'Қыркүйек'),
        tr('Октябрь', 'Қазан'),
        tr('Ноябрь', 'Қараша'),
        tr('Декабрь', 'Желтоқсан')
      ];

  String monthShort(DateTime d) =>
      '${monthAbbreviations[d.month - 1]} ${d.year}';

  String monthLong(DateTime d) => '${monthNames[d.month - 1]} ${d.year}';

  String forMonth(DateTime d) =>
      tr('За ${monthNames[d.month - 1]}', '${monthNames[d.month - 1]} үшін');
}
