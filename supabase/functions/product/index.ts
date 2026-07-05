// ─── Qoima: тауардың публичный share-беті ────────────────────────────────────
//
// GET /functions/v1/product?id=<productId>
//
// Мақсаты: дүкен иесі/сатушы бөліскен сілтемені кез келген адам браузерде ашқанда
// тауардың әдемі карточкасын көреді (қосымша қажет емес). WhatsApp/Telegram
// сілтемеге сурет+аты+бағасы бар превью-карточка көрсетеді (Open Graph тегтері).
//
// ҚАУІПСІЗДІК:
//  • Тек ПУБЛИЧНЫЙ дерек беріледі: аты, суреті, САТУ бағасы, размерлері,
//    сипаттамасы. Өзіндік құн (batch_costs) МҮЛДЕМ сұралмайды әрі берілмейді.
//  • Бөлісу — иесінің өз еркіндегі әрекеті, сол себепті ОФЛАЙН (жарияланбаған)
//    дүкендердің тауары да ашылады. Тек МОДЕРАЦИЯ блогы жабады: иесі глобалды
//    блокталса (users.blocked) НЕ дүкені блокталса (stores.status='blocked') → 404.
//  • service_role кілт тек серверде (браузерге кетпейді); RLS-ті айналып өтсе де
//    сұраныстар нақты өрістермен шектеліп, көріну ережесі қолмен тексеріледі.
//  • Барлық пайдаланушы енгізген мәтін HTML-ге қашырылып (escape) шығады.

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const UUID_RE = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;

// ── Утилиталар ────────────────────────────────────────────────────────────────
function esc(s: unknown): string {
  return String(s ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

// Тек https суреттерін ғана өткіземіз (javascript:/data: инъекциясынан қорғау).
function safeImg(u: unknown): string {
  return typeof u === "string" && /^https:\/\//i.test(u) ? u : "";
}

// Ақшаны форматтау (қосымшадағы money() сияқты): "25000" → "25 000 ₸".
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

// Жеңілдікпен есептелген нақты баға (batch_model.dart effectivePrice көшірмесі).
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

// ── Қателік/404 беті ──────────────────────────────────────────────────────────
function notFound(): Response {
  const html = `<!doctype html><html xmlns="http://www.w3.org/1999/xhtml" lang="ru"><head>
<meta charset="utf-8" /><meta name="viewport" content="width=device-width,initial-scale=1" />
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
</body></html>`;
  return new Response(html, {
    status: 404,
    headers: { "content-type": "application/xhtml+xml; charset=utf-8" },
  });
}

// ── Негізгі handler ───────────────────────────────────────────────────────────
Deno.serve(async (req) => {
  const url = new URL(req.url);
  const id = url.searchParams.get("id") ?? "";
  if (!UUID_RE.test(id)) return notFound();

  // 1) Тауар (тек публичный өрістер; purchase_price/batch_costs МҮЛДЕМ жоқ).
  const prodRows = await rest(
    `products?id=eq.${id}&limit=1&select=id,name,brand,type,material,category,category_key,color,season,country,description,images,status,owner_uid`,
  );
  const product = prodRows?.[0];
  if (!product) return notFound();

  // 2) Иесі (users) — глобалды блок тексеру + аты (дүкен жолы жоқ офлайн
  //    сатушы үшін карточкада көрсету).
  const ownerRows = await rest(
    `users?id=eq.${encodeURIComponent(product.owner_uid)}&limit=1&select=name,blocked`,
  );
  const owner = ownerRows?.[0] ?? null;
  if (owner?.blocked === true) return notFound(); // глобалды модерация блогы

  // 3) Дүкен — БОЛМАУЫ мүмкін (офлайн сатушы). Бар болып, БЛОКТАЛСА — 404.
  //    is_published ТЕКСЕРІЛМЕЙДІ: офлайн (жарияланбаған) дүкендер де бөлісе алады.
  const storeRows = await rest(
    `stores?admin_uid=eq.${encodeURIComponent(product.owner_uid)}&limit=1&select=store_name,city,status,visible_warehouse_ids`,
  );
  const store = storeRows?.[0] ?? null;
  if (store && store.status === "blocked") return notFound(); // онлайн блок

  // Дүкен жолы жоқ болса — иесінің атын қолданамыз.
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
  const visibleWh: string[] = Array.isArray(store?.visible_warehouse_ids)
    ? store.visible_warehouse_ids
    : [];
  const batches: Batch[] = (batchesRaw as Batch[]).filter(
    (b) => visibleWh.length === 0 || visibleWh.includes(b.warehouse_id ?? ""),
  );

  // Қолжетімді размерлер (qty - reserved).
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

  // Баға: қолжетімді партияны артық көреміз, әйтпесе кез келгенін.
  const priceBatch =
    batches.find((b) =>
      Object.keys(b.sizes_quantity ?? {}).some((s) => availableForSize(b, s) > 0)
    ) ??
    batches[0] ??
    null;
  const basePrice = priceBatch ? Number(priceBatch.selling_price) || 0 : 0;
  const price = priceBatch ? effectivePrice(priceBatch) : 0;
  const hasDiscount = price < basePrice;
  const discountPct = hasDiscount
    ? Math.round((1 - price / basePrice) * 100)
    : 0;

  const images: string[] = Array.isArray(product.images)
    ? product.images.map(safeImg).filter(Boolean)
    : [];
  const heroImg = images[0] ?? "";

  // ── Open Graph превью (WhatsApp/Telegram карточкасы) ──────────────────────
  const priceLabel = price > 0 ? money(price) : "";
  const ogTitle = priceLabel
    ? `${product.name} — ${priceLabel}`
    : String(product.name ?? "Qoima");
  const ogDescParts = [product.brand, product.type, storeName].filter(
    (x) => x && String(x).trim(),
  );
  const ogDesc = ogDescParts.join(" · ");
  const pageUrl = `${url.origin}${url.pathname}?id=${id}`;

  // ── Сипаттамалар кестесі ──────────────────────────────────────────────────
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
              }" onclick="setHero('${esc(im)}',this)" />`,
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
          <span class="price${hasDiscount ? " sale" : ""}">${esc(
          money(price),
        )}</span>
          ${
            hasDiscount
              ? `<span class="old">${esc(money(basePrice))}</span>
                 <span class="badge">−${discountPct}%</span>`
              : ""
          }
        </div>`
      : "";

  const html = `<!doctype html><html xmlns="http://www.w3.org/1999/xhtml" lang="ru"><head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover" />
<title>${esc(product.name)} · Qoima</title>
<meta name="description" content="${esc(ogDesc)}" />
<meta property="og:type" content="product" />
<meta property="og:site_name" content="Qoima" />
<meta property="og:title" content="${esc(ogTitle)}" />
<meta property="og:description" content="${esc(ogDesc)}" />
${heroImg ? `<meta property="og:image" content="${esc(heroImg)}" />` : ""}
<meta property="og:url" content="${esc(pageUrl)}" />
<meta name="twitter:card" content="summary_large_image" />
<meta name="twitter:title" content="${esc(ogTitle)}" />
<meta name="twitter:description" content="${esc(ogDesc)}" />
${heroImg ? `<meta name="twitter:image" content="${esc(heroImg)}" />` : ""}
<style>
  :root{color-scheme:light}
  *{box-sizing:border-box}
  body{margin:0;background:#F1F4F3;color:#0C120F;
    font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;
    -webkit-font-smoothing:antialiased}
  .wrap{max-width:480px;margin:0 auto;background:#fff;min-height:100vh}
  .hero{width:100%;aspect-ratio:1/1;background:#E4F7EE;display:block;object-fit:cover}
  .hero-ph{width:100%;aspect-ratio:1/1;background:linear-gradient(135deg,#E4F7EE,#C8EEDB);
    display:flex;align-items:center;justify-content:center;color:#8fb9a6;font-size:15px}
  .thumbs{display:flex;gap:8px;padding:12px 16px 0;overflow-x:auto}
  .thumb{width:56px;height:56px;border-radius:12px;object-fit:cover;flex:0 0 auto;
    border:2px solid transparent;cursor:pointer;opacity:.6;transition:.15s}
  .thumb.active{border-color:#00A862;opacity:1}
  .body{padding:18px 18px 40px}
  .brand{font-size:11px;font-weight:800;letter-spacing:1px;color:#00A862;text-transform:uppercase}
  h1{font-size:22px;font-weight:800;letter-spacing:-.4px;margin:4px 0 2px;line-height:1.2}
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
  .foot{text-align:center;color:#B4BEB9;font-size:12px;padding:26px 0 6px}
  .foot b{color:#00A862;font-weight:800}
</style></head><body>
<div class="wrap">
  ${
    heroImg
      ? `<img class="hero" id="hero" src="${esc(heroImg)}" alt="${esc(
          product.name,
        )}" />`
      : `<div class="hero-ph">Нет фото</div>`
  }
  ${thumbsHtml}
  <div class="body">
    ${product.brand ? `<div class="brand">${esc(product.brand)}</div>` : ""}
    <h1>${esc(product.name)}</h1>
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
    <div class="foot">Витрина <b>Qoima</b></div>
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

  return new Response(html, {
    status: 200,
    headers: {
      // Supabase ортақ доменінде text/html → text/plain-ге мәжбүрленеді
      // (HTML рендерлеуге тыйым). application/xhtml+xml сол шектеуден өтеді
      // әрі браузер оны бет ретінде рендерлейді.
      "content-type": "application/xhtml+xml; charset=utf-8",
      // Превью-роботтар мен браузер үшін жеңіл кэш (5 мин).
      "cache-control": "public, max-age=300",
    },
  });
});
