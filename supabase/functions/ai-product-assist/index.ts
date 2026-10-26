// ai-product-assist — дүкен иесіне тауар қосуда AI көмегі.
//
// Режимдер (POST JSON):
//   { mode: 'suggest', images: [...], fields: {...}, lang: 'ru'|'kk' }
//     → { category_key, type, category, color, season, material, brand,
//         name_suggestion, confidence, remaining }
//     Суреттен тауар категориясын/түрін/кімге/түсін/сезонын/материалын/
//     брендін ұсынады. Мәндер ТЕК каталогтың канондық мәндері (structured output
//     enum) — UI оларды тікелей формаға қоя алады, иесі қарап растайды.
//   { mode: 'describe', images: [...], fields: {...}, lang: 'ru'|'kk' }
//     → { description, remaining }
//     Сурет + толтырылған өрістерден сатушы сипаттама жазады (ойдан факт жоқ).
//
// images[]: https URL (Cloudinary) НЕМЕСЕ base64 JPEG ('data:image/jpeg;base64,…'
//   не таза base64). Ең көбі 4 сурет.
//
// Қауіпсіздік:
//   • Verify JWT = ON + шақырушы /auth/v1/user арқылы тексеріледі.
//   • Квота ШАҚЫРУШЫНЫҢ атынан consume_owner_ai_quota() (0075) — тек дүкен
//     қызметкері (admin/seller), дүкен бойынша күндік шек. AI сәтсіз болса —
//     refund_owner_ai_quota() (тек service_role) квотаны қайтарады.
//   • ANTHROPIC_API_KEY тек Secrets-те (кодта/клиентте ЕШҚАШАН).
//
// Қателер: {error:'code'} — bad_request 400, no_auth/invalid_session 401,
//   not_authorized 403, feature_disabled 403, ai_quota_exceeded 429, refused 422, ai_failed 502,
//   not_configured 503.
import type Anthropic from "npm:@anthropic-ai/sdk@1.3.0";
import {
  aiConfigured,
  aiModel,
  makeLlmClient,
  refreshProviderSetting,
  supportsServerFallback,
} from "../_shared/llm.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
// Провайдер (Anthropic / Gemini) мен кілттер — ../_shared/llm.ts ішінде.

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...CORS },
  });
}

// ── Каталог (lib/data/models/category_data.dart-пен СИНХРОНДЫ ұстау!) ──
const CATEGORIES: Record<
  string,
  { ru: string; audience: boolean; types: string[]; materials: string[] }
> = {
  shoes: {
    ru: "Обувь",
    audience: true,
    types: ["Туфли", "Кеды", "Кроссовки", "Ботинки", "Сапоги", "Сланцы", "Босоножки", "Лоферы"],
    materials: ["Кожа", "Экокожа", "Замша", "Текстиль", "Резина", "Синтетика"],
  },
  tshirt: {
    ru: "Футболки и майки",
    audience: true,
    types: ["Футболка", "Оверсайз", "Поло", "Базовая", "С принтом", "Рубашка", "Лонгслив"],
    materials: ["Хлопок", "Полиэстер", "Трикотаж", "Вискоза", "Лён", "Синтетика"],
  },
  outer: {
    ru: "Верхняя одежда",
    audience: true,
    types: ["Куртка", "Пуховик", "Ветровка", "Пальто", "Худи", "Свитшот", "Жилет"],
    materials: ["Нейлон", "Полиэстер", "Пух", "Шерсть", "Мембрана", "Синтетика"],
  },
  pants: {
    ru: "Брюки и джинсы",
    audience: true,
    types: ["Джинсы", "Карго", "Шорты", "Спортивные", "Брюки", "Леггинсы"],
    materials: ["Хлопок", "Деним", "Полиэстер", "Лён", "Велюр", "Синтетика"],
  },
  dress: {
    ru: "Платья и юбки",
    audience: true,
    types: ["Платье", "Юбка", "Сарафан", "Костюм"],
    materials: ["Хлопок", "Шёлк", "Трикотаж", "Атлас", "Вискоза", "Синтетика"],
  },
  caps: {
    ru: "Головные уборы",
    audience: true,
    types: ["Кепка", "Шапка", "Панама", "Бини", "Бандана"],
    materials: ["Шерсть", "Хлопок", "Акрил", "Вязка", "Фетр"],
  },
  underwear: {
    ru: "Нижнее бельё",
    audience: true,
    types: ["Трусы", "Бюстгальтер", "Носки", "Пижама", "Термобельё", "Колготки"],
    materials: ["Хлопок", "Полиэстер", "Кружево", "Микрофибра", "Бамбук", "Синтетика"],
  },
  acc: {
    ru: "Аксессуары",
    audience: true,
    types: ["Ремень", "Сумка", "Очки", "Кошелек", "Рюкзак", "Перчатки", "Шарф"],
    materials: ["Кожа", "Экокожа", "Текстиль", "Металл", "Пластик"],
  },
  jewelry: {
    ru: "Украшения",
    audience: true,
    types: ["Кольцо", "Серьги", "Цепочка", "Браслет", "Кулон", "Часы"],
    materials: ["Золото", "Серебро", "Сталь", "Бижутерия", "Металл"],
  },
  sport: {
    ru: "Спорт и туризм",
    audience: true,
    types: ["Спортивный костюм", "Леггинсы", "Топ", "Шорты", "Тренажёр", "Велосипед", "Палатка", "Мяч"],
    materials: ["Полиэстер", "Спандекс", "Сетка", "Нейлон", "Синтетика"],
  },
  kids: {
    ru: "Детские товары",
    audience: false,
    types: ["Коляска", "Автокресло", "Детская одежда", "Подгузники", "Детское питание", "Кроватка"],
    materials: ["Пластик", "Текстиль", "Дерево", "Металл", "Силикон"],
  },
  toys: {
    ru: "Игрушки",
    audience: false,
    types: ["Конструктор", "Кукла", "Мягкая игрушка", "Настольная игра", "Машинка", "Развивающая игрушка"],
    materials: ["Пластик", "Дерево", "Плюш", "Металл", "Резина"],
  },
  beauty: {
    ru: "Красота и уход",
    audience: false,
    types: ["Парфюм", "Уход за лицом", "Уход за волосами", "Декоративная косметика", "Маникюр", "Приборы для красоты"],
    materials: ["Стекло", "Пластик", "Металл"],
  },
  pharmacy: {
    ru: "Аптека и здоровье",
    audience: false,
    types: ["Витамины", "Медтехника", "Первая помощь", "Гигиена", "Оптика"],
    materials: ["Пластик", "Стекло", "Текстиль", "Металл"],
  },
  electronics: {
    ru: "ТВ, аудио, видео",
    audience: false,
    types: ["Телевизор", "Наушники", "Колонка", "Игровая приставка", "Фотоаппарат", "Проектор"],
    materials: ["Пластик", "Металл", "Стекло", "Алюминий"],
  },
  phones: {
    ru: "Телефоны и гаджеты",
    audience: false,
    types: ["Смартфон", "Планшет", "Смарт-часы", "Чехол", "Зарядка", "Повербанк"],
    materials: ["Пластик", "Металл", "Стекло", "Силикон", "Алюминий"],
  },
  computers: {
    ru: "Компьютеры",
    audience: false,
    types: ["Ноутбук", "Монитор", "Клавиатура", "Мышь", "Комплектующие", "Принтер"],
    materials: ["Пластик", "Металл", "Алюминий", "Стекло"],
  },
  appliances: {
    ru: "Бытовая техника",
    audience: false,
    types: ["Холодильник", "Стиральная машина", "Пылесос", "Микроволновка", "Чайник", "Кондиционер"],
    materials: ["Металл", "Пластик", "Стекло", "Нержавеющая сталь"],
  },
  furniture: {
    ru: "Мебель",
    audience: false,
    types: ["Диван", "Кровать", "Шкаф", "Стол", "Стул", "Полка"],
    materials: ["Дерево", "ЛДСП", "МДФ", "Металл", "Стекло", "Ткань"],
  },
  textile: {
    ru: "Домашний текстиль",
    audience: false,
    types: ["Постельное бельё", "Одеяло", "Подушка", "Плед", "Полотенце", "Штора"],
    materials: ["Хлопок", "Бязь", "Сатин", "Поплин", "Микрофибра", "Лён", "Шерсть"],
  },
  dishes: {
    ru: "Посуда",
    audience: false,
    types: ["Кастрюля", "Сковорода", "Тарелка", "Кружка", "Столовые приборы", "Контейнер"],
    materials: ["Нержавеющая сталь", "Керамика", "Стекло", "Чугун", "Пластик", "Фарфор"],
  },
  home: {
    ru: "Товары для дома",
    audience: false,
    types: ["Хранение", "Освещение", "Декор", "Для уборки", "Ванная", "Кухня"],
    materials: ["Пластик", "Металл", "Дерево", "Стекло", "Текстиль"],
  },
  garden: {
    ru: "Дача и сад",
    audience: false,
    types: ["Садовый инвентарь", "Мангал", "Бассейн", "Мебель для дачи", "Семена", "Теплица"],
    materials: ["Металл", "Пластик", "Дерево", "Резина"],
  },
  tools: {
    ru: "Строительство и ремонт",
    audience: false,
    types: ["Электроинструмент", "Ручной инструмент", "Крепёж", "Отделка", "Сантехника", "Электрика"],
    materials: ["Металл", "Сталь", "Пластик", "Дерево"],
  },
  auto: {
    ru: "Автотовары",
    audience: false,
    types: ["Шины", "Диски", "Масла", "Автохимия", "Автозапчасти", "Аксессуары для авто"],
    materials: ["Резина", "Металл", "Пластик", "Алюминий"],
  },
  pets: {
    ru: "Зоотовары",
    audience: false,
    types: ["Корм", "Игрушки для питомцев", "Лежанка", "Переноска", "Аквариум", "Уход"],
    materials: ["Пластик", "Металл", "Текстиль", "Дерево"],
  },
  books: {
    ru: "Книги",
    audience: false,
    types: ["Художественная", "Детская", "Учебная", "Бизнес", "Кулинария", "Комиксы"],
    materials: ["Бумага", "Твёрдый переплёт", "Мягкий переплёт"],
  },
  stationery: {
    ru: "Канцелярские товары",
    audience: false,
    types: ["Тетради", "Ручки", "Школьный рюкзак", "Папки", "Бумага", "Для творчества"],
    materials: ["Бумага", "Пластик", "Металл", "Дерево"],
  },
  grocery: {
    ru: "Продукты питания",
    audience: false,
    types: ["Бакалея", "Напитки", "Сладости", "Снеки", "Консервы", "Чай и кофе"],
    materials: ["Стекло", "Пластик", "Бумага", "Металл"],
  },
};

// ProductModel.colorOptions (product_model.dart) — канондық түс атаулары.
const COLORS = [
  "Черный",
  "Белый",
  "Коричневый",
  "Серый",
  "Бежевый",
  "Красный",
  "Зеленый",
  "Синий",
  "Желтый",
  "Розовый",
  "Оранжевый",
  "Мульти",
];
const AUDIENCES = ["Мужские", "Женские", "Унисекс", "Детские"];
const SEASONS = ["Лето", "Зима", "Осень", "Весна"];

const CATEGORY_KEYS = Object.keys(CATEGORIES);
const ALL_TYPES = [...new Set(Object.values(CATEGORIES).flatMap((c) => c.types))];
const ALL_MATERIALS = [
  ...new Set(Object.values(CATEGORIES).flatMap((c) => c.materials)),
];

// ── Сұрау денесін тазалау ─────────────────────────────────────────────────
type Lang = "ru" | "kk";
type Fields = Record<string, string>;
const FIELD_KEYS = [
  "name",
  "brand",
  "category_key",
  "type",
  "category",
  "color",
  "material",
  "season",
  "sizes",
  "country",
];
const MAX_IMAGES = 4;
const CLOUDINARY_PREFIX = "https://res.cloudinary.com/divynstru/";
const MAX_B64_LEN = 2_000_000; // ~1.5 МБ сурет (base64)

type ImageBlock = {
  type: "image";
  source:
    | { type: "url"; url: string }
    | { type: "base64"; media_type: "image/jpeg" | "image/png" | "image/webp"; data: string };
};

function cleanFields(raw: unknown): Fields {
  const out: Fields = {};
  if (!raw || typeof raw !== "object") return out;
  for (const k of FIELD_KEYS) {
    const v = (raw as Record<string, unknown>)[k];
    if (typeof v === "string" && v.trim()) out[k] = v.trim().slice(0, 200);
  }
  return out;
}

function toImageBlocks(raw: unknown): ImageBlock[] | null {
  if (raw == null) return [];
  if (!Array.isArray(raw)) return null;
  const out: ImageBlock[] = [];
  for (const item of raw.slice(0, MAX_IMAGES)) {
    if (typeof item !== "string" || !item) return null;
    if (item.startsWith("https://")) {
      // Тек өз Cloudinary аккаунтымыз: әйтпесе функция тегін «vision-прокси»
      // болып, Anthropic кез келген сыртқы URL-ді жүктер еді.
      if (item.length > 2000 || !item.startsWith(CLOUDINARY_PREFIX)) return null;
      out.push({ type: "image", source: { type: "url", url: item } });
      continue;
    }
    let mediaType: "image/jpeg" | "image/png" | "image/webp" = "image/jpeg";
    let data = item;
    const m = /^data:(image\/(?:jpeg|png|webp));base64,(.*)$/s.exec(item);
    if (m) {
      mediaType = m[1] as typeof mediaType;
      data = m[2];
    }
    if (data.length > MAX_B64_LEN || !/^[A-Za-z0-9+/=\s]+$/.test(data)) {
      return null;
    }
    out.push({
      type: "image",
      source: { type: "base64", media_type: mediaType, data: data.replace(/\s/g, "") },
    });
  }
  return out;
}

function fieldsText(f: Fields): string {
  const cat = f.category_key ? CATEGORIES[f.category_key] : undefined;
  const rows: string[] = [];
  if (f.name) rows.push(`Название: ${f.name}`);
  if (f.brand) rows.push(`Бренд: ${f.brand}`);
  if (cat) rows.push(`Категория: ${cat.ru}`);
  if (f.type) rows.push(`Тип: ${f.type}`);
  if (f.category) rows.push(`Для кого: ${f.category}`);
  if (f.color) rows.push(`Цвет: ${f.color}`);
  if (f.material) rows.push(`Материал: ${f.material}`);
  if (f.season) rows.push(`Сезон: ${f.season}`);
  if (f.sizes) rows.push(`Размеры в наличии: ${f.sizes}`);
  if (f.country) rows.push(`Страна производства: ${f.country}`);
  return rows.length ? rows.join("\n") : "(поля не заполнены)";
}

// ── Промпттар ─────────────────────────────────────────────────────────────
const SUGGEST_SYSTEM =
  `You help a store owner in Kazakhstan list a product in the Qoima marketplace app.
Look at the product photo(s) and pick catalog values for the listing form.

Rules:
- category_key: the catalog category that best fits the item; "" (empty) if the photo does not show a sellable product (screenshot, person, blur) and you cannot tell.
- type: one of the canonical types listed for that category below; "" if none fits.
- category (audience, only for fashion categories marked audience=true): "Мужские", "Женские", "Унисекс" or "Детские"; "" for other categories or if unclear.
- color: the dominant color from the allowed list; "Мульти" for clearly multicolor items; "" if the photo doesn't show it.
- season: only when the item is clearly seasonal (e.g. down jacket → "Зима", sandals → "Лето"); otherwise "".
- material: only when it is visually obvious (e.g. denim, knit, suede); otherwise "". Never guess a premium material.
- brand: only if a logo or brand name is clearly readable on the item or its label; otherwise "". Never invent a brand.
- name_suggestion: a short Russian product title as a shopper would search it (2–6 words, brand first if known, no color, no price), e.g. "Nike Air Max 270", "Пуховик удлинённый с капюшоном".
- confidence: "high" if the photo clearly shows the item, "medium" if partly, "low" if unclear.
Values already filled in by the owner (given below) are hints; keep them unless the photo clearly contradicts them.

Catalog (key — name — audience — canonical types):
${
    CATEGORY_KEYS.map((k) => {
      const c = CATEGORIES[k];
      return `${k} — ${c.ru} — ${c.audience ? "audience=true" : "audience=false"} — ${c.types.join(", ")}`;
    }).join("\n")
  }`;

function describeSystem(lang: Lang): string {
  const language = lang === "kk"
    ? `Write in natural, fluent Kazakh (қазақ тілі, Cyrillic) as spoken in Kazakhstan — not a word-for-word translation from Russian. Common loanwords for sizes/brands are fine.`
    : `Write in natural, fluent Russian.`;
  return `You write product descriptions for an online store in Kazakhstan (Qoima marketplace).
${language}

Write a clear, honest, selling description a shopper can read in 15 seconds:
- 3–6 short sentences of plain prose. Optionally add up to 4 short bullet points ("• ") with key features.
- Describe only what is visible in the photos or stated in the given fields. Do NOT invent facts: no made-up materials, composition, technologies, certificates, warranty, origin or sizes.
- Never mention prices, discounts, delivery terms, stock, phone numbers or links.
- No headings, no markdown (no **, no #), at most one emoji or none.
- Don't repeat the brand/name more than once. Don't address the seller; address the buyer.
- Return only the description text.`;
}

const SUGGEST_SCHEMA = {
  type: "object",
  properties: {
    // "" — фото тауар емес/анық емес: клиент категорияны толтырмайды.
    category_key: { type: "string", enum: [...CATEGORY_KEYS, ""] },
    type: { type: "string", enum: [...ALL_TYPES, ""] },
    category: { type: "string", enum: [...AUDIENCES, ""] },
    color: { type: "string", enum: [...COLORS, ""] },
    season: { type: "string", enum: [...SEASONS, ""] },
    material: { type: "string", enum: [...ALL_MATERIALS, ""] },
    brand: { type: "string" },
    name_suggestion: { type: "string" },
    confidence: { type: "string", enum: ["high", "medium", "low"] },
  },
  required: [
    "category_key",
    "type",
    "category",
    "color",
    "season",
    "material",
    "brand",
    "name_suggestion",
    "confidence",
  ],
  additionalProperties: false,
};

// ── Claude шақыруы ────────────────────────────────────────────────────────
class AiError extends Error {
  // refundable=true — Anthropic генерация жасамады (желі/5xx/429/529): квота
  // қайтарылады. Refusal/max_tokens/parse қатесінде токен ЕСЕПКЕ ЖАЗЫЛҒАН —
  // қайтарсақ, квотаны айналып өтіп шексіз шығын жасауға болады.
  constructor(
    public code: string,
    public status: number,
    public refundable = false,
  ) {
    super(code);
  }
}

async function callClaude(params: {
  system: string;
  content: unknown[];
  maxTokens: number;
  format?: unknown;
}): Promise<string> {
  const client = makeLlmClient({ timeout: 45_000, maxRetries: 1 });
  // Haiku 5.5-те сервер жағындағы fallback ЖОҚ: `fallbacks` пен beta-ны
  // жібермейміз (қате болады) — қарапайым messages.create. Opus/Sonnet
  // модельдерінде ғана fallbacks:'default' қосылады (классификатор бас
  // тартса, сұрау серверде басқа модельде қайта орындалады). SDK типтері
  // бұл өрісті әлі білмеуі мүмкін — сондықтан минималды cast.
  const isHaiku = !supportsServerFallback();
  // deno-lint-ignore no-explicit-any
  const body: any = {
    model: aiModel(),
    max_tokens: params.maxTokens,
    system: params.system,
    messages: [{ role: "user", content: params.content }],
    output_config: params.format
      ? { effort: "low", format: params.format }
      : { effort: "low" },
  };
  if (!isHaiku) {
    body.betas = ["server-side-fallback-2026-07-01"];
    body.fallbacks = "default";
  }
  // deno-lint-ignore no-explicit-any
  let res: any;
  try {
    res = isHaiku
      ? await client.messages.create(body)
      : await client.beta.messages.create(body);
  } catch (e) {
    // SDK-дің типтелген қателері (APIError ұрпақтары) `status` өрісін береді.
    const status = (e as { status?: number })?.status;
    console.error("anthropic_error", status, (e as Error)?.message);
    if (status === 429 || status === 529) throw new AiError("ai_busy", 503, true);
    // 4xx (400 т.б.) — сұрау қате (мысалы жарамсыз сурет): генерация болмады.
    throw new AiError("ai_failed", 502, true);
  }
  if (res.stop_reason === "refusal") throw new AiError("refused", 422);
  // max_tokens: describe-та қиылған мәтін жарамды нәтиже; suggest-те JSON
  // толық емес болса parse қатесі (квота қайтарылмайды — токен жұмсалды).
  const text = (res.content ?? [])
    // deno-lint-ignore no-explicit-any
    .filter((b: any) => b.type === "text")
    // deno-lint-ignore no-explicit-any
    .map((b: any) => b.text as string)
    .join("")
    .trim();
  if (!text) throw new AiError("ai_failed", 502);
  return text;
}

// ── Нәтижені тексеру (enum + категорияға сәйкестік) ──────────────────────
function sanitizeSuggestion(raw: Record<string, unknown>) {
  const s = (v: unknown, max = 80) =>
    typeof v === "string" ? v.trim().slice(0, max) : "";
  const key = CATEGORY_KEYS.includes(s(raw.category_key))
    ? s(raw.category_key)
    : "";
  const cat = key ? CATEGORIES[key] : undefined;
  const type = cat && cat.types.includes(s(raw.type)) ? s(raw.type) : "";
  const audience = cat?.audience && AUDIENCES.includes(s(raw.category))
    ? s(raw.category)
    : "";
  const color = COLORS.includes(s(raw.color)) ? s(raw.color) : "";
  const season = SEASONS.includes(s(raw.season)) ? s(raw.season) : "";
  const material = ALL_MATERIALS.includes(s(raw.material)) ? s(raw.material) : "";
  const conf = ["high", "medium", "low"].includes(s(raw.confidence))
    ? s(raw.confidence)
    : "low";
  return {
    category_key: key,
    type,
    category: audience,
    color,
    season,
    material,
    brand: s(raw.brand, 60),
    name_suggestion: s(raw.name_suggestion, 100),
    confidence: conf,
  };
}

// ── Квота ─────────────────────────────────────────────────────────────────
async function refund(uid: string): Promise<void> {
  try {
    const admin = createClient(SUPABASE_URL, SERVICE_KEY);
    const { data } = await admin
      .from("users")
      .select("id, owner_id")
      .eq("id", uid)
      .maybeSingle();
    const owner = (data?.owner_id as string | null) || (data?.id as string | undefined);
    if (!owner) return;
    await admin.rpc("refund_owner_ai_quota", { p_owner: owner });
  } catch (e) {
    console.error("refund_failed", e);
  }
}

// ── Негізгі өңдеуші ───────────────────────────────────────────────────────
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader) return json({ error: "no_auth" }, 401);
  const whoRes = await fetch(`${SUPABASE_URL}/auth/v1/user`, {
    headers: { apikey: ANON_KEY, Authorization: authHeader },
  });
  if (!whoRes.ok) return json({ error: "invalid_session" }, 401);
  const uid = (await whoRes.json())?.id as string | undefined;
  if (!uid) return json({ error: "invalid_session" }, 401);

  // deno-lint-ignore no-explicit-any
  let body: any;
  try {
    body = await req.json();
  } catch (_) {
    return json({ error: "bad_request" }, 400);
  }
  const mode = body?.mode;
  if (mode !== "suggest" && mode !== "describe") {
    return json({ error: "bad_request" }, 400);
  }
  const lang: Lang = body?.lang === "kk" ? "kk" : "ru";
  const fields = cleanFields(body?.fields);
  const images = toImageBlocks(body?.images);
  if (images === null) return json({ error: "bad_request" }, 400);
  // Суретсіз «толтыру» мағынасыз; сипаттамаға кемінде сурет НЕМЕСЕ атау керек.
  if (mode === "suggest" && images.length === 0) {
    return json({ error: "bad_request" }, 400);
  }
  if (mode === "describe" && images.length === 0 && !fields.name) {
    return json({ error: "bad_request" }, 400);
  }

  // Кілт жоқ болса квотаны тұтынбай-ақ қайтарамыз.
  await refreshProviderSetting();
  if (!aiConfigured()) return json({ error: "not_configured" }, 503);

  // Квота — шақырушының атынан (RLS/auth.uid() сол адамдікі).
  const userClient = createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false },
  });
  // Суперадмин жалауы: өшік болса квота да тұтынылмайды.
  const { data: flagOn } = await userClient.rpc("feature_enabled", {
    p_name: "ai_product_assist",
  });
  if (flagOn !== true) return json({ error: "feature_disabled" }, 403);

  const { data: remaining, error: qErr } = await userClient.rpc(
    "consume_owner_ai_quota",
  );
  if (qErr) {
    const msg = `${qErr.message ?? ""} ${qErr.details ?? ""}`;
    if (msg.includes("ai_quota_exceeded")) {
      return json({ error: "ai_quota_exceeded", remaining: 0 }, 429);
    }
    if (msg.includes("feature_disabled")) {
      return json({ error: "feature_disabled" }, 403);
    }
    if (msg.includes("not_authorized")) {
      return json({ error: "not_authorized" }, 403);
    }
    console.error("quota_error", qErr);
    return json({ error: "ai_failed" }, 502);
  }

  try {
    if (mode === "suggest") {
      const text = await callClaude({
        system: SUGGEST_SYSTEM,
        maxTokens: 3000,
        format: { type: "json_schema", schema: SUGGEST_SCHEMA },
        content: [
          ...images,
          {
            type: "text",
            text: `Owner's current form values (hints):\n${fieldsText(fields)}\n\nFill in the listing fields from the photo(s).`,
          },
        ],
      });
      let parsed: Record<string, unknown>;
      try {
        parsed = JSON.parse(text);
      } catch (_) {
        throw new AiError("ai_failed", 502); // refundable=false: токен жұмсалған
      }
      return json({ ...sanitizeSuggestion(parsed), remaining });
    }

    const text = await callClaude({
      system: describeSystem(lang),
      maxTokens: 4000,
      content: [
        ...images,
        {
          type: "text",
          text: `Product data from the seller:\n${fieldsText(fields)}\n\n${
            lang === "kk"
              ? "Write the description in Kazakh."
              : "Write the description in Russian."
          }`,
        },
      ],
    });
    // Markdown қалдықтарын тазалау (модель кейде ** қояды).
    const description = text.replace(/\*\*/g, "").replace(/^#+\s*/gm, "")
      .slice(0, 2000);
    return json({ description, remaining });
  } catch (e) {
    if (e instanceof AiError) {
      if (e.refundable) await refund(uid);
      return json({ error: e.code }, e.status);
    }
    console.error("unexpected", e);
    return json({ error: "ai_failed" }, 502);
  }
});
