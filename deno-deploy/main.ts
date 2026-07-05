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

Deno.serve(async (req) => {
  const url = new URL(req.url);
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
