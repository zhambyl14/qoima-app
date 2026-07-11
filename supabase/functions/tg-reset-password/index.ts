// ─── Qoima: Telegram арқылы парольді қалпына келтіру ─────────────────────────
//
// POST /functions/v1/tg-reset-password   (Verify JWT = OFF)
//   body: { token: string, newPassword: string }
//
// Мақсаты: «Парольді ұмыттым» ағыны. Пайдаланушы алдымен телефонын Telegram-мен
// растайды (telegram-webhook → telegram_verifications.verified=true, phone),
// содан соң қосымша осы функцияны шақырып жаңа пароль қояды. Функция:
//   1) token расталған әрі мерзімі өтпеген бе — тексереді (phone алады).
//   2) сол phone-мен аккаунт табады (users → clients).
//   3) service_role Admin API-мен парольді жаңартады.
//   4) токенді жарамсыз етеді (қайта қолданбау үшін).
//   5) {ok:true, phone} қайтарады → қосымша сол телефон+жаңа парольмен кіреді.
//
// ҚАУІПСІЗДІК: пароль ауыстыру ТЕК расталған токенмен мүмкін (телефон иесі
// екені webhook-та дәлелденген). service_role тек серверде.

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

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

function restHeaders(): Record<string, string> {
  return {
    "apikey": SERVICE_KEY,
    "Authorization": `Bearer ${SERVICE_KEY}`,
    "Content-Type": "application/json",
  };
}

async function findUserIdByPhone(phone: string): Promise<string | null> {
  for (const table of ["users", "clients"]) {
    const res = await fetch(
      `${SUPABASE_URL}/rest/v1/${table}?phone=eq.${encodeURIComponent(phone)}&select=id&limit=1`,
      { headers: restHeaders() },
    );
    const rows = await res.json().catch(() => []);
    if (Array.isArray(rows) && rows[0]?.id) return rows[0].id as string;
  }
  return null;
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  let body: { token?: string; newPassword?: string };
  try {
    body = await req.json();
  } catch (_) {
    return json({ error: "bad_request" }, 400);
  }

  const token = (body.token ?? "").trim();
  const newPassword = body.newPassword ?? "";
  if (!token) return json({ error: "no_token" }, 400);
  if (newPassword.length < 6) return json({ error: "weak_password" }, 400);

  // 1) Токен расталған әрі мерзімі өтпеген бе?
  const nowIso = new Date().toISOString();
  const vres = await fetch(
    `${SUPABASE_URL}/rest/v1/telegram_verifications` +
      `?token=eq.${encodeURIComponent(token)}&verified=eq.true` +
      `&expires_at=gt.${encodeURIComponent(nowIso)}&select=phone&limit=1`,
    { headers: restHeaders() },
  );
  const vrows = await vres.json().catch(() => []);
  const phone: string | undefined = Array.isArray(vrows) && vrows[0]?.phone;
  if (!phone) return json({ error: "not_verified" }, 400);

  // 2) Аккаунт табу.
  const uid = await findUserIdByPhone(phone);
  if (!uid) return json({ error: "no_account", phone }, 404);

  // 3) Парольді жаңарту (Admin API).
  const ures = await fetch(`${SUPABASE_URL}/auth/v1/admin/users/${uid}`, {
    method: "PUT",
    headers: restHeaders(),
    body: JSON.stringify({ password: newPassword }),
  });
  if (!ures.ok) {
    const detail = await ures.text().catch(() => "");
    return json({ error: "update_failed", detail }, 500);
  }

  // 4) Токенді жарамсыз ету (қайта қолданбау үшін).
  await fetch(`${SUPABASE_URL}/rest/v1/telegram_verifications?token=eq.${encodeURIComponent(token)}`, {
    method: "DELETE",
    headers: restHeaders(),
  });

  // 5) Қосымша осы телефон+жаңа парольмен кіреді.
  return json({ ok: true, phone });
});
