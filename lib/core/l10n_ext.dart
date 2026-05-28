import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../l10n/app_localizations.dart';

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
        'Янв',
        'Фев',
        'Мар',
        'Апр',
        'Май',
        'Июн',
        'Июл',
        'Авг',
        'Сен',
        'Окт',
        'Ноя',
        'Дек'
      ];

  List<String> get monthNames => [
        'Январь',
        'Февраль',
        'Март',
        'Апрель',
        'Май',
        'Июнь',
        'Июль',
        'Август',
        'Сентябрь',
        'Октябрь',
        'Ноябрь',
        'Декабрь'
      ];

  String monthShort(DateTime d) =>
      '${monthAbbreviations[d.month - 1]} ${d.year}';

  String monthLong(DateTime d) => '${monthNames[d.month - 1]} ${d.year}';

  String forMonth(DateTime d) => 'За ${monthNames[d.month - 1]}';
}
