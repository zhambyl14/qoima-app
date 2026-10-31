import '../../../core/lang.dart';
import '../../../data/models/product_model.dart';

/// Киіп көру түрі. [wire] — серверге/ережелер кестесіне жазылатын мән
/// (supabase/functions/virtual-tryon `TryOnKind` ДӘЛ осындай).
enum TryOnKind {
  tops('tops'),
  bottoms('bottoms'),
  onePieces('one-pieces'),
  auto('auto'),
  footwear('footwear'),
  headwear('headwear'),
  eyewear('eyewear'),
  bag('bag'),
  jewelry('jewelry'),
  watch('watch'),
  accessory('accessory');

  final String wire;
  const TryOnKind(this.wire);

  /// FASHN (tryon-v1.6) тек киімді біледі: tops/bottoms/one-pieces/auto.
  /// Қалғаны (аяқ киім, бас киім, көзілдірік, сөмке, әшекей, сағат) тек
  /// Gemini сурет моделімен жасалады — сервер сол жаққа бағыттайды.
  bool get fashnSupported => index <= TryOnKind.auto.index;
}

/// Бір категорияның ережесі: [all] — барлық түрге әдепкі шешім (null = жарамайды,
/// «Свой вариант» түрі де осыған түседі), [types] — нақты түрге ерекшелік.
class TryOnRule {
  final TryOnKind? all;
  final Map<String, TryOnKind?> types;
  const TryOnRule(this.all, [this.types = const {}]);

  TryOnKind? kindFor(String type) =>
      types.containsKey(type) ? types[type] : all;
}

/// ЕРЕЖЕЛЕР КЕСТЕСІ — барлық 29 категория, әрқайсысы нақты көрсетілген.
/// Сервердегі `TRYON_RULES` (supabase/functions/virtual-tryon/index.ts) осының
/// дәл көшірмесі — екеуін БІР коммитте өзгерту керек; test/try_on_eligibility_test.dart
/// екі кестені салыстырып, алшақтаса құлайды.
///
/// Негіз: денеге/бетке киюге болатын және фотода «кигізгенде» мағына беретін
/// тауар ғана. Электроника, азық-түлік, кітап, жиһаз т.б. — киілмейді.
/// Балалар (аудитория «Детские», категория kids) — ЕШҚАШАН: кәмелетке
/// толмағандардың суреті үшінші тарап AI-ына берілмейді.
const Map<String, TryOnRule> kTryOnRules = {
  // ── Мода: киілетін ──
  // Аяқ киім: барлық түрі (туфли…сланцы). Тек Gemini; фотода аяқ көрінуі керек.
  'shoes': TryOnRule(TryOnKind.footwear),
  'tshirt': TryOnRule(TryOnKind.tops), // жейде, поло, лонгслив…
  'outer': TryOnRule(TryOnKind.tops), // куртка, пальто, худи, жилет…
  'pants': TryOnRule(TryOnKind.bottoms), // джинсы, шорты, леггинсы…
  // Көйлек/юбка: түрі нақты болса — дәл категория, «Свой вариант» — auto.
  'dress': TryOnRule(TryOnKind.auto, {
    'Юбка': TryOnKind.bottoms,
    'Платье': TryOnKind.onePieces,
    'Сарафан': TryOnKind.onePieces,
    'Костюм': TryOnKind.onePieces,
  }),
  'caps': TryOnRule(TryOnKind.headwear), // кепка, шапка, панама…
  // Іш киім: модерация бұғаттайды және жеке өмірге тым сезімтал — жоқ.
  'underwear': TryOnRule(null),
  // Аксессуарлар: сөмке/рюкзак/көзілдірік/белдік/қолғап/шарф киіледі немесе
  // көтеріледі; әмиян киілмейді. «Свой вариант» — жалпы accessory.
  'acc': TryOnRule(TryOnKind.accessory, {
    'Сумка': TryOnKind.bag,
    'Рюкзак': TryOnKind.bag,
    'Очки': TryOnKind.eyewear,
    'Кошелек': null,
  }),
  // Әшекей: сақина, сырға, шынжыр, білезік, кулон, сағат — барлығы киіледі.
  'jewelry': TryOnRule(TryOnKind.jewelry, {'Часы': TryOnKind.watch}),
  // Спорт: тек киім түрлері; тренажёр/велосипед/палатка/мяч — жабдық.
  'sport': TryOnRule(null, {
    'Спортивный костюм': TryOnKind.onePieces,
    'Топ': TryOnKind.tops,
    'Леггинсы': TryOnKind.bottoms,
    'Шорты': TryOnKind.bottoms,
  }),
  // ── Балалар: ЕШҚАШАН (кәмелетке толмағандар) ──
  'kids': TryOnRule(null),
  'toys': TryOnRule(null), // киілмейді
  // ── Сұлулық/денсаулық ──
  'beauty': TryOnRule(null), // макияж/парфюм — киім емес, модель қолдамайды
  // Оптика (линза+көзілдірік қоспасы) анық емес, көзілдірік «Аксессуарлар»-да.
  'pharmacy': TryOnRule(null),
  // ── Электроника: киілмейді (смарт-сағаттан басқасы) ──
  'electronics': TryOnRule(null),
  'phones': TryOnRule(null, {'Смарт-часы': TryOnKind.watch}),
  'computers': TryOnRule(null),
  'appliances': TryOnRule(null),
  // ── Үй, бақша, құрал, авто, жануар, кітап, кеңсе, азық: киілмейді ──
  'furniture': TryOnRule(null),
  'textile': TryOnRule(null),
  'dishes': TryOnRule(null),
  'home': TryOnRule(null),
  'garden': TryOnRule(null),
  'tools': TryOnRule(null),
  'auto': TryOnRule(null),
  'pets': TryOnRule(null),
  'books': TryOnRule(null),
  'stationery': TryOnRule(null),
  'grocery': TryOnRule(null),
};

/// Тауарға қолданылатын киіп көру түрі немесе null (жарамайды).
/// [categoryKey] бос болса — ескі тауар → 'shoes' (ProductModel.effectiveCategoryKey).
/// [audience] — тауардың `category` өрісі («Мужские/Женские/Унисекс/Детские»).
TryOnKind? tryOnKindFor({
  required String categoryKey,
  required String type,
  required String audience,
}) {
  if (audience.startsWith('Детские')) return null; // кәмелетке толмағандар
  final rule = kTryOnRules[categoryKey.isEmpty ? 'shoes' : categoryKey];
  return rule?.kindFor(type.trim());
}

/// Сервер https емес суретті қабылдамайды (SSRF), сондықтан клиент те солай.
bool hasTryOnImage(ProductModel p) =>
    p.images.any((u) => u.startsWith('https://'));

/// Онлайн киіп көруге жарайтын тауар ма.
///
/// Ереже серверді (supabase/functions/virtual-tryon `tryOnKindFor`) ДӘЛ
/// қайталайды. Суреті жоқ тауарда түймені жасырамыз: көрсетсек, басқанда
/// сервер not_eligible қайтарар еді.
bool isTryOnEligible(ProductModel p) =>
    hasTryOnImage(p) &&
    tryOnKindFor(
          categoryKey: p.effectiveCategoryKey,
          type: p.type,
          audience: p.category,
        ) !=
        null;

/// Фотоға қысқа кеңес: қай дене бөлігі көрінуі керек (түрге қарай).
String tryOnFramingTip(TryOnKind? k) {
  switch (k) {
    case TryOnKind.footwear:
      return tr('Фото в полный рост, ноги и обувь хорошо видны',
          'Толық бойымен, аяқ пен аяқ киім анық көрінсін');
    case TryOnKind.headwear:
    case TryOnKind.eyewear:
      return tr('Фото лица крупным планом, голова не обрезана',
          'Бет жақын планмен, бас кесілмесін');
    case TryOnKind.jewelry:
      return tr('Фото крупным планом: лицо, шея и уши видны',
          'Жақын планмен: бет, мойын және құлақ көрінсін');
    case TryOnKind.watch:
      return tr(
          'Фото, где запястье хорошо видно', 'Білек анық көрінетін сурет');
    case TryOnKind.bag:
    case TryOnKind.accessory:
    case TryOnKind.tops:
    case TryOnKind.bottoms:
    case TryOnKind.onePieces:
    case TryOnKind.auto:
    case null:
      return tr('Фото в полный рост, стоя прямо',
          'Толық бойымен, түзу тұрып түскен сурет');
  }
}

/// «Образ құрастыру» үшін тауар жарай ма (ai-stylist `slotsFor`-пен сәйкес).
bool isLookEligible(ProductModel p) {
  switch (p.effectiveCategoryKey) {
    case 'shoes':
    case 'tshirt':
    case 'outer':
    case 'pants':
    case 'dress':
    case 'caps':
    case 'acc':
    case 'jewelry':
      return true;
    case 'sport':
      return const {'Спортивный костюм', 'Топ', 'Леггинсы', 'Шорты'}
          .contains(p.type);
    default:
      return false;
  }
}
