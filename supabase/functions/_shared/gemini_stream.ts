// Gemini streamGenerateContent (alt=sse) ағынын жинау — таза логика, Deno/npm
// тәуелділігі жоқ (сондықтан `node --test` арқылы тексеріледі).
//
// Екі бөлік:
//   • SseParser — байттардан келген мәтінді {event, data} кадрларына бөледі
//     (бөлшектеніп келген кадрлар, \r\n, түсініктеме жолдары ': ...');
//   • GeminiStreamAssembler — әр chunk-тан мәтін дельтасын қайтарады және
//     соңында Anthropic-пішімді content блоктарын жинап береді.

// deno-lint-ignore no-explicit-any
type Any = any;

export interface SseFrame {
  event: string;
  data: string;
}

export class SseParser {
  private buf = "";

  /// Келген мәтін бөлігін береді; аяқталған кадрларды қайтарады.
  feed(chunk: string): SseFrame[] {
    this.buf += chunk;
    const out: SseFrame[] = [];
    for (;;) {
      // Кадр бос жолмен бөлінеді: \n\n, \r\n\r\n немесе \r\r.
      const m = /\r\n\r\n|\n\n|\r\r/.exec(this.buf);
      if (!m) break;
      const raw = this.buf.slice(0, m.index);
      this.buf = this.buf.slice(m.index + m[0].length);
      const f = parseFrame(raw);
      if (f) out.push(f);
    }
    return out;
  }

  /// Ағын бос жолсыз аяқталса — қалған кадр.
  flush(): SseFrame[] {
    const rest = this.buf;
    this.buf = "";
    const f = rest.trim() ? parseFrame(rest) : null;
    return f ? [f] : [];
  }
}

function parseFrame(raw: string): SseFrame | null {
  let event = "message";
  const data: string[] = [];
  for (const line of raw.split(/\r\n|\n|\r/)) {
    if (!line || line.startsWith(":")) continue;
    const i = line.indexOf(":");
    const field = i < 0 ? line : line.slice(0, i);
    let value = i < 0 ? "" : line.slice(i + 1);
    if (value.startsWith(" ")) value = value.slice(1);
    if (field === "event") event = value;
    else if (field === "data") data.push(value);
  }
  return data.length ? { event, data: data.join("\n") } : null;
}

export interface GeminiStreamSummary {
  content: Any[];
  finishReason: string | undefined;
  blocked: boolean;
  inputTokens: number;
  outputTokens: number;
}

export class GeminiStreamAssembler {
  private content: Any[] = [];
  private n = 0;
  private finishReason: string | undefined;
  private blocked = false;
  private inTok = 0;
  private outTok = 0;

  /// Бір chunk (JSON): жаңа МӘТІН бөлігін қайтарады (бос болуы мүмкін).
  /// Қате объектісі келсе (`{error:{...}}`) — лақтырады.
  push(chunk: Any): string {
    if (chunk?.error) {
      const e = new Error(String(chunk.error?.message ?? "gemini_stream_error"));
      (e as Any).status = Number(chunk.error?.code) || 502;
      throw e;
    }
    if (chunk?.promptFeedback?.blockReason) this.blocked = true;
    if (chunk?.usageMetadata) {
      this.inTok = chunk.usageMetadata.promptTokenCount ?? this.inTok;
      this.outTok = chunk.usageMetadata.candidatesTokenCount ?? this.outTok;
    }
    const cand = chunk?.candidates?.[0];
    if (cand?.finishReason) this.finishReason = cand.finishReason;
    let delta = "";
    for (const p of (cand?.content?.parts ?? []) as Any[]) {
      if (p.functionCall) {
        this.content.push({
          type: "tool_use",
          id: `gem_${Date.now().toString(36)}_${this.n++}`,
          name: p.functionCall.name,
          input: p.functionCall.args ?? {},
          _sig: p.thoughtSignature,
        });
      } else if (typeof p.text === "string" && !p.thought && p.text) {
        delta += p.text;
        const last = this.content[this.content.length - 1];
        if (last?.type === "text") last.text += p.text;
        else this.content.push({ type: "text", text: p.text });
      }
    }
    return delta;
  }

  summary(): GeminiStreamSummary {
    return {
      content: this.content,
      finishReason: this.finishReason,
      blocked: this.blocked,
      inputTokens: this.inTok,
      outputTokens: this.outTok,
    };
  }
}
