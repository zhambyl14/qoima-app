// cloudinary-cleanup функциясының ТАЗА шешім логикасы (Deno/npm тәуелділігісіз —
// Node-та тестіленеді: node --test test/edge/cloudinary_cleanup_guard.test.ts).
//
//  • URL → public_id талдауы ҚАТАҢ: тек https://res.cloudinary.com/<біздің
//    cloud>/image/upload/[v<сан>/]<біздің қалта>/<id>[.<кеңейтім>]. Трансфор-
//    мация сегменттері, %-кодтау, «..», «//», query/fragment, бөтен хост/cloud
//    — бәрі қабылданбайды. Cloudinary destroy тек public_id-ді алады, сондықтан
//    біз де тек public_id бойынша шешім қабылдаймыз.
//  • Рұқсат/тыйым: «бөтеннің жолында сілтелген» public_id-лер БД-да
//    (cloudinary_blocked_ids, 0089) есептеледі; мұнда тек сол жиынмен бөлеміз.
//  • Рөлдер: drain тек қызметкерге (admin/superadmin, блоксыз);
//    reconcile (dry-run да, confirm да) — тек superadmin.

/** cloudinary_service.dart-тағы қалталар (жаңа қалта қоссаңыз — осында да). */
export const ALLOWED_FOLDERS: readonly string[] = [
  'qoima_products',
  'qoima_receipts',
  'qoima_banners',
  'qoima_returns',
  'qoima_stories',
];

/** Бір {urls} шақыруындағы ең көп URL саны (клиент 30-дан бөліп жібереді). */
export const MAX_URLS = 30;
/** Бір URL-дің ең көп ұзындығы (store_stories_url_len-мен бірдей). */
export const MAX_URL_LEN = 500;
/** Сұраныс денесінің ең көп өлшемі (JSON.parse-тан бұрын тексеріледі). */
export const MAX_BODY_BYTES = 32 * 1024;
/** Жаңа жүктелген суретті reconcile өшірмейді (тауар әлі сақталмаған болуы мүмкін). */
export const RECONCILE_GRACE_MS = 24 * 60 * 60 * 1000;

export interface ParsedImage {
  /** Клиент жіберген URL (өзгеріссіз). */
  url: string;
  /** Cloudinary public_id, мысалы 'qoima_products/abc123'. */
  publicId: string;
  /** Бірінші сегмент — ALLOWED_FOLDERS-тің бірі. */
  folder: string;
}

export type ParseResult =
  | { ok: true; value: ParsedImage }
  | { ok: false; reason: string };

const CLOUD_NAME_RE = /^[a-z0-9_-]{1,64}$/;
const SEGMENT_RE = /^[A-Za-z0-9_-]{1,200}$/;
const EXT_RE = /^[A-Za-z0-9]{1,8}$/;

export function isValidCloudName(name: unknown): name is string {
  return typeof name === 'string' && CLOUD_NAME_RE.test(name);
}

/**
 * public_id қауіпсіз әрі біздің қалтада ма: «қалта/сегмент[/сегмент…]»,
 * әр сегмент [A-Za-z0-9_-], нүкте/слэш трюктері жоқ.
 */
export function isSafePublicId(pid: unknown, folders: readonly string[] = ALLOWED_FOLDERS): pid is string {
  if (typeof pid !== 'string' || pid.length < 3 || pid.length > 300) return false;
  const segs = pid.split('/');
  if (segs.length < 2) return false;
  if (!folders.includes(segs[0])) return false;
  return segs.slice(1).every((s) => SEGMENT_RE.test(s));
}

/**
 * Клиент жіберген URL-ді қатаң талдайды. Тек біздің cloud-тың
 * image/upload жолы, біздің қалталар, бір ғана міндетті емес нұсқа
 * сегменті (v123/) және соңғы сегментте бір ғана міндетті емес кеңейтім.
 */
export function parseImageUrl(raw: unknown, cloudName: string): ParseResult {
  if (typeof raw !== 'string') return { ok: false, reason: 'not_string' };
  if (raw.length === 0 || raw.length > MAX_URL_LEN) return { ok: false, reason: 'length' };
  if (!isValidCloudName(cloudName)) return { ok: false, reason: 'cloud_name' };

  const prefix = `https://res.cloudinary.com/${cloudName}/image/upload/`;
  if (!raw.startsWith(prefix)) return { ok: false, reason: 'host' };
  let rest = raw.substring(prefix.length);

  // Тек қарапайым ASCII жол таңбалары: %, ?, #, \, «,», бос орын, unicode — жоқ.
  if (!/^[A-Za-z0-9_\-./]+$/.test(rest)) return { ok: false, reason: 'charset' };

  const ver = /^v\d{1,15}\//.exec(rest);
  if (ver) rest = rest.substring(ver[0].length);

  const segs = rest.split('/');
  if (segs.length < 2) return { ok: false, reason: 'path' };
  const folder = segs[0];
  if (!ALLOWED_FOLDERS.includes(folder)) return { ok: false, reason: 'folder' };

  const last = segs[segs.length - 1];
  let stem = last;
  const dot = last.indexOf('.');
  if (dot !== -1) {
    if (last.indexOf('.', dot + 1) !== -1) return { ok: false, reason: 'path' };
    stem = last.substring(0, dot);
    if (!EXT_RE.test(last.substring(dot + 1))) return { ok: false, reason: 'path' };
  }
  const idSegs = [...segs.slice(0, -1), stem];
  // Ортаңғы сегменттерде нүкте жоқ, бос сегмент (//) жоқ, «..» жоқ.
  if (!idSegs.slice(1).every((s) => SEGMENT_RE.test(s))) return { ok: false, reason: 'path' };

  const publicId = idSegs.join('/');
  if (!isSafePublicId(publicId)) return { ok: false, reason: 'path' };
  return { ok: true, value: { url: raw, publicId, folder } };
}

export type UrlListResult =
  | { ok: false; status: number; error: string }
  | { ok: true; images: ParsedImage[]; rejected: number };

/**
 * {urls:[...]} тізімін тексереді: массив емес → 400; MAX_URLS-тен көп → 413
 * (бүкіл сұраныс). Жарамсыз элементтер (жол емес, бөтен хост, трюк) жай
 * санап өткізіледі — ЕШҚАШАН өшірілмейді де, кезекке де түспейді.
 * public_id бойынша дедуп.
 */
export function validateUrlList(input: unknown, cloudName: string): UrlListResult {
  if (!Array.isArray(input)) return { ok: false, status: 400, error: 'bad_request' };
  if (input.length > MAX_URLS) return { ok: false, status: 413, error: 'too_many' };
  const seen = new Set<string>();
  const images: ParsedImage[] = [];
  let rejected = 0;
  for (const raw of input) {
    const r = parseImageUrl(raw, cloudName);
    if (!r.ok) {
      rejected++;
      continue;
    }
    if (seen.has(r.value.publicId)) continue;
    seen.add(r.value.publicId);
    images.push(r.value);
  }
  return { ok: true, images, rejected };
}

/** Бұғатталған public_id-лерді бөліп алады (тыйым — БД шешімі). */
export function splitByBlocked<T extends { publicId: string }>(
  items: readonly T[],
  blocked: Iterable<string>,
): { allowed: T[]; denied: T[] } {
  const b = new Set(blocked);
  const allowed: T[] = [];
  const denied: T[] = [];
  for (const it of items) (b.has(it.publicId) ? denied : allowed).push(it);
  return { allowed, denied };
}

/**
 * БД-дағы сілтемелерден public_id алу үшін ЖҰМСАҚ талдау (reconcile-дағы
 * «сілтелген» жиыны). Мұнда артық сәйкестік қауіпсіз — тек өшірмеуге әкеледі.
 */
export function lenientPublicId(url: unknown): string | null {
  if (typeof url !== 'string') return null;
  const marker = '/upload/';
  const idx = url.indexOf(marker);
  if (idx === -1) return null;
  let path = url.substring(idx + marker.length);
  path = path.replace(/[?#].*$/, '');
  path = path.replace(/^v\d+\//, '');
  const slash = path.lastIndexOf('/');
  const dot = path.lastIndexOf('.');
  if (dot > slash) path = path.substring(0, dot);
  return path.length ? path : null;
}

// ── Аутентификация көмекшілері ──────────────────────────────────────────────

/** "Bearer <token>" → token (басқа пішін → null). */
export function bearerToken(header: string | null | undefined): string | null {
  if (typeof header !== 'string') return null;
  const m = /^Bearer\s+(\S+)$/i.exec(header.trim());
  return m ? m[1] : null;
}

/** JWT payload-ын ҚОЛТАҢБАСЫЗ оқиды — тек алдын ала сүзгі үшін. */
export function decodeJwtPayload(token: string): Record<string, unknown> | null {
  const parts = token.split('.');
  if (parts.length !== 3) return null;
  try {
    let b64 = parts[1].replace(/-/g, '+').replace(/_/g, '/');
    while (b64.length % 4) b64 += '=';
    const obj = JSON.parse(atob(b64));
    return obj && typeof obj === 'object' && !Array.isArray(obj) ? obj : null;
  } catch (_) {
    return null;
  }
}

/**
 * Арзан алдын ала сүзгі: anon/service кілті, publishable кілт не бұзылған
 * токен желіге шықпай-ақ 401 алады. НАҚТЫ тексеріс — серверде
 * auth.getUser(token) (қолтаңба + сессия), бұл функция оны алмастырмайды.
 */
export function isPlausibleUserJwt(token: string | null, anonKey = ''): boolean {
  if (!token || token.length > 8192) return false;
  if (anonKey && token === anonKey) return false;
  const p = decodeJwtPayload(token);
  if (!p) return false;
  return p.role === 'authenticated' && typeof p.sub === 'string' && p.sub.length > 0;
}

// ── Рөлдер ─────────────────────────────────────────────────────────────────

export interface CallerProfile {
  role: string | null;
  blocked: boolean;
}

/** drain/reconcile: дүкен иесі (admin) не модератор (superadmin), блоксыз. */
export function isStaff(p: CallerProfile | null): boolean {
  return !!p && !p.blocked && (p.role === 'admin' || p.role === 'superadmin');
}

export function isSuperadmin(p: CallerProfile | null): boolean {
  return !!p && !p.blocked && p.role === 'superadmin';
}

/**
 * reconcile (dry-run да, confirm:true да) — тек superadmin. 'admin' рөлін кез
 * келген адам тіркеліп-ақ алады (handle_new_user, модератор бекітпейді), ал
 * reconcile платформаның бүкіл Cloudinary тізімін оқиды (Admin API лимиті
 * ортақ) және жалпы сандарды ашады. Қосымшада оны шақыратын код жоқ.
 */
export function canReconcile(p: CallerProfile | null, _confirm: boolean): boolean {
  return isSuperadmin(p);
}

/** {urls} режимі: бір пайдаланушыға шақырулар арасындағы ең аз уақыт (сек). */
export const URLS_MIN_SECONDS = 2;

/** cloudinary_gc_try_claim кілті ({urls} дросселі). uid — auth.getUser-ден. */
export function userThrottleKey(uid: string): string | null {
  const id = uid.toLowerCase();
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(id)
    ? `u:${id}`
    : null;
}

// ── reconcile таңдауы ───────────────────────────────────────────────────────

export interface CloudResource {
  public_id: unknown;
  created_at?: unknown;
}

/**
 * Cloudinary тізімінен өшіруге ҮМІТКЕРЛЕР: тек qoima_products/ ішіндегі
 * қауіпсіз public_id, products.images-те сілтелмеген және [graceMs]-тен ескі
 * (жаңа жүктелген, бірақ тауар әлі сақталмаған фото өшпесін). created_at
 * оқылмаса — ескі ЕМЕС деп есептеледі (өшірмейміз).
 */
export function reconcileCandidates(
  resources: readonly CloudResource[],
  referenced: ReadonlySet<string>,
  nowMs: number,
  graceMs = RECONCILE_GRACE_MS,
): string[] {
  const out = new Set<string>();
  for (const r of resources) {
    const pid = r.public_id;
    if (!isSafePublicId(pid, ['qoima_products'])) continue;
    if (referenced.has(pid)) continue;
    const t = typeof r.created_at === 'string' ? Date.parse(r.created_at) : NaN;
    if (!Number.isFinite(t) || nowMs - t < graceMs) continue;
    out.add(pid);
  }
  return [...out];
}

/** Кезек жолдарын бөлу: жарамды (public_id-мен) / жарамсыз (тек кезектен алынады). */
export function classifyQueueRows<R extends { id: number; url: unknown }>(
  rows: readonly R[],
  cloudName: string,
): { valid: Array<R & { publicId: string }>; invalidIds: number[] } {
  const valid: Array<R & { publicId: string }> = [];
  const invalidIds: number[] = [];
  for (const row of rows) {
    const r = parseImageUrl(row.url, cloudName);
    if (r.ok) valid.push({ ...row, publicId: r.value.publicId });
    else invalidIds.push(row.id);
  }
  return { valid, invalidIds };
}
