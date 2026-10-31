import '../../core/lang.dart';

/// Дүкеннің қайтару шарттары (0082).
///
/// Екі жерде бірдей пішінде өмір сүреді: `stores` бағандарында (иесі өзгертеді)
/// және `orders.return_policy` снапшотында (сату сәтінде сервер жазады, клиент
/// келіскен шарт ретінде өзгермейді). Хабарлама мен тапсырыс беті ТЕК снапшотты
/// көрсетеді.
class ReturnPolicy {
  static const modeAccept = 'accept';
  static const modeNone = 'none';

  /// Заң бойынша ең кемі 14 күн — дүкен тек ұзарта алады.
  /// Ақ тізім екі жерде: осы жер ↔ 0082 (stores_return_days_chk).
  static const allowedDays = [14, 21, 30];

  /// Ақ тізім екі жерде: осы жер ↔ 0082 (stores_return_conditions_chk).
  /// Тек қайтару ағыны шынымен тексере алатын шарттар: «тек ауыстыру» мен «тек
  /// ақау болса» әдейі жоқ — оларды жүйе орындамайды, әрі бұл 'none'-дың
  /// модератор рұқсатын айналып өтер еді.
  static const conditionCodes = [
    'tags',
    'unused',
    'packaging',
    'receipt',
  ];

  final String mode;
  final int days;
  final List<String> conditions;
  final String note;

  /// productId → тауарға жазылған ескертпе (products.return_note).
  final Map<String, String> productNotes;

  const ReturnPolicy({
    this.mode = modeAccept,
    this.days = 14,
    this.conditions = const [],
    this.note = '',
    this.productNotes = const {},
  });

  bool get isNoReturns => mode == modeNone;

  /// Снапшот жоқ (ескі тапсырыс, сыйлық, жалауша өшік) — null.
  static ReturnPolicy? fromSnapshot(Object? raw) {
    if (raw is! Map) return null;
    final notes = raw['product_notes'];
    return ReturnPolicy(
      mode: raw['mode'] as String? ?? modeAccept,
      days: (raw['days'] as num?)?.toInt() ?? 14,
      conditions: raw['conditions'] is List
          ? (raw['conditions'] as List).map((e) => e.toString()).toList()
          : const [],
      note: (raw['note'] as String? ?? '').trim(),
      productNotes: notes is Map
          ? notes.map((k, v) => MapEntry(k.toString(), v.toString()))
          : const {},
    );
  }

  /// Шарттың адамша мәтіні. Белгісіз код (жаңа нұсқадан келген) — бос жол,
  /// шақырушы оны тізімге қоспайды.
  static String conditionLabel(String code) {
    switch (code) {
      case 'tags':
        return tr('Сохранены бирки и ярлыки', 'Бирка мен жапсырмалар сақталған');
      case 'unused':
        return tr('Товар не был в использовании', 'Тауар қолданылмаған');
      case 'packaging':
        return tr('Сохранена упаковка', 'Қорабы сақталған');
      case 'receipt':
        return tr('Есть чек или номер заказа', 'Чек немесе тапсырыс нөмірі бар');
    }
    return '';
  }
}
