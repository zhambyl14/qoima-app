import '../../core/lang.dart';

/// Тауар сипаттамасына бір басып қосылатын дайын үлгілер (snippet).
///
/// Үлгілер — БАСТАМА мәтін: иесі «…» орындарын өз тауарына сай толтырады.
/// Ойдан факт қоспау үшін нақты құрам/кепілдік/күй/жеткізу сияқты мәліметтер
/// әдейі «…» болып қалдырылған. «…» қалса — сақтау алдында ескертіледі
/// ([hasUnfilledPlaceholder]).
///
/// Тіл: мәтін сипаттама ТІЛІНДЕ қосылады ([textFor]) — UI тілінде емес, өйткені
/// иесі қазақ интерфейсінде отырып орысша сипаттама жазуы мүмкін.
class DescriptionTemplate {
  final String titleRu, titleKk;
  final String textRu, textKk;
  const DescriptionTemplate({
    required this.titleRu,
    required this.titleKk,
    required this.textRu,
    required this.textKk,
  });

  /// Чиптегі атауы — UI тілінде.
  String get title => tr(titleRu, titleKk);

  /// Қосылатын мәтін — сипаттама тілінде ('kk' | 'ru').
  String textFor(String lang) => lang == 'kk' ? textKk : textRu;
}

// ── Барлық категорияға ортақ ────────────────────────────────────────────────
const List<DescriptionTemplate> _common = [
  DescriptionTemplate(
    titleRu: 'Получение заказа',
    titleKk: 'Тапсырысты алу',
    textRu:
        'Получение: … (самовывоз из магазина / доставка курьером — оставьте то, что доступно).',
    textKk:
        'Алу тәсілі: … (дүкеннен өзі алу / курьермен жеткізу — қолжетімдісін қалдырыңыз).',
  ),
  DescriptionTemplate(
    titleRu: 'Есть вопросы?',
    titleKk: 'Сұрақ бар ма?',
    textRu:
        'Остались вопросы по товару — напишите нам, ответим и пришлём дополнительные фото.',
    textKk:
        'Тауар бойынша сұрақтарыңыз болса — жазыңыз, жауап беріп, қосымша фото жібереміз.',
  ),
  DescriptionTemplate(
    titleRu: 'Цвет на фото',
    titleKk: 'Фотодағы түс',
    textRu:
        'Оттенок на фото может немного отличаться от реального из-за освещения и настроек экрана.',
    textKk:
        'Жарық пен экран баптауларына байланысты фотодағы реңк шынайы түстен сәл өзгеше болуы мүмкін.',
  ),
];

// ── Аяқ киім ────────────────────────────────────────────────────────────────
const List<DescriptionTemplate> _shoes = [
  DescriptionTemplate(
    titleRu: 'Размерная сетка',
    titleKk: 'Өлшем торы',
    textRu:
        'Размеры соответствуют стандартной сетке. Длина стельки: … см (размер …). Если сомневаетесь — напишите нам длину стопы, подскажем размер.',
    textKk:
        'Өлшемдер стандартты торға сай. Ұлтарақ ұзындығы: … см (… өлшем). Күмәнданып тұрсаңыз — аяғыңыздың ұзындығын жазыңыз, өлшемін айтып береміз.',
  ),
  DescriptionTemplate(
    titleRu: 'Материалы',
    titleKk: 'Материалдары',
    textRu: 'Верх: … Подкладка: … Подошва: …',
    textKk: 'Сырты: … Астары: … Табаны: …',
  ),
  DescriptionTemplate(
    titleRu: 'Уход за обувью',
    titleKk: 'Аяқ киім күтімі',
    textRu:
        'Уход: протирайте влажной тканью, сушите при комнатной температуре вдали от батареи.',
    textKk:
        'Күтімі: дымқыл шүберекпен сүртіңіз, батареядан алыс бөлме температурасында кептіріңіз.',
  ),
  DescriptionTemplate(
    titleRu: 'Удобная посадка',
    titleKk: 'Ыңғайлы отырысы',
    textRu: 'Стелька: … Колодка: … Подходит для: …',
    textKk: 'Ұлтарағы: … Қалыбы: … Жарайды: …',
  ),
];

// ── Киім (футболка, сырт киім, шалбар, көйлек, іш киім, спорт) ──────────────
const List<DescriptionTemplate> _clothing = [
  DescriptionTemplate(
    titleRu: 'Состав ткани',
    titleKk: 'Мата құрамы',
    textRu: 'Состав: …% хлопок, …% … Ткань приятная к телу.',
    textKk: 'Құрамы: …% мақта, …% … Мата денеге жағымды.',
  ),
  DescriptionTemplate(
    titleRu: 'Размер и посадка',
    titleKk: 'Өлшемі мен отырысы',
    textRu:
        'Посадка: … (свободная / по фигуре / оверсайз). Модель на фото: рост … см, размер … Размеры соответствуют стандартной сетке.',
    textKk:
        'Отырысы: … (кең / денеге қонымды / оверсайз). Фотодағы модель: бойы … см, өлшемі … Өлшемдер стандартты торға сай.',
  ),
  DescriptionTemplate(
    titleRu: 'Уход и стирка',
    titleKk: 'Күтімі мен жуу',
    textRu:
        'Уход: деликатная стирка при … °C, не отбеливать, гладить при низкой температуре.',
    textKk:
        'Күтімі: … °C-та нәзік режимде жуу, ағартпау, төмен температурада үтіктеу.',
  ),
  DescriptionTemplate(
    titleRu: 'С чем носить',
    titleKk: 'Немен киюге болады',
    textRu:
        'Легко сочетается с джинсами, брюками и кроссовками — подойдёт и на каждый день, и на прогулку.',
    textKk:
        'Джинсымен, шалбармен және кроссовкамен оңай үйлеседі — күнделікті де, серуенге де жарасады.',
  ),
];

// ── Сырт киім (қыс) ──────────────────────────────────────────────────────────
const List<DescriptionTemplate> _outer = [
  DescriptionTemplate(
    titleRu: 'Утеплитель и температура',
    titleKk: 'Жылытқышы мен температура',
    textRu: 'Утеплитель: … Рассчитана на температуру до … °C.',
    textKk: 'Жылытқышы: … Ұсынылатын температура: … °C-қа дейін.',
  ),
  DescriptionTemplate(
    titleRu: 'Детали',
    titleKk: 'Бөлшектері',
    textRu: 'Капюшон: … Застёжка: … Карманы: …',
    textKk: 'Күләпарасы: … Түймесі/сыдырмасы: … Қалталары: …',
  ),
];

// ── Бас киім, аксессуарлар ──────────────────────────────────────────────────
const List<DescriptionTemplate> _accessories = [
  DescriptionTemplate(
    titleRu: 'Размеры',
    titleKk: 'Өлшемдері',
    textRu: 'Размеры: … × … см. Регулируется: …',
    textKk: 'Өлшемдері: … × … см. Реттеледі: …',
  ),
  DescriptionTemplate(
    titleRu: 'Материал и фурнитура',
    titleKk: 'Материалы мен фурнитурасы',
    textRu: 'Материал: … Фурнитура: …',
    textKk: 'Материалы: … Фурнитурасы: …',
  ),
  DescriptionTemplate(
    titleRu: 'Отличный подарок',
    titleKk: 'Тамаша сыйлық',
    textRu: 'Хороший вариант для подарка — стильно и практично.',
    textKk: 'Сыйлыққа тамаша нұсқа — сәнді әрі практикалық.',
  ),
];

// ── Зергерлік бұйымдар ──────────────────────────────────────────────────────
const List<DescriptionTemplate> _jewelry = [
  DescriptionTemplate(
    titleRu: 'Металл и проба',
    titleKk: 'Металы мен сынамы',
    textRu: 'Металл: … Проба: … Вставка: …',
    textKk: 'Металы: … Сынамы: … Әшекей тасы: …',
  ),
  DescriptionTemplate(
    titleRu: 'Размер',
    titleKk: 'Өлшемі',
    textRu: 'Размер: … Вес: … г.',
    textKk: 'Өлшемі: … Салмағы: … г.',
  ),
  DescriptionTemplate(
    titleRu: 'Уход за украшением',
    titleKk: 'Әшекей күтімі',
    textRu:
        'Храните отдельно в мешочке, избегайте контакта с парфюмом и водой.',
    textKk: 'Бөлек қапшықта сақтаңыз, иіссу мен суға тигізбеңіз.',
  ),
];

// ── Балалар тауарлары, ойыншықтар ──────────────────────────────────────────
const List<DescriptionTemplate> _kids = [
  DescriptionTemplate(
    titleRu: 'Возраст',
    titleKk: 'Жасы',
    textRu: 'Рекомендуемый возраст: от … лет.',
    textKk: 'Ұсынылатын жасы: … жастан бастап.',
  ),
  DescriptionTemplate(
    titleRu: 'Безопасность',
    titleKk: 'Қауіпсіздігі',
    textRu:
        'Мелкие детали: … (есть / нет). Использовать под присмотром взрослых.',
    textKk:
        'Ұсақ бөлшектері: … (бар / жоқ). Үлкендердің қарауымен қолдану керек.',
  ),
  DescriptionTemplate(
    titleRu: 'Комплектация',
    titleKk: 'Жиынтығы',
    textRu: 'В комплекте: …',
    textKk: 'Жиынтықта: …',
  ),
];

// ── Сұлулық, дәріхана ──────────────────────────────────────────────────────
const List<DescriptionTemplate> _beauty = [
  DescriptionTemplate(
    titleRu: 'Объём и срок годности',
    titleKk: 'Көлемі мен жарамдылық мерзімі',
    textRu: 'Объём: … мл. Срок годности: до …',
    textKk: 'Көлемі: … мл. Жарамдылық мерзімі: … дейін.',
  ),
  DescriptionTemplate(
    titleRu: 'Способ применения',
    titleKk: 'Қолдану тәсілі',
    textRu: 'Способ применения: …',
    textKk: 'Қолдану тәсілі: …',
  ),
  DescriptionTemplate(
    titleRu: 'Для какого типа',
    titleKk: 'Қай түріне арналған',
    textRu: 'Подходит для … типа кожи / волос.',
    textKk: 'Терінің / шаштың … түріне жарайды.',
  ),
  DescriptionTemplate(
    titleRu: 'Хранение',
    titleKk: 'Сақтау',
    textRu: 'Хранить в сухом месте при температуре до … °C.',
    textKk: '… °C-қа дейінгі температурада құрғақ жерде сақтаңыз.',
  ),
];

// ── Электроника, телефондар, компьютерлер, тұрмыстық техника ───────────────
const List<DescriptionTemplate> _electronics = [
  DescriptionTemplate(
    titleRu: 'Характеристики',
    titleKk: 'Сипаттамалары',
    textRu: 'Модель: … Память: … Цвет: … Подключение: …',
    textKk: 'Моделі: … Жады: … Түсі: … Қосылуы: …',
  ),
  DescriptionTemplate(
    titleRu: 'Комплектация',
    titleKk: 'Жиынтығы',
    textRu: 'В комплекте: устройство, …, документация.',
    textKk: 'Жиынтықта: құрылғы, …, құжаттама.',
  ),
  DescriptionTemplate(
    titleRu: 'Состояние и гарантия',
    titleKk: 'Күйі мен кепілдігі',
    textRu: 'Состояние: … (новое / б/у). Упаковка: … Гарантия: …',
    textKk: 'Күйі: … (жаңа / қолданылған). Қаптамасы: … Кепілдігі: …',
  ),
  DescriptionTemplate(
    titleRu: 'Проверка при покупке',
    titleKk: 'Сатып алғанда тексеру',
    textRu:
        'Проверка при покупке: … (можно ли включить и проверить в магазине).',
    textKk: 'Сатып алғанда тексеру: … (дүкенде қосып тексеруге бола ма).',
  ),
];

// ── Үй: жиһаз, тоқыма, ыдыс, үй, бақ, құралдар ──────────────────────────────
const List<DescriptionTemplate> _home = [
  DescriptionTemplate(
    titleRu: 'Размеры',
    titleKk: 'Өлшемдері',
    textRu: 'Размеры: … × … × … см. Вес: … кг.',
    textKk: 'Өлшемдері: … × … × … см. Салмағы: … кг.',
  ),
  DescriptionTemplate(
    titleRu: 'Материал',
    titleKk: 'Материалы',
    textRu: 'Материал: … Цвет: …',
    textKk: 'Материалы: … Түсі: …',
  ),
  DescriptionTemplate(
    titleRu: 'Уход',
    titleKk: 'Күтімі',
    textRu:
        'Уход: … (можно мыть в посудомоечной машине / только ручная стирка).',
    textKk: 'Күтімі: … (ыдыс жуғыш машинада жууға болады / тек қолмен жуу).',
  ),
  DescriptionTemplate(
    titleRu: 'Сборка и комплект',
    titleKk: 'Құрастыру және жиынтық',
    textRu: 'В комплекте: … Сборка: …',
    textKk: 'Жиынтықта: … Құрастыру: …',
  ),
];

// ── Авто ────────────────────────────────────────────────────────────────────
const List<DescriptionTemplate> _auto = [
  DescriptionTemplate(
    titleRu: 'Совместимость',
    titleKk: 'Үйлесімділігі',
    textRu: 'Подходит для: … (марка, модель, год).',
    textKk: 'Жарайтын көліктер: … (маркасы, моделі, жылы).',
  ),
  DescriptionTemplate(
    titleRu: 'Параметры',
    titleKk: 'Параметрлері',
    textRu: 'Параметры: … Объём / размер: …',
    textKk: 'Параметрлері: … Көлемі / өлшемі: …',
  ),
];

// ── Үй жануарлары ──────────────────────────────────────────────────────────
const List<DescriptionTemplate> _pets = [
  DescriptionTemplate(
    titleRu: 'Для кого',
    titleKk: 'Кімге арналған',
    textRu: 'Подходит для: … (кошки / собаки, возраст, размер породы).',
    textKk: 'Жарайды: … (мысық / ит, жасы, тұқым өлшемі).',
  ),
  DescriptionTemplate(
    titleRu: 'Вес / размер',
    titleKk: 'Салмағы / өлшемі',
    textRu: 'Вес упаковки: … кг. Размер: …',
    textKk: 'Қаптама салмағы: … кг. Өлшемі: …',
  ),
];

// ── Кітаптар, кеңсе тауарлары ──────────────────────────────────────────────
const List<DescriptionTemplate> _books = [
  DescriptionTemplate(
    titleRu: 'Об издании',
    titleKk: 'Басылым туралы',
    textRu: 'Автор: … Издательство: … Год: … Страниц: … Язык: …',
    textKk: 'Авторы: … Баспасы: … Жылы: … Беті: … Тілі: …',
  ),
  DescriptionTemplate(
    titleRu: 'Формат',
    titleKk: 'Пішімі',
    textRu: 'Формат: … Переплёт: …',
    textKk: 'Пішімі: … Мұқабасы: …',
  ),
];

// ── Азық-түлік ─────────────────────────────────────────────────────────────
const List<DescriptionTemplate> _grocery = [
  DescriptionTemplate(
    titleRu: 'Состав и вес',
    titleKk: 'Құрамы мен салмағы',
    textRu: 'Состав: … Вес / объём: …',
    textKk: 'Құрамы: … Салмағы / көлемі: …',
  ),
  DescriptionTemplate(
    titleRu: 'Срок и хранение',
    titleKk: 'Мерзімі мен сақтау',
    textRu: 'Срок годности: до … Хранить при температуре …',
    textKk: 'Жарамдылық мерзімі: … дейін. … температурада сақтаңыз.',
  ),
];

/// Категория кілті → үлгілер тобы (category_data.dart кілттері).
const Map<String, List<DescriptionTemplate>> _byCategory = {
  'shoes': _shoes,
  'tshirt': _clothing,
  'pants': _clothing,
  'dress': _clothing,
  'underwear': _clothing,
  'sport': _clothing,
  'outer': [..._outer, ..._clothing],
  'caps': _accessories,
  'acc': _accessories,
  'jewelry': _jewelry,
  'kids': _kids,
  'toys': _kids,
  'beauty': _beauty,
  'pharmacy': _beauty,
  'electronics': _electronics,
  'phones': _electronics,
  'computers': _electronics,
  'appliances': _electronics,
  'furniture': _home,
  'textile': _home,
  'dishes': _home,
  'home': _home,
  'garden': _home,
  'tools': _home,
  'auto': _auto,
  'pets': _pets,
  'books': _books,
  'stationery': _books,
  'grocery': _grocery,
};

/// Категорияға сай үлгілер + ортақ үлгілер (жеткізу, сұрақ, түс).
/// Категория таңдалмаса — тек ортақтары.
List<DescriptionTemplate> descriptionTemplatesFor(String? categoryKey) => [
      ...?_byCategory[categoryKey ?? ''],
      ..._common,
    ];

/// Сипаттамада толтырылмаған «…» орны қалды ма (сақтау алдындағы ескерту үшін).
bool hasUnfilledPlaceholder(String text) => text.contains('…');
