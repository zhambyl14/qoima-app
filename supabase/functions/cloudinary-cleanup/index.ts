// Cloudinary суреттерін жою (image garbage collection).
//
// Екі режим:
//   { urls: [...] }   → берілген суреттерді ЛЕЗДЕ өшіреді (клиент: фото ауыстыру/жою).
//                       Сәтсіз болғандар cloudinary_delete_queue кезегіне түседі
//                       (кілт қате/уақытша болса да жоғалмайды — кейін drain тазалайды).
//   { mode: 'drain' } → sweep_sold_out_images() шақырып, кезектегі барлық ескі
//                       суретті Cloudinary-ден өшіреді (админ қосымша ашқанда).
//
// ⚠️ КІЛТТЕРДІ КОДҚА ЖАЗБАҢАЗ! Олар Dashboard → Edge Functions → Secrets
// бөлімінде тұрады, ал мұнда тек АТЫМЕН оқылады:
//   CLOUDINARY_API_KEY, CLOUDINARY_API_SECRET, CLOUDINARY_CLOUD_NAME.
import { createClient } from 'jsr:@supabase/supabase-js@2';

const CLOUD_NAME = Deno.env.get('CLOUDINARY_CLOUD_NAME') ?? 'divynstru';
const API_KEY = Deno.env.get('CLOUDINARY_API_KEY') ?? '';
const API_SECRET = Deno.env.get('CLOUDINARY_API_SECRET') ?? '';

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, 'Content-Type': 'application/json' },
  });
}

function admin() {
  return createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );
}

// Сәтсіз өшірілген URL-дерді кезекке қосу (service_role — RLS айналып өтеді).
// Осылай кілт УАҚЫТША қате болса да сурет жоғалмайды: кілт түзелген соң келесі
// drain оларды өшіреді.
async function enqueue(urls: string[]): Promise<void> {
  if (!urls.length) return;
  try {
    await admin()
        .from('cloudinary_delete_queue')
        .insert(urls.map((u) => ({ url: u })));
  } catch (_) {
    // best-effort — жетім сурет қалуы мүмкін, бірақ UX бұзылмайды
  }
}

// secure_url → public_id ('.../upload/v123/qoima_products/abc.jpg' → 'qoima_products/abc')
function publicIdFromUrl(url: string): string | null {
  const marker = '/upload/';
  const idx = url.indexOf(marker);
  if (idx === -1) return null;
  let path = url.substring(idx + marker.length);
  path = path.replace(/^v\d+\//, '');
  const slash = path.lastIndexOf('/');
  const dot = path.lastIndexOf('.');
  if (dot > slash) path = path.substring(0, dot);
  return path.length ? path : null;
}

async function sha1Hex(input: string): Promise<string> {
  const buf = await crypto.subtle.digest('SHA-1', new TextEncoder().encode(input));
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

// Бір суретті Cloudinary-ден өшіреді (signed destroy). Табылмаса да сәтті саналады.
async function destroy(url: string): Promise<boolean> {
  const publicId = publicIdFromUrl(url);
  if (!publicId) return false;
  const ts = Math.floor(Date.now() / 1000);
  const signature = await sha1Hex(`public_id=${publicId}&timestamp=${ts}${API_SECRET}`);
  const body = new URLSearchParams({
    public_id: publicId,
    timestamp: String(ts),
    api_key: API_KEY,
    signature,
  });
  const resp = await fetch(
    `https://api.cloudinary.com/v1_1/${CLOUD_NAME}/image/destroy`,
    { method: 'POST', body },
  );
  if (!resp.ok) return false;
  const data = await resp.json().catch(() => ({}));
  return data.result === 'ok' || data.result === 'not found';
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);

  let payload: { urls?: string[]; mode?: string } = {};
  try {
    payload = await req.json();
  } catch (_) {
    payload = {};
  }

  const secretsOk = !!API_KEY && !!API_SECRET;

  // ── Лездік режим: берілген URL-дерді өшіру ────────────────────────────────
  if (Array.isArray(payload.urls)) {
    const urls =
        payload.urls.filter((u) => typeof u === 'string' && u) as string[];
    // Кілт жоқ болса — өшірмей, бәрін кезекке сақтап қоямыз (жоғалмасын).
    if (!secretsOk) {
      await enqueue(urls);
      return json(
          { deleted: 0, requested: urls.length, queued: urls.length, secrets: false });
    }
    let deleted = 0;
    const failed: string[] = [];
    for (const u of urls) {
      if (await destroy(u)) {
        deleted++;
      } else {
        failed.push(u); // кілт қате/желі болса осында түседі → кезекке
      }
    }
    await enqueue(failed);
    return json({ deleted, requested: urls.length, queued: failed.length });
  }

  // ── Drain режимі: sweep + кезекті тазалау (service_role) ──────────────────
  if (payload.mode === 'drain') {
    if (!secretsOk) return json({ error: 'cloudinary_secrets_missing' }, 500);
    const a = admin();

    // 1) 14+ күн сатулы тұрғандардың фотосын кезекке қосамыз.
    await a.rpc('sweep_sold_out_images', { p_days: 14 });

    // 2) Кезекті партиялап Cloudinary-ден өшіреміз. Сәтсіздер кезекте ҚАЛАДЫ
    //    (кілт түзелген соң келесі drain тазалайды).
    let deleted = 0;
    let processed = 0;
    for (;;) {
      const { data: rows, error } = await a
        .from('cloudinary_delete_queue')
        .select('id,url')
        .limit(100);
      if (error || !rows || rows.length === 0) break;
      const doneIds: number[] = [];
      for (const row of rows) {
        processed++;
        if (await destroy(row.url)) {
          deleted++;
          doneIds.push(row.id); // тек СӘТТІ өшкенді кезектен аламыз
        }
      }
      if (doneIds.length) {
        await a.from('cloudinary_delete_queue').delete().in('id', doneIds);
      }
      // Осы партияда ешнәрсе өшпесе (бәрі сәтсіз) — шексіз циклден шығамыз.
      if (doneIds.length === 0 || rows.length < 100) break;
    }
    return json({ mode: 'drain', processed, deleted });
  }

  return json({ error: 'bad_request' }, 400);
});
