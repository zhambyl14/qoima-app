// cloudinary-cleanup edge функциясының шешім логикасы (Deno/npm тәуелділігісіз):
//   node --test test/edge/cloudinary_cleanup_guard.test.ts
import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import {
  ALLOWED_FOLDERS,
  bearerToken,
  canReconcile,
  classifyQueueRows,
  decodeJwtPayload,
  isPlausibleUserJwt,
  isSafePublicId,
  isStaff,
  isSuperadmin,
  lenientPublicId,
  MAX_URL_LEN,
  MAX_URLS,
  parseImageUrl,
  reconcileCandidates,
  RECONCILE_GRACE_MS,
  splitByBlocked,
  URLS_MIN_SECONDS,
  userThrottleKey,
  validateUrlList,
} from "../../supabase/functions/cloudinary-cleanup/guard.ts";

const CLOUD = "divynstru";
const BASE = `https://res.cloudinary.com/${CLOUD}/image/upload/`;

function pid(url: unknown): string | null {
  const r = parseImageUrl(url, CLOUD);
  return r.ok ? r.value.publicId : null;
}

test("қалыпты URL: нұсқа/кеңейтім варианттары бір public_id береді", () => {
  assert.equal(pid(`${BASE}v1700000000/qoima_products/abc123.jpg`), "qoima_products/abc123");
  assert.equal(pid(`${BASE}qoima_products/abc123.jpg`), "qoima_products/abc123");
  assert.equal(pid(`${BASE}v1/qoima_products/abc123.png`), "qoima_products/abc123");
  assert.equal(pid(`${BASE}qoima_products/abc123`), "qoima_products/abc123");
  assert.equal(pid(`${BASE}v1/qoima_products/abc123.JPEG`), "qoima_products/abc123");
  assert.equal(pid(`${BASE}v1/qoima_receipts/r_1-x.pdf`), "qoima_receipts/r_1-x");
  assert.equal(pid(`${BASE}v1/qoima_stories/story_1.jpg`), "qoima_stories/story_1");
  assert.equal(pid(`${BASE}v1/qoima_returns/x.jpg`), "qoima_returns/x");
  assert.equal(pid(`${BASE}v1/qoima_banners/x.webp`), "qoima_banners/x");
  // Ішкі қалта біздің қалтаның ішінде болса — рұқсат.
  assert.equal(pid(`${BASE}v1/qoima_products/sub/abc.jpg`), "qoima_products/sub/abc");
});

test("бөтен хост / бөтен cloud / http / регистр", () => {
  assert.equal(pid(`https://res.cloudinary.com/othercloud/image/upload/v1/qoima_products/a.jpg`), null);
  assert.equal(pid(`https://res.cloudinary.com.evil.com/${CLOUD}/image/upload/qoima_products/a.jpg`), null);
  assert.equal(pid(`https://evil.com/res.cloudinary.com/${CLOUD}/image/upload/qoima_products/a.jpg`), null);
  assert.equal(pid(`https://res.cloudinary.com@evil.com/${CLOUD}/image/upload/qoima_products/a.jpg`), null);
  assert.equal(pid(`http://res.cloudinary.com/${CLOUD}/image/upload/qoima_products/a.jpg`), null);
  assert.equal(pid(`https://RES.cloudinary.com/${CLOUD}/image/upload/qoima_products/a.jpg`), null);
  assert.equal(pid(`https://res.cloudinary.com/${CLOUD.toUpperCase()}/image/upload/qoima_products/a.jpg`), null);
  assert.equal(pid(`https://res.cloudinary.com/${CLOUD}/video/upload/qoima_products/a.mp4`), null);
  assert.equal(pid(`https://res.cloudinary.com/${CLOUD}/image/private/qoima_products/a.jpg`), null);
  assert.equal(pid(`https://res.cloudinary.com/${CLOUD}/image/fetch/qoima_products/a.jpg`), null);
  assert.equal(pid(` ${BASE}qoima_products/a.jpg`), null);
  assert.equal(pid(`${BASE}qoima_products/a.jpg `), null);
  // Жарамсыз cloud атауы (regex инъекциясы) — бәрі қабылданбайды.
  assert.equal(parseImageUrl(`${BASE}qoima_products/a.jpg`, "divyn.*").ok, false);
});

test("трансформация сегменттері қабылданбайды", () => {
  assert.equal(pid(`${BASE}w_100/qoima_products/a.jpg`), null);
  assert.equal(pid(`${BASE}c_fill,w_100,h_100/qoima_products/a.jpg`), null);
  assert.equal(pid(`${BASE}f_jpg,w_1400/v1/qoima_receipts/a.jpg`), null);
  assert.equal(pid(`${BASE}pg_1,f_jpg,w_1400/qoima_receipts/a.jpg`), null);
  assert.equal(pid(`${BASE}v1/v2/qoima_products/a.jpg`), null);
});

test("жол трюктері: ../, %2e%2e, //, \\, query, fragment, unicode", () => {
  assert.equal(pid(`${BASE}qoima_products/../qoima_receipts/a.jpg`), null);
  assert.equal(pid(`${BASE}qoima_products/%2e%2e/qoima_receipts/a.jpg`), null);
  assert.equal(pid(`${BASE}qoima_products/%2E%2E/a.jpg`), null);
  assert.equal(pid(`${BASE}qoima_products/a%2fb.jpg`), null);
  assert.equal(pid(`${BASE}qoima_products//a.jpg`), null);
  assert.equal(pid(`${BASE}qoima_products/./a.jpg`), null);
  assert.equal(pid(`${BASE}qoima_products/.jpg`), null);
  assert.equal(pid(`${BASE}qoima_products/a.`), null);
  assert.equal(pid(`${BASE}qoima_products/a..jpg`), null);
  assert.equal(pid(`${BASE}qoima_products/a.b.jpg`), null);
  assert.equal(pid(`${BASE}qoima_products/a.b/c.jpg`), null);
  assert.equal(pid(`${BASE}qoima_products/a\\..\\b.jpg`), null);
  assert.equal(pid(`${BASE}qoima_products/a.jpg?x=1`), null);
  assert.equal(pid(`${BASE}qoima_products/a.jpg#x`), null);
  assert.equal(pid(`${BASE}qoima_products/а.jpg`), null); // кирилл «а»
  assert.equal(pid(`${BASE}qoima_products/a b.jpg`), null);
  assert.equal(pid(`${BASE}qoima_products/a.jpg/`), null);
  assert.equal(pid(`${BASE}qoima_products/a.toolongext`), null);
});

test("бөтен қалта / қалтасыз / тек қалта", () => {
  assert.equal(pid(`${BASE}v1/other_folder/a.jpg`), null);
  assert.equal(pid(`${BASE}v1/a.jpg`), null);
  assert.equal(pid(`${BASE}v1/qoima_products`), null);
  assert.equal(pid(`${BASE}v1/qoima_products/`), null);
  assert.equal(pid(`${BASE}v1/QOIMA_PRODUCTS/a.jpg`), null);
  assert.equal(pid(`${BASE}v1/qoima_products_evil/a.jpg`), null);
  assert.equal(pid(`${BASE}samples/qoima_products/a.jpg`), null);
});

test("жол емес мәндер мен ұзындық", () => {
  for (const v of [null, undefined, 1, {}, [], true, ""]) assert.equal(pid(v), null);
  const long = `${BASE}qoima_products/${"a".repeat(MAX_URL_LEN)}.jpg`;
  assert.equal(pid(long), null);
});

test("validateUrlList: массив емес → 400, көп → 413, жарамсыз элемент санап өтіледі", () => {
  assert.deepEqual(validateUrlList("x", CLOUD), { ok: false, status: 400, error: "bad_request" });
  assert.deepEqual(validateUrlList({ 0: "a" }, CLOUD), { ok: false, status: 400, error: "bad_request" });
  const many = Array.from({ length: MAX_URLS + 1 }, (_, i) => `${BASE}qoima_products/a${i}.jpg`);
  assert.deepEqual(validateUrlList(many, CLOUD), { ok: false, status: 413, error: "too_many" });
  const huge = Array.from({ length: 100000 }, () => 1);
  assert.equal((validateUrlList(huge, CLOUD) as { status: number }).status, 413);

  const r = validateUrlList([
    `${BASE}v1/qoima_products/a.jpg`,
    `${BASE}v2/qoima_products/a.png`, // сол public_id — дедуп
    `${BASE}qoima_stories/s.jpg`,
    42,
    null,
    "https://evil.com/x.jpg",
    `${BASE}w_1/qoima_products/a.jpg`,
  ], CLOUD);
  assert.ok(r.ok);
  if (r.ok) {
    assert.deepEqual(r.images.map((i) => i.publicId), ["qoima_products/a", "qoima_stories/s"]);
    assert.equal(r.rejected, 4);
    assert.equal(r.images[0].url, `${BASE}v1/qoima_products/a.jpg`);
  }
  const exact = Array.from({ length: MAX_URLS }, (_, i) => `${BASE}qoima_products/a${i}.jpg`);
  const e = validateUrlList(exact, CLOUD);
  assert.ok(e.ok && e.images.length === MAX_URLS);
});

test("splitByBlocked: БД бұғаттағаны өшірілмейді", () => {
  const r = validateUrlList([`${BASE}qoima_products/a.jpg`, `${BASE}qoima_products/b.jpg`], CLOUD);
  assert.ok(r.ok);
  if (!r.ok) return;
  const { allowed, denied } = splitByBlocked(r.images, ["qoima_products/b"]);
  assert.deepEqual(allowed.map((i) => i.publicId), ["qoima_products/a"]);
  assert.deepEqual(denied.map((i) => i.publicId), ["qoima_products/b"]);
  assert.equal(splitByBlocked(r.images, []).denied.length, 0);
});

test("isSafePublicId", () => {
  assert.ok(isSafePublicId("qoima_products/abc"));
  assert.ok(!isSafePublicId("qoima_products"));
  assert.ok(!isSafePublicId("qoima_products/../x"));
  assert.ok(!isSafePublicId("qoima_products/a.b"));
  assert.ok(!isSafePublicId("other/abc"));
  assert.ok(!isSafePublicId("qoima_receipts/abc", ["qoima_products"]));
  assert.ok(!isSafePublicId(5));
});

test("lenientPublicId — БД сілтемелері үшін (ескі publicIdFromUrl + ?/#)", () => {
  assert.equal(lenientPublicId(`${BASE}v17/qoima_products/abc.jpg`), "qoima_products/abc");
  assert.equal(lenientPublicId(`${BASE}qoima_products/abc.jpg?x=1`), "qoima_products/abc");
  assert.equal(lenientPublicId("https://x.com/no-marker.jpg"), null);
  assert.equal(lenientPublicId(5), null);
});

function fakeJwt(payload: Record<string, unknown>): string {
  const b64 = (o: unknown) => Buffer.from(JSON.stringify(o)).toString("base64url");
  return `${b64({ alg: "HS256", typ: "JWT" })}.${b64(payload)}.sig`;
}

test("bearerToken / JWT алдын ала сүзгісі: anon кілті, service кілті, бұзылған токен", () => {
  assert.equal(bearerToken(null), null);
  assert.equal(bearerToken(""), null);
  assert.equal(bearerToken("Basic abc"), null);
  assert.equal(bearerToken("Bearer"), null);
  assert.equal(bearerToken("Bearer a b"), null);
  assert.equal(bearerToken("Bearer abc.def.ghi"), "abc.def.ghi");
  assert.equal(bearerToken("bearer abc"), "abc");

  const anon = fakeJwt({ role: "anon", iss: "supabase" });
  const service = fakeJwt({ role: "service_role" });
  const user = fakeJwt({ role: "authenticated", sub: "8b0c6c0e-0000-4000-8000-000000000001" });
  const noSub = fakeJwt({ role: "authenticated" });
  assert.equal(isPlausibleUserJwt(anon, anon), false);
  assert.equal(isPlausibleUserJwt(anon, ""), false); // role=anon
  assert.equal(isPlausibleUserJwt(service, anon), false);
  assert.equal(isPlausibleUserJwt(noSub, anon), false);
  assert.equal(isPlausibleUserJwt(user, anon), true);
  assert.equal(isPlausibleUserJwt(user, user), false); // anon кілтімен бірдей → жоқ
  assert.equal(isPlausibleUserJwt("sb_publishable_abc123", anon), false);
  assert.equal(isPlausibleUserJwt("a.%%%.c", anon), false);
  assert.equal(isPlausibleUserJwt(null, anon), false);
  assert.equal(isPlausibleUserJwt("x".repeat(9000), anon), false);
  assert.equal(decodeJwtPayload("a.b"), null);
  assert.equal(decodeJwtPayload(`x.${Buffer.from("[1]").toString("base64url")}.y`), null);
});

test("рөлдер: drain — admin/superadmin; reconcile confirm — тек superadmin", () => {
  const p = (role: string | null, blocked = false) => ({ role, blocked });
  assert.ok(isStaff(p("admin")));
  assert.ok(isStaff(p("superadmin")));
  for (const r of ["seller", "client", "courier", null, "Admin"]) assert.ok(!isStaff(p(r)));
  assert.ok(!isStaff(p("admin", true)));
  assert.ok(!isStaff(null));
  assert.ok(isSuperadmin(p("superadmin")));
  assert.ok(!isSuperadmin(p("superadmin", true)));
  // reconcile (dry-run да) — тек superadmin: 'admin' рөлін кез келген адам
  // тіркеліп алады (handle_new_user), ал reconcile бүкіл Cloudinary-ді оқиды.
  assert.ok(!canReconcile(p("admin"), false));
  assert.ok(!canReconcile(p("admin"), true));
  assert.ok(canReconcile(p("superadmin"), false));
  assert.ok(canReconcile(p("superadmin"), true));
  assert.ok(!canReconcile(p("superadmin", true), false));
  assert.ok(!canReconcile(p("seller"), false));
  assert.ok(!canReconcile(null, false));
});

test("{urls} дроссель кілті: тек канондық uuid, SQL ақ тізімімен бірдей пішін", () => {
  assert.equal(userThrottleKey("8B0C6C0E-0000-4000-8000-000000000001"), "u:8b0c6c0e-0000-4000-8000-000000000001");
  for (const bad of ["", "drain", "x' or 1=1", "8b0c6c0e00004000800000000000000 1", "u:8b0c6c0e-0000-4000-8000-000000000001"]) {
    assert.equal(userThrottleKey(bad), null, bad);
  }
  assert.ok(URLS_MIN_SECONDS >= 1);
  const sql = readFileSync("supabase/migrations/0089_cloudinary_cleanup_guard.sql", "utf-8");
  assert.ok(sql.includes("'^u:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'"),
    "0089 cloudinary_gc_try_claim 'u:<uuid>' кілтін қабылдамайды");
});

test("reconcileCandidates: тек qoima_products, сілтелмеген, 24 сағаттан ескі", () => {
  const now = Date.parse("2026-11-03T12:00:00Z");
  const old = new Date(now - RECONCILE_GRACE_MS - 1000).toISOString();
  const fresh = new Date(now - 60_000).toISOString();
  const res = [
    { public_id: "qoima_products/old_orphan", created_at: old },
    { public_id: "qoima_products/fresh_orphan", created_at: fresh },
    { public_id: "qoima_products/referenced", created_at: old },
    { public_id: "qoima_receipts/receipt", created_at: old },
    { public_id: "qoima_stories/story", created_at: old },
    { public_id: "qoima_products/no_date" },
    { public_id: "qoima_products/bad_date", created_at: "nope" },
    { public_id: "qoima_products/../x", created_at: old },
    { public_id: 7, created_at: old },
    { public_id: "qoima_products/old_orphan", created_at: old }, // дубль
  ];
  assert.deepEqual(
    reconcileCandidates(res, new Set(["qoima_products/referenced"]), now),
    ["qoima_products/old_orphan"],
  );
});

test("classifyQueueRows: бөтен/жарамсыз жол кезектен алынады, өшірілмейді", () => {
  const rows = [
    { id: 1, url: `${BASE}v1/qoima_products/a.jpg` },
    { id: 2, url: "https://evil.com/a.jpg" },
    { id: 3, url: `${BASE}w_10/qoima_products/a.jpg` },
    { id: 4, url: null },
    { id: 5, url: `${BASE}qoima_stories/s.png` },
  ];
  const r = classifyQueueRows(rows, CLOUD);
  assert.deepEqual(r.valid.map((v) => [v.id, v.publicId]), [[1, "qoima_products/a"], [5, "qoima_stories/s"]]);
  assert.deepEqual(r.invalidIds, [2, 3, 4]);
});

test("ALLOWED_FOLDERS cloudinary_service.dart-тағы қалталармен бірдей", () => {
  const dart = readFileSync("lib/data/services/cloudinary_service.dart", "utf-8");
  // static const String _xxxFolder = 'qoima_…'; (upload preset 'qoima_unsigned' — қалта емес)
  const inDart = [...dart.matchAll(/_\w*[fF]older\s*=\s*'(qoima_[a-z_]+)'/g)].map((m) => m[1]);
  assert.ok(inDart.length >= 5, "Dart қалта тұрақтылары табылмады");
  for (const f of inDart) assert.ok(ALLOWED_FOLDERS.includes(f), `guard.ts-те жоқ қалта: ${f}`);
  for (const f of ALLOWED_FOLDERS) assert.ok(inDart.includes(f), `Dart-та жоқ қалта: ${f}`);
  assert.ok(dart.includes("_maxUrlsPerCall = " + MAX_URLS), "Dart бөлу шегі MAX_URLS-пен бірдей емес");
});
