// ─── AI провайдері: Anthropic (Claude) НЕМЕСЕ Gemini (тегін деңгей) ───────────
//
// Үш AI функция (ai-assistant, ai-stylist, ai-product-assist) Anthropic
// `messages.create` пішімімен жазылған. Бұл модуль сол пішімді сақтайды:
//   • ANTHROPIC_API_KEY бар → нағыз Anthropic SDK (Claude Haiku 5.5 әдепкі);
//   • болмаса GEMINI_API_KEY бар → Gemini-ге аударатын жеңіл адаптер
//     (мәтін, сурет, tool-use, JSON-схема) — Anthropic кілті келгенше уақытша;
//   • Суперадмин таңдауы: app_settings.ai_provider = auto|gemini|anthropic
//     (0080; refreshProviderSetting() әр сұраудың басында, 60 с кэш);
//   • AI_PROVIDER=anthropic|gemini (Secret) — бәрінен басым, қолмен мәжбүрлеу.
//
// Secrets: ANTHROPIC_API_KEY, AI_MODEL (әдепкі claude-haiku-5-5),
//          GEMINI_API_KEY, GEMINI_MODEL (әдепкі gemini-3.1-flash-lite).
// Кілттер ЕШҚАШАН кодта/клиентте емес — тек Supabase Secrets-те.
import Anthropic from "npm:@anthropic-ai/sdk@1.3.0";

const ANTHROPIC_API_KEY = Deno.env.get("ANTHROPIC_API_KEY") ?? "";
const GEMINI_API_KEY = Deno.env.get("GEMINI_API_KEY") ?? "";
const FORCED = (Deno.env.get("AI_PROVIDER") ?? "").toLowerCase();
const CLAUDE_MODEL = Deno.env.get("AI_MODEL") || "claude-haiku-5-5";
// gemini-2.5-flash тегін деңгейде күніне 20 сұрау ғана — lite модель әлдеқайда кең.
const GEMINI_MODEL = Deno.env.get("GEMINI_MODEL") || "gemini-3.1-flash-lite";

export type Provider = "anthropic" | "gemini";

// ── Суперадмин таңдауы (app_settings.ai_provider) ──────────────────────────
const SB_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SB_SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
let setting = "auto";
let settingAt = 0;

/// app_settings.ai_provider-ді оқиды (60 секундтық кэш). Оқу сәтсіз болса
/// бұрынғы мән қалады — AI сол үшін тоқтап қалмайды.
export async function refreshProviderSetting(): Promise<void> {
  if (Date.now() - settingAt < 60_000 || !SB_URL || !SB_SERVICE) return;
  settingAt = Date.now();
  try {
    const r = await fetch(
      `${SB_URL}/rest/v1/app_settings?key=eq.ai_provider&select=value`,
      { headers: { apikey: SB_SERVICE, Authorization: `Bearer ${SB_SERVICE}` } },
    );
    if (!r.ok) return;
    const rows = await r.json();
    const v = String(rows?.[0]?.value ?? "auto").toLowerCase();
    setting = v === "gemini" || v === "anthropic" ? v : "auto";
  } catch (_) {
    // желі қатесі — бұрынғы мән
  }
}

/// Суперадминнің таңдауы ('auto' | 'gemini' | 'anthropic').
export function providerSetting(): string {
  return FORCED === "gemini" || FORCED === "anthropic" ? FORCED : setting;
}

export function hasGeminiKey(): boolean {
  return !!GEMINI_API_KEY;
}

export function aiProvider(): Provider | null {
  const want = providerSetting();
  if (want === "gemini" && GEMINI_API_KEY) return "gemini";
  if (want === "anthropic" && ANTHROPIC_API_KEY) return "anthropic";
  if (ANTHROPIC_API_KEY) return "anthropic";
  if (GEMINI_API_KEY) return "gemini";
  return null;
}

export function aiConfigured(): boolean {
  return aiProvider() !== null;
}

export function aiModel(): string {
  return aiProvider() === "gemini" ? GEMINI_MODEL : CLAUDE_MODEL;
}

/// true — Anthropic-тың сервер жағындағы fallback-ын (beta) қолдануға болады
/// (тек Claude Opus/Sonnet). Haiku мен Gemini-де жібермейміз.
export function supportsServerFallback(): boolean {
  return aiProvider() === "anthropic" && !CLAUDE_MODEL.startsWith("claude-haiku");
}

// deno-lint-ignore no-explicit-any
type Any = any;

class LlmHttpError extends Error {
  constructor(public status: number, message: string) {
    super(message);
  }
}

// ── JSON Schema → Gemini Schema (OpenAPI ішкі жиыны) ───────────────────────
const DROP_KEYS = new Set([
  "additionalProperties",
  "$schema",
  "$id",
  "$ref",
  "$defs",
  "definitions",
  "default",
  "examples",
  "title",
  "const",
  "pattern",
  "minLength",
  "maxLength",
  "uniqueItems",
  "patternProperties",
]);

function cleanSchema(s: Any): Any {
  if (Array.isArray(s)) return s.map(cleanSchema);
  if (s === null || typeof s !== "object") return s;
  const out: Any = {};
  for (const [k, v] of Object.entries(s)) {
    if (DROP_KEYS.has(k)) continue;
    if (k === "type" && Array.isArray(v)) {
      const nonNull = (v as string[]).filter((t) => t !== "null");
      out.type = nonNull[0] ?? "string";
      if (nonNull.length !== (v as string[]).length) out.nullable = true;
      continue;
    }
    if (k === "properties" && v && typeof v === "object") {
      out.properties = Object.fromEntries(
        Object.entries(v as Any).map(([pk, pv]) => [pk, cleanSchema(pv)]),
      );
      continue;
    }
    out[k] = cleanSchema(v);
  }
  return out;
}

// ── Сурет: URL → inlineData ───────────────────────────────────────────────
const MAX_IMG_BYTES = 6 * 1024 * 1024;

export async function fetchImage(url: string): Promise<{ mime: string; data: string }> {
  if (!/^https:\/\//i.test(url)) throw new LlmHttpError(400, "bad_image_url");
  const ctl = new AbortController();
  const t = setTimeout(() => ctl.abort(), 10_000);
  try {
    const r = await fetch(url, { signal: ctl.signal });
    if (!r.ok) throw new LlmHttpError(400, "image_fetch_failed");
    const buf = new Uint8Array(await r.arrayBuffer());
    if (buf.byteLength > MAX_IMG_BYTES) throw new LlmHttpError(400, "image_too_large");
    let bin = "";
    for (let i = 0; i < buf.length; i += 0x8000) {
      bin += String.fromCharCode(...buf.subarray(i, i + 0x8000));
    }
    const mime = (r.headers.get("content-type") ?? "").split(";")[0].trim();
    return { mime: mime.startsWith("image/") ? mime : "image/jpeg", data: btoa(bin) };
  } catch (e) {
    if (e instanceof LlmHttpError) throw e;
    throw new LlmHttpError(400, "image_fetch_failed");
  } finally {
    clearTimeout(t);
  }
}

// ── Anthropic messages → Gemini contents ──────────────────────────────────
async function toGeminiContents(messages: Any[]): Promise<Any[]> {
  // tool_use_id → функция аты (functionResponse-қа керек)
  const nameById = new Map<string, string>();
  for (const m of messages) {
    if (Array.isArray(m.content)) {
      for (const b of m.content) {
        if (b?.type === "tool_use" && b.id) nameById.set(b.id, b.name);
      }
    }
  }
  const out: Any[] = [];
  const push = (role: string, parts: Any[]) => {
    if (!parts.length) return;
    const last = out[out.length - 1];
    if (last && last.role === role) last.parts.push(...parts);
    else out.push({ role, parts });
  };
  for (const m of messages) {
    const role = m.role === "assistant" ? "model" : "user";
    if (typeof m.content === "string") {
      if (m.content) push(role, [{ text: m.content }]);
      continue;
    }
    const parts: Any[] = [];
    for (const b of (m.content ?? []) as Any[]) {
      if (b.type === "text") {
        if (b.text) parts.push({ text: b.text });
      } else if (b.type === "image") {
        if (b.source?.type === "base64") {
          parts.push({
            inlineData: { mimeType: b.source.media_type, data: b.source.data },
          });
        } else if (b.source?.type === "url") {
          const img = await fetchImage(b.source.url);
          parts.push({ inlineData: { mimeType: img.mime, data: img.data } });
        }
      } else if (b.type === "tool_use") {
        const p: Any = { functionCall: { name: b.name, args: b.input ?? {} } };
        if (b._sig) p.thoughtSignature = b._sig;
        parts.push(p);
      } else if (b.type === "tool_result") {
        const name = nameById.get(b.tool_use_id) ?? "tool";
        let content: Any = b.content;
        if (Array.isArray(content)) {
          content = content.map((c: Any) => c?.text ?? "").join("");
        }
        parts.push({
          functionResponse: {
            name,
            response: b.is_error ? { error: content } : { result: content },
          },
        });
      }
    }
    push(role, parts);
  }
  return out;
}

function mapFinish(candidate: Any, blocked: boolean, hasTool: boolean): string {
  if (blocked) return "refusal";
  if (hasTool) return "tool_use";
  switch (candidate?.finishReason) {
    case "MAX_TOKENS":
      return "max_tokens";
    case "SAFETY":
    case "PROHIBITED_CONTENT":
    case "BLOCKLIST":
    case "SPII":
    case "IMAGE_SAFETY":
      return "refusal";
    default:
      return "end_turn";
  }
}

async function geminiCreate(body: Any, timeoutMs: number, retries: number): Promise<Any> {
  const model = GEMINI_MODEL;
  const payload: Any = {
    contents: await toGeminiContents(body.messages ?? []),
    generationConfig: {
      maxOutputTokens: body.max_tokens ?? 2048,
    },
  };
  // Ойлауды азайтамыз (жылдамдық + тегін лимит): 2.x — thinkingBudget,
  // 3.x — thinkingLevel. Баптау: GEMINI_THINKING (2.x-те сан, 3.x-те деңгей).
  const think = Deno.env.get("GEMINI_THINKING") ?? "";
  payload.generationConfig.thinkingConfig = model.startsWith("gemini-2")
    ? { thinkingBudget: Number(think || "0") }
    : { thinkingLevel: think || "low" };
  if (body.system) {
    payload.systemInstruction = {
      parts: [{ text: typeof body.system === "string" ? body.system : JSON.stringify(body.system) }],
    };
  }
  const fmt = body.output_config?.format;
  if (fmt?.type === "json_schema" && fmt.schema) {
    payload.generationConfig.responseMimeType = "application/json";
    payload.generationConfig.responseSchema = cleanSchema(fmt.schema);
  }
  if (Array.isArray(body.tools) && body.tools.length) {
    payload.tools = [{
      functionDeclarations: body.tools.map((t: Any) => ({
        name: t.name,
        description: t.description ?? "",
        parameters: cleanSchema(t.input_schema ?? { type: "object", properties: {} }),
      })),
    }];
  }

  const url =
    `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`;
  let lastErr: LlmHttpError | null = null;
  for (let attempt = 0; attempt <= retries; attempt++) {
    const ctl = new AbortController();
    const timer = setTimeout(() => ctl.abort(), timeoutMs);
    try {
      const r = await fetch(url, {
        method: "POST",
        headers: { "content-type": "application/json", "x-goog-api-key": GEMINI_API_KEY },
        body: JSON.stringify(payload),
        signal: ctl.signal,
      });
      if (!r.ok) {
        const txt = (await r.text()).slice(0, 300);
        // 503 (overloaded) → Anthropic 529-ға ұқсас «busy» ретінде беріледі.
        lastErr = new LlmHttpError(r.status === 503 ? 529 : r.status, txt);
        if (r.status === 429 || r.status >= 500) {
          if (attempt < retries) {
            await new Promise((res) => setTimeout(res, 1200));
            continue;
          }
        }
        throw lastErr;
      }
      const data = await r.json();
      const cand = data?.candidates?.[0];
      const blocked = !!data?.promptFeedback?.blockReason;
      const content: Any[] = [];
      let n = 0;
      for (const p of (cand?.content?.parts ?? []) as Any[]) {
        if (p.functionCall) {
          content.push({
            type: "tool_use",
            id: `gem_${Date.now().toString(36)}_${n++}`,
            name: p.functionCall.name,
            input: p.functionCall.args ?? {},
            _sig: p.thoughtSignature,
          });
        } else if (typeof p.text === "string" && !p.thought) {
          content.push({ type: "text", text: p.text });
        }
      }
      const hasTool = content.some((b) => b.type === "tool_use");
      return {
        content,
        stop_reason: mapFinish(cand, blocked, hasTool),
        usage: {
          input_tokens: data?.usageMetadata?.promptTokenCount ?? 0,
          output_tokens: data?.usageMetadata?.candidatesTokenCount ?? 0,
        },
      };
    } catch (e) {
      if (e instanceof LlmHttpError) throw e;
      // timeout / желі
      lastErr = new LlmHttpError(504, (e as Error)?.message ?? "network");
      if (attempt >= retries) throw lastErr;
    } finally {
      clearTimeout(timer);
    }
  }
  throw lastErr ?? new LlmHttpError(502, "gemini_failed");
}

/// Anthropic-пішімді клиент: `client.messages.create(body)` және
/// `client.beta.messages.create(body)`. Қателерде `status` өрісі бар
/// (429/529 = busy), сондықтан функциялардағы бұрынғы өңдеу өзгермейді.
export function makeLlmClient(
  opts: { timeout?: number; maxRetries?: number } = {},
  // deno-lint-ignore no-explicit-any
): any {
  const timeout = opts.timeout ?? 30_000;
  const retries = opts.maxRetries ?? 1;
  if (aiProvider() === "gemini") {
    const create = (body: Any) => geminiCreate(body, timeout, retries);
    return { messages: { create }, beta: { messages: { create } } };
  }
  const anth = new Anthropic({ apiKey: ANTHROPIC_API_KEY, timeout, maxRetries: retries });
  if (!GEMINI_API_KEY) return anth;
  // Екі кілт те бар: Claude бірінші. Claude кілті жарамсыз / баланс бітті /
  // модель жоқ / сұрау қабылданбаса (400/401/403/404) — Gemini-ге автоматты ауысады
  // және 10 минут бойы Claude-қа бармай тұрады (әр сұрауда қате күтпеу үшін).
  const viaGemini = (body: Any) => geminiCreate(body, timeout, retries);
  const wrap = (fn: (b: Any) => Promise<Any>) => async (body: Any) => {
    if (Date.now() < claudeDownUntil) return await viaGemini(body);
    try {
      return await fn(body);
    } catch (e) {
      const st = (e as { status?: number })?.status;
      // 400 да кіреді: кілт workspace-ке байланбаған / баланс бітті / сұрау жарамсыз.
      const dead = st === 400 || st === 401 || st === 403 || st === 404;
      if (!dead) throw e;
      console.error("claude_unavailable_fallback_to_gemini", st);
      claudeDownUntil = Date.now() + 10 * 60_000;
      return await viaGemini(body);
    }
  };
  return {
    messages: { create: wrap((b) => anth.messages.create(b)) },
    beta: { messages: { create: wrap((b) => anth.beta.messages.create(b)) } },
  };
}

let claudeDownUntil = 0;

// ── Gemini сурет генерациясы (уақытша «киіп көру») ─────────────────────────
const GEMINI_IMAGE_MODEL = Deno.env.get("GEMINI_IMAGE_MODEL") || "gemini-2.5-flash-image";

export type GeminiImageResult =
  | { ok: true; mime: string; data: string }
  | { ok: false; status: number; reason: "blocked" | "no_image" | "http"; message: string };

/// Мәтін + суреттер → бір сурет. Суреттер {mime, data(base64)}.
export async function geminiGenerateImage(
  prompt: string,
  images: { mime: string; data: string }[],
  timeoutMs = 60_000,
): Promise<GeminiImageResult> {
  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), timeoutMs);
  try {
    const r = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_IMAGE_MODEL}:generateContent`,
      {
        method: "POST",
        headers: { "content-type": "application/json", "x-goog-api-key": GEMINI_API_KEY },
        signal: ctl.signal,
        body: JSON.stringify({
          contents: [{
            role: "user",
            parts: [
              { text: prompt },
              ...images.map((i) => ({ inlineData: { mimeType: i.mime, data: i.data } })),
            ],
          }],
          generationConfig: { responseModalities: ["IMAGE"] },
        }),
      },
    );
    if (!r.ok) {
      return { ok: false, status: r.status, reason: "http", message: (await r.text()).slice(0, 1500) };
    }
    const data = await r.json();
    if (data?.promptFeedback?.blockReason) {
      return { ok: false, status: 200, reason: "blocked", message: String(data.promptFeedback.blockReason) };
    }
    const cand = data?.candidates?.[0];
    for (const p of (cand?.content?.parts ?? []) as Any[]) {
      if (p?.inlineData?.data) {
        return { ok: true, mime: p.inlineData.mimeType ?? "image/png", data: p.inlineData.data };
      }
    }
    const fr = String(cand?.finishReason ?? "");
    const blocked = ["SAFETY", "PROHIBITED_CONTENT", "IMAGE_SAFETY", "BLOCKLIST", "SPII", "IMAGE_PROHIBITED_CONTENT"]
      .includes(fr);
    return { ok: false, status: 200, reason: blocked ? "blocked" : "no_image", message: fr };
  } catch (e) {
    return { ok: false, status: 504, reason: "http", message: (e as Error)?.message ?? "network" };
  } finally {
    clearTimeout(timer);
  }
}
