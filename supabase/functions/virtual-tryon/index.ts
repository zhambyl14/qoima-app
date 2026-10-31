// virtual-tryon — «Онлайн киіп көру»: клиент суреті + тауар суреті → FASHN try-on.
//
// POST JSON: { productId: uuid, imageIndex?: int, personImageBase64: string,
//              lang?: 'kk'|'ru' }
//   personImageBase64 — JPEG/PNG (таза base64 немесе data URI), ≤ ~4 МБ.
//   → { imageUrl, remaining }   (imageUrl — FASHN CDN сілтемесі, ~3 күн тұрады)
//
// Провайдер: FASHN (https://docs.fashn.ai), model_name 'tryon-v1.6':
//   POST https://api.fashn.ai/v1/run  → {id}
//   GET  https://api.fashn.ai/v1/status/{id} → {status: starting|in_queue|
//        processing|completed|failed, output:[url], error:{name,message}}
//   Auth: Authorization: Bearer <FASHN_API_KEY>.
//
// Қауіпсіздік / жеке өмір:
//   • Verify JWT = ON + /auth/v1/user тексерісі.
//   • Жалау 'ai_tryon' (0067b): өшік болса 403 feature_disabled.
//   • Адам суреті ЕШҚАШАН сақталмайды (ДБ-ға да, Storage-қа да) — жадта ғана
//     жүріп FASHN-ға кетеді. Киім суреті сервер жағында ДБ-дан алынады
//     (клиент жіберген URL-ге сенбейміз → SSRF/ойдан сурет жоқ).
//   • Қолжетімділік ережесі (TRYON_RULES) lib/ui/client/ai/try_on_eligibility.dart-тағы
//     kTryOnRules-пен БІРДЕЙ. Киімнен басқа түрлер (аяқ киім, бас киім,
//     көзілдірік, сөмке, әшекей, сағат) FASHN-да жоқ — тек Gemini; Gemini кілті
//     жоқ болса олар not_configured (квота жұмсалмайды).
//   • Квота consume_ai_quota('tryon') — тек провайдерді шақыру алдында;
//     refund_ai_quota (тек service_role) — тек провайдер ақауында (5xx, output
//     жоқ, кіріске қатысты емес қате). Кіріс қатесі мен таймаутта қайтарылмайды.
//   • Secrets: FASHN_API_KEY немесе GEMINI_API_KEY (екеуі де жоқ → 503).
//
// Қозғалтқыш (0080): суперадмин app_settings.ai_provider = 'gemini' қойса —
//   Gemini сурет моделі (gemini-2.5-flash-image, уақытша/арзан нұсқа);
//   әйтпесе FASHN кілті бар болса — FASHN; болмаса Gemini.
//   Gemini нәтижесі жабық 'tryon-results' bucket-ке жазылып, клиентке 1 сағаттық
//   signed URL қайтады (жауап пішімі өзгермейді: {imageUrl, remaining}).
//   Сол пайдаланушының 1 сағаттан ескі нәтижелері келесі шақыруда өшіріледі.
//
// Қателер: bad_request 400, not_eligible 400, no_auth/invalid_session 401,
//   feature_disabled 403, not_found 404, ai_quota_exceeded 429, tryon_failed 502,
//   tryon_timeout 504, not_configured 503.
import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  fetchImage,
  geminiGenerateImage,
  hasGeminiKey,
  providerSetting,
  refreshProviderSetting,
} from "../_shared/llm.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const FASHN_API_KEY = Deno.env.get("FASHN_API_KEY") ?? "";
const FASHN_BASE = "https://api.fashn.ai/v1";

const POLL_TOTAL_MS = 55_000;
const POLL_EVERY_MS = 2_000;
// ~4 МБ бинар ≈ 5.4 млн base64 таңба; шағын қор қалдырамыз.
const MAX_B64_CHARS = 5_700_000;
// Бүкіл JSON денесінің шегі (base64 + аз ғана қосымша өріс).
const MAX_BODY_BYTES = 6_000_000;

// FASHN қателері: пайдаланушының кірісіне байланысты (суреті жарамсыз, поза
// табылмады, модерация) — бұларда квота ҚАЙТАРЫЛМАЙДЫ, әйтпесе жарамсыз
// суретпен шексіз тегін шақыруға болады. Қалғаны — провайдер ақауы.
const USER_INPUT_ERRORS = new Set([
  "ImageLoadError",
  "PoseError",
  "ContentModerationError",
  "InputValidationError",
  "ValidationError",
]);

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

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

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

// ── Қолжетімділік (Dart: lib/ui/client/ai/try_on_eligibility.dart `kTryOnRules`) ──
// Кесте Dart-тағымен ДӘЛ бірдей — БІР коммитте өзгерту керек (test/
// try_on_eligibility_test.dart осы блокты оқып, салыстырады, сондықтан әр
// категория бір жолда, форматы өзгермейді: `key: { all: kind|null, types: {…} },`).
// `all` — барлық түрге әдепкі (null = жарамайды, «Свой вариант» та осыған түседі),
// `types` — нақты түрге ерекшелік. Негіздемесі Dart файлындағы түсініктемелерде.
type TryOnKind =
  | "tops" | "bottoms" | "one-pieces" | "auto" // FASHN да, Gemini де біледі
  | "footwear" | "headwear" | "eyewear" | "bag" | "jewelry" | "watch" | "accessory"; // тек Gemini
type TryOnRule = { all: TryOnKind | null; types?: Record<string, TryOnKind | null> };

// deno-fmt-ignore
const TRYON_RULES: Record<string, TryOnRule> = {
  // TRYON_RULES_BEGIN
  shoes: { all: "footwear" },
  tshirt: { all: "tops" },
  outer: { all: "tops" },
  pants: { all: "bottoms" },
  dress: { all: "auto", types: { "Юбка": "bottoms", "Платье": "one-pieces", "Сарафан": "one-pieces", "Костюм": "one-pieces" } },
  caps: { all: "headwear" },
  underwear: { all: null },
  acc: { all: "accessory", types: { "Сумка": "bag", "Рюкзак": "bag", "Очки": "eyewear", "Кошелек": null } },
  jewelry: { all: "jewelry", types: { "Часы": "watch" } },
  sport: { all: null, types: { "Спортивный костюм": "one-pieces", "Топ": "tops", "Леггинсы": "bottoms", "Шорты": "bottoms" } },
  kids: { all: null },
  toys: { all: null },
  beauty: { all: null },
  pharmacy: { all: null },
  electronics: { all: null },
  phones: { all: null, types: { "Смарт-часы": "watch" } },
  computers: { all: null },
  appliances: { all: null },
  furniture: { all: null },
  textile: { all: null },
  dishes: { all: null },
  home: { all: null },
  garden: { all: null },
  tools: { all: null },
  auto: { all: null },
  pets: { all: null },
  books: { all: null },
  stationery: { all: null },
  grocery: { all: null },
  // TRYON_RULES_END
};

// FASHN tryon-v1.6 тек киімді біледі; қалған түрлер Gemini-ге бағытталады.
const FASHN_KINDS = new Set<TryOnKind>(["tops", "bottoms", "one-pieces", "auto"]);

// Қайтарады: киіп көру түрі немесе null (жарамсыз).
function tryOnKindFor(key: string, type: string, audience: string): TryOnKind | null {
  if (audience.startsWith("Детские")) return null; // кәмелетке толмағандар
  const rule = TRYON_RULES[key || "shoes"];
  if (!rule) return null;
  const t = type.trim();
  if (rule.types && Object.prototype.hasOwnProperty.call(rule.types, t)) {
    return rule.types[t];
  }
  return rule.all;
}

// Base64 → ({data URI}) немесе null. JPEG (/9j/) пен PNG (iVBOR) қабылданады.
function toDataUri(raw: string): string | null {
  let s = raw.trim();
  const m = /^data:image\/(jpeg|jpg|png);base64,/i.exec(s);
  if (m) s = s.slice(m[0].length);
  s = s.replace(/\s+/g, "");
  if (!s || s.length > MAX_B64_CHARS || !/^[A-Za-z0-9+/]+=*$/.test(s)) {
    return null;
  }
  if (s.startsWith("/9j/")) return `data:image/jpeg;base64,${s}`;
  if (s.startsWith("iVBOR")) return `data:image/png;base64,${s}`;
  return null;
}

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

  // Дене өлшемі: парсингтен БҰРЫН шектейміз (жадты тауыспау үшін).
  const declared = Number(req.headers.get("content-length") ?? 0);
  if (declared > MAX_BODY_BYTES) return json({ error: "bad_request" }, 413);
  // deno-lint-ignore no-explicit-any
  let body: any;
  try {
    const raw = await req.text();
    if (raw.length > MAX_BODY_BYTES) return json({ error: "bad_request" }, 413);
    body = JSON.parse(raw);
  } catch (_) {
    return json({ error: "bad_request" }, 400);
  }
  const productId = String(body?.productId ?? "");
  if (!UUID_RE.test(productId)) return json({ error: "bad_request" }, 400);
  const person = typeof body?.personImageBase64 === "string"
    ? toDataUri(body.personImageBase64)
    : null;
  if (!person) return json({ error: "bad_request" }, 400);
  const idxRaw = Number(body?.imageIndex ?? 0);
  const imageIndex = Number.isInteger(idxRaw) && idxRaw >= 0 ? idxRaw : 0;

  const userClient = createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false },
  });
  const { data: flagOn } = await userClient.rpc("feature_enabled", {
    p_name: "ai_tryon",
  });
  if (flagOn !== true) return json({ error: "feature_disabled" }, 403);

  // ── Тауар (RLS) + қолжетімділік ──
  const { data: p, error: pErr } = await userClient
    .from("products")
    .select("id, type, category, category_key, images, status, storefront_hidden")
    .eq("id", productId)
    .maybeSingle();
  if (pErr) {
    console.error("product_error", pErr);
    return json({ error: "tryon_failed" }, 502);
  }
  if (!p || p.storefront_hidden === true) return json({ error: "not_found" }, 404);
  const category = tryOnKindFor(
    (p.category_key as string) || "shoes",
    String(p.type ?? ""),
    String(p.category ?? ""),
  );
  if (!category) return json({ error: "not_eligible" }, 400);

  // Индекс ТҮПНҰСҚА p.images массивіне қатысты (клиент нобайы сол тізім).
  // Таңдалған сурет https емес болса — алғашқы https суретке түсеміз.
  const allImages = (p.images ?? []) as unknown[];
  const isHttps = (u: unknown): u is string =>
    typeof u === "string" && u.startsWith("https://");
  const picked = allImages[imageIndex];
  const garment: string | undefined = isHttps(picked)
    ? picked
    : allImages.find(isHttps);
  if (!garment) return json({ error: "not_eligible" }, 400);

  // Қозғалтқыш: суперадмин таңдауы → FASHN → Gemini. Кілт жоқ — квота жұмсалмайды.
  await refreshProviderSetting();
  // Киімнен басқа түрлерді (аяқ киім, аксессуар…) FASHN жасай алмайды —
  // олар үшін тек Gemini; кілті жоқ болса квота жұмсалмай not_configured.
  const engine: "gemini" | "fashn" | null = !FASHN_KINDS.has(category)
    ? (hasGeminiKey() ? "gemini" : null)
    : providerSetting() === "gemini" && hasGeminiKey()
    ? "gemini"
    : FASHN_API_KEY
    ? "fashn"
    : hasGeminiKey()
    ? "gemini"
    : null;
  if (!engine) return json({ error: "not_configured" }, 503);

  // ── Квота: провайдерді шақыру алдында ──
  const { data: remaining, error: qErr } = await userClient.rpc(
    "consume_ai_quota",
    { p_kind: "tryon" },
  );
  if (qErr) {
    const msg = `${qErr.message ?? ""} ${qErr.details ?? ""}`;
    if (msg.includes("ai_quota_exceeded")) {
      return json({ error: "ai_quota_exceeded", remaining: 0 }, 429);
    }
    if (msg.includes("feature_disabled")) {
      return json({ error: "feature_disabled" }, 403);
    }
    console.error("quota_error", qErr);
    return json({ error: "tryon_failed" }, 502);
  }
  const refund = async () => {
    try {
      const admin = createClient(SUPABASE_URL, SERVICE_KEY);
      await admin.rpc("refund_ai_quota", { p_client: uid, p_kind: "tryon" });
    } catch (e) {
      console.error("refund_failed", e);
    }
  };

  if (engine === "gemini") {
    return await geminiTryOn({ uid, person, garment, category, remaining, refund });
  }

  const fashnHeaders = {
    "Content-Type": "application/json",
    Authorization: `Bearer ${FASHN_API_KEY}`,
  };

  try {
    // 1) Тапсырманы бастау
    const runRes = await fetch(`${FASHN_BASE}/run`, {
      method: "POST",
      headers: fashnHeaders,
      body: JSON.stringify({
        model_name: "tryon-v1.6",
        inputs: {
          model_image: person,
          garment_image: garment,
          category,
          mode: "balanced",
          garment_photo_type: "auto",
          num_samples: 1,
          output_format: "jpeg",
          return_base64: false,
        },
      }),
    });
    const runJson = await runRes.json().catch(() => ({}));
    if (!runRes.ok || !runJson?.id) {
      console.error("fashn_run", runRes.status, JSON.stringify(runJson?.error ?? runJson).slice(0, 300));
      // Қайтару тек провайдер жағының ақауында (5xx/429); 4xx — біздің кіріс.
      if (runRes.status >= 500 || runRes.status === 429) await refund();
      return json({ error: "tryon_failed" }, 502);
    }
    const predId = String(runJson.id);

    // 2) Нәтижені күту (≤55 с)
    const started = Date.now();
    while (Date.now() - started < POLL_TOTAL_MS) {
      await sleep(POLL_EVERY_MS);
      const stRes = await fetch(
        `${FASHN_BASE}/status/${encodeURIComponent(predId)}`,
        { headers: { Authorization: `Bearer ${FASHN_API_KEY}` } },
      );
      if (!stRes.ok) {
        // Уақытша қате (rate limit т.б.) — тыңдай береміз, лимит біткенше.
        if (stRes.status === 401 || stRes.status === 403) break;
        continue;
      }
      const st = await stRes.json().catch(() => ({}));
      if (st?.status === "completed") {
        const out = Array.isArray(st.output) ? st.output[0] : null;
        if (typeof out === "string" && out) {
          return json({ imageUrl: out, remaining });
        }
        await refund(); // completed, бірақ output жоқ → қате
        return json({ error: "tryon_failed" }, 502);
      }
      if (st?.status === "failed") {
        console.error("fashn_failed", JSON.stringify(st.error ?? {}).slice(0, 300));
        const errName = String(st.error?.name ?? "");
        if (!USER_INPUT_ERRORS.has(errName)) await refund();
        return json({ error: "tryon_failed" }, 502);
      }
    }
    // Таймаут: FASHN тапсырмасы жалғасып, төлемге жазылуы мүмкін — квота
    // ҚАЙТАРЫЛМАЙДЫ (қайтарсақ, тегін шақырудың тесігі болады).
    return json({ error: "tryon_timeout" }, 504);
  } catch (e) {
    // Желі/күтпеген қате: провайдерге жетпеуі мүмкін → қайтарамыз.
    console.error("tryon_error", (e as Error)?.message);
    await refund();
    return json({ error: "tryon_failed" }, 502);
  }
});

// ── Gemini арқылы киіп көру ────────────────────────────────────────────────
// Түр → (не, қалай). `what` — өнімнің сипаттамасы, `verb` — адамға қалай
// «қосылады», `area` — сол бөлік көрінбесе-ақ ойдан қоспау үшін ескерту.
const KIND_TEXT: Record<TryOnKind, { what: string; verb: string; area: string }> = {
  "tops": { what: "the upper-body garment (top / jacket)", verb: "wearing", area: "the upper body" },
  "bottoms": { what: "the lower-body garment (pants / skirt / shorts)", verb: "wearing", area: "the lower body" },
  "one-pieces": { what: "the full outfit (dress / suit / jumpsuit)", verb: "wearing", area: "the whole outfit" },
  "auto": { what: "the clothing item", verb: "wearing", area: "that area" },
  "footwear": { what: "the pair of shoes", verb: "wearing", area: "the feet" },
  "headwear": { what: "the hat / headwear", verb: "wearing", area: "the head" },
  "eyewear": { what: "the glasses", verb: "wearing", area: "the eyes and nose" },
  "bag": { what: "the bag", verb: "carrying", area: "the shoulder or hand" },
  "jewelry": { what: "the jewelry piece", verb: "wearing", area: "the matching place (ear, neck, finger or wrist)" },
  "watch": { what: "the wrist watch", verb: "wearing", area: "the wrist" },
  "accessory": { what: "the fashion accessory", verb: "wearing or holding", area: "the matching place" },
};

async function geminiTryOn(a: {
  uid: string;
  person: string; // data URI
  garment: string; // https URL (ДБ-дан)
  category: TryOnKind;
  remaining: unknown;
  refund: () => Promise<void>;
}): Promise<Response> {
  const m = /^data:(image\/[a-z]+);base64,(.*)$/s.exec(a.person);
  if (!m) return json({ error: "bad_request" }, 400);
  const person = { mime: m[1] === "image/jpg" ? "image/jpeg" : m[1], data: m[2] };

  let garment: { mime: string; data: string };
  try {
    garment = await fetchImage(a.garment);
  } catch (e) {
    console.error("garment_fetch", (e as Error)?.message);
    await a.refund();
    return json({ error: "tryon_failed" }, 502);
  }

  const t = KIND_TEXT[a.category as TryOnKind] ?? KIND_TEXT.auto;
  const prompt =
    "Virtual try-on. Image 1 is a photo of a person. Image 2 is a product photo of " +
    `${t.what}. Generate ONE photorealistic image of the SAME person from image 1 ` +
    `${t.verb} ${t.what} from image 2 on ${t.area}, replacing what they currently have there. ` +
    "Keep the person's face, identity, skin tone, hair, body shape, pose, framing and " +
    "background exactly as in image 1. Reproduce the product's color, material, pattern, " +
    "logos and details exactly as in image 2, with a natural fit, correct scale and realistic " +
    "folds, reflections and lighting. Do not add text, watermarks or extra people. " +
    "Output only the image.";

  const res = await geminiGenerateImage(prompt, [person, garment]);
  if (!res.ok) {
    console.error("gemini_tryon", res.status, res.reason, res.message.slice(0, 300));
    // Модерация (суреттің өзі) — квота қайтарылмайды; қалғаны провайдер ақауы.
    if (res.reason !== "blocked") await a.refund();
    // Тегін деңгейде сурет моделі жабық (limit: 0) — Google-да төлем қосылмаған.
    if (res.status === 429 && /limit:\s*0/.test(res.message)) {
      return json({ error: "not_configured" }, 503);
    }
    return json({ error: "tryon_failed" }, 502);
  }

  try {
    const admin = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } });
    const bucket = admin.storage.from("tryon-results");
    // Сол пайдаланушының 1 сағаттан ескі нәтижелерін тазалаймыз.
    try {
      const { data: old } = await bucket.list(a.uid, { limit: 100 });
      const cutoff = Date.now() - 60 * 60_000;
      const stale = (old ?? [])
        .filter((o) => o.created_at && Date.parse(o.created_at) < cutoff)
        .map((o) => `${a.uid}/${o.name}`);
      if (stale.length) await bucket.remove(stale);
    } catch (_) {
      // тазалау сәтсіз — басты жұмысқа кедергі емес
    }

    const ext = res.mime.includes("jpeg") ? "jpg" : res.mime.includes("webp") ? "webp" : "png";
    const path = `${a.uid}/${crypto.randomUUID()}.${ext}`;
    const bin = Uint8Array.from(atob(res.data), (c) => c.charCodeAt(0));
    const up = await bucket.upload(path, bin, { contentType: res.mime, upsert: false });
    if (up.error) throw up.error;
    const signed = await bucket.createSignedUrl(path, 60 * 60);
    if (signed.error || !signed.data?.signedUrl) throw signed.error ?? new Error("sign_failed");
    return json({ imageUrl: signed.data.signedUrl, remaining: a.remaining });
  } catch (e) {
    console.error("tryon_store", (e as Error)?.message);
    await a.refund();
    return json({ error: "tryon_failed" }, 502);
  }
}
