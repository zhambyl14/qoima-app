// Алдын ала іздеу: қолданушының соңғы хабарламасынан СЕРВЕР жағында (LLM-сіз)
// сүзгілерді шығарып, search_catalog-ты бірден шақыруға мүмкіндік береді.
//
// Не үшін: бұрын «LLM → іздеу құралы → LLM» екі айналым болатын (≈6–15 с).
// Енді сұрау түсінікті болса (тауар түрі/санаты танылса) іздеу LLM-мен
// ПАРАЛЛЕЛЬ жүреді де, нәтиже модельге дайын беріледі, ал клиент карточкаларды
// бірден көреді. Түсінікті болмаса (null) — бұрынғы жол: LLM өзі іздейді.
//
// Принцип: recall емес PRECISION. Тек сенімді танылған сөздер ғана сүзгі болады;
// күмәнді сөз (мысалы «подарок мужу») → null. Таза модуль, Deno API жоқ.
import { AUDIENCE_CATEGORIES, TYPE_CATEGORIES } from "./catalog.ts";

export interface Prefilter {
  category_keys?: string[];
  types?: string[];
  audience?: string;
  season?: string;
  size?: string;
  min_price?: number;
  max_price?: number;
  query?: string;
}

interface Entry {
  re: RegExp; // бір токенге (толық сәйкестік)
  types?: string[];
  cats?: string[];
}

// Орыс сын есім жалғаулары.
const ADJ = "(?:ый|ий|ая|яя|ое|ее|ые|ие|ого|его|ой|ей|ую|юю|ым|им|ых|их)";

function e(src: string, types?: string[], cats?: string[]): Entry {
  return { re: new RegExp(`^(?:${src})$`, "u"), types, cats };
}

// Тауар түрлері мен санаттар. Типтер catalog.ts-тегі канондық мәнмен ДӘЛ бірдей
// болуы керек (тест тексереді). Қазақша түбірлер жалғаулармен (\p{L}*) келеді.
const TYPE_ENTRIES: Entry[] = [
  // shoes
  e("кроссов\\p{L}*|кроссы", ["Кроссовки"]),
  e("кед(?:ы|ов|ах|ам|ами)?|кедтер\\p{L}*", ["Кеды"]),
  e("туфл\\p{L}*|туфел\\p{L}*", ["Туфли"]),
  e("ботин\\p{L}*|боты|ботах", ["Ботинки"]),
  e("сапог\\p{L}*|етік\\p{L}*|чобот\\p{L}*", ["Сапоги", "Ботинки"]),
  e("сланц\\p{L}*|шлепан\\p{L}*", ["Сланцы"]),
  e("босонож\\p{L}*|сандал\\p{L}*", ["Босоножки"]),
  e("лофер\\p{L}*", ["Лоферы"]),
  e("обув\\p{L}*|аяққиім\\p{L}*", undefined, ["shoes"]),
  // tshirt
  e("футболк\\p{L}*|футболок|майк\\p{L}*", ["Футболка"]),
  e("оверсайз\\p{L}*", ["Оверсайз"]),
  e("поло", ["Поло"]),
  e("рубашк\\p{L}*|рубах\\p{L}*|жейде\\p{L}*", ["Рубашка"]),
  e("лонгслив\\p{L}*", ["Лонгслив"]),
  // outer
  e("куртк\\p{L}*|курток|күрте\\p{L}*", ["Куртка"]),
  e("пуховик\\p{L}*|пуховк\\p{L}*", ["Пуховик"]),
  e("ветровк\\p{L}*", ["Ветровка"]),
  e("пальто|пальт\\p{L}*", ["Пальто"]),
  e("худи|толстовк\\p{L}*", ["Худи"]),
  e("свитшот\\p{L}*", ["Свитшот"]),
  e("жилет\\p{L}*", ["Жилет"]),
  // pants
  e("джинс\\p{L}*", ["Джинсы"]),
  e("карго", ["Карго"]),
  e("шорт\\p{L}*", ["Шорты"]),
  e("брюк\\p{L}*|шалбар\\p{L}*", ["Брюки"]),
  e("штан\\p{L}*", ["Брюки", "Спортивные"]),
  e("леггинс\\p{L}*|легинс\\p{L}*|лосин\\p{L}*", ["Леггинсы"]),
  // dress
  e("плать\\p{L}*|көйлек\\p{L}*", ["Платье"]),
  e("юбк\\p{L}*|белдемше\\p{L}*", ["Юбка"]),
  e("сарафан\\p{L}*", ["Сарафан"]),
  e("костюм\\p{L}*", ["Костюм"]),
  // caps
  e("кепк\\p{L}*|бейсболк\\p{L}*", ["Кепка"]),
  e("шапк\\p{L}*|шапочк\\p{L}*|қалпақ\\p{L}*", ["Шапка"]),
  e("панам\\p{L}*", ["Панама"]),
  e("бини", ["Бини"]),
  // underwear
  e("носк\\p{L}*|носок", ["Носки"]),
  e("трус\\p{L}*", ["Трусы"]),
  e("бюстгальтер\\p{L}*|лифчик\\p{L}*", ["Бюстгальтер"]),
  e("пижам\\p{L}*", ["Пижама"]),
  e("колготк\\p{L}*|колгот", ["Колготки"]),
  // acc
  e("ремень|ремн\\p{L}*|ремешк\\p{L}*|белбеу\\p{L}*", ["Ремень"]),
  e("сумк\\p{L}*|сумок|сөмке\\p{L}*", ["Сумка"]),
  e("очк\\p{L}*|көзілдірік\\p{L}*", ["Очки"]),
  e("кошел\\p{L}*|кошельк\\p{L}*|әмиян\\p{L}*", ["Кошелек"]),
  e("рюкзак\\p{L}*", ["Рюкзак"]),
  e("перчатк\\p{L}*|перчаток|қолғап\\p{L}*", ["Перчатки"]),
  e("шарф\\p{L}*", ["Шарф"]),
  // jewelry
  e("кольц\\p{L}*|колец|сақина\\p{L}*", ["Кольцо"]),
  e("серьг\\p{L}*|сырға\\p{L}*", ["Серьги"]),
  e("цепочк\\p{L}*|цепочек", ["Цепочка"]),
  e("браслет\\p{L}*|білезік\\p{L}*", ["Браслет"]),
  e("кулон\\p{L}*", ["Кулон"]),
  e("час(?:ы|ов|ам|ах|ами)|сағат\\p{L}*", ["Часы"]),
  // sport / kids / toys
  e("мяч\\p{L}*", ["Мяч"]),
  e("палатк\\p{L}*", ["Палатка"]),
  e("велосипед\\p{L}*", ["Велосипед"]),
  e("коляск\\p{L}*", ["Коляска"]),
  e("подгузник\\p{L}*|памперс\\p{L}*", ["Подгузники"]),
  e("конструктор\\p{L}*", ["Конструктор"]),
  e("кукл\\p{L}*|қуыршақ\\p{L}*", ["Кукла"]),
  e("игрушк\\p{L}*|ойыншық\\p{L}*", undefined, ["toys"]),
  // beauty / electronics / phones
  e("парфюм\\p{L}*|духи|иіссу\\p{L}*", ["Парфюм"]),
  e("наушник\\p{L}*|құлаққап\\p{L}*", ["Наушники"]),
  e("смартфон\\p{L}*|телефон\\p{L}*|айфон\\p{L}*|iphone", ["Смартфон"]),
  e("планшет\\p{L}*", ["Планшет"]),
  e("повербанк\\p{L}*|powerbank", ["Повербанк"]),
  e("ноутбук\\p{L}*", ["Ноутбук"]),
  // тек санат
  e("мебел\\p{L}*|жиһаз\\p{L}*", undefined, ["furniture"]),
  e("посуд\\p{L}*|ыдыс\\p{L}*", undefined, ["dishes"]),
  e("книг\\p{L}*|кітап\\p{L}*", undefined, ["books"]),
];

// Тауар түрінің бөлек тізімі тестке керек (catalog.ts-пен сәйкестікті тексеру).
export const KNOWN_TYPES: string[] = [...new Set(TYPE_ENTRIES.flatMap((x) => x.types ?? []))];
export const KNOWN_CATS: string[] = [...new Set(TYPE_ENTRIES.flatMap((x) => x.cats ?? []))];

const AUD_MALE = new RegExp(
  "^(?:муж(?:ск\\p{L}*|чин\\p{L}*|у|а|ик\\p{L}*|ей)?|парн\\p{L}*|ерлер\\p{L}*)$",
  "u",
);
const AUD_FEMALE = new RegExp(
  "^(?:женск\\p{L}*|женщин\\p{L}*|девуш\\p{L}*|жене|жену|әйел\\p{L}*)$",
  "u",
);
const AUD_KIDS = new RegExp(
  "^(?:детск\\p{L}*|детей|детям|ребен\\p{L}*|малыш\\p{L}*|мальчик\\p{L}*|девочк\\p{L}*|бала\\p{L}*)$",
  "u",
);

const SEASON_ENTRIES: [RegExp, string][] = [
  [/^(?:лет(?:н\p{L}*|о|ом)|жазғы|жаз)$/u, "Лето"],
  [/^(?:зим(?:а|у|н\p{L}*|ой|е|ы)|қысқы|қыс)$/u, "Зима"],
  [/^(?:осенн\p{L}*|осень|осенью|күзгі|күз)$/u, "Осень"],
  [/^(?:весенн\p{L}*|весна|весной|көктемгі|көктем)$/u, "Весна"],
];

// Түстер: DB-дағы канондық мәннің кіші әріпті түрі (substring іздеу үшін).
const COLOR_ENTRIES: [RegExp, string][] = [
  [new RegExp(`^(?:бел${ADJ}|ақ|ақты)$`, "u"), "белый"],
  [new RegExp(`^(?:черн${ADJ}|қара)$`, "u"), "черный"],
  [new RegExp(`^(?:сер${ADJ}|сұр)$`, "u"), "серый"],
  [new RegExp(`^(?:красн${ADJ}|қызыл)$`, "u"), "красный"],
  [new RegExp(`^(?:зелен${ADJ}|жасыл)$`, "u"), "зеленый"],
  [new RegExp(`^(?:син${ADJ}|көк)$`, "u"), "синий"],
  [new RegExp(`^(?:желт${ADJ}|сары)$`, "u"), "желтый"],
  [new RegExp(`^(?:розов${ADJ}|қызғылт)$`, "u"), "розовый"],
  [new RegExp(`^(?:оранжев${ADJ})$`, "u"), "оранжевый"],
  [new RegExp(`^(?:коричнев${ADJ}|қоңыр)$`, "u"), "коричневый"],
  [new RegExp(`^(?:бежев${ADJ})$`, "u"), "бежевый"],
];

const SIZE_LETTERS = new Set(["xxs", "xs", "s", "m", "l", "xl", "xxl", "xxxl"]);
const L = String.raw`[\p{L}\p{N}]`;
const NUM = String.raw`(\d{1,7}(?:[.,]\d+)?)\s*(к|k|тыс\p{L}*|мың\p{L}*)?`;
const CUR = String.raw`(?:₸|тг|тнг|тенге|теңге|kzt)?`;
const BEG = String.raw`(?<!${L})`;

function mk(src: string): RegExp {
  return new RegExp(src, "gu");
}

const RE_MAX = [
  mk(
    `${BEG}(?:до|дешевле|не\\s+дороже|недороже|не\\s+более|не\\s+выше|менее|ниже|бюджет|в\\s+пределах|максимум|макс)\\s*${NUM}\\s*${CUR}`,
  ),
  mk(`${NUM}\\s*${CUR}\\s*-?\\s*(?:ға|ге|қа|ке|на|не)?\\s*дейін`),
];
const RE_MIN = [
  mk(`${BEG}(?:от|дороже|более|свыше|выше|минимум)\\s*${NUM}\\s*${CUR}`),
  mk(`${NUM}\\s*${CUR}\\s*-?\\s*(?:нан|нен|тан|тен|дан|ден)?\\s*(?:бастап|жоғары)`),
];
const RE_BARE = mk(`${BEG}${NUM}\\s*(?:₸|тг|тнг|тенге|теңге)`);

function toNum(raw: string, suffix: string | undefined): number | null {
  let n = Number(raw.replace(",", "."));
  if (!isFinite(n) || n <= 0) return null;
  if (suffix) n *= 1000;
  return Math.round(n);
}

// Бағаны табады және мәтіннен кесіп алады (өлшемге шатаспасын).
function takePrice(
  text: string,
  res: RegExp[],
  needSuffixOrBig: boolean,
): { value: number | null; text: string } {
  let value: number | null = null;
  let out = text;
  for (const re of res) {
    re.lastIndex = 0;
    out = out.replace(re, (m: string, raw: string, suf: string | undefined) => {
      const n = toNum(raw, suf);
      // «до 40 размера» ≠ баға: кілт сөзбен келген кішкентай сан суффикссіз қабылданбайды.
      if (n === null || (needSuffixOrBig && !suf && n < 500)) return m;
      if (value === null) value = n;
      return " ";
    });
  }
  return { value, text: out };
}

const RE_SIZE_PRE = new RegExp(
  `${BEG}(?:размер\\p{L}*|р-р|р\\.|өлшем\\p{L}*|size)\\s*[:№-]?\\s*(xxxl|xxl|xl|xs|s|m|l|\\d{2,3})(?!${L})`,
  "u",
);
const RE_SIZE_POST = new RegExp(
  `${BEG}(xxxl|xxl|xl|xs|s|m|l|\\d{2,3})\\s*-?\\s*(?:го\\s+|й\\s+)?(?:размер\\p{L}*|р-р|өлшем\\p{L}*)`,
  "u",
);
const RE_SHOE_NUM = new RegExp(`${BEG}(3[5-9]|4[0-8])(?![\\p{L}\\p{N}.,])`, "u");

/// Мәтіннен сүзгі. Тауар түрі/санаты танылмаса null (LLM өзі іздейді).
export function extractFilters(input: string): Prefilter | null {
  let t = input.toLowerCase().replace(/ё/g, "е").replace(/[  ]/g, " ");
  t = t.replace(/аяқ\s+киім/g, "аяққиім");
  // «30 000» → «30000» (бірнеше топ: 1 500 000).
  for (let i = 0; i < 3; i++) t = t.replace(/(\d)[ .](\d{3})(?!\d)/g, "$1$2");

  const f: Prefilter = {};

  const mx = takePrice(t, RE_MAX, true);
  t = mx.text;
  const mn = takePrice(t, RE_MIN, true);
  t = mn.text;
  let maxP = mx.value;
  const minP = mn.value;
  if (maxP === null && minP === null) {
    const bare = takePrice(t, [RE_BARE], false);
    t = bare.text;
    maxP = bare.value;
  }
  if (maxP !== null) f.max_price = maxP;
  if (minP !== null) f.min_price = minP;
  if (f.min_price && f.max_price && f.min_price > f.max_price) {
    delete f.min_price;
    delete f.max_price;
  }

  let size: string | null = null;
  const sm = RE_SIZE_PRE.exec(t) ?? RE_SIZE_POST.exec(t);
  if (sm) size = sm[1].toUpperCase();

  const tokens = t.match(/[\p{L}\p{N}][\p{L}\p{N}-]*/gu) ?? [];

  const types: string[] = [];
  const cats: string[] = [];
  const addUnique = (arr: string[], v: string) => {
    if (!arr.includes(v)) arr.push(v);
  };
  for (const tok of tokens) {
    for (const en of TYPE_ENTRIES) {
      if (!en.re.test(tok)) continue;
      for (const ty of en.types ?? []) addUnique(types, ty);
      for (const c of en.cats ?? []) addUnique(cats, c);
    }
  }
  // «спортивный костюм» — бөлек түр, жай «Костюм» емес.
  if (types.includes("Костюм") && tokens.some((x) => /^спортивн\p{L}*$/u.test(x))) {
    types.splice(types.indexOf("Костюм"), 1, "Спортивный костюм");
  }
  if (!types.length && !cats.length) return null;

  if (types.length) f.types = types;
  // Түр аталса, санат сүзгісі керек емес; тек санат аталса — санат.
  if (!types.length && cats.length) f.category_keys = cats;

  // Аудитория/маусым/өлшем тек киім-аяқкиім санаттарында мағыналы.
  const typeCats = types.map((ty) => TYPE_CATEGORIES.get(ty) ?? []);
  const apparel = (types.length > 0 || cats.length > 0) &&
    typeCats.every((cs) => cs.some((c) => AUDIENCE_CATEGORIES.includes(c))) &&
    cats.every((c) => AUDIENCE_CATEGORIES.includes(c));

  if (apparel) {
    const aud = new Set<string>();
    for (const tok of tokens) {
      if (AUD_KIDS.test(tok)) aud.add("Детские");
      else if (AUD_MALE.test(tok)) aud.add("Мужские");
      else if (AUD_FEMALE.test(tok)) aud.add("Женские");
    }
    if (aud.size === 1) f.audience = [...aud][0];

    const seasons = new Set<string>();
    for (const tok of tokens) {
      for (const [re, name] of SEASON_ENTRIES) if (re.test(tok)) seasons.add(name);
    }
    if (seasons.size === 1) f.season = [...seasons][0];
  } else {
    size = null; // техника/мебельде «42» өлшем емес
  }

  // Өлшем: «размер 42» анық; жай «кроссовки 42» — тек аяқ киімде.
  const isShoes = cats.includes("shoes") || typeCats.some((cs) => cs.includes("shoes"));
  if (!size && isShoes) {
    const m = RE_SHOE_NUM.exec(t);
    if (m) size = m[1];
  }
  if (size) f.size = size;

  // Қосымша сөздер: түс және латын (бренд) сөздері → query (БАРЛЫҚ сөз сәйкес болуы керек).
  const words: string[] = [];
  const colors = new Set<string>();
  for (const tok of tokens) {
    for (const [re, name] of COLOR_ENTRIES) if (re.test(tok)) colors.add(name);
  }
  if (colors.size === 1) words.push([...colors][0]);
  for (const tok of tokens) {
    if (
      /^[a-z][a-z0-9-]{2,}$/.test(tok) && !SIZE_LETTERS.has(tok) &&
      tok !== "iphone" && tok !== "powerbank"
    ) {
      if (words.length < 2 && !words.includes(tok)) words.push(tok);
    }
  }
  if (words.length) f.query = words.join(" ");

  return f;
}

/// Сүзгілерді босатып, тек түр/санатты қалдырады (қатаң іздеу бос болғанда
/// модельге «босатылған» нәтиже беру үшін). Босатылатын ештеңе болмаса null.
export function relaxFilters(f: Prefilter): Prefilter | null {
  const r: Prefilter = {};
  if (f.types) r.types = f.types;
  if (f.category_keys) r.category_keys = f.category_keys;
  const strict = Object.keys(f).filter((k) => k !== "types" && k !== "category_keys");
  return strict.length ? r : null;
}
