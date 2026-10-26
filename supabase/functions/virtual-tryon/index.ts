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
//   • Қолжетімділік ережесі lib/ui/client/ai/try_on_eligibility.dart-пен БІРДЕЙ.
//   • Квота consume_ai_quota('tryon') — тек провайдерді шақыру алдында;
//     refund_ai_quota (тек service_role) — тек провайдер ақауында (5xx, output
//     жоқ, кіріске қатысты емес қате). Кіріс қатесі мен таймаутта қайтарылмайды.
//   • Secrets: FASHN_API_KEY (міндетті; жоқ болса 503 not_configured).
//
// Қателер: bad_request 400, not_eligible 400, no_auth/invalid_session 401,
//   feature_disabled 403, not_found 404, ai_quota_exceeded 429, tryon_failed 502,
//   tryon_timeout 504, not_configured 503.
import { createClient } from "jsr:@supabase/supabase-js@2";

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

// ── Қолжетімділік (Dart: isTryOnEligible-пен СИНХРОНДЫ) ──────────────────
// Қайтарады: FASHN киім категориясы немесе null (жарамсыз).
function garmentCategory(
  key: string,
  type: string,
  audience: string,
): "tops" | "bottoms" | "one-pieces" | "auto" | null {
  if (audience.startsWith("Детские")) return null; // кәмелетке толмағандар
  switch (key) {
    case "tshirt":
    case "outer":
      return "tops";
    case "pants":
      return "bottoms";
    case "dress":
      if (type === "Юбка") return "bottoms";
      if (type === "Платье" || type === "Сарафан" || type === "Костюм") {
        return "one-pieces";
      }
      return "auto"; // «Свой вариант» түрі
    case "sport":
      if (type === "Спортивный костюм") return "one-pieces";
      if (type === "Топ") return "tops";
      if (type === "Леггинсы" || type === "Шорты") return "bottoms";
      return null; // жабдық
    default:
      return null; // underwear, kids, shoes, acc, caps, jewelry, киім емес
  }
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
  const category = garmentCategory(
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

  // Кілт жоқ болса — квотаны жұмсамаймыз.
  if (!FASHN_API_KEY) return json({ error: "not_configured" }, 503);

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
