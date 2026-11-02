import 'dart:convert';

import '../../core/lang.dart';
import 'category_data.dart';

/// Категорияға тән сипаттамалар (`products.attributes`, 0085).
///
/// Бұрын әр категория аяқ киім сияқты толтырылатын: түс міндетті, маусым,
/// материал — бәрінде бірдей. Енді әр категорияның ӨЗ өрістері бар: телефонда
/// жады/жағдайы/кепілдік, кітапта автор/тілі, тағамда салмағы/жарамдылығы.
///
/// Мәндер `products.attributes` jsonb объектісінде `{кілт: мән}` түрінде:
///  * [AttrKind.chips] — канондық орысша жол (`'Новый'`);
///  * [AttrKind.multiChips] — канондық жолдар тізімі (`['Бег','Фитнес']`);
///  * [AttrKind.text] — иесі жазған жол (аударылмайды);
///  * [AttrKind.number] — сан (`8`, `15.6`), бірлігі схемада.
///
/// ⚠️ [AttrDef.key] мен опциялар DB-де сақталады — бар мәнді ӨЗГЕРТПЕҢІЗ,
/// тек жаңасын қосыңыз. Опция аудармасы — lang.dart (trValue), сақталатын мән
/// әрқашан орысша.
enum AttrKind { chips, multiChips, text, number }

class AttrDef {
  /// snake_case, мәңгі тұрақты (DB кілті).
  final String key;
  final String labelRu, labelKk;
  final AttrKind kind;

  /// chips/multiChips опциялары — канондық орысша мәндер.
  final List<String> options;

  /// false — опциялар тілге тәуелсіз ('8 ГБ', 'A4', '585'): trValue-сыз.
  final bool translateOptions;

  /// number бірлігі ('ГБ', 'мл'). Бос — бірліксіз (мыс. жыл).
  final String unitRu, unitKk;

  /// number: бөлшек сан рұқсат па (15.6″, 0.35 л). false — тек бүтін.
  final bool decimal;

  /// Сатып алушы онсыз шеше алмайтын өріс қана (категорияда ең көбі 1–2).
  final bool required;
  final String hintRu, hintKk;

  /// Клиент карточкасында (тізімде) қысқа белгі болып шығатын өріс —
  /// категорияда ең көбі біреу.
  final bool showOnCard;

  /// text: ең ұзын жол.
  final int maxLength;

  /// number: ең көп цифр саны (бөлшекті қоса).
  final int maxDigits;

  const AttrDef({
    required this.key,
    required this.labelRu,
    required this.labelKk,
    required this.kind,
    this.options = const [],
    this.translateOptions = true,
    this.unitRu = '',
    this.unitKk = '',
    this.decimal = false,
    this.required = false,
    this.hintRu = '',
    this.hintKk = '',
    this.showOnCard = false,
    this.maxLength = 60,
    this.maxDigits = 6,
  });

  String get label => tr(labelRu, labelKk);
  String get hint => tr(hintRu, hintKk);
  String get unit => tr(unitRu, unitKk);

  bool get isChoice => kind == AttrKind.chips || kind == AttrKind.multiChips;

  /// Опцияның ағымдағы тілдегі жазуы.
  String optionLabel(String value) => translateOptions ? trValue(value) : value;

  /// Мәннің ағымдағы тілдегі көрсетілімі ('' = мән жоқ).
  String valueLabel(Object? raw) {
    final v = normalizeAttrValue(this, raw);
    if (v == null) return '';
    switch (kind) {
      case AttrKind.chips:
        return optionLabel(v as String);
      case AttrKind.multiChips:
        return (v as List<String>).map(optionLabel).join(', ');
      case AttrKind.text:
        return v as String;
      case AttrKind.number:
        final n = formatAttrNumber(v as num);
        return unit.isEmpty ? n : '$n $unit';
    }
  }
}

/// Форманың категорияға бейімделуі: қай ортақ өріс керек.
class CategoryVisibility {
  /// false — түс бөлімі жасырын; тауар ЖАЛҒЫЗ түссіз нұсқа (color = '').
  final bool needsColor;

  /// Маусым тек киім-кешек, спорт және балалар тауарларына мағыналы.
  final bool needsSeason;

  /// Материал тек [kMaterialsByCategory]-де тізімі бар және мағынасы бар жерде.
  final bool needsMaterial;

  const CategoryVisibility({
    required this.needsColor,
    required this.needsSeason,
    required this.needsMaterial,
  });
}

// ── Ортақ опция жиындары ─────────────────────────────────────────────────────
const List<String> _kCondition = ['Новый', 'Б/у', 'Восстановленный'];
const List<String> _kSleeve = ['Короткий', 'Длинный', '3/4', 'Без рукава'];
const List<String> _kInsulation = [
  'Без утепления',
  'Флис',
  'Байка',
  'Синтепон',
  'Холлофайбер',
  'Пух',
  'Мех',
  'Искусственный мех',
];
const List<String> _kPowerSource = [
  'Ручной',
  'Сеть 220 В',
  'Аккумуляторный',
  'Бензиновый',
  'Батарейки',
  'Солнечный',
];

const AttrDef _warranty = AttrDef(
  key: 'warranty_months',
  labelRu: 'Гарантия',
  labelKk: 'Кепілдік',
  kind: AttrKind.number,
  unitRu: 'мес.',
  unitKk: 'ай',
  maxDigits: 3,
);

const AttrDef _condition = AttrDef(
  key: 'condition',
  labelRu: 'Состояние',
  labelKk: 'Жағдайы',
  kind: AttrKind.chips,
  options: _kCondition,
);

const AttrDef _dimensions = AttrDef(
  key: 'dimensions',
  labelRu: 'Размеры (Ш×В×Г)',
  labelKk: 'Өлшемдері (Е×Б×Т)',
  kind: AttrKind.text,
  hintRu: 'Напр: 60×185×65 см',
  hintKk: 'Мыс: 60×185×65 см',
  maxLength: 40,
);

const AttrDef _bestBefore = AttrDef(
  key: 'best_before',
  labelRu: 'Годен до',
  labelKk: 'Жарамдылық мерзімі',
  kind: AttrKind.text,
  hintRu: 'Напр: 12.2027',
  hintKk: 'Мыс: 12.2027',
  maxLength: 20,
);

const AttrDef _packQty = AttrDef(
  key: 'pack_qty',
  labelRu: 'В упаковке',
  labelKk: 'Қаптамада',
  kind: AttrKind.number,
  unitRu: 'шт.',
  unitKk: 'дана',
  maxDigits: 4,
);

/// Әр 29 категорияның сипаттамалары (тәртібі = формадағы реті).
/// Тек сатып алушы шынымен шешім қабылдайтын өрістер; бәрі дерлік чип —
/// иесі тергеннен гөрі басқаны жөн көреді.
const Map<String, List<AttrDef>> kCategoryAttributes = {
  // ── Мода ──────────────────────────────────────────────────────────────────
  'shoes': [
    AttrDef(
      key: 'heel_height',
      labelRu: 'Каблук',
      labelKk: 'Өкшесі',
      kind: AttrKind.chips,
      options: ['Без каблука', 'Низкий', 'Средний', 'Высокий', 'Платформа'],
    ),
    AttrDef(
      key: 'closure',
      labelRu: 'Застёжка',
      labelKk: 'Ілгегі',
      kind: AttrKind.chips,
      options: ['Шнурки', 'Липучка', 'Молния', 'Пряжка', 'Без застёжки'],
    ),
    AttrDef(
      key: 'sole',
      labelRu: 'Подошва',
      labelKk: 'Табаны',
      kind: AttrKind.chips,
      options: ['Резина', 'Пена (EVA)', 'Полиуретан', 'ТЭП', 'Кожа'],
    ),
    AttrDef(
      key: 'insulation',
      labelRu: 'Утепление',
      labelKk: 'Жылытқышы',
      kind: AttrKind.chips,
      options: _kInsulation,
    ),
  ],
  'tshirt': [
    AttrDef(
      key: 'fit',
      labelRu: 'Посадка',
      labelKk: 'Пішімі',
      kind: AttrKind.chips,
      options: ['Обычный', 'Оверсайз', 'Приталенный', 'Свободный'],
    ),
    AttrDef(
      key: 'sleeve',
      labelRu: 'Рукав',
      labelKk: 'Жеңі',
      kind: AttrKind.chips,
      options: _kSleeve,
    ),
    AttrDef(
      key: 'neckline',
      labelRu: 'Вырез / воротник',
      labelKk: 'Мойын ойығы / жағасы',
      kind: AttrKind.chips,
      options: ['Круглый', 'V-образный', 'Поло', 'Стойка', 'С капюшоном'],
    ),
  ],
  'outer': [
    AttrDef(
      key: 'insulation',
      labelRu: 'Утеплитель',
      labelKk: 'Жылытқышы',
      kind: AttrKind.chips,
      options: _kInsulation,
    ),
    AttrDef(
      key: 'temp_rating',
      labelRu: 'Для температуры',
      labelKk: 'Температураға',
      kind: AttrKind.chips,
      options: ['до 0°C', 'до −10°C', 'до −20°C', 'до −30°C'],
      showOnCard: true,
    ),
    AttrDef(
      key: 'length',
      labelRu: 'Длина',
      labelKk: 'Ұзындығы',
      kind: AttrKind.chips,
      options: ['Короткая', 'Средняя', 'Длинная'],
    ),
    AttrDef(
      key: 'hood',
      labelRu: 'Капюшон',
      labelKk: 'Капюшон',
      kind: AttrKind.chips,
      options: ['С капюшоном', 'Без капюшона', 'Съёмный капюшон'],
    ),
    AttrDef(
      key: 'closure',
      labelRu: 'Застёжка',
      labelKk: 'Ілгегі',
      kind: AttrKind.chips,
      options: ['Молния', 'Пуговицы', 'Кнопки', 'Без застёжки'],
    ),
  ],
  'pants': [
    AttrDef(
      key: 'fit',
      labelRu: 'Крой',
      labelKk: 'Пішімі',
      kind: AttrKind.chips,
      options: [
        'Прямые',
        'Зауженные',
        'Широкие',
        'Скинни',
        'Клёш',
        'Мом',
        'Джоггеры'
      ],
    ),
    AttrDef(
      key: 'rise',
      labelRu: 'Посадка',
      labelKk: 'Отырысы',
      kind: AttrKind.chips,
      options: ['Низкая', 'Средняя', 'Высокая'],
    ),
    AttrDef(
      key: 'length',
      labelRu: 'Длина',
      labelKk: 'Ұзындығы',
      kind: AttrKind.chips,
      options: ['Укороченные', 'Стандарт', 'Удлинённые'],
    ),
  ],
  'dress': [
    AttrDef(
      key: 'length',
      labelRu: 'Длина',
      labelKk: 'Ұзындығы',
      kind: AttrKind.chips,
      options: ['Мини', 'Миди', 'Макси'],
      showOnCard: true,
    ),
    AttrDef(
      key: 'silhouette',
      labelRu: 'Силуэт',
      labelKk: 'Пішімі',
      kind: AttrKind.chips,
      options: ['Прямое', 'А-силуэт', 'Приталенное', 'Свободное', 'На запах'],
    ),
    AttrDef(
      key: 'sleeve',
      labelRu: 'Рукав',
      labelKk: 'Жеңі',
      kind: AttrKind.chips,
      options: _kSleeve,
    ),
    AttrDef(
      key: 'occasion',
      labelRu: 'Повод',
      labelKk: 'Қай жерге',
      kind: AttrKind.multiChips,
      options: [
        'Повседневное',
        'Офисное',
        'Вечернее',
        'Праздничное',
        'Пляжное'
      ],
    ),
  ],
  'caps': [
    AttrDef(
      key: 'insulation',
      labelRu: 'Утепление',
      labelKk: 'Жылытқышы',
      kind: AttrKind.chips,
      options: ['Без утепления', 'Флис', 'Мех', 'Искусственный мех'],
    ),
    AttrDef(
      key: 'adjustable',
      labelRu: 'Регулировка размера',
      labelKk: 'Өлшемін реттеу',
      kind: AttrKind.chips,
      options: ['Регулируется', 'Не регулируется'],
    ),
  ],
  'underwear': [
    _packQty,
    AttrDef(
      key: 'cup',
      labelRu: 'Чашка',
      labelKk: 'Тостағаны',
      kind: AttrKind.chips,
      options: ['AA', 'A', 'B', 'C', 'D', 'E', 'F'],
      translateOptions: false,
      hintRu: 'Для бюстгальтеров',
      hintKk: 'Бюстгальтерлер үшін',
    ),
    AttrDef(
      key: 'density_den',
      labelRu: 'Плотность',
      labelKk: 'Тығыздығы',
      kind: AttrKind.number,
      unitRu: 'ден',
      unitKk: 'ден',
      hintRu: 'Для колготок',
      hintKk: 'Колготкиге',
      maxDigits: 4,
    ),
  ],
  'acc': [
    AttrDef(
      key: 'bag_volume_l',
      labelRu: 'Объём',
      labelKk: 'Көлемі',
      kind: AttrKind.number,
      unitRu: 'л',
      unitKk: 'л',
      decimal: true,
      hintRu: 'Для сумок и рюкзаков',
      hintKk: 'Сөмке мен рюкзакқа',
      maxDigits: 4,
    ),
    AttrDef(
      key: 'strap_length_cm',
      labelRu: 'Длина ремня / ручки',
      labelKk: 'Белбеу / тұтқа ұзындығы',
      kind: AttrKind.number,
      unitRu: 'см',
      unitKk: 'см',
      maxDigits: 4,
    ),
    AttrDef(
      key: 'lens',
      labelRu: 'Линзы',
      labelKk: 'Линзалары',
      kind: AttrKind.multiChips,
      options: ['UV400', 'Поляризация', 'Фотохром'],
      hintRu: 'Для очков',
      hintKk: 'Көзілдірікке',
    ),
  ],
  'jewelry': [
    // Материал өрісінің орнына: металл — әшекейдің басты белгісі.
    AttrDef(
      key: 'metal',
      labelRu: 'Металл',
      labelKk: 'Металы',
      kind: AttrKind.chips,
      options: [
        'Золото',
        'Белое золото',
        'Розовое золото',
        'Серебро',
        'Платина',
        'Сталь',
        'Бижутерия'
      ],
      required: true,
      showOnCard: true,
    ),
    AttrDef(
      key: 'fineness',
      labelRu: 'Проба',
      labelKk: 'Сынамасы',
      kind: AttrKind.chips,
      options: ['375', '500', '585', '750', '875', '925', '999'],
      translateOptions: false,
    ),
    AttrDef(
      key: 'stone',
      labelRu: 'Камень',
      labelKk: 'Тасы',
      kind: AttrKind.chips,
      options: [
        'Без камня',
        'Бриллиант',
        'Фианит',
        'Жемчуг',
        'Изумруд',
        'Сапфир',
        'Рубин',
        'Другой'
      ],
    ),
    AttrDef(
      key: 'weight_g',
      labelRu: 'Вес',
      labelKk: 'Салмағы',
      kind: AttrKind.number,
      unitRu: 'г',
      unitKk: 'г',
      decimal: true,
      maxDigits: 5,
    ),
  ],
  'sport': [
    AttrDef(
      key: 'sport_kind',
      labelRu: 'Вид спорта',
      labelKk: 'Спорт түрі',
      kind: AttrKind.multiChips,
      options: [
        'Бег',
        'Фитнес',
        'Йога',
        'Футбол',
        'Баскетбол',
        'Плавание',
        'Велоспорт',
        'Единоборства',
        'Туризм',
        'Зимние виды'
      ],
    ),
    AttrDef(
      key: 'level',
      labelRu: 'Уровень',
      labelKk: 'Деңгейі',
      kind: AttrKind.chips,
      options: ['Начинающий', 'Любитель', 'Профессионал'],
    ),
    AttrDef(
      key: 'max_load_kg',
      labelRu: 'Макс. нагрузка',
      labelKk: 'Ең көп жүктеме',
      kind: AttrKind.number,
      unitRu: 'кг',
      unitKk: 'кг',
      hintRu: 'Для тренажёров, велосипедов',
      hintKk: 'Тренажёр, велосипедке',
      maxDigits: 4,
    ),
  ],

  // ── Балалар ───────────────────────────────────────────────────────────────
  'kids': [
    AttrDef(
      key: 'for_whom',
      labelRu: 'Для кого',
      labelKk: 'Кімге',
      kind: AttrKind.chips,
      options: ['Для мальчика', 'Для девочки', 'Унисекс'],
    ),
    AttrDef(
      key: 'height_cm',
      labelRu: 'Рост',
      labelKk: 'Бойы',
      kind: AttrKind.multiChips,
      options: [
        '50–62',
        '68–74',
        '80–86',
        '92–98',
        '104–110',
        '116–122',
        '128–134',
        '140–146',
        '152–158'
      ],
      translateOptions: false,
      hintRu: 'Для одежды, см',
      hintKk: 'Киімге, см',
    ),
    AttrDef(
      key: 'max_weight_kg',
      labelRu: 'Вес ребёнка до',
      labelKk: 'Бала салмағы',
      kind: AttrKind.number,
      unitRu: 'кг',
      unitKk: 'кг',
      hintRu: 'Для колясок и автокресел',
      hintKk: 'Коляска мен автокреслоға',
      maxDigits: 3,
    ),
  ],
  'toys': [
    AttrDef(
      key: 'age_group',
      labelRu: 'Возраст',
      labelKk: 'Жасы',
      kind: AttrKind.chips,
      options: ['0+', '1+', '3+', '6+', '8+', '12+', '18+'],
      translateOptions: false,
      required: true,
      showOnCard: true,
    ),
    AttrDef(
      key: 'battery',
      labelRu: 'Питание',
      labelKk: 'Қуат көзі',
      kind: AttrKind.chips,
      options: ['Не нужно', 'Батарейки', 'Аккумулятор'],
    ),
    AttrDef(
      key: 'pieces',
      labelRu: 'Деталей',
      labelKk: 'Бөлшек саны',
      kind: AttrKind.number,
      unitRu: 'шт.',
      unitKk: 'дана',
      hintRu: 'Для конструкторов и пазлов',
      hintKk: 'Конструктор мен пазлға',
      maxDigits: 5,
    ),
  ],

  // ── Красота және денсаулық ────────────────────────────────────────────────
  'beauty': [
    AttrDef(
      key: 'volume_ml',
      labelRu: 'Объём',
      labelKk: 'Көлемі',
      kind: AttrKind.number,
      unitRu: 'мл',
      unitKk: 'мл',
      showOnCard: true,
      maxDigits: 5,
    ),
    AttrDef(
      key: 'skin_type',
      labelRu: 'Тип кожи / волос',
      labelKk: 'Тері / шаш түрі',
      kind: AttrKind.multiChips,
      options: [
        'Для всех типов',
        'Сухая',
        'Жирная',
        'Комбинированная',
        'Нормальная',
        'Чувствительная'
      ],
    ),
    AttrDef(
      key: 'shade',
      labelRu: 'Оттенок / аромат',
      labelKk: 'Реңкі / иісі',
      kind: AttrKind.text,
      hintRu: 'Напр: 02 Nude',
      hintKk: 'Мыс: 02 Nude',
      maxLength: 40,
    ),
    _bestBefore,
  ],
  // Дәріханада ешнәрсе міндетті емес: дәрі туралы шешімді дәрігер береді.
  'pharmacy': [
    AttrDef(
      key: 'dosage_form',
      labelRu: 'Форма выпуска',
      labelKk: 'Шығарылу түрі',
      kind: AttrKind.chips,
      options: [
        'Таблетки',
        'Капсулы',
        'Сироп',
        'Капли',
        'Мазь',
        'Гель',
        'Спрей',
        'Порошок'
      ],
    ),
    _packQty,
    AttrDef(
      key: 'prescription',
      labelRu: 'Отпуск',
      labelKk: 'Берілуі',
      kind: AttrKind.chips,
      options: ['Без рецепта', 'По рецепту'],
    ),
    _bestBefore,
  ],

  // ── Электроника ───────────────────────────────────────────────────────────
  'electronics': [
    AttrDef(
      key: 'model',
      labelRu: 'Модель',
      labelKk: 'Моделі',
      kind: AttrKind.text,
      hintRu: 'Напр: WH-1000XM5',
      hintKk: 'Мыс: WH-1000XM5',
      maxLength: 50,
    ),
    _condition,
    _warranty,
    AttrDef(
      key: 'screen_inch',
      labelRu: 'Диагональ',
      labelKk: 'Диагоналы',
      kind: AttrKind.number,
      unitRu: '″',
      unitKk: '″',
      decimal: true,
      hintRu: 'Для ТВ и проекторов',
      hintKk: 'ТВ мен проекторға',
      maxDigits: 5,
    ),
    AttrDef(
      key: 'connection',
      labelRu: 'Подключение',
      labelKk: 'Қосылуы',
      kind: AttrKind.multiChips,
      options: ['Bluetooth', 'Wi-Fi', 'Проводное', 'USB-C', 'HDMI'],
    ),
    AttrDef(
      key: 'power_w',
      labelRu: 'Мощность',
      labelKk: 'Қуаты',
      kind: AttrKind.number,
      unitRu: 'Вт',
      unitKk: 'Вт',
      maxDigits: 5,
    ),
  ],
  // Жады — бұл категорияда РАЗМЕР осі (sizes), сондықтан мұнда қайталанбайды.
  'phones': [
    AttrDef(
      key: 'condition',
      labelRu: 'Состояние',
      labelKk: 'Жағдайы',
      kind: AttrKind.chips,
      options: _kCondition,
      required: true,
      showOnCard: true,
    ),
    AttrDef(
      key: 'ram_gb',
      labelRu: 'Оперативная память',
      labelKk: 'Жедел жады',
      kind: AttrKind.chips,
      options: ['2 ГБ', '3 ГБ', '4 ГБ', '6 ГБ', '8 ГБ', '12 ГБ', '16 ГБ'],
      translateOptions: false,
    ),
    AttrDef(
      key: 'sim',
      labelRu: 'SIM-карты',
      labelKk: 'SIM-карталар',
      kind: AttrKind.chips,
      options: ['1 SIM', '2 SIM', 'SIM + eSIM', 'eSIM'],
      translateOptions: false,
    ),
    _warranty,
    AttrDef(
      key: 'compatibility',
      labelRu: 'Совместимость',
      labelKk: 'Сәйкестігі',
      kind: AttrKind.text,
      hintRu: 'Для чехлов и зарядок: iPhone 15',
      hintKk: 'Чехол мен зарядқа: iPhone 15',
      maxLength: 60,
    ),
  ],
  'computers': [
    AttrDef(
      key: 'processor',
      labelRu: 'Процессор',
      labelKk: 'Процессор',
      kind: AttrKind.text,
      hintRu: 'Напр: Intel Core i5-12450H',
      hintKk: 'Мыс: Intel Core i5-12450H',
      maxLength: 50,
    ),
    AttrDef(
      key: 'ram_gb',
      labelRu: 'Оперативная память',
      labelKk: 'Жедел жады',
      kind: AttrKind.chips,
      options: ['4 ГБ', '8 ГБ', '16 ГБ', '32 ГБ', '64 ГБ'],
      translateOptions: false,
      showOnCard: true,
    ),
    AttrDef(
      key: 'storage',
      labelRu: 'Накопитель',
      labelKk: 'Жинақтағыш',
      kind: AttrKind.chips,
      options: ['128 ГБ', '256 ГБ', '512 ГБ', '1 ТБ', '2 ТБ'],
      translateOptions: false,
    ),
    AttrDef(
      key: 'screen_inch',
      labelRu: 'Диагональ',
      labelKk: 'Диагоналы',
      kind: AttrKind.number,
      unitRu: '″',
      unitKk: '″',
      decimal: true,
      maxDigits: 4,
    ),
    _condition,
    _warranty,
  ],
  'appliances': [
    AttrDef(
      key: 'power_w',
      labelRu: 'Мощность',
      labelKk: 'Қуаты',
      kind: AttrKind.number,
      unitRu: 'Вт',
      unitKk: 'Вт',
      maxDigits: 5,
    ),
    AttrDef(
      key: 'energy_class',
      labelRu: 'Класс энергопотребления',
      labelKk: 'Энергия класы',
      kind: AttrKind.chips,
      options: ['A+++', 'A++', 'A+', 'A', 'B', 'C'],
      translateOptions: false,
    ),
    AttrDef(
      key: 'volume_l',
      labelRu: 'Объём',
      labelKk: 'Көлемі',
      kind: AttrKind.number,
      unitRu: 'л',
      unitKk: 'л',
      decimal: true,
      hintRu: 'Холодильник, чайник, стиральная',
      hintKk: 'Тоңазытқыш, шәйнек, кір жуғыш',
      maxDigits: 5,
    ),
    _dimensions,
    _warranty,
  ],

  // ── Үй ────────────────────────────────────────────────────────────────────
  'furniture': [
    // Жиһазды өлшемін білмей ешкім алмайды — жалғыз міндетті өріс.
    AttrDef(
      key: 'dimensions',
      labelRu: 'Размеры (Ш×В×Г)',
      labelKk: 'Өлшемдері (Е×Б×Т)',
      kind: AttrKind.text,
      hintRu: 'Напр: 200×90×95 см',
      hintKk: 'Мыс: 200×90×95 см',
      maxLength: 40,
      required: true,
      showOnCard: true,
    ),
    AttrDef(
      key: 'assembly',
      labelRu: 'Сборка',
      labelKk: 'Құрастыру',
      kind: AttrKind.chips,
      options: ['Требуется сборка', 'Собрано'],
    ),
    AttrDef(
      key: 'room',
      labelRu: 'Комната',
      labelKk: 'Бөлме',
      kind: AttrKind.multiChips,
      options: [
        'Гостиная',
        'Спальня',
        'Кухня',
        'Детская комната',
        'Прихожая',
        'Ванная',
        'Офис'
      ],
    ),
    AttrDef(
      key: 'max_load_kg',
      labelRu: 'Макс. нагрузка',
      labelKk: 'Ең көп жүктеме',
      kind: AttrKind.number,
      unitRu: 'кг',
      unitKk: 'кг',
      maxDigits: 4,
    ),
  ],
  'textile': [
    AttrDef(
      key: 'dimensions',
      labelRu: 'Размеры',
      labelKk: 'Өлшемдері',
      kind: AttrKind.text,
      hintRu: 'Напр: 200×220 см',
      hintKk: 'Мыс: 200×220 см',
      maxLength: 40,
    ),
    AttrDef(
      key: 'composition',
      labelRu: 'Состав',
      labelKk: 'Құрамы',
      kind: AttrKind.text,
      hintRu: 'Напр: 100% хлопок',
      hintKk: 'Мыс: 100% мақта',
      maxLength: 60,
    ),
    AttrDef(
      key: 'pillowcase',
      labelRu: 'Наволочки',
      labelKk: 'Жастық тыстары',
      kind: AttrKind.chips,
      options: ['50×70', '70×70', 'Без наволочек'],
    ),
    AttrDef(
      key: 'density_gsm',
      labelRu: 'Плотность',
      labelKk: 'Тығыздығы',
      kind: AttrKind.number,
      unitRu: 'г/м²',
      unitKk: 'г/м²',
      maxDigits: 4,
    ),
  ],
  'dishes': [
    AttrDef(
      key: 'set_size',
      labelRu: 'Предметов в наборе',
      labelKk: 'Жиынтықтағы зат саны',
      kind: AttrKind.number,
      unitRu: 'шт.',
      unitKk: 'дана',
      maxDigits: 3,
    ),
    AttrDef(
      key: 'volume_l',
      labelRu: 'Объём',
      labelKk: 'Көлемі',
      kind: AttrKind.number,
      unitRu: 'л',
      unitKk: 'л',
      decimal: true,
      hintRu: 'Напр: 0.35 для кружки',
      hintKk: 'Мыс: кесеге 0.35',
      maxDigits: 5,
    ),
    AttrDef(
      key: 'stove',
      labelRu: 'Для плит',
      labelKk: 'Плитаға',
      kind: AttrKind.multiChips,
      options: ['Газ', 'Электро', 'Индукция', 'Стеклокерамика'],
    ),
    AttrDef(
      key: 'dishwasher',
      labelRu: 'Посудомойка',
      labelKk: 'Ыдыс жуғыш',
      kind: AttrKind.chips,
      options: ['Можно', 'Нельзя'],
    ),
  ],
  'home': [
    _dimensions,
    AttrDef(
      key: 'power_source',
      labelRu: 'Питание',
      labelKk: 'Қуат көзі',
      kind: AttrKind.chips,
      options: ['Сеть 220 В', 'Батарейки', 'USB', 'Аккумуляторный'],
      hintRu: 'Для светильников и приборов',
      hintKk: 'Шам мен құрылғыларға',
    ),
    AttrDef(
      key: 'set_size',
      labelRu: 'Предметов в наборе',
      labelKk: 'Жиынтықтағы зат саны',
      kind: AttrKind.number,
      unitRu: 'шт.',
      unitKk: 'дана',
      maxDigits: 3,
    ),
  ],
  'garden': [
    AttrDef(
      key: 'power_source',
      labelRu: 'Питание',
      labelKk: 'Қуат көзі',
      kind: AttrKind.chips,
      options: _kPowerSource,
    ),
    _dimensions,
    AttrDef(
      key: 'pack_weight_g',
      labelRu: 'Вес упаковки',
      labelKk: 'Қаптама салмағы',
      kind: AttrKind.number,
      unitRu: 'г',
      unitKk: 'г',
      hintRu: 'Для семян и удобрений',
      hintKk: 'Тұқым мен тыңайтқышқа',
      maxDigits: 6,
    ),
  ],
  'tools': [
    AttrDef(
      key: 'power_source',
      labelRu: 'Питание',
      labelKk: 'Қуат көзі',
      kind: AttrKind.chips,
      options: _kPowerSource,
      showOnCard: true,
    ),
    AttrDef(
      key: 'power_w',
      labelRu: 'Мощность',
      labelKk: 'Қуаты',
      kind: AttrKind.number,
      unitRu: 'Вт',
      unitKk: 'Вт',
      maxDigits: 5,
    ),
    AttrDef(
      key: 'battery_v',
      labelRu: 'Напряжение аккумулятора',
      labelKk: 'Аккумулятор кернеуі',
      kind: AttrKind.number,
      unitRu: 'В',
      unitKk: 'В',
      maxDigits: 3,
    ),
    _warranty,
  ],

  // ── Басқа ─────────────────────────────────────────────────────────────────
  'auto': [
    AttrDef(
      key: 'compatibility',
      labelRu: 'Подходит для авто',
      labelKk: 'Қай көлікке',
      kind: AttrKind.text,
      hintRu: 'Напр: Toyota Camry 2018–2023',
      hintKk: 'Мыс: Toyota Camry 2018–2023',
      maxLength: 80,
    ),
    _condition,
    AttrDef(
      key: 'tire_size',
      labelRu: 'Размер шин / дисков',
      labelKk: 'Дөңгелек / диск өлшемі',
      kind: AttrKind.text,
      hintRu: 'Напр: 205/55 R16',
      hintKk: 'Мыс: 205/55 R16',
      maxLength: 20,
    ),
    AttrDef(
      key: 'tire_season',
      labelRu: 'Сезонность шин',
      labelKk: 'Дөңгелек маусымы',
      kind: AttrKind.chips,
      options: ['Летние', 'Зимние', 'Всесезонные'],
    ),
    AttrDef(
      key: 'volume_l',
      labelRu: 'Объём',
      labelKk: 'Көлемі',
      kind: AttrKind.number,
      unitRu: 'л',
      unitKk: 'л',
      decimal: true,
      hintRu: 'Для масел и автохимии',
      hintKk: 'Май мен автохимияға',
      maxDigits: 4,
    ),
  ],
  'pets': [
    // Қай жануарға — онсыз сатып алушы шеше алмайды.
    AttrDef(
      key: 'pet_kind',
      labelRu: 'Для кого',
      labelKk: 'Қай жануарға',
      kind: AttrKind.multiChips,
      options: ['Собаки', 'Кошки', 'Птицы', 'Грызуны', 'Рыбы', 'Рептилии'],
      required: true,
      showOnCard: true,
    ),
    AttrDef(
      key: 'pet_age',
      labelRu: 'Возраст питомца',
      labelKk: 'Жануар жасы',
      kind: AttrKind.chips,
      options: [
        'Для малышей',
        'Для взрослых',
        'Для пожилых',
        'Для всех возрастов'
      ],
    ),
    AttrDef(
      key: 'pet_size',
      labelRu: 'Размер породы',
      labelKk: 'Тұқым өлшемі',
      kind: AttrKind.chips,
      options: ['Мелкие породы', 'Средние породы', 'Крупные породы'],
    ),
    AttrDef(
      key: 'net_weight_kg',
      labelRu: 'Вес',
      labelKk: 'Салмағы',
      kind: AttrKind.number,
      unitRu: 'кг',
      unitKk: 'кг',
      decimal: true,
      hintRu: 'Для корма и наполнителя',
      hintKk: 'Жем мен толтырғышқа',
      maxDigits: 5,
    ),
  ],
  'books': [
    AttrDef(
      key: 'author',
      labelRu: 'Автор',
      labelKk: 'Авторы',
      kind: AttrKind.text,
      hintRu: 'Напр: Абай Кунанбаев',
      hintKk: 'Мыс: Абай Құнанбайұлы',
      maxLength: 80,
      showOnCard: true,
    ),
    // Қазақстанда кітапты тіліне қарап алады — жалғыз міндетті өріс.
    AttrDef(
      key: 'language',
      labelRu: 'Язык',
      labelKk: 'Тілі',
      kind: AttrKind.chips,
      options: ['Казахский', 'Русский', 'Английский', 'Другой'],
      required: true,
    ),
    AttrDef(
      key: 'cover',
      labelRu: 'Переплёт',
      labelKk: 'Мұқабасы',
      kind: AttrKind.chips,
      options: ['Твёрдый переплёт', 'Мягкий переплёт'],
    ),
    AttrDef(
      key: 'pages',
      labelRu: 'Страниц',
      labelKk: 'Беті',
      kind: AttrKind.number,
      unitRu: 'стр.',
      unitKk: 'бет',
      maxDigits: 5,
    ),
    AttrDef(
      key: 'publisher',
      labelRu: 'Издательство',
      labelKk: 'Баспасы',
      kind: AttrKind.text,
      maxLength: 60,
    ),
    AttrDef(
      key: 'year',
      labelRu: 'Год издания',
      labelKk: 'Шыққан жылы',
      kind: AttrKind.number,
      maxDigits: 4,
    ),
  ],
  'stationery': [
    _packQty,
    AttrDef(
      key: 'sheets',
      labelRu: 'Листов',
      labelKk: 'Парақ саны',
      kind: AttrKind.number,
      unitRu: 'л.',
      unitKk: 'парақ',
      hintRu: 'Для тетрадей и бумаги',
      hintKk: 'Дәптер мен қағазға',
      maxDigits: 4,
    ),
    AttrDef(
      key: 'ruling',
      labelRu: 'Линовка',
      labelKk: 'Сызылуы',
      kind: AttrKind.chips,
      options: ['Клетка', 'Линейка', 'Без линовки', 'Точки'],
    ),
    AttrDef(
      key: 'paper_format',
      labelRu: 'Формат',
      labelKk: 'Пішімі',
      kind: AttrKind.chips,
      options: ['A3', 'A4', 'A5', 'A6'],
      translateOptions: false,
    ),
  ],
  'grocery': [
    AttrDef(
      key: 'net_weight',
      labelRu: 'Вес / объём',
      labelKk: 'Салмағы / көлемі',
      kind: AttrKind.text,
      hintRu: 'Напр: 500 г или 1 л',
      hintKk: 'Мыс: 500 г немесе 1 л',
      maxLength: 20,
      showOnCard: true,
    ),
    _bestBefore,
    AttrDef(
      key: 'storage',
      labelRu: 'Хранение',
      labelKk: 'Сақталуы',
      kind: AttrKind.chips,
      options: ['Комнатная температура', 'В холодильнике', 'В морозилке'],
    ),
    AttrDef(
      key: 'halal',
      labelRu: 'Халал',
      labelKk: 'Халал',
      kind: AttrKind.chips,
      options: ['Халал'],
    ),
  ],
};

/// Категорияға қай ортақ өріс керек. Тізімде жоқ кілт (ескі/белгісіз) —
/// [_kDefaultVisibility]: бәрі көрінеді, бұрынғыдай.
///
/// Маусым ТЕК киім-кешек, аксессуар, спорт және балалар тауарларында: тоңазытқыш
/// пен кітаптың «маусымы» болмайды. Түс — сатып алушы түсіне қарап таңдайтын
/// жерде ғана; кітап, азық-түлік, дәрі, кеңсе, авто, құрал, бақша, жем — түссіз.
/// Әшекейде түстің орнын металл, сұлулықта — реңк өрісі алады.
const Map<String, CategoryVisibility> kCategoryVisibility = {
  'shoes': _wear,
  'tshirt': _wear,
  'outer': _wear,
  'pants': _wear,
  'dress': _wear,
  'caps': _wear,
  'underwear': _wear,
  'acc': _wear,
  'sport': _wear,
  'kids': _wear,
  'jewelry': CategoryVisibility(
      needsColor: false, needsSeason: false, needsMaterial: false),
  'toys': CategoryVisibility(
      needsColor: false, needsSeason: false, needsMaterial: true),
  'beauty': _plain,
  'pharmacy': _plain,
  'electronics': _colored,
  'phones': _colored,
  'computers': _colored,
  'appliances': _colored,
  'furniture': _colored,
  'textile': _colored,
  'dishes': _colored,
  'home': _colored,
  'garden': _uncolored,
  'tools': _uncolored,
  'auto': _uncolored,
  'pets': _uncolored,
  // Переплёт — енді «Переплёт» сипаттамасы, материал керек емес.
  'books': _plain,
  'stationery': _uncolored,
  'grocery': _plain,
};

const CategoryVisibility _wear = CategoryVisibility(
    needsColor: true, needsSeason: true, needsMaterial: true);
const CategoryVisibility _colored = CategoryVisibility(
    needsColor: true, needsSeason: false, needsMaterial: true);
const CategoryVisibility _uncolored = CategoryVisibility(
    needsColor: false, needsSeason: false, needsMaterial: true);
const CategoryVisibility _plain = CategoryVisibility(
    needsColor: false, needsSeason: false, needsMaterial: false);
const CategoryVisibility _kDefaultVisibility = _wear;

/// Категорияның форма ережесі (null/белгісіз → бәрі көрінеді). Материал
/// [kMaterialsByCategory]-де тізімі жоқ болса әрқашан жасырын.
CategoryVisibility visibilityFor(String? categoryKey) {
  final v = kCategoryVisibility[categoryKey] ?? _kDefaultVisibility;
  final hasMaterials =
      (kMaterialsByCategory[categoryKey] ?? const <String>[]).isNotEmpty;
  if (v.needsMaterial && !hasMaterials) {
    return CategoryVisibility(
        needsColor: v.needsColor,
        needsSeason: v.needsSeason,
        needsMaterial: false);
  }
  return v;
}

/// Категорияның сипаттамалары (белгісіз → бос тізім).
List<AttrDef> attributesFor(String? categoryKey) =>
    kCategoryAttributes[categoryKey] ?? const <AttrDef>[];

/// Категориядағы бір сипаттаманың анықтамасы (жоқ болса null).
AttrDef? attrDefFor(String? categoryKey, String key) {
  for (final d in attributesFor(categoryKey)) {
    if (d.key == key) return d;
  }
  return null;
}

/// Сан көрсетілімі: бүтін болса «.0»-сыз, әйтпесе ең көбі 2 таңба.
String formatAttrNumber(num n) {
  if (n == n.roundToDouble()) return n.round().toString();
  var s = n.toStringAsFixed(2);
  while (s.endsWith('0')) {
    s = s.substring(0, s.length - 1);
  }
  return s;
}

/// Мән бар ма (бос жол/бос тізім/null — жоқ).
bool hasAttrValue(Object? v) {
  if (v == null) return false;
  if (v is String) return v.trim().isNotEmpty;
  if (v is Iterable) return v.any((e) => e.toString().trim().isNotEmpty);
  if (v is num) return v.isFinite;
  return true;
}

/// Мәнді схема түріне келтіреді; бос/жарамсыз → null.
///  * chips — жол (тізімде жоқ ескі мән де сақталады: дерек жоғалмасын);
///  * multiChips — қайталанбайтын жолдар, опциялар ретімен, белгісіздер соңында;
///  * text — қиылған жол; number — шекті, теріс емес сан (decimal=false → бүтін).
Object? normalizeAttrValue(AttrDef d, Object? raw) {
  switch (d.kind) {
    case AttrKind.chips:
      final s = raw is String ? raw.trim() : (raw is num ? '$raw' : '');
      if (s.isEmpty) return null;
      return s.length > 60 ? s.substring(0, 60) : s;
    case AttrKind.multiChips:
      final items = raw is Iterable
          ? raw.map((e) => e.toString().trim())
          : raw is String
              ? [raw.trim()]
              : const <String>[];
      final seen = <String>{
        for (final s in items)
          if (s.isNotEmpty) s
      };
      if (seen.isEmpty) return null;
      return <String>[
        for (final o in d.options)
          if (seen.contains(o)) o,
        for (final s in seen)
          if (!d.options.contains(s)) s.length > 60 ? s.substring(0, 60) : s,
      ];
    case AttrKind.text:
      final s = raw is String ? raw.trim() : (raw is num ? '$raw' : '');
      if (s.isEmpty) return null;
      return s.length > d.maxLength ? s.substring(0, d.maxLength) : s;
    case AttrKind.number:
      final n = parseAttrNumber(raw, decimal: d.decimal);
      return n;
  }
}

/// Өрістегі мәтінді не JSON санын санға айналдырады ('15,6' → 15.6).
/// Теріс, шексіз не бос → null. decimal=false → бүтін (int).
num? parseAttrNumber(Object? raw, {bool decimal = false}) {
  num? n;
  if (raw is num) {
    n = raw;
  } else if (raw is String) {
    n = num.tryParse(raw.trim().replaceAll(',', '.'));
  }
  if (n == null || !n.isFinite || n < 0) return null;
  if (!decimal) return n.round();
  if (n == n.roundToDouble()) return n.round();
  return double.parse(n.toStringAsFixed(2));
}

/// DB шегі (0085: pg_column_size ≤ 4096). JSON мәтінімен 3500 байтқа дейін
/// ұстаймыз — jsonb басы мен Unicode-қа қор қалсын.
const int kAttributesMaxBytes = 3500;

/// Сақтауға дайын объект: схема кілттері түріне келтіріледі, бос мәндер
/// алынады. Схемада жоқ кілттер (ескі нұсқадан қалған) жоғалмайды — қарапайым
/// мәндері сақталады. Шектен асса, алдымен белгісіз кілттер түсіріледі.
Map<String, dynamic> sanitizeAttributes(
    String? categoryKey, Map<String, dynamic>? raw) {
  if (raw == null || raw.isEmpty) return {};
  final out = <String, dynamic>{};
  final defs = attributesFor(categoryKey);
  for (final d in defs) {
    final v = normalizeAttrValue(d, raw[d.key]);
    if (v != null) out[d.key] = v;
  }
  final unknown = <String>[];
  raw.forEach((k, v) {
    if (out.containsKey(k) || defs.any((d) => d.key == k)) return;
    if (k.isEmpty || k.length > 40 || !hasAttrValue(v)) return;
    if (v is String) {
      out[k] = v.trim().length > 80 ? v.trim().substring(0, 80) : v.trim();
    } else if (v is num || v is bool) {
      out[k] = v;
    } else if (v is Iterable) {
      out[k] = [
        for (final e in v)
          if (e.toString().trim().isNotEmpty) e.toString().trim()
      ];
    } else {
      return;
    }
    unknown.add(k);
  });
  while (attributesByteSize(out) > kAttributesMaxBytes && unknown.isNotEmpty) {
    out.remove(unknown.removeLast());
  }
  return out;
}

/// JSON түріндегі байт өлшемі (DB шегін алдын ала тексеру үшін).
int attributesByteSize(Map<String, dynamic> attrs) =>
    utf8.encode(jsonEncode(attrs)).length;

/// Толтырылмаған міндетті сипаттамалар (форма тексерісі үшін).
List<AttrDef> missingRequiredAttributes(
        String? categoryKey, Map<String, dynamic> attrs) =>
    [
      for (final d in attributesFor(categoryKey))
        if (d.required && normalizeAttrValue(d, attrs[d.key]) == null) d
    ];

/// Көрсетуге дайын жолдар: схема ретімен, тек толтырылғандары. Схемада жоқ
/// кілттер көрсетілмейді (аудармасы жоқ ішкі кілтті клиентке шығармаймыз).
List<({AttrDef def, String label, String value})> displayAttributes(
    String? categoryKey, Map<String, dynamic> attrs) {
  if (attrs.isEmpty) return const [];
  return [
    for (final d in attributesFor(categoryKey))
      if (d.valueLabel(attrs[d.key]).isNotEmpty)
        (def: d, label: d.label, value: d.valueLabel(attrs[d.key])),
  ];
}

/// Карточкадағы қысқа белгі ([AttrDef.showOnCard] өрісінің мәні) не null.
String? cardAttributeLabel(String? categoryKey, Map<String, dynamic> attrs) {
  for (final d in attributesFor(categoryKey)) {
    if (!d.showOnCard) continue;
    final v = d.valueLabel(attrs[d.key]);
    return v.isEmpty ? null : v;
  }
  return null;
}

/// Сипаттамаларды іздеу/AI үшін бір жолға жинайды: «Автор: X; Язык: Русский».
/// Канондық мәндер орысша (AI мен іздеу буфері орысша ақпаратты күтеді).
String attributesSummaryRu(String? categoryKey, Map<String, dynamic> attrs) {
  final parts = <String>[];
  for (final d in attributesFor(categoryKey)) {
    final v = normalizeAttrValue(d, attrs[d.key]);
    if (v == null) continue;
    final text = switch (d.kind) {
      AttrKind.multiChips => (v as List<String>).join(', '),
      AttrKind.number => d.unitRu.isEmpty
          ? formatAttrNumber(v as num)
          : '${formatAttrNumber(v as num)} ${d.unitRu}',
      _ => v.toString(),
    };
    parts.add('${d.labelRu}: $text');
  }
  return parts.join('; ');
}
