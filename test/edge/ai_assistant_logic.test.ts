// ai-assistant edge функциясының таза логикасы (Deno/npm тәуелділігісіз):
//   node --test test/edge/ai_assistant_logic.test.ts
import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { extractFilters, KNOWN_CATS, KNOWN_TYPES, relaxFilters } from "../../supabase/functions/ai-assistant/prefetch.ts";
import { CATEGORY_KEYS, TYPE_CATEGORIES } from "../../supabase/functions/ai-assistant/catalog.ts";
import { DeltaFilter } from "../../supabase/functions/ai-assistant/stream_text.ts";
import { GeminiStreamAssembler, SseParser } from "../../supabase/functions/_shared/gemini_stream.ts";

test("prefetch: танылатын түрлер catalog.ts-тегі канондық мәнмен сәйкес", () => {
  for (const t of KNOWN_TYPES) assert.ok(TYPE_CATEGORIES.has(t), `белгісіз түр: ${t}`);
  for (const c of KNOWN_CATS) assert.ok(CATEGORY_KEYS.includes(c), `белгісіз санат: ${c}`);
});

test("catalog.ts категория кілттері category_data.dart-пен бірдей", () => {
  const dart = readFileSync("lib/data/models/category_data.dart", "utf-8");
  for (const k of CATEGORY_KEYS) {
    assert.ok(dart.includes(`'${k}'`), `Dart-та жоқ: ${k}`);
  }
});

test("prefetch: түр + баға + өлшем + аудитория", () => {
  const f = extractFilters("Мужские кроссовки 42 размера до 30 000 тенге")!;
  assert.deepEqual(f.types, ["Кроссовки"]);
  assert.equal(f.audience, "Мужские");
  assert.equal(f.size, "42");
  assert.equal(f.max_price, 30000);
});

test("prefetch: қазақша сұрау және маусым", () => {
  const f = extractFilters("қысқы күрте 20к дейін")!;
  assert.deepEqual(f.types, ["Куртка"]);
  assert.equal(f.season, "Зима");
  assert.equal(f.max_price, 20000);
});

test("prefetch: түсінікті емес сұрау — null (LLM өзі іздейді)", () => {
  assert.equal(extractFilters("подарок мужу"), null);
  assert.equal(extractFilters("привет, как дела?"), null);
});

test("prefetch: «до 40 размера» баға емес", () => {
  const f = extractFilters("туфли до 40 размера")!;
  assert.equal(f.max_price, undefined);
});

test("prefetch: техникада 42 өлшем емес", () => {
  const f = extractFilters("смартфон 42")!;
  assert.equal(f.size, undefined);
});

test("relaxFilters: тек түр/санат қалады, босататыны жоқ болса null", () => {
  const f = extractFilters("красные кроссовки 42 до 30000")!;
  const r = relaxFilters(f)!;
  assert.deepEqual(Object.keys(r), ["types"]);
  assert.equal(relaxFilters({ types: ["Куртка"] }), null);
});

test("DeltaFilter: сөзді ортасынан үзбейді, сілтемені алып тастайды", () => {
  const d = new DeltaFilter();
  assert.equal(d.push("Сәл"), "");
  assert.equal(d.push("ем бол"), "Сәлем ");
  assert.equal(d.push("ыңыз https://evil.example/x "), "болыңыз  "); // қос бос орынды done-дағы stripLinks жинайды
  assert.equal(d.flush(), "");
  const e = new DeltaFilter();
  e.push("см. www.bad.kz/pay ");
  assert.equal(e.flush(), "");
});

test("SseParser: бөлшектелген кадрлар, CRLF, түсініктеме", () => {
  const p = new SseParser();
  assert.deepEqual(p.feed(": ok\n\ndata: {\"a\""), []);
  const fr = p.feed(":1}\r\n\r\n");
  assert.equal(fr.length, 1);
  assert.equal(fr[0].data, '{"a":1}');
  assert.equal(p.flush().length, 0);
  assert.equal(p.feed("data: tail").length, 0);
  assert.equal(p.flush()[0].data, "tail");
});

test("GeminiStreamAssembler: мәтін дельталары мен tool_use жиналады", () => {
  const a = new GeminiStreamAssembler();
  assert.equal(a.push({ candidates: [{ content: { parts: [{ text: "Сәл" }] } }] }), "Сәл");
  assert.equal(
    a.push({ candidates: [{ content: { parts: [{ text: "ем", thought: true }, { text: "!" }] } }] }),
    "!",
  );
  a.push({
    candidates: [{
      content: { parts: [{ functionCall: { name: "search_products", args: { query: "x" } } }] },
      finishReason: "STOP",
    }],
    usageMetadata: { promptTokenCount: 10, candidatesTokenCount: 3 },
  });
  const s = a.summary();
  assert.equal(s.content[0].text, "Сәл!");
  assert.equal(s.content[1].type, "tool_use");
  assert.equal(s.content[1].name, "search_products");
  assert.equal(s.inputTokens, 10);
  assert.equal(s.finishReason, "STOP");
});

test("GeminiStreamAssembler: қате chunk лақтырады", () => {
  assert.throws(() => new GeminiStreamAssembler().push({ error: { code: 429, message: "quota" } }));
});
