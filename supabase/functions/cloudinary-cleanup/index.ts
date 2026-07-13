// Cloudinary суреттерін жою (image garbage collection).
//
// Режимдер:
//   { urls: [...] }   → берілген суреттерді ЛЕЗДЕ өшіреді (клиент: фото ауыстыру/жою).
//                       Сәтсіз болғандар cloudinary_delete_queue кезегіне түседі
//                       (кілт қате/уақытша болса да жоғалмайды — кейін drain тазалайды).
//   { mode: 'drain' } → АВТОМАТТЫ толық тазалау (админ қосымша ашқанда, қолмен
//                       растаусыз): sweep_sold_out_images() → кезекті тазалау →
//                       Cloudinary ↔ БД ТОЛЫҚ салыстыру (reconcile, doDelete=true) —
//                       products.images-те ешбір жерде сілтелмейтін кез келген
//                       қалдық сурет (restock/ескі баг қалдығы, т.б.) осында өшеді.
//   { mode: 'reconcile', confirm?: bool } → қолмен диагностика/тексеру ғана
//                       (confirm жоқ/false — dry-run, тек сан; confirm:true — өшіреді).
//                       Күнделікті тазалау drain-нің ІШІНДЕ автоматты жүреді.
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

// Cloudinary-дегі qoima_products қалтасының БАРЛЫҚ public_id-ін оқиды.
// ЕСКЕРТУ: классикалық prefix-іздеу (`resources/image/upload?prefix=`) жаңа
// Cloudinary аккаунттарында (Dynamic Folder Mode) толық тізім қайтармайды —
// сол себепті нақты қалта бойынша `resources/by_asset_folder` қолданамыз
// (дұрыс тексерілді: prefix әдісі 56/92 қайтарса, by_asset_folder 92/92 береді).
// Кез келген жағдайда екеуін де шақырып, нәтижені біріктіреміз (дедуп) —
// аккаунт режимінен тәуелсіз қауіпсіз.
async function listAllProductPublicIds(): Promise<string[]> {
  const auth = 'Basic ' + btoa(`${API_KEY}:${API_SECRET}`);
  const ids = new Set<string>();

  // 1) Заманауи: asset_folder бойынша (Dynamic Folder Mode-та дұрыс жұмыс істейді).
  {
    let cursor: string | undefined;
    for (;;) {
      const url = new URL(
        `https://api.cloudinary.com/v1_1/${CLOUD_NAME}/resources/by_asset_folder`,
      );
      url.searchParams.set('asset_folder', 'qoima_products');
      url.searchParams.set('max_results', '500');
      if (cursor) url.searchParams.set('next_cursor', cursor);
      const resp = await fetch(url.toString(), { headers: { Authorization: auth } });
      if (!resp.ok) break;
      const data = await resp.json().catch(() => ({}));
      for (const r of data.resources ?? []) {
        if (typeof r.public_id === 'string') ids.add(r.public_id);
      }
      cursor = data.next_cursor;
      if (!cursor) break;
    }
  }

  // 2) Классикалық: prefix бойынша (ескі/Fixed Folder Mode аккаунттар үшін).
  {
    let cursor: string | undefined;
    for (;;) {
      const url = new URL(
        `https://api.cloudinary.com/v1_1/${CLOUD_NAME}/resources/image/upload`,
      );
      url.searchParams.set('prefix', 'qoima_products/');
      url.searchParams.set('type', 'upload');
      url.searchParams.set('max_results', '500');
      if (cursor) url.searchParams.set('next_cursor', cursor);
      const resp = await fetch(url.toString(), { headers: { Authorization: auth } });
      if (!resp.ok) break;
      const data = await resp.json().catch(() => ({}));
      for (const r of data.resources ?? []) {
        if (typeof r.public_id === 'string') ids.add(r.public_id);
      }
      cursor = data.next_cursor;
      if (!cursor) break;
    }
  }

  return [...ids];
}

// Cloudinary ↔ БД толық салыстыру: products.images-те сілтелмейтін (жетім)
// public_id-дерді табады. [doDelete] true болса — тапқанын бірден өшіреді
// (drain — автоматты жол); false болса — тек санайды (reconcile dry-run).
async function reconcile(
  a: ReturnType<typeof admin>,
  doDelete: boolean,
): Promise<{ total: number; referenced: number; orphaned: number; deleted: number }> {
  const allIds = await listAllProductPublicIds();

  const referenced = new Set<string>();
  let from = 0;
  const pageSize = 1000;
  for (;;) {
    const { data: rows, error } = await a
      .from('products')
      .select('images')
      .range(from, from + pageSize - 1);
    if (error || !rows) break;
    for (const row of rows) {
      for (const u of (row as { images?: string[] }).images ?? []) {
        const pid = publicIdFromUrl(u);
        if (pid) referenced.add(pid);
      }
    }
    if (rows.length < pageSize) break;
    from += pageSize;
  }

  const orphanIds = allIds.filter((id) => !referenced.has(id));
  let deleted = 0;
  if (doDelete) {
    for (const pid of orphanIds) {
      if (await destroyById(pid)) deleted++;
    }
  }
  return {
    total: allIds.length,
    referenced: referenced.size,
    orphaned: orphanIds.length,
    deleted,
  };
}

// Бір суретті public_id бойынша Cloudinary-ден өшіреді (signed destroy).
async function destroyById(publicId: string): Promise<boolean> {
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

// Бір суретті жою (secure_url арқылы). Табылмаса да сәтті саналады.
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

  let payload: { urls?: string[]; mode?: string; confirm?: boolean } = {};
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

    // 3) ТОЛЫҚ салыстыру: Cloudinary-дегі qoima_products файлдарын
    //    products.images-пен салыстырып, сілтелмейтіндерін АВТОМАТТЫ өшіреді.
    //    Бұл drain-нің бөлігі болғандықтан ешбір қолмен растау қажет емес —
    //    админ қосымшаны әр ашқанда фондық түрде қайталанады.
    const rec = await reconcile(a, /* doDelete */ true);

    return json({
      mode: 'drain',
      processed,
      deleted,
      reconcile: rec,
    });
  }

  // ── Reconcile режимі: қолмен шақыру (тестілеу/тексеру үшін) ────────────────
  // Әдепкі — DRY-RUN (confirm:true жіберілмесе ештеңе өшірілмейді, тек сан
  // қайтарады). Күнделікті автоматты тазалау 'drain' режимінің ІШІНДЕ жүреді
  // (жоғарыны қараңыз) — бұл тек диагностика/бір реттік тексеру үшін.
  if (payload.mode === 'reconcile') {
    if (!secretsOk) return json({ error: 'cloudinary_secrets_missing' }, 500);
    const a = admin();
    const rec = await reconcile(a, payload.confirm === true);
    return json({
      mode: 'reconcile',
      dryRun: payload.confirm !== true,
      totalInCloudinary: rec.total,
      referencedInDb: rec.referenced,
      orphaned: rec.orphaned,
      deleted: rec.deleted,
    });
  }

  return json({ error: 'bad_request' }, 400);
});
