// ─── Qoima: LiveKit кіру токені (live shopping, 0071) ──────────────────────
//
// POST /functions/v1/livekit-token   body: { sessionId: "<uuid>", asViewer?: true }
// Verify JWT = ON (тек кірген қолданушы). Caller uid-і /auth/v1/user арқылы
// ӨЗ JWT-імен анықталады; эфир/дүкен деректері service_role-мен оқылады.
//
// Жауап: { url, token, role: 'host' | 'viewer', identity }
//   • host   — осы дүкеннің белсенді қызметкері (admin не active seller,
//              блоксыз): canPublish + canPublishData + canSubscribe.
//   • viewer — қалғандары, ТЕК дүкен жарияланған әрі блокталмаған болса:
//              тек canSubscribe (жариялау/дата жоқ — чат RPC арқылы).
//   identity = uid (бір адам — бір қатысушы), name = тек аты.
//   Токен мерзімі — 2 сағат.
//
// Қажетті secrets (Dashboard → Edge Functions → Secrets):
//   LIVEKIT_URL         wss://<project>.livekit.cloud
//   LIVEKIT_API_KEY     LiveKit API key
//   LIVEKIT_API_SECRET  LiveKit API secret
//   (SUPABASE_URL / SUPABASE_ANON_KEY / SUPABASE_SERVICE_ROLE_KEY — әдепкі)
// Біреуі жоқ болса → 503 { error: 'not_configured' }.
// Суперадмин өшіргіші (0067b): feature_enabled('live_shopping') жоқ болса →
// 403 { error: 'feature_disabled' } (хост пен көрерменге бірдей).
//
// JWT (HS256) WebCrypto арқылы қолмен қол қойылады — сыртқы тәуелділік жоқ.
// Формат: docs.livekit.io → Tokens & grants (iss=api key, sub=identity,
// nbf/exp, video grant {room, roomJoin, canPublish, canSubscribe, canPublishData}).

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;

const LIVEKIT_URL = Deno.env.get("LIVEKIT_URL") ?? "";
const LIVEKIT_API_KEY = Deno.env.get("LIVEKIT_API_KEY") ?? "";
const LIVEKIT_API_SECRET = Deno.env.get("LIVEKIT_API_SECRET") ?? "";

const TOKEN_TTL_SEC = 2 * 60 * 60;
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

function serviceHeaders(): Record<string, string> {
  return {
    apikey: SERVICE_KEY,
    Authorization: `Bearer ${SERVICE_KEY}`,
    "Content-Type": "application/json",
  };
}

// service_role-мен бір жолды оқу (табылмаса null).
async function selectOne<T>(path: string): Promise<T | null> {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/${path}`, {
    headers: serviceHeaders(),
  });
  if (!res.ok) throw new Error(`db_${res.status}`);
  const rows = (await res.json()) as T[];
  return rows.length > 0 ? rows[0] : null;
}

// ── HS256 JWT (WebCrypto) ───────────────────────────────────────────────────
function b64url(bytes: Uint8Array): string {
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
function b64urlJson(obj: unknown): string {
  return b64url(new TextEncoder().encode(JSON.stringify(obj)));
}
async function signJwt(payload: Record<string, unknown>): Promise<string> {
  const head = b64urlJson({ alg: "HS256", typ: "JWT" });
  const body = b64urlJson(payload);
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(LIVEKIT_API_SECRET),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(`${head}.${body}`),
  );
  return `${head}.${body}.${b64url(new Uint8Array(sig))}`;
}

// Суперадмин жалаушасы (app_settings 'feature_live_shopping'). Қате болса —
// жабық деп санаймыз (белгісіз → false, 0067b-мен бірдей).
async function featureOn(name: string): Promise<boolean> {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/feature_enabled`, {
    method: "POST",
    headers: serviceHeaders(),
    body: JSON.stringify({ p_name: name }),
  });
  if (!res.ok) return false;
  return (await res.json()) === true;
}

type UserRow = {
  id: string;
  role: string | null;
  owner_id: string | null;
  blocked: boolean | null;
  join_status: string | null;
  name: string | null;
};

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  if (!LIVEKIT_URL || !LIVEKIT_API_KEY || !LIVEKIT_API_SECRET) {
    return json({ error: "not_configured" }, 503);
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader) return json({ error: "no_auth" }, 401);

  // 1) Caller кім — ӨЗ JWT-імен (service_role емес).
  const whoRes = await fetch(`${SUPABASE_URL}/auth/v1/user`, {
    headers: { apikey: ANON_KEY, Authorization: authHeader },
  });
  if (!whoRes.ok) return json({ error: "invalid_session" }, 401);
  const who = await whoRes.json().catch(() => ({}));
  const uid = who?.id as string | undefined;
  if (!uid) return json({ error: "invalid_session" }, 401);

  const body = await req.json().catch(() => ({}));
  const sessionId = String(body?.sessionId ?? "");
  // asViewer: қызметкер өз эфирін көрермен ретінде қарағанда — хостпен бір
  // identity болып, LiveKit хостты (duplicate identity) үзіп жібермесін.
  const asViewer = body?.asViewer === true;
  if (!UUID_RE.test(sessionId)) return json({ error: "bad_request" }, 400);

  try {
    if (!(await featureOn("live_shopping"))) {
      return json({ error: "feature_disabled" }, 403);
    }

    // 2) Эфир бар ма, тірі ме.
    const session = await selectOne<{
      id: string;
      admin_uid: string;
      status: string;
      room_name: string;
    }>(
      `live_sessions?id=eq.${sessionId}&select=id,admin_uid,status,room_name`,
    );
    if (!session) return json({ error: "live_not_found" }, 404);
    if (session.status !== "live") return json({ error: "live_ended" }, 410);

    // 3) Caller осы дүкеннің қызметкері ме.
    const user = await selectOne<UserRow>(
      `users?id=eq.${uid}&select=id,role,owner_id,blocked,join_status,name`,
    );
    let isHost = false;
    if (
      user &&
      (user.role === "admin" || user.role === "seller") &&
      !user.blocked &&
      (user.owner_id ?? user.id) === session.admin_uid &&
      (user.role === "admin" || user.join_status === "active")
    ) {
      // Иесі глобал блокта болса — сатушы да хост бола алмайды (каскад).
      const owner = user.id === session.admin_uid ? user : await selectOne<
        UserRow
      >(`users?id=eq.${session.admin_uid}&select=id,blocked`);
      isHost = !owner?.blocked && !asViewer;
    }

    // 4) Көрермен — тек жарияланған, блоксыз дүкен.
    if (!isHost) {
      const store = await selectOne<{
        is_published: boolean | null;
        status: string | null;
      }>(
        `stores?admin_uid=eq.${session.admin_uid}&select=is_published,status`,
      );
      const owner = await selectOne<{ blocked: boolean | null }>(
        `users?id=eq.${session.admin_uid}&select=blocked`,
      );
      if (
        !store || store.is_published !== true || store.status === "blocked" ||
        owner?.blocked === true
      ) {
        return json({ error: "store_unavailable" }, 403);
      }
    }

    // 5) Аты (тек бірінші сөз): clients → users.
    let fullName = user?.name ?? "";
    if (!fullName) {
      const client = await selectOne<{ name: string | null }>(
        `clients?id=eq.${uid}&select=name`,
      );
      fullName = client?.name ?? "";
    }
    const firstName = fullName.trim().split(/\s+/)[0] ?? "";

    const identity = asViewer ? `${uid}:v` : uid;
    const now = Math.floor(Date.now() / 1000);
    const token = await signJwt({
      iss: LIVEKIT_API_KEY,
      // Қызметкер көрермен ретінде кірсе — бөлек identity (хостты үзбеу үшін).
      sub: identity,
      jti: `${identity}_${now}`,
      name: firstName,
      nbf: now - 10,
      exp: now + TOKEN_TTL_SEC,
      video: {
        room: session.room_name,
        roomJoin: true,
        canSubscribe: true,
        canPublish: isHost,
        canPublishData: isHost,
        ...(isHost ? { canPublishSources: ["camera", "microphone"] } : {}),
      },
      metadata: JSON.stringify({ role: isHost ? "host" : "viewer" }),
    });

    return json({
      url: LIVEKIT_URL,
      token,
      role: isHost ? "host" : "viewer",
      identity,
    });
  } catch (e) {
    console.error("livekit-token failed", e);
    return json({ error: "internal" }, 500);
  }
});
