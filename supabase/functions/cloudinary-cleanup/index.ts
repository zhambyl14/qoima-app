// Cloudinary суреттерін жою (image garbage collection).
//
// ҚАУІПСІЗДІК (2026-11): бұрын функция ешкімді тексермейтін — публиктік anon
// кілті бар кез келген адам кез келген суретті өшіре алатын. Енді:
//   • Әр сұранысқа НАҚТЫ пайдаланушы JWT-і керек (Authorization: Bearer …),
//     серверде auth.getUser(token) арқылы тексеріледі. anon/publishable кілт,
//     анонимді сессия, жоқ/жарамсыз токен → 401.
//   • Шешім логикасы guard.ts-те (Node-та тестіленеді), «кімнің суреті»
//     тексерісі БД-да: cloudinary_blocked_ids (0089 миграция).
//   • 0089 қолданылмаған болса — ЕШТЕҢЕ ӨШІРІЛМЕЙДІ (fail-closed): {urls}
//     кезекке түседі, drain/reconcile 503 қайтарады.
//
// Режимдер:
//   { urls: [...] }   → кез келген кірген пайдаланушы. ≤30 URL, әрқайсысы тек
//                       https://res.cloudinary.com/<CLOUD>/image/upload/[v…/]
//                       <біздің қалта>/… (guard.ts). Бөтен жолда сілтелген
//                       сурет (басқа дүкеннің тауары/сторисі, басқа клиенттің
//                       чегі, т.б.) ӨШІРІЛМЕЙДІ (denied). Ешқайда сілтелмеген
//                       сурет өшіріледі — ешкімге зияны жоқ (тек біздің
//                       қалталарда, ал public_id кездейсоқ — тауып алу мүмкін емес).
//                       Сәтсіз destroy → cloudinary_delete_queue (drain қайталайды).
//                       Пайдаланушы бойынша дроссель: URLS_MIN_SECONDS-та бір
//                       шақыру, әйтпесе 429 (клиент кезекке салады).
//   { mode: 'drain' } → тек admin/superadmin (блоксыз). Жаһандық дроссель:
//                       10 минутта бір рет (cloudinary_gc_try_claim). Ағыны:
//                       sweep_sold_out_images() → кезекті тазалау (әр жол қайта
//                       тексеріледі: жарамсыз/бөтен сілтелген → кезектен
//                       алынады, өшірілмейді) → 6 сағатта бір рет
//                       Cloudinary ↔ БД салыстыру (reconcile, өшіреді).
//   { mode: 'reconcile', confirm?: bool } → диагностика, ТЕК superadmin
//                       (dry-run да): 'admin' рөлін кез келген адам тіркеліп
//                       алады. confirm:true — өшіреді. 2 минутта бір рет.
//
// ⚠️ КІЛТТЕРДІ КОДҚА ЖАЗБАҢАЗ! Олар Dashboard → Edge Functions → Secrets
// бөлімінде тұрады, ал мұнда тек АТЫМЕН оқылады:
//   CLOUDINARY_API_KEY, CLOUDINARY_API_SECRET, CLOUDINARY_CLOUD_NAME.
// Лог-қа ешқашан токен/кілт/URL тізімі жазылмайды — тек қате коды мен сандар.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import {
  bearerToken,
  canReconcile,
  type CallerProfile,
  classifyQueueRows,
  isPlausibleUserJwt,
  isStaff,
  isValidCloudName,
  lenientPublicId,
  MAX_BODY_BYTES,
  type ParsedImage,
  reconcileCandidates,
  splitByBlocked,
  URLS_MIN_SECONDS,
  userThrottleKey,
  validateUrlList,
} from './guard.ts';

const CLOUD_NAME = Deno.env.get('CLOUDINARY_CLOUD_NAME') ?? 'divynstru';
const API_KEY = Deno.env.get('CLOUDINARY_API_KEY') ?? '';
const API_SECRET = Deno.env.get('CLOUDINARY_API_SECRET') ?? '';
const ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY') ?? '';

/** drain арасындағы ең аз уақыт (жаһандық, барлық дүкен үшін). */
const DRAIN_MIN_SECONDS = 10 * 60;
/** drain ішіндегі автоматты reconcile (Admin API тізімі қымбат). */
const RECONCILE_AUTO_MIN_SECONDS = 6 * 60 * 60;
/** Қолмен reconcile. */
const RECONCILE_MANUAL_MIN_SECONDS = 2 * 60;
/** Бір drain-де кезектен өңделетін ең көп жол / reconcile-де ең көп өшіру. */
const DRAIN_MAX_ROWS = 300;
const RECONCILE_MAX_DELETES = 300;
/** cloudinary_blocked_ids-ке бір шақыруда жіберілетін id саны. */
const GUARD_CHUNK = 200;

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
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
    { auth: { persistSession: false, autoRefreshToken: false } },
  );
}
type Admin = ReturnType<typeof admin>;

class GuardUnavailable extends Error {}

// Сәтсіз өшірілген URL-дерді кезекке қосу (service_role — RLS айналып өтеді).
// Осылай кілт УАҚЫТША қате болса да сурет жоғалмайды: кілт түзелген соң келесі
// drain оларды (қайта тексеріп) өшіреді. Тек guard.ts-тен өткен URL-дер келеді.
async function enqueue(a: Admin, urls: string[]): Promise<number> {
  if (!urls.length) return 0;
  const { error } = await a
    .from('cloudinary_delete_queue')
    .insert(urls.map((u) => ({ url: u })));
  if (error) {
    console.error('enqueue_failed', error.code ?? '');
    return 0;
  }
  return urls.length;
}

/**
 * Өшіруге болмайтын public_id-лер (0089 cloudinary_blocked_ids).
 * Қате (миграция жоқ, БД қатесі) → GuardUnavailable: шақырушы ЕШТЕҢЕ өшірмейді.
 */
async function blockedIds(
  a: Admin,
  ids: string[],
  caller: string | null,
  mode: 'user' | 'queue',
): Promise<Set<string>> {
  const out = new Set<string>();
  for (let i = 0; i < ids.length; i += GUARD_CHUNK) {
    const chunk = ids.slice(i, i + GUARD_CHUNK);
    const { data, error } = await a.rpc('cloudinary_blocked_ids', {
      p_public_ids: chunk,
      p_caller: caller,
      p_mode: mode,
    });
    if (error || !Array.isArray(data)) {
      console.error('guard_rpc_failed', error?.code ?? 'no_data');
      throw new GuardUnavailable();
    }
    for (const v of data as unknown[]) {
      // setof text → ['id', …]; кейбір клиенттер [{cloudinary_blocked_ids:'id'}] береді.
      if (typeof v === 'string') out.add(v);
      else if (v && typeof v === 'object') {
        const s = Object.values(v as Record<string, unknown>)[0];
        if (typeof s === 'string') out.add(s);
      }
    }
  }
  return out;
}

/** Атомды дроссель (0089). null → функция жоқ/қате (fail-closed). */
async function tryClaim(a: Admin, key: string, minSeconds: number): Promise<boolean | null> {
  const { data, error } = await a.rpc('cloudinary_gc_try_claim', {
    p_key: key,
    p_min_seconds: minSeconds,
  });
  if (error) {
    console.error('claim_rpc_failed', error.code ?? '');
    return null;
  }
  return data === true;
}

async function sha1Hex(input: string): Promise<string> {
  const buf = await crypto.subtle.digest('SHA-1', new TextEncoder().encode(input));
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

// Бір суретті public_id бойынша Cloudinary-ден өшіреді (signed destroy).
// Тек guard.ts тексерген public_id келеді. Табылмаса да сәтті саналады.
async function destroyById(publicId: string): Promise<boolean> {
  try {
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
  } catch (_) {
    return false;
  }
}

interface CloudRes { public_id: unknown; created_at?: unknown }

// Cloudinary-дегі qoima_products қалтасының БАРЛЫҚ ресурсын оқиды.
// ЕСКЕРТУ: классикалық prefix-іздеу (`resources/image/upload?prefix=`) жаңа
// Cloudinary аккаунттарында (Dynamic Folder Mode) толық тізім қайтармайды —
// сол себепті нақты қалта бойынша `resources/by_asset_folder` қолданамыз
// (дұрыс тексерілді: prefix әдісі 56/92 қайтарса, by_asset_folder 92/92 береді).
// Кез келген жағдайда екеуін де шақырып, нәтижені біріктіреміз (дедуп) —
// аккаунт режимінен тәуелсіз қауіпсіз. created_at — reconcile-дің 24 сағаттық
// «жаңа жүктелген» шегі үшін.
async function listAllProductResources(): Promise<CloudRes[]> {
  const auth = 'Basic ' + btoa(`${API_KEY}:${API_SECRET}`);
  const byId = new Map<string, CloudRes>();
  const sources: Array<(u: URL) => void> = [
    (u) => u.searchParams.set('asset_folder', 'qoima_products'),
    (u) => {
      u.searchParams.set('prefix', 'qoima_products/');
      u.searchParams.set('type', 'upload');
    },
  ];
  const paths = ['resources/by_asset_folder', 'resources/image/upload'];
  for (let s = 0; s < sources.length; s++) {
    let cursor: string | undefined;
    for (let page = 0; page < 200; page++) {
      const url = new URL(`https://api.cloudinary.com/v1_1/${CLOUD_NAME}/${paths[s]}`);
      sources[s](url);
      url.searchParams.set('max_results', '500');
      if (cursor) url.searchParams.set('next_cursor', cursor);
      const resp = await fetch(url.toString(), { headers: { Authorization: auth } });
      if (!resp.ok) break;
      const data = await resp.json().catch(() => ({}));
      for (const r of data.resources ?? []) {
        if (typeof r?.public_id === 'string' && !byId.has(r.public_id)) {
          byId.set(r.public_id, { public_id: r.public_id, created_at: r.created_at });
        }
      }
      cursor = typeof data.next_cursor === 'string' ? data.next_cursor : undefined;
      if (!cursor) break;
    }
  }
  return [...byId.values()];
}

// Cloudinary ↔ БД толық салыстыру: products.images-те сілтелмейтін, 24
// сағаттан ескі qoima_products суреттерін табады, содан соң БД күзетінен
// (queue режимі — кез келген «тірі» сілтеме) өткізеді. [doDelete] true болса
// өшіреді (RECONCILE_MAX_DELETES-ке дейін). Тек ТАУАР суреттері: by_asset_folder
// чектерді де қайтаруы мүмкін (public_id qoima_receipts/…) — олар
// reconcileCandidates-те сүзіледі.
async function reconcile(a: Admin, doDelete: boolean) {
  const all = await listAllProductResources();

  const referenced = new Set<string>();
  const pageSize = 1000;
  for (let from = 0; ; from += pageSize) {
    const { data: rows, error } = await a
      .from('products')
      .select('images')
      .order('id')
      .range(from, from + pageSize - 1);
    // Тауарларды оқи алмасақ — сілтемелер белгісіз: ештеңе өшірмейміз.
    if (error || !rows) throw new GuardUnavailable();
    for (const row of rows) {
      for (const u of (row as { images?: string[] }).images ?? []) {
        const pid = lenientPublicId(u);
        if (pid) referenced.add(pid);
      }
    }
    if (rows.length < pageSize) break;
  }

  const candidates = reconcileCandidates(all, referenced, Date.now());
  const blocked = await blockedIds(a, candidates, null, 'queue');
  const orphans = candidates.filter((id) => !blocked.has(id));

  let deleted = 0;
  if (doDelete) {
    for (const pid of orphans.slice(0, RECONCILE_MAX_DELETES)) {
      if (await destroyById(pid)) deleted++;
    }
  }
  return {
    total: all.length,
    referenced: referenced.size,
    orphaned: orphans.length,
    protectedByOtherRows: blocked.size,
    deleted,
  };
}

// Кезекті тазалау: әр жол guard.ts-пен талданады (жарамсыз → кезектен
// алынады, өшірілмейді), содан соң БД күзеті (queue): «тірі» жолда
// сілтелгені → кезектен алынады, өшірілмейді. Қалғаны destroy; сәтсізі
// кезекте ҚАЛАДЫ (кілт түзелген соң келесі drain).
async function drainQueue(a: Admin) {
  let processed = 0, deleted = 0, skipped = 0, failed = 0;
  let lastId = 0;
  while (processed < DRAIN_MAX_ROWS) {
    const { data: rows, error } = await a
      .from('cloudinary_delete_queue')
      .select('id,url')
      .gt('id', lastId)
      .order('id')
      .limit(Math.min(100, DRAIN_MAX_ROWS - processed));
    if (error || !rows || rows.length === 0) break;
    lastId = rows[rows.length - 1].id as number;
    processed += rows.length;

    const { valid, invalidIds } = classifyQueueRows(
      rows as Array<{ id: number; url: unknown }>, CLOUD_NAME);
    const blocked = await blockedIds(a, [...new Set(valid.map((v) => v.publicId))], null, 'queue');

    const removeIds = [...invalidIds];
    skipped += invalidIds.length;
    const doneByPid = new Map<string, boolean>(); // бір public_id — бір destroy
    for (const row of valid) {
      if (blocked.has(row.publicId)) {
        skipped++;
        removeIds.push(row.id);
        continue;
      }
      let ok = doneByPid.get(row.publicId);
      if (ok === undefined) {
        ok = await destroyById(row.publicId);
        doneByPid.set(row.publicId, ok);
        if (ok) deleted++;
      }
      if (ok) removeIds.push(row.id);
      else failed++;
    }
    if (removeIds.length) {
      await a.from('cloudinary_delete_queue').delete().in('id', removeIds);
    }
    if (rows.length < 100) break;
  }
  return { processed, deleted, skipped, failed };
}

// {urls} режимі.
async function handleUrls(a: Admin, uid: string, rawUrls: unknown, secretsOk: boolean) {
  const v = validateUrlList(rawUrls, CLOUD_NAME);
  if (!v.ok) return json({ error: v.error }, v.status);
  const images: ParsedImage[] = v.images;
  if (!images.length) {
    return json({ deleted: 0, requested: 0, rejected: v.rejected, denied: 0, queued: 0 });
  }

  // Пайдаланушы бойынша дроссель: әр тексеріс бірнеше кестені толық
  // сканерлейді. false → 429 (клиент URL-дерді кезекке салады, drain кейін
  // қайта тексеріп өшіреді). null (0089 жоқ/қате) → төмендегі күзет те жоқ
  // болады да, бәрі кезекке түседі (өшірілмейді).
  const key = userThrottleKey(uid);
  if (!key) return json({ error: 'invalid_session' }, 401);
  if ((await tryClaim(a, key, URLS_MIN_SECONDS)) === false) {
    return json({ error: 'throttled' }, 429);
  }

  let blocked: Set<string>;
  try {
    blocked = await blockedIds(a, images.map((i) => i.publicId), uid, 'user');
  } catch (_) {
    // Күзет жоқ (0089 қолданылмаған) → өшірмейміз; кезекке салып қоямыз —
    // drain оны кейін өзі қайта тексереді. 200 — клиент қайта кезектемесін.
    const queued = await enqueue(a, images.map((i) => i.url));
    return json({
      deleted: 0, requested: images.length, rejected: v.rejected,
      denied: 0, queued, guard: false,
    });
  }
  const { allowed, denied } = splitByBlocked(images, blocked);

  // Кілт жоқ болса — өшірмей, рұқсат етілгенін кезекке сақтаймыз (жоғалмасын).
  if (!secretsOk) {
    const queued = await enqueue(a, allowed.map((i) => i.url));
    return json({
      deleted: 0, requested: images.length, rejected: v.rejected,
      denied: denied.length, queued, secrets: false,
    });
  }
  let deleted = 0;
  const failed: string[] = [];
  for (const img of allowed) {
    if (await destroyById(img.publicId)) deleted++;
    else failed.push(img.url); // кілт қате/желі → кезекке
  }
  const queued = await enqueue(a, failed);
  return json({
    deleted, requested: images.length, rejected: v.rejected,
    denied: denied.length, queued,
  });
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);
  if (!isValidCloudName(CLOUD_NAME)) return json({ error: 'misconfigured' }, 500);

  // ── 1) Аутентификация: нақты пайдаланушы JWT-і ──────────────────────────
  const token = bearerToken(req.headers.get('Authorization'));
  if (!token) return json({ error: 'no_auth' }, 401);
  if (!isPlausibleUserJwt(token, ANON_KEY)) return json({ error: 'invalid_session' }, 401);

  const a = admin();
  const { data: who, error: whoErr } = await a.auth.getUser(token);
  const user = who?.user;
  if (whoErr || !user?.id) return json({ error: 'invalid_session' }, 401);
  // deno-lint-ignore no-explicit-any
  if ((user as any).is_anonymous === true) return json({ error: 'invalid_session' }, 401);
  const uid = user.id;

  // ── 2) Дене (өлшемі парсингтен БҰРЫН шектеледі) ──────────────────────────
  if (Number(req.headers.get('content-length') ?? 0) > MAX_BODY_BYTES) {
    return json({ error: 'body_too_large' }, 413);
  }
  let payload: { urls?: unknown; mode?: unknown; confirm?: unknown } = {};
  try {
    const raw = await req.text();
    if (raw.length > MAX_BODY_BYTES) return json({ error: 'body_too_large' }, 413);
    const parsed = JSON.parse(raw);
    if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
      return json({ error: 'bad_request' }, 400);
    }
    payload = parsed;
  } catch (_) {
    return json({ error: 'bad_request' }, 400);
  }

  const secretsOk = !!API_KEY && !!API_SECRET;

  // ── 3) Лездік режим: берілген URL-дерді өшіру ─────────────────────────────
  if (payload.urls !== undefined) {
    return await handleUrls(a, uid, payload.urls, secretsOk);
  }

  // drain/reconcile — тек қызметкер. Профиль service_role-мен оқылады.
  if (payload.mode !== 'drain' && payload.mode !== 'reconcile') {
    return json({ error: 'bad_request' }, 400);
  }
  const { data: prof, error: profErr } = await a
    .from('users')
    .select('role, blocked')
    .eq('id', uid)
    .maybeSingle();
  if (profErr) return json({ error: 'profile_unavailable' }, 503);
  const profile: CallerProfile | null = prof
    ? { role: (prof.role as string) ?? null, blocked: prof.blocked === true }
    : null;

  // ── 4) Drain: sweep + кезек + (6 сағатта бір) reconcile ───────────────────
  if (payload.mode === 'drain') {
    if (!isStaff(profile)) return json({ error: 'forbidden' }, 403);
    if (!secretsOk) return json({ error: 'cloudinary_secrets_missing' }, 500);
    const claimed = await tryClaim(a, 'drain', DRAIN_MIN_SECONDS);
    if (claimed === null) return json({ error: 'guard_unavailable' }, 503);
    if (!claimed) return json({ mode: 'drain', throttled: true });

    try {
      // 1) 14+ күн сатулы тұрғандардың фотосын кезекке қосамыз.
      //    ⚠️ Төлем чектерін АВТОМАТТЫ ӨШІРМЕЙМІЗ — олар төлем айғағы.
      const sweep = await a.rpc('sweep_sold_out_images', { p_days: 14 });
      if (sweep.error) console.error('sweep_failed', sweep.error.code ?? '');

      // 2) Кезек (әр жол қайта тексеріледі).
      const q = await drainQueue(a);

      // 3) Cloudinary ↔ БД салыстыру — Admin API лимиті үшін сирек.
      let rec: Awaited<ReturnType<typeof reconcile>> | { skipped: true } = { skipped: true };
      if (await tryClaim(a, 'reconcile_auto', RECONCILE_AUTO_MIN_SECONDS)) {
        rec = await reconcile(a, /* doDelete */ true);
      }
      return json({ mode: 'drain', ...q, reconcile: rec });
    } catch (e) {
      if (e instanceof GuardUnavailable) return json({ error: 'guard_unavailable' }, 503);
      console.error('drain_failed');
      return json({ error: 'internal' }, 500);
    }
  }

  // ── 5) Reconcile: қолмен диагностика ──────────────────────────────────────
  // Әдепкі — DRY-RUN (тек сан). confirm:true — өшіреді. Екеуі де тек superadmin.
  const confirm = payload.confirm === true;
  if (!canReconcile(profile, confirm)) return json({ error: 'forbidden' }, 403);
  if (!secretsOk) return json({ error: 'cloudinary_secrets_missing' }, 500);
  const claimed = await tryClaim(a, 'reconcile_manual', RECONCILE_MANUAL_MIN_SECONDS);
  if (claimed === null) return json({ error: 'guard_unavailable' }, 503);
  if (!claimed) return json({ mode: 'reconcile', throttled: true });
  try {
    const rec = await reconcile(a, confirm);
    return json({
      mode: 'reconcile',
      dryRun: !confirm,
      totalInCloudinary: rec.total,
      referencedInDb: rec.referenced,
      orphaned: rec.orphaned,
      protectedByOtherRows: rec.protectedByOtherRows,
      deleted: rec.deleted,
    });
  } catch (e) {
    if (e instanceof GuardUnavailable) return json({ error: 'guard_unavailable' }, 503);
    console.error('reconcile_failed');
    return json({ error: 'internal' }, 500);
  }
});
