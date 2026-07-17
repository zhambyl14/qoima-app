// ─── Qoima: push-хабарлама жіберу (FCM v1, Google Service Account OAuth2) ────
//
// Backend Supabase-те қалады — бұл функция ТЕК Firebase-ке хабарлама
// жеткізуге арналған делдал. Шақырушы — тек DB триггерлері (public.notify_push,
// pg_net арқылы), пайдаланушы JWT-і ЕМЕС, сол себепті verify_jwt=false және
// оның орнына ортақ құпия header (x-push-secret) тексеріледі.
//
// POST body: { uid?: string, uids?: string[], title: string, body: string,
//              data?: Record<string, unknown> }
//
// Керек секреттер (Supabase Dashboard → Edge Functions → send-push → Secrets):
//   FIREBASE_SERVICE_ACCOUNT — Firebase Console → Project Settings →
//     Service accounts → Generate new private key → JSON-ды ТОЛЫҒЫМЕН бір
//     жол етіп осы секретке қой.
//   PUSH_TRIGGER_SECRET — DB vault-тағы 'push_trigger_secret' мәнімен ДӘЛ
//     бірдей болуы керек (0020 миграциясы жасаған кездейсоқ жол).

const PUSH_SECRET = Deno.env.get("PUSH_TRIGGER_SECRET") ?? "";
const SA_RAW = Deno.env.get("FIREBASE_SERVICE_ACCOUNT") ?? "";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "x-push-secret, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...CORS },
  });
}

// ── Google service-account JWT bearer flow (RS256, Web Crypto — пакетсіз) ───
let cachedToken: { token: string; exp: number } | null = null;

function base64url(bytes: ArrayBuffer | Uint8Array): string {
  const b = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  let s = "";
  for (const byte of b) s += String.fromCharCode(byte);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function importPrivateKey(pem: string): Promise<CryptoKey> {
  const clean = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  const der = Uint8Array.from(atob(clean), (c) => c.charCodeAt(0));
  return crypto.subtle.importKey(
    "pkcs8",
    der.buffer,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
}

async function getAccessToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedToken && cachedToken.exp - 60 > now) return cachedToken.token;

  const sa = JSON.parse(SA_RAW) as {
    client_email: string;
    private_key: string;
  };
  const header = { alg: "RS256", typ: "JWT" };
  const claims = {
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  };
  const enc = new TextEncoder();
  const unsigned = `${base64url(enc.encode(JSON.stringify(header)))}.${
    base64url(enc.encode(JSON.stringify(claims)))
  }`;
  const key = await importPrivateKey(sa.private_key);
  const sig = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    enc.encode(unsigned),
  );
  const jwt = `${unsigned}.${base64url(sig)}`;

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: `grant_type=${
      encodeURIComponent("urn:ietf:params:oauth:grant-type:jwt-bearer")
    }&assertion=${jwt}`,
  });
  if (!res.ok) throw new Error(`oauth_failed: ${await res.text()}`);
  const tok = await res.json();
  cachedToken = {
    token: tok.access_token,
    exp: now + (tok.expires_in ?? 3600),
  };
  return tok.access_token;
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  // Тек DB триггерлері (ортақ құпиямен) шақыра алады.
  if (!PUSH_SECRET || req.headers.get("x-push-secret") !== PUSH_SECRET) {
    return json({ error: "forbidden" }, 403);
  }
  if (!SA_RAW) return json({ error: "not_configured" }, 500);

  const body = await req.json().catch(() => ({}));
  const uids: string[] = body.uids ?? (body.uid ? [body.uid] : []);
  const title = (body.title ?? "").toString();
  const msgBody = (body.body ?? "").toString();
  const data = (body.data ?? {}) as Record<string, unknown>;
  if (uids.length === 0 || !title) return json({ error: "bad_request" }, 400);

  // fcm_tokens-тен осы uid(-дер)дің токендерін аламыз (service_role — RLS айналып өтеді).
  const tokensRes = await fetch(
    `${SUPABASE_URL}/rest/v1/fcm_tokens?uid=in.(${uids.join(",")})&select=token`,
    {
      headers: {
        apikey: SERVICE_KEY,
        Authorization: `Bearer ${SERVICE_KEY}`,
      },
    },
  );
  const rows = await tokensRes.json().catch(() => []);
  const tokens: string[] = Array.isArray(rows)
    ? rows.map((r: { token: string }) => r.token)
    : [];
  if (tokens.length === 0) return json({ ok: true, sent: 0 });

  let accessToken: string;
  try {
    accessToken = await getAccessToken();
  } catch (e) {
    return json({ error: "auth_failed", detail: String(e) }, 500);
  }

  const sa = JSON.parse(SA_RAW) as { project_id: string };
  const stringData: Record<string, string> = {};
  for (const [k, v] of Object.entries(data)) stringData[k] = String(v);

  let sent = 0;
  const invalid: string[] = [];
  await Promise.all(
    tokens.map(async (token) => {
      const res = await fetch(
        `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`,
        {
          method: "POST",
          headers: {
            Authorization: `Bearer ${accessToken}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            message: {
              token,
              notification: { title, body: msgBody },
              data: stringData,
              android: { priority: "high" },
              apns: {
                payload: { aps: { sound: "default" } },
                headers: { "apns-priority": "10" },
              },
            },
          }),
        },
      );
      if (res.ok) {
        sent++;
      } else {
        const errText = await res.text().catch(() => "");
        // Токен ескірген/аппты жойған — базадан тазалаймыз (FCM v1 үлгі қатесі).
        if (
          errText.includes("UNREGISTERED") ||
          errText.includes("NOT_FOUND") ||
          errText.includes("INVALID_ARGUMENT")
        ) {
          invalid.push(token);
        }
      }
    }),
  );

  if (invalid.length > 0) {
    await Promise.all(
      invalid.map((t) =>
        fetch(
          `${SUPABASE_URL}/rest/v1/fcm_tokens?token=eq.${
            encodeURIComponent(t)
          }`,
          {
            method: "DELETE",
            headers: {
              apikey: SERVICE_KEY,
              Authorization: `Bearer ${SERVICE_KEY}`,
            },
          },
        )
      ),
    );
  }

  return json({ ok: true, sent, invalidRemoved: invalid.length });
});
