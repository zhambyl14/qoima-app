// ─── Qoima: Telegram телефон растау webhook ──────────────────────────────────
//
// POST /functions/v1/telegram-webhook   (Verify JWT = OFF)
//
// Мақсаты: тіркелуде/парольді қалпына келтіруде телефонды SMS-сіз, ТЕГІН растау.
// Ағын:
//   1) Қосымша `tg_start_verification()` RPC-пен кездейсоқ токен алады да,
//      пайдаланушыны `t.me/<bot>?start=<токен>`-ке жібереді.
//   2) Пайдаланушы ботта Start басқанда осында `/start <токен>` келеді →
//      сол токен жолына chat_id/user_id жазып, «📱 Нөмірімді бөлісу» түймесі
//      бар пернетақтаны жібереміз.
//   3) Пайдаланушы түймені басқанда Telegram НӨМІРДІ ӨЗІ растап `contact`
//      хабарын жібереді (жалған нөмір беру мүмкін емес) → сол chat-тың соңғы
//      расталмаған жолын `verified=true, phone`-мен толтырамыз.
//   4) Қосымша `tg_check_verification(token)`-пен статусты сұрап отырады.
//
// ҚАУІПСІЗДІК:
//  • Тек Telegram жіберген сұраныстарды қабылдаймыз: `X-Telegram-Bot-Api-Secret-
//    Token` header `TELEGRAM_WEBHOOK_SECRET`-пен тең болуы шарт.
//  • Контакт ИЕСІНІКІ болуы тексеріледі: `contact.user_id === message.from.id`
//    (басқаның контактісін forward жасап растай алмайды).
//  • Бот токені (`TELEGRAM_BOT_TOKEN`) мен service_role тек серверде.
//  • Кестеге жазу service_role арқылы (RLS айналып өтеді); кестеде саясат жоқ.

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const BOT_TOKEN = Deno.env.get("TELEGRAM_BOT_TOKEN")!;
const WEBHOOK_SECRET = Deno.env.get("TELEGRAM_WEBHOOK_SECRET")!;

const TG_API = `https://api.telegram.org/bot${BOT_TOKEN}`;
const REST = `${SUPABASE_URL}/rest/v1/telegram_verifications`;

// ── Telegram Bot API шақыру ───────────────────────────────────────────────────
async function tg(method: string, payload: unknown): Promise<void> {
  try {
    await fetch(`${TG_API}/${method}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });
  } catch (_) {
    // Telegram-ге жауап беру best-effort; қате болса webhook 200 қайтарады.
  }
}

// ── Supabase REST (service_role) көмекшілері ─────────────────────────────────
function restHeaders(extra: Record<string, string> = {}): Record<string, string> {
  return {
    "apikey": SERVICE_KEY,
    "Authorization": `Bearer ${SERVICE_KEY}`,
    "Content-Type": "application/json",
    ...extra,
  };
}

async function patchByToken(token: string, body: unknown): Promise<void> {
  await fetch(`${REST}?token=eq.${encodeURIComponent(token)}`, {
    method: "PATCH",
    headers: restHeaders(),
    body: JSON.stringify(body),
  });
}

// ── Телефонды E.164 (+7XXXXXXXXXX) қалыпқа келтіру ───────────────────────────
function normalizePhone(raw: string): string {
  let d = (raw || "").replace(/\D/g, "");
  if (d.length === 11 && d.startsWith("8")) d = "7" + d.slice(1);
  if (d.length === 10) d = "7" + d; // 7XXXXXXXXX (кодсыз) — сирек
  return "+" + d;
}

const CONTACT_BUTTON_TEXT = "📱 Нөмірімді бөлісу / Поделиться номером";

Deno.serve(async (req: Request): Promise<Response> => {
  // 1) Тек Telegram: құпия header тексеру.
  if (req.headers.get("x-telegram-bot-api-secret-token") !== WEBHOOK_SECRET) {
    return new Response("forbidden", { status: 401 });
  }

  let update: any;
  try {
    update = await req.json();
  } catch (_) {
    return new Response("ok"); // жарамсыз body — елемейміз
  }

  const msg = update?.message ?? update?.edited_message;
  const chatId: number | undefined = msg?.chat?.id;
  if (!msg || chatId == null) return new Response("ok");

  try {
    // ── /start <token> ────────────────────────────────────────────────────
    const text: string = typeof msg.text === "string" ? msg.text : "";
    if (text.startsWith("/start")) {
      const token = text.split(/\s+/)[1]?.trim() ?? "";
      if (token) {
        // Токен жолына chat/user байлаймыз (расталмаған, мерзімі өтпеген).
        await patchByToken(token, {
          telegram_chat_id: chatId,
          telegram_user_id: msg.from?.id ?? null,
        });
        await tg("sendMessage", {
          chat_id: chatId,
          text:
            "Нөміріңізді растау үшін төмендегі түймені басыңыз 👇\n\n" +
            "Чтобы подтвердить номер, нажмите кнопку ниже 👇",
          reply_markup: {
            keyboard: [[{ text: CONTACT_BUTTON_TEXT, request_contact: true }]],
            resize_keyboard: true,
            one_time_keyboard: true,
          },
        });
      } else {
        await tg("sendMessage", {
          chat_id: chatId,
          text:
            "Растауды қосымшадағы «Telegram арқылы растау» түймесінен бастаңыз.\n" +
            "Начните подтверждение кнопкой «Подтвердить через Telegram» в приложении.",
        });
      }
      return new Response("ok");
    }

    // ── Контакт (нөмір бөлісу) ────────────────────────────────────────────
    const contact = msg.contact;
    if (contact?.phone_number) {
      // Тек ӨЗ нөмірі: contact.user_id === message.from.id.
      if (contact.user_id && msg.from?.id && contact.user_id !== msg.from.id) {
        await tg("sendMessage", {
          chat_id: chatId,
          text:
            "Тек ӨЗ нөміріңізді бөлісіңіз.\nПоделитесь, пожалуйста, СВОИМ номером.",
        });
        return new Response("ok");
      }

      const phone = normalizePhone(contact.phone_number);
      const nowIso = new Date().toISOString();
      // Осы chat-тың соңғы расталмаған, мерзімі өтпеген жолын табамыз.
      const res = await fetch(
        `${REST}?telegram_chat_id=eq.${chatId}&verified=eq.false` +
          `&expires_at=gt.${encodeURIComponent(nowIso)}` +
          `&order=created_at.desc&limit=1&select=token`,
        { headers: restHeaders() },
      );
      const rows = await res.json().catch(() => []);
      const token = Array.isArray(rows) && rows[0]?.token;

      if (token) {
        await patchByToken(token, { verified: true, phone });
        await tg("sendMessage", {
          chat_id: chatId,
          text:
            `✅ Нөмір расталды: ${phone}\nҚосымшаға оралыңыз.\n\n` +
            `✅ Номер подтверждён: ${phone}\nВернитесь в приложение.`,
          reply_markup: { remove_keyboard: true },
        });
      } else {
        await tg("sendMessage", {
          chat_id: chatId,
          text:
            "Растау сессиясы табылмады немесе мерзімі өтті. Қосымшадан қайта бастаңыз.\n" +
            "Сессия не найдена или истекла. Начните заново из приложения.",
          reply_markup: { remove_keyboard: true },
        });
      }
      return new Response("ok");
    }
  } catch (_) {
    // Кез келген қатеде де 200 қайтарамыз (Telegram қайта жібермеу үшін).
  }

  return new Response("ok");
});
