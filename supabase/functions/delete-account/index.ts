// ─── Qoima: аккаунтты өзін-өзі өшіру (client/seller/admin бәріне ортақ) ──────
//
// POST /functions/v1/delete-account   (Verify JWT = ON — тек кіріп тұрған
// пайдаланушы шақыра алады, ешбір body қажет емес — caller = жойылатын uid)
//
// Ағыны:
//   1) Caller-дің өз JWT-і арқылы (Authorization header, /auth/v1/user) uid
//      анықталады — ешкім басқа біреудің аккаунтын жоя алмайды.
//   2) Егер бұл admin (дүкен иесі) болса, оны owner_id ретінде меңзеп тұрған
//      сатушылар алдын ала БОСАТЫЛАДЫ (owner_id=null, join_status='none') —
//      әйтпесе users.owner_id FK RESTRICT-і auth.users өшіруге кедергі жасайды
//      (AuthService.detachFromOwner-мен бірдей семантика).
//   3) service_role Admin API-мен auth.users жолы өшіріледі — қалғанының бәрі
//      (users/clients/products/batches/sales_history/orders/warehouses/stores...)
//      FK ON DELETE CASCADE арқылы АВТОМАТТЫ өшеді (0001 схемасы солай құрылған).
//
// ЕСКЕРТУ: admin өз аккаунтын өшірсе — БҮКІЛ бизнес деректері (тауарлар,
// сатылым тарихы, дүкен) қайтарылмастай жойылады. Қосымша UI мұны нақты
// ескертуі керек (жай "Точно?" емес).
//
// Cloudinary суреттері бұл жерде ӨШІРІЛМЕЙДІ (жылдамдық үшін) — жетім
// қалғандарын cloudinary-cleanup fn-нің АВТОМАТТЫ 'drain' режимі келесі
// admin қосымшаны ашқанда өзі тазалайды (reconcile, [[cloudinary_image_gc]]).

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;

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

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader) return json({ error: "no_auth" }, 401);

  // 1) Caller кім екенін ӨЗ JWT-імен анықтаймыз (service_role емес).
  const whoRes = await fetch(`${SUPABASE_URL}/auth/v1/user`, {
    headers: { apikey: ANON_KEY, Authorization: authHeader },
  });
  if (!whoRes.ok) return json({ error: "invalid_session" }, 401);
  const who = await whoRes.json().catch(() => ({}));
  const uid = who?.id as string | undefined;
  if (!uid) return json({ error: "invalid_session" }, 401);

  // 2) Бұл uid-ты owner_id ретінде меңзейтін сатушылар болса — босатамыз
  //    (FK RESTRICT-ке тірелмес үшін). Admin/client/жеке сатушыда әсері жоқ.
  await fetch(
    `${SUPABASE_URL}/rest/v1/users?owner_id=eq.${uid}&id=neq.${uid}`,
    {
      method: "PATCH",
      headers: { ...serviceHeaders(), Prefer: "return=minimal" },
      body: JSON.stringify({
        owner_id: null,
        join_status: "none",
        assigned_warehouse_id: null,
      }),
    },
  );

  // 3) auth.users жолын өшіру — қалғаны FK CASCADE арқылы кетеді.
  const delRes = await fetch(`${SUPABASE_URL}/auth/v1/admin/users/${uid}`, {
    method: "DELETE",
    headers: serviceHeaders(),
  });
  if (!delRes.ok) {
    const detail = await delRes.text().catch(() => "");
    return json({ error: "delete_failed", detail }, 500);
  }

  return json({ ok: true });
});
