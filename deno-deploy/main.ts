  // ─── Qoima: тауардың публичный share-беті (Deno Deploy) ──────────────────────
  //
  // НЕГЕ Deno Deploy: Supabase-тің тегін *.supabase.co домені қауіпсіздік үшін
  // HTML-ді браузерде РЕНДЕРЛЕМЕЙДІ (text/plain + sandbox CSP мәжбүрлейді). Deno
  // Deploy болса қалыпты text/html береді әрі тегін *.deno.dev субдоменін ұсынады.
  //
  // ОРНАТУ (бір рет):
  //  1. https://deno.com/deploy → GitHub-пен кіру → New Playground.
  //  2. Осы файлдың МАЗМҰНЫН толық сол жерге қою.
  //  3. Settings → Environment Variables:
  //       SUPABASE_URL              = https://ujpcdfgwxdholsepioji.supabase.co
  //       SUPABASE_SERVICE_ROLE_KEY = <Supabase → Settings → API → service_role key>
  //  4. Save & Deploy. URL аласыз: https://<аты>.deno.dev
  //     Сол URL-ді қосымшаға (SupabaseConfig.shareBaseUrl) жазамыз.
  //  5. (міндетті емес) SUPABASE_ANON_KEY — сыйлық/тілек тізімі беттерінің
  //     публик RPC-лері үшін; болмаса service key қолданылады (қауіпсіз: RPC
  //     auth.uid() = null деп қарайды).
  //
  // ҚАУІПСІЗДІК: тек ПУБЛИЧНЫЙ өрістер беріледі (өзіндік құн/batch_costs МҮЛДЕМ
  // сұралмайды); модерация блогы (users.blocked / stores.status='blocked') → 404;
  // service_role кілт тек серверде; барлық user-input HTML-ге escape.

  const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
  const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  const UUID_RE = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;

  function esc(s: unknown): string {
    return String(s ?? "")
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#39;");
  }

  function safeImg(u: unknown): string {
    return typeof u === "string" && /^https:\/\//i.test(u) ? u : "";
  }

  function money(v: number): string {
    const s = Math.round(v).toString();
    let out = "";
    for (let i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 === 0) out += " ";
      out += s[i];
    }
    return out + " ₸";
  }

  type Discount = {
    active?: boolean;
    type?: string;
    value?: number;
    starts_at?: string | null;
    ends_at?: string | null;
  } | null;

  type Batch = {
    selling_price?: number;
    sizes_quantity?: Record<string, number>;
    reserved_sizes?: Record<string, number>;
    warehouse_id?: string;
    discount?: Discount;
  };

  function effectivePrice(b: Batch): number {
    const sp = Number(b.selling_price) || 0;
    const d = b.discount;
    if (!d || !d.active) return sp;
    const now = Date.now();
    if (d.starts_at && now < Date.parse(d.starts_at)) return sp;
    if (d.ends_at && now > Date.parse(d.ends_at)) return sp;
    const val = Number(d.value) || 0;
    const raw = d.type === "percent" ? sp * (1 - val / 100) : sp - val;
    return raw < 0 ? 0 : Math.round(raw);
  }

  function availableForSize(b: Batch, size: string): number {
    const qty = Number(b.sizes_quantity?.[size]) || 0;
    const reserved = Number(b.reserved_sizes?.[size]) || 0;
    const a = qty - reserved;
    return a < 0 ? 0 : a;
  }

  async function rest(path: string): Promise<any[] | null> {
    try {
      const r = await fetch(`${SUPABASE_URL}/rest/v1/${path}`, {
        headers: { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}` },
      });
      if (!r.ok) return null;
      return await r.json();
    } catch {
      return null;
    }
  }

  function page(html: string, status: number): Response {
    return new Response(html, {
      status,
      headers: {
        "content-type": "text/html; charset=utf-8",
        // Қысқа кэш: товар өшсе/бағасы өзгерсе сілтеме тез жаңарсын (60 сек).
        "cache-control": "public, max-age=60",
      },
    });
  }

  function notFound(): Response {
    return page(
      `<!doctype html><html lang="ru"><head>
  <meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
  <title>Товар не найден · Qoima</title>
  <style>
    :root{color-scheme:light}
    body{margin:0;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;
      background:#F1F4F3;color:#0C120F;display:flex;min-height:100vh;align-items:center;justify-content:center}
    .box{text-align:center;padding:32px}
    .logo{font-weight:800;font-size:26px;letter-spacing:-1px;color:#00A862;margin-bottom:16px}
    h1{font-size:18px;margin:0 0 8px}p{color:#566B61;margin:0}
  </style></head><body>
  <div class="box"><div class="logo">Qoima</div>
  <h1>Товар недоступен</h1>
  <p>Возможно, он снят с продажи или ссылка неверна.</p></div>
  </body></html>`,
      404,
    );
  }

  // ─── 🎁 Сыйлық (?g=) және Тілек тізімі (?w=) қонақ беттері ─────────────────────
  //
  // Сілтемені WhatsApp/Telegram-да ашқан адам (қосымшасы жоқ/кірмеген) алдымен
  // осы бетті көреді: сыйлық/тізім мазмұны + «Qoima-да ашу» батырмасы.
  // Деректер ТЕК публиктік RPC арқылы (get_gift_public / get_registry_public) —
  // токен болжанбайтын uuid; бағасы жасырын сыйлықтың бағасы мұнда ЕШҚАШАН
  // шықпайды (қонақ сыйлаушы емес, auth.uid() жоқ → RPC өзі null қайтарады).
  // Қонақтардың жеке деректері (телефон, мекенжай, кім сатып алды) қайтпайды.

  // ⚠️ ОРНАТУ: қосымша дүкендеріне сілтемелер. Android id — build.gradle.kts-тан;
  // iOS App Store сілтемесі жарияланғанша бос қалдырыңыз (батырма жасырылады).
  const PLAY_STORE_URL =
    "https://play.google.com/store/apps/details?id=com.jambyl.qoima.qoima";
  const APP_STORE_URL = ""; // TODO: App Store сілтемесін қойыңыз

  // Публик RPC үшін анон кілт (болса). Жоқ болса — service key (RPC бәрібір
  // auth.uid() = null деп қарайды, сондықтан баға жасыру сақталады).
  const RPC_KEY = Deno.env.get("SUPABASE_ANON_KEY") || SERVICE_KEY;

  async function rpc(
    fn: string,
    args: Record<string, unknown>,
  ): Promise<any | null> {
    try {
      const r = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${fn}`, {
        method: "POST",
        headers: {
          apikey: RPC_KEY,
          Authorization: `Bearer ${RPC_KEY}`,
          "content-type": "application/json",
        },
        body: JSON.stringify(args),
      });
      if (!r.ok) return null;
      return await r.json();
    } catch {
      return null;
    }
  }

  const LANDING_CSS = `
    :root{color-scheme:light}
    *{box-sizing:border-box}
    body{margin:0;background:linear-gradient(180deg,#E4F7EE 0%,#F1F4F3 55%);color:#0C120F;
      font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;
      -webkit-font-smoothing:antialiased;min-height:100vh}
    .wrap{max-width:480px;margin:0 auto;padding:22px 16px 40px}
    .logo{font-weight:800;font-size:22px;letter-spacing:-1px;color:#00A862;text-align:center;margin-bottom:14px}
    .hero{text-align:center;margin:6px 0 14px}
    .hero .em{font-size:64px;line-height:1;display:block;margin-bottom:6px}
    .hero h1{font-size:24px;font-weight:800;letter-spacing:-.5px;margin:0 0 4px}
    .hero p{margin:0;color:#566B61;font-size:14.5px}
    .card{background:#fff;border-radius:22px;box-shadow:0 8px 28px rgba(0,100,60,.10);overflow:hidden;margin-top:14px}
    .card img.pic{width:100%;aspect-ratio:1/1;object-fit:cover;display:block;background:#E4F7EE}
    .pad{padding:16px 18px}
    .brand{font-size:11px;font-weight:800;letter-spacing:1px;color:#00A862;text-transform:uppercase}
    .nm{font-size:19px;font-weight:800;margin:3px 0 0;line-height:1.25}
    .price{font-size:22px;font-weight:800;margin-top:8px}
    .msg{background:#FFF7E0;border-radius:16px;padding:14px 16px;margin-top:14px;font-size:15px;
      line-height:1.5;color:#5B4300;font-style:italic;white-space:pre-wrap}
    .from{font-size:12.5px;color:#8A6D00;font-style:normal;font-weight:700;margin-top:6px;display:block}
    .store{display:flex;align-items:center;gap:10px;margin-top:14px;padding:12px 14px;background:#E4F7EE;
      border-radius:16px;font-size:13.5px;color:#00713F;font-weight:700}
    .store small{display:block;font-weight:500;color:#3d8a68;font-size:12px}
    .btn{display:block;text-align:center;text-decoration:none;background:#00A862;color:#fff;font-weight:800;
      font-size:16px;padding:16px;border-radius:16px;margin-top:18px;box-shadow:0 6px 18px rgba(0,168,98,.35)}
    .btn.alt{background:#fff;color:#00A862;box-shadow:none;border:1.5px solid #00A862;margin-top:10px;font-size:14.5px;padding:13px}
    .hint{text-align:center;color:#566B61;font-size:12.5px;margin-top:10px;line-height:1.5}
    .state{background:#fff;border-radius:18px;padding:16px 18px;margin-top:14px;font-size:14px;line-height:1.5;color:#3d4a44;text-align:center}
    .item{display:flex;gap:12px;padding:12px 0;border-bottom:1px solid #EEF1F0;align-items:center}
    .item:last-child{border-bottom:0}
    .item img{width:56px;height:56px;border-radius:12px;object-fit:cover;background:#E4F7EE;flex:0 0 auto}
    .item .t{font-size:14px;font-weight:700;line-height:1.3}
    .item .s{font-size:12px;color:#8A968F;margin-top:2px}
    .tag{display:inline-block;font-size:11px;font-weight:800;padding:2px 8px;border-radius:8px;margin-left:6px}
    .tag.ok{background:#E4F7EE;color:#00713F}.tag.done{background:#EEF1F0;color:#8A968F}
  `;

  function landingShell(opts: {
    title: string;
    desc: string;
    image: string;
    pageUrl: string;
    body: string;
    status?: number;
  }): Response {
    const img = safeImg(opts.image);
    const html = `<!doctype html><html lang="ru"><head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
  <title>${esc(opts.title)} · Qoima</title>
  <meta name="description" content="${esc(opts.desc)}">
  <meta name="robots" content="noindex,nofollow">
  <meta property="og:type" content="website">
  <meta property="og:site_name" content="Qoima">
  <meta property="og:title" content="${esc(opts.title)}">
  <meta property="og:description" content="${esc(opts.desc)}">
  ${img ? `<meta property="og:image" content="${esc(img)}">
  <meta property="og:image:secure_url" content="${esc(img)}">
  <meta name="twitter:image" content="${esc(img)}">` : ""}
  <meta property="og:url" content="${esc(opts.pageUrl)}">
  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:title" content="${esc(opts.title)}">
  <meta name="twitter:description" content="${esc(opts.desc)}">
  <style>${LANDING_CSS}</style></head><body>
  <div class="wrap"><div class="logo">Qoima</div>${opts.body}</div>
  </body></html>`;
    return new Response(html, {
      status: opts.status ?? 200,
      headers: {
        "content-type": "text/html; charset=utf-8",
        // Сыйлық күйі (төленді/алынды) мен баға жасыру тез өзгереді — кэш жоқ.
        "cache-control": "no-store",
      },
    });
  }

  /// «Қосымшада ашу» + дүкенге сілтемелер блогы. [deepLink] — qoima://…
  function openAppHtml(deepLink: string): string {
    return `
    <a class="btn" id="openapp" href="${esc(deepLink)}">Открыть в Qoima · Qoima-да ашу</a>
    <div class="hint" id="noapp" style="display:none;color:#B3261E;font-weight:700">Приложение не открылось — установите или обновите Qoima.<br>Қосымша ашылмады — Qoima-ны орнатыңыз немесе жаңартыңыз.</div>
    <script>
    (function(){
      var b=document.getElementById('openapp'),n=document.getElementById('noapp');
      b.addEventListener('click',function(e){
        e.preventDefault();
        var t=Date.now(),hid=false;
        document.addEventListener('visibilitychange',function(){if(document.hidden)hid=true;});
        // iframe арқылы: қосымша жоқ болса Safari «адрес недействителен» терезесін шығармайды.
        var f=document.createElement('iframe');f.style.display='none';f.src=b.href;document.body.appendChild(f);
        setTimeout(function(){if(!hid&&!document.hidden)n.style.display='block';},1500);
      });
    })();
    </script>
    ${PLAY_STORE_URL ? `<a class="btn alt" href="${esc(PLAY_STORE_URL)}">Скачать для Android · Android үшін жүктеу</a>` : ""}
    ${APP_STORE_URL ? `<a class="btn alt" href="${esc(APP_STORE_URL)}">Скачать для iPhone · iPhone үшін жүктеу</a>` : ""}
    <div class="hint">Нет приложения? Установите Qoima, затем снова нажмите «Открыть».<br>
    Қосымша жоқ па? Qoima-ны орнатып, «Ашу» батырмасын қайта басыңыз.</div>`;
  }

  function landingNotFound(kind: "gift" | "registry"): Response {
    const g = kind === "gift";
    return landingShell({
      title: g ? "Подарок не найден" : "Список не найден",
      desc: "Qoima",
      image: "",
      pageUrl: "",
      status: 404,
      body: `<div class="hero"><span class="em">${g ? "🎁" : "📝"}</span>
        <h1>${g ? "Подарок не найден · Сыйлық табылмады" : "Список не найден · Тізім табылмады"}</h1>
        <p>Ссылка неверна или устарела.<br>Сілтеме қате немесе ескірген.</p></div>`,
    });
  }

  async function giftLanding(token: string, origin: string): Promise<Response> {
    const g = await rpc("get_gift_public", { p_token: token });
    if (!g || typeof g !== "object") return landingNotFound("gift");

    const product = g.product ?? {};
    const store = g.store ?? {};
    const giver = String(g.giver_first_name ?? "").trim();
    const recipient = String(g.recipient_name ?? "").trim();
    const message = String(g.message ?? "").trim();
    const status = String(g.status ?? "");
    const pageUrl = `${origin}/?g=${token}`;
    const deepLink = `qoima://gift/${token}`;
    const img = safeImg(product.image_url);
    // Баға: RPC жасырын бағада null қайтарады (қонақ сыйлаушы емес).
    const price = typeof g.price === "number" && g.price > 0 ? money(g.price) : "";

    const ogDesc = [product.brand, product.name]
      .filter((x) => x && String(x).trim())
      .join(" · ") || "Qoima";

    let stateHtml = "";
    let showOpen = true;
    switch (status) {
      case "awaiting_payment":
        stateHtml =
          `<div class="state">⏳ Подарок почти готов — ожидается подтверждение оплаты. Загляните чуть позже.<br>Сыйлық дайындалып жатыр — төлем расталуын күтеміз. Сәл кейінірек қараңыз.</div>`;
        break;
      case "claimed":
        stateHtml =
          `<div class="state">✅ Этот подарок уже получен. · Бұл сыйлық алынып қойған.</div>`;
        showOpen = false;
        break;
      case "expired":
        stateHtml =
          `<div class="state">⌛ Срок получения подарка истёк. Свяжитесь с дарителем.<br>Сыйлықты алу мерзімі өтті. Сыйлаушымен байланысыңыз.</div>`;
        showOpen = false;
        break;
      case "cancelled":
        stateHtml =
          `<div class="state">❌ Заказ отменён. · Тапсырыс бас тартылды.</div>`;
        showOpen = false;
        break;
      default: {
        // Сыйлаушы өлшемді өзі таңдаса (0070, брондалған) — алушы ауыстыра алады,
        // қайтарылмайтын тауарда — жоқ.
        const chosen = String(g.chosen_size ?? "").trim();
        const locked = g.non_returnable === true;
        stateHtml = chosen
          ? (locked
            ? `<div class="state">Размер выбран: ${esc(chosen)}. Откройте в приложении и подтвердите получение.<br>Өлшемі таңдалған: ${esc(chosen)}. Қосымшада ашып, сыйлықты алуды растаңыз.</div>`
            : `<div class="state">Размер выбран: ${esc(chosen)} — при желании можно поменять размер или товар.<br>Өлшемі таңдалған: ${esc(chosen)} — қаласаңыз ауыстыра аласыз.</div>`)
          : `<div class="state">Откройте в приложении, выберите свой размер — и подарок поедет к вам.<br>Қосымшада өз өлшеміңізді таңдаңыз — сыйлық сізге жолға шығады.</div>`;
      }
    }

    const body = `
    <div class="hero"><span class="em">🎁</span>
      <h1>${recipient ? `${esc(recipient)}, ` : ""}Сізге сыйлық бар!</h1>
      <p>${giver ? `${esc(giver)} · ` : ""}Вам подарок!</p></div>
    <div class="card">
      ${img ? `<img class="pic" src="${esc(img)}" alt="${esc(product.name)}">` : ""}
      <div class="pad">
        ${product.brand ? `<div class="brand">${esc(product.brand)}</div>` : ""}
        <div class="nm">${esc(product.name ?? "")}</div>
        ${price ? `<div class="price">${esc(price)}</div>` : ""}
      </div>
    </div>
    ${
      message
        ? `<div class="msg">«${esc(message)}»${giver ? `<span class="from">— ${esc(giver)}</span>` : ""}</div>`
        : ""
    }
    ${
      store.name
        ? `<div class="store">🏬<div>${esc(store.name)}<small>${esc([store.city, store.address].filter(Boolean).join(", "))}</small></div></div>`
        : ""
    }
    ${stateHtml}
    ${showOpen ? openAppHtml(deepLink) : ""}`;

    return landingShell({
      title: "🎁 Сізге сыйлық бар! · Вам подарок!",
      desc: ogDesc,
      image: img,
      pageUrl,
      body,
    });
  }

  async function registryLanding(
    token: string,
    origin: string,
  ): Promise<Response> {
    const r = await rpc("get_registry_public", { p_token: token });
    if (!r || typeof r !== "object") return landingNotFound("registry");

    const owner = String(r.owner_name ?? "").trim();
    const title = String(r.title ?? "").trim() || "Список желаний · Тілек тізімі";
    const message = String(r.message ?? "").trim();
    const city = String(r.city ?? "").trim();
    const items: any[] = Array.isArray(r.items) ? r.items : [];
    const pageUrl = `${origin}/?w=${token}`;
    const deepLink = `qoima://registry/${token}`;
    const firstImg = safeImg(
      items.find((i) => safeImg(i?.image_url))?.image_url,
    );

    let dateTxt = "";
    if (r.event_date) {
      const d = new Date(String(r.event_date));
      if (!isNaN(d.getTime())) {
        dateTxt = `${String(d.getUTCDate()).padStart(2, "0")}.${
          String(d.getUTCMonth() + 1).padStart(2, "0")
        }.${d.getUTCFullYear()}`;
      }
    }

    const rows = items.slice(0, 12).map((i) => {
      const rem = Number(i.remaining) || 0;
      const pic = safeImg(i.image_url);
      const sub = [
        i.size ? `Размер ${esc(i.size)}` : "",
        Number(i.price) > 0 ? esc(money(Number(i.price))) : "",
      ].filter(Boolean).join(" · ");
      return `<div class="item">
        ${pic ? `<img src="${esc(pic)}" alt="">` : `<img alt="" src="data:image/gif;base64,R0lGODlhAQABAAAAACH5BAEKAAEALAAAAAABAAEAAAICTAEAOw==">`}
        <div><div class="t">${esc(i.product_name ?? "")}${
        rem > 0
          ? `<span class="tag ok">${rem}</span>`
          : `<span class="tag done">✓</span>`
      }</div>
        <div class="s">${sub}</div></div>
      </div>`;
    }).join("");

    const ogDesc = [owner, dateTxt, city].filter(Boolean).join(" · ") || "Qoima";

    const body = `
    <div class="hero"><span class="em">🎀</span>
      <h1>${esc(title)}</h1>
      <p>${[owner ? esc(owner) : "", dateTxt, city ? esc(city) : ""].filter(Boolean).join(" · ")}</p></div>
    ${
      message
        ? `<div class="msg">«${esc(message)}»${owner ? `<span class="from">— ${esc(owner)}</span>` : ""}</div>`
        : ""
    }
    ${rows ? `<div class="card"><div class="pad">${rows}</div></div>` : ""}
    ${
      items.length > 12
        ? `<div class="hint">+${items.length - 12} ещё в приложении · қосымшада тағы бар</div>`
        : ""
    }
    <div class="state">Выберите подарок из списка и забронируйте его — никто не купит такой же.<br>Тізімнен сыйлық таңдап, брондаңыз — басқа ешкім дәл соны алмайды.</div>
    ${openAppHtml(deepLink)}`;

    return landingShell({
      title: owner ? `🎀 ${title} — ${owner}` : `🎀 ${title}`,
      desc: ogDesc,
      image: firstImg,
      pageUrl,
      body,
    });
  }

  Deno.serve(async (req) => {
    const url = new URL(req.url);

    // ?g=<gift_token> / ?w=<registry_token> — сыйлық және тілек тізімі беттері.
    const gTok = url.searchParams.get("g");
    if (gTok !== null) {
      return UUID_RE.test(gTok)
        ? await giftLanding(gTok.toLowerCase(), url.origin)
        : landingNotFound("gift");
    }
    const wTok = url.searchParams.get("w");
    if (wTok !== null) {
      return UUID_RE.test(wTok)
        ? await registryLanding(wTok.toLowerCase(), url.origin)
        : landingNotFound("registry");
    }

    const id = url.searchParams.get("id") ?? "";
    if (!UUID_RE.test(id)) return notFound();

    // 1) Тауар (тек публичный өрістер; purchase_price/batch_costs МҮЛДЕМ жоқ).
    const prodRows = await rest(
      `products?id=eq.${id}&limit=1&select=id,name,brand,type,material,category,category_key,color,articul,season,country,description,images,status,owner_uid`,
    );
    const product = prodRows?.[0];
    if (!product) return notFound();

    // 2) Иесі — глобалды блок тексеру + аты (дүкен жолы жоқ офлайн сатушы үшін).
    const ownerRows = await rest(
      `users?id=eq.${encodeURIComponent(product.owner_uid)}&limit=1&select=name,blocked`,
    );
    const owner = ownerRows?.[0] ?? null;
    if (owner?.blocked === true) return notFound();

    // 3) Дүкен — БОЛМАУЫ мүмкін (офлайн сатушы). Бар болып БЛОКТАЛСА — 404.
    //    is_published ТЕКСЕРІЛМЕЙДІ: офлайн дүкендер де бөлісе алады.
    const storeRows = await rest(
      `stores?admin_uid=eq.${encodeURIComponent(product.owner_uid)}&limit=1&select=store_name,city,status,visible_warehouse_ids`,
    );
    const store = storeRows?.[0] ?? null;
    if (store && store.status === "blocked") return notFound();

    const storeName =
      (store?.store_name && String(store.store_name).trim()) ||
      (owner?.name && String(owner.name).trim()) ||
      "Продавец";
    const storeCity = store?.city ? String(store.city) : "";

    // 4) Партиялар — тек көрінетін қоймалардан; баға мен размерлерді есептейміз.
    const batchesRaw =
      (await rest(
        `batches?product_id=eq.${id}&select=selling_price,sizes_quantity,reserved_sizes,warehouse_id,discount`,
      )) ?? [];
    // Партия МҮЛДЕМ жоқ болса — товар өшірілген деп есептеп, сілтемені жабамыз
    // (партияны өшірген соң товар жолы қалады, бірақ ол «жоқ» болып саналады).
    if (batchesRaw.length === 0) return notFound();
    const visibleWh: string[] = Array.isArray(store?.visible_warehouse_ids)
      ? store.visible_warehouse_ids
      : [];
    const batches: Batch[] = (batchesRaw as Batch[]).filter(
      (b) => visibleWh.length === 0 || visibleWh.includes(b.warehouse_id ?? ""),
    );

    const sizeMap: Record<string, number> = {};
    for (const b of batches) {
      for (const size of Object.keys(b.sizes_quantity ?? {})) {
        sizeMap[size] = (sizeMap[size] ?? 0) + availableForSize(b, size);
      }
    }
    const availSizes = Object.entries(sizeMap)
      .filter(([, v]) => v > 0)
      .map(([k]) => k)
      .sort((a, b) => (parseFloat(a) || 0) - (parseFloat(b) || 0));
    const inStock = availSizes.length > 0;

    const priceBatch =
      batches.find((b) =>
        Object.keys(b.sizes_quantity ?? {}).some((s) => availableForSize(b, s) > 0)
      ) ??
      batches[0] ??
      null;
    const basePrice = priceBatch ? Number(priceBatch.selling_price) || 0 : 0;
    const price = priceBatch ? effectivePrice(priceBatch) : 0;
    const hasDiscount = price < basePrice;
    const discountPct = hasDiscount ? Math.round((1 - price / basePrice) * 100) : 0;

    const images: string[] = Array.isArray(product.images)
      ? product.images.map(safeImg).filter(Boolean)
      : [];
    const heroImg = images[0] ?? "";

    const priceLabel = price > 0 ? money(price) : "";
    const ogTitle = priceLabel
      ? `${product.name} — ${priceLabel}`
      : String(product.name ?? "Qoima");
    const ogDesc = [product.brand, product.type, storeName]
      .filter((x) => x && String(x).trim())
      .join(" · ");
    const pageUrl = `${url.origin}${url.pathname}?id=${id}`;

    const specs: [string, string][] = [];
    const push = (label: string, val: unknown) => {
      if (val && String(val).trim()) specs.push([label, String(val)]);
    };
    push("Бренд", product.brand);
    push("Тип", product.type);
    push("Для кого", product.category);
    push("Цвет", product.color);
    push("Материал", product.material);
    push("Сезон", product.season);
    push("Страна", product.country);

    const sizesHtml = availSizes
      .map((s) => `<span class="size">${esc(s)}</span>`)
      .join("");

    const thumbsHtml =
      images.length > 1
        ? `<div class="thumbs">${images
            .map(
              (im, i) =>
                `<img src="${esc(im)}" alt="" class="thumb${
                  i === 0 ? " active" : ""
                }" onclick="setHero('${esc(im)}',this)">`,
            )
            .join("")}</div>`
        : "";

    const specsHtml = specs
      .map(
        ([k, v]) =>
          `<div class="spec"><span class="k">${esc(k)}</span><span class="v">${esc(
            v,
          )}</span></div>`,
      )
      .join("");

    const descHtml = product.description
      ? `<div class="section"><div class="sec-title">Описание</div>
        <div class="desc">${esc(product.description)}</div></div>`
      : "";

    const priceHtml =
      price > 0
        ? `<div class="price-row">
            <span class="price${hasDiscount ? " sale" : ""}">${esc(money(price))}</span>
            ${
              hasDiscount
                ? `<span class="old">${esc(money(basePrice))}</span>
                  <span class="badge">−${discountPct}%</span>`
                : ""
            }
          </div>`
        : "";

    const html = `<!doctype html><html lang="ru"><head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
  <title>${esc(product.name)} · Qoima</title>
  <meta name="description" content="${esc(ogDesc)}">
  <meta property="og:type" content="product">
  <meta property="og:site_name" content="Qoima">
  <meta property="og:title" content="${esc(ogTitle)}">
  <meta property="og:description" content="${esc(ogDesc)}">
  ${heroImg ? `<meta property="og:image" content="${esc(heroImg)}">
  <meta property="og:image:secure_url" content="${esc(heroImg)}">
  <meta property="og:image:type" content="image/jpeg">
  <meta property="og:image:width" content="1080">
  <meta property="og:image:height" content="1080">
  <meta property="og:image:alt" content="${esc(product.name)}">` : ""}
  <meta property="og:url" content="${esc(pageUrl)}">
  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:title" content="${esc(ogTitle)}">
  <meta name="twitter:description" content="${esc(ogDesc)}">
  ${heroImg ? `<meta name="twitter:image" content="${esc(heroImg)}">` : ""}
  <style>
    :root{color-scheme:light}
    *{box-sizing:border-box}
    body{margin:0;background:#F1F4F3;color:#0C120F;
      font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;
      -webkit-font-smoothing:antialiased}
    .wrap{max-width:480px;margin:0 auto;background:#fff;min-height:100vh}
    .hero-wrap{position:relative;overflow:hidden}
    .hero{width:100%;aspect-ratio:1/1;background:#E4F7EE;display:block;object-fit:cover}
    /* Үлкен мөлдір диагональ бренд-watermark — фото ортасында, скриншотта да
      Qoima сақталады (Krisha-стиль). */
    .wm{position:absolute;inset:0;z-index:2;display:flex;align-items:center;
      justify-content:center;pointer-events:none}
    .wm span{font-weight:800;font-size:clamp(72px,24vw,120px);letter-spacing:2px;
      color:#00A862;opacity:.08;transform:rotate(-30deg);white-space:nowrap;
      user-select:none;-webkit-user-select:none}
    .hero-ph{width:100%;aspect-ratio:1/1;background:linear-gradient(135deg,#E4F7EE,#C8EEDB);
      display:flex;align-items:center;justify-content:center;color:#8fb9a6;font-size:15px}
    .thumbs{display:flex;gap:8px;padding:12px 16px 0;overflow-x:auto}
    .thumb{width:56px;height:56px;border-radius:12px;object-fit:cover;flex:0 0 auto;
      border:2px solid transparent;cursor:pointer;opacity:.6;transition:.15s}
    .thumb.active{border-color:#00A862;opacity:1}
    .body{padding:18px 18px 40px}
    .brand{font-size:11px;font-weight:800;letter-spacing:1px;color:#00A862;text-transform:uppercase}
    h1{font-size:22px;font-weight:800;letter-spacing:-.4px;margin:4px 0 2px;line-height:1.2}
    .articul{display:inline-block;margin:6px 0 2px;padding:2px 8px;border-radius:6px;
      background:#F1F4F3;color:#8A968F;font-size:11.5px;font-weight:600;
      font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace}
    .type{font-size:13.5px;color:#8A968F;margin-bottom:12px}
    .price-row{display:flex;align-items:flex-end;gap:10px;flex-wrap:wrap;margin-bottom:14px}
    .price{font-size:28px;font-weight:800}
    .price.sale{color:#F0384B}
    .old{font-size:16px;color:#8A968F;text-decoration:line-through;font-weight:600;margin-bottom:4px}
    .badge{background:#F0384B;color:#fff;font-weight:800;font-size:12.5px;
      padding:3px 8px;border-radius:8px;margin-bottom:5px}
    .stock{display:inline-flex;align-items:center;gap:6px;font-size:12.5px;font-weight:700;
      padding:5px 11px;border-radius:20px;margin-bottom:16px}
    .stock.in{background:#E4F7EE;color:#00713F}
    .stock.out{background:#EEF1F0;color:#8A968F}
    .stock i{width:7px;height:7px;border-radius:50%;background:currentColor;display:inline-block}
    .section{margin-top:18px}
    .sec-title{font-size:12px;font-weight:700;letter-spacing:.4px;color:#8A968F;
      text-transform:uppercase;margin-bottom:10px}
    .sizes{display:flex;flex-wrap:wrap;gap:9px}
    .size{min-width:48px;text-align:center;padding:13px 10px;border-radius:13px;
      background:#F7FAF9;border:1.5px solid #E7ECEA;font-weight:800;font-size:15px}
    .desc{font-size:13.5px;color:#3d4a44;line-height:1.6;white-space:pre-wrap}
    .specs{border:1px solid #E7ECEA;border-radius:14px;overflow:hidden;margin-top:6px}
    .spec{display:flex;padding:11px 14px;font-size:13.5px}
    .spec:not(:last-child){border-bottom:1px solid #EEF1F0}
    .spec .k{width:104px;color:#8A968F;flex:0 0 auto}
    .spec .v{font-weight:700}
    .store{margin-top:20px;display:flex;align-items:center;gap:11px;padding:14px;
      background:#E4F7EE;border-radius:18px}
    .store .ic{width:22px;height:22px;flex:0 0 auto}
    .store .nm{font-weight:700;font-size:14px;color:#00713F}
    .store .ct{font-size:12px;color:#3d8a68}
  </style></head><body>
  <div class="wrap">
    <div class="hero-wrap">
      ${
        heroImg
          ? `<img class="hero" id="hero" src="${esc(heroImg)}" alt="${esc(product.name)}">`
          : `<div class="hero-ph">Нет фото</div>`
      }
      <div class="wm"><span>QOIMA</span></div>
    </div>
    ${thumbsHtml}
    <div class="body">
      ${product.brand ? `<div class="brand">${esc(product.brand)}</div>` : ""}
      <h1>${esc(product.name)}</h1>
      ${product.articul ? `<div class="articul">${esc(product.articul)}</div>` : ""}
      ${product.type ? `<div class="type">${esc(product.type)}</div>` : ""}
      ${priceHtml}
      <div class="stock ${inStock ? "in" : "out"}"><i></i>${
      inStock ? "В наличии" : "Нет в наличии"
    }</div>
      ${
        sizesHtml
          ? `<div class="section"><div class="sec-title">Доступные размеры</div>
            <div class="sizes">${sizesHtml}</div></div>`
          : ""
      }
      ${descHtml}
      ${
        specsHtml
          ? `<div class="section"><div class="sec-title">Характеристики</div>
            <div class="specs">${specsHtml}</div></div>`
          : ""
      }
      <div class="store">
        <svg class="ic" viewBox="0 0 24 24" fill="none" stroke="#00713F" stroke-width="2"
          stroke-linecap="round" stroke-linejoin="round"><path d="M3 9l1-5h16l1 5"/>
          <path d="M4 9v11h16V9"/><path d="M9 20v-6h6v6"/></svg>
        <div><div class="nm">${esc(storeName)}</div>
        ${storeCity ? `<div class="ct">${esc(storeCity)}</div>` : ""}</div>
      </div>
    </div>
  </div>
  <script>
    function setHero(src,el){
      var h=document.getElementById('hero'); if(h)h.src=src;
      document.querySelectorAll('.thumb').forEach(function(t){t.classList.remove('active')});
      if(el)el.classList.add('active');
    }
  </script>
  </body></html>`;

    return page(html, 200);
  });
