-- ════════════════════════════════════════════════════════════════════════════
--  0068 · AI мүмкіндіктері: онлайн киіп көру, AI-стилист, AI-көмекші
-- ────────────────────────────────────────────────────────────────────────────
--  НЕГЕ:
--  1) Серверде каталог іздеуі ЖОҚ еді — бүкіл сүзгі Dart-та, N+1 жүктеуден
--     кейін жүреді. LLM құралы (ai-assistant / ai-stylist edge функциялары)
--     бір сұраумен тауар табуы керек → public.search_catalog(...).
--     SECURITY INVOKER: RLS (products_read / batches_read / stores_read)
--     ӨЗІ қорғайды; функция тек ОҒАН ҚОСЫМША витрина ережелерін қайталайды
--     (visible_warehouse_ids, storefront_hidden, «Продано», суретсіз, hidden_stores).
--     Баға Dart-тағы effectivePrice()-пен (batch_model.dart:42) ДӘЛ бірдей.
--  2) AI сұраулары ақылы (Anthropic / FASHN) → әр клиентке күндік лимит.
--     ai_usage кестесіне клиент ТІКЕЛЕЙ жаза алмайды (жазу саясаты жоқ),
--     санақ тек consume_ai_quota() арқылы, атомды upsert-пен өседі.
--
--  ҚАУІПСІЗДІК ЕСКЕРТУІ (тірі БД-дан расталды, 2026-10-25):
--  pg_default_acl жаңа функцияға anon-ға да АЙҚЫН `anon=X` береді. Сондықтан
--  `revoke … from public` жеткіліксіз — әр функцияда `from public, anon`.
--
--  Қалалар stores.city-де ҚАЗАҚША канондық атаумен сақталады (kz_cities.dart:
--  'Алматы','Астана','Шымкент','Қарағанды','Ақтөбе','Өскемен','Қостанай',…).
--  search_catalog салыстыруды lower(btrim()) арқылы жасайды.
-- ════════════════════════════════════════════════════════════════════════════


-- ── 0. Жеңілдік мерзімін қауіпсіз оқу ───────────────────────────────────────
--  Dart starts_at/ends_at-ты toIso8601String() арқылы жазады: жергілікті уақыт
--  болса ЗОНАСЫЗ ('2026-10-26T12:00:00.000'). ::timestamptz оны UTC деп санар еді
--  (Қазақстанда +5 сағат ығысу), ал Dart DateTime.parse оны ЖЕРГІЛІКТІ деп оқиды.
--  Сондықтан зонасыз жолды Asia/Almaty деп түсінеміз; жарамсыз жол search_catalog-ты
--  құлатпауы үшін null қайтарамыз (мерзім жоқ = шектеусіз, Dart-пен бірдей).
create or replace function public._discount_ts(p_text text)
returns timestamptz
language plpgsql
immutable
security invoker
set search_path = public
as $function$
begin
  if p_text is null or btrim(p_text) = '' then
    return null;
  end if;
  if p_text ~ '(Z|[+-][0-9]{2}(:?[0-9]{2})?)$' then
    return p_text::timestamptz;
  end if;
  return (p_text::timestamp) at time zone 'Asia/Almaty';
exception when others then
  return null;
end;
$function$;

revoke execute on function public._discount_ts(text) from public, anon;
grant execute on function public._discount_ts(text) to authenticated;


-- ── 1. Каталог іздеуі ───────────────────────────────────────────────────────
--  Қайтарады: әр тауар үшін БІР жол.
--    price / base_price / batch_id / warehouse_id — ең арзан қолжетімді партия;
--    available_sizes — {өлшем: дана} (сол өлшемнің ең арзан партиясы бойынша);
--    size_batches   — {өлшем: {batch_id, warehouse_id, price, base_price}} —
--                     клиент себет жолын ДӘЛ сол өлшемнің партиясымен құрады
--                     (client_product_detail._batchForSize-пен бір логика).
--  p_season берілсе — сол маусым НЕМЕСЕ маусымы көрсетілмеген ('') тауар.
--  p_audience: 'Детские' → category LIKE 'Детские%' (ескі «Детские (мальчики)»);
--              басқасы → сол топ НЕМЕСЕ 'Унисекс'.
--  p_query: сөздерге бөлінеді, ӘР сөз name/brand/type/color/keywords/
--           description/material/variant_note ішінде болуы керек (position()
--           — ilike-тағы % / _ арнайы таңбалары әсер етпейді). quick_code
--           ӘДЕЙІ кірмейді (дүкен ішкі коды, клиентке көрінбеуі тиіс).
drop function if exists public.search_catalog(text, text[], text, text[], text, numeric, numeric, text, uuid, text, integer);

create or replace function public.search_catalog(
  p_city text default null,
  p_category_keys text[] default null,
  p_audience text default null,
  p_types text[] default null,
  p_size text default null,
  p_min_price numeric default null,
  p_max_price numeric default null,
  p_query text default null,
  p_exclude_product uuid default null,
  p_season text default null,
  p_limit integer default 20
)
returns table (
  product_id uuid,
  admin_uid uuid,
  store_name text,
  city text,
  name text,
  brand text,
  type text,
  category_key text,
  audience text,
  color text,
  season text,
  material text,
  variant_note text,
  articul text,
  description text,
  image_url text,
  images text[],
  price numeric,
  base_price numeric,
  batch_id uuid,
  warehouse_id uuid,
  available_sizes jsonb,
  size_batches jsonb,
  rating_avg double precision,
  rating_count integer
)
language sql
stable
security invoker
set search_path = public
as $function$
  with params as (
    select
      nullif(lower(btrim(coalesce(p_city, ''))), '') as city,
      nullif(btrim(coalesce(p_audience, '')), '') as audience,
      nullif(btrim(coalesce(p_season, '')), '') as season,
      nullif(btrim(coalesce(p_size, '')), '') as size,
      nullif(lower(btrim(left(coalesce(p_query, ''), 200))), '') as q,
      case when cardinality(p_category_keys) > 0 then p_category_keys end as cat_keys,
      case when cardinality(p_types) > 0 then p_types end as types,
      least(greatest(coalesce(p_limit, 20), 1), 50) as lim
  ),
  -- Витринада көрінетін партиялар + тиімді баға (effectivePrice көшірмесі).
  vb as (
    select
      p.id as product_id,
      b.id as batch_id,
      b.warehouse_id,
      b.sizes_quantity,
      b.reserved_sizes,
      b.selling_price::numeric as base_price,
      (case
         when coalesce((b.discount ->> 'active')::boolean, false)
          and (public._discount_ts(b.discount ->> 'starts_at') is null
               or public._discount_ts(b.discount ->> 'starts_at') <= now())
          and (public._discount_ts(b.discount ->> 'ends_at') is null
               or public._discount_ts(b.discount ->> 'ends_at') >= now())
         then greatest(0::numeric, round(
                case when coalesce(b.discount ->> 'type', 'percent') = 'percent'
                     then b.selling_price::numeric
                          * (1 - coalesce((b.discount ->> 'value')::numeric, 0) / 100)
                     else b.selling_price::numeric
                          - coalesce((b.discount ->> 'value')::numeric, 0)
                end))
         else b.selling_price::numeric
       end) as eff
    from public.products p
    join public.stores s on s.admin_uid = p.owner_uid
    join public.batches b on b.product_id = p.id and b.owner_uid = p.owner_uid
    cross join params x
    where s.is_published = true
      and coalesce(s.status, '') <> 'blocked'
      and b.warehouse_id::text = any (coalesce(s.visible_warehouse_ids, '{}'::text[]))
      and (x.city is null or lower(btrim(coalesce(s.city, ''))) = x.city)
      and not exists (
        select 1 from public.hidden_stores h
        where h.client_uid = auth.uid() and h.admin_uid = s.admin_uid)
      and p.status = 'В наличии'
      and coalesce(p.storefront_hidden, false) = false
      and cardinality(p.images) > 0
      and (p_exclude_product is null or p.id <> p_exclude_product)
      and (x.cat_keys is null
           or coalesce(nullif(p.category_key, ''), 'shoes') = any (x.cat_keys))
      and (x.types is null or p.type = any (x.types))
      and (x.audience is null
           or (x.audience = 'Детские' and p.category like 'Детские%')
           or (x.audience <> 'Детские'
               and (p.category = x.audience or p.category = 'Унисекс')))
      and (x.season is null or coalesce(p.season, '') in (x.season, ''))
      and (x.q is null or not exists (
        select 1
        from regexp_split_to_table(x.q, '\s+') w(word)
        where length(w.word) > 0
          and position(w.word in lower(concat_ws(' ',
                p.name, p.brand, p.type, p.color, p.keywords,
                p.description, p.material, p.variant_note))) = 0))
  ),
  -- Өлшем бойынша қолжетімді қалдық (qty − reserved > 0), баға сүзгісімен.
  vs as (
    select vb.product_id, vb.batch_id, vb.warehouse_id, vb.base_price, vb.eff,
           e.key as size,
           (e.value)::int - coalesce((vb.reserved_sizes ->> e.key)::int, 0) as q
    from vb
    cross join lateral jsonb_each_text(coalesce(vb.sizes_quantity, '{}'::jsonb)) e
    where (p_min_price is null or vb.eff >= p_min_price)
      and (p_max_price is null or vb.eff <= p_max_price)
  ),
  -- Әр (тауар, өлшем) үшін ең арзан партия.
  per_size as (
    select distinct on (vs.product_id, vs.size)
           vs.product_id, vs.size, vs.batch_id, vs.warehouse_id,
           vs.eff, vs.base_price, vs.q
    from vs
    where vs.q > 0
    order by vs.product_id, vs.size, vs.eff, vs.batch_id
  ),
  agg as (
    select ps.product_id,
           jsonb_object_agg(ps.size, ps.q) as available_sizes,
           jsonb_object_agg(ps.size, jsonb_build_object(
             'batch_id', ps.batch_id,
             'warehouse_id', ps.warehouse_id,
             'price', ps.eff,
             'base_price', ps.base_price)) as size_batches
    from per_size ps
    group by ps.product_id
  ),
  main_batch as (
    select distinct on (ps.product_id)
           ps.product_id, ps.batch_id, ps.warehouse_id, ps.eff, ps.base_price
    from per_size ps
    cross join params x
    where x.size is null or ps.size = x.size
    order by ps.product_id, ps.eff, ps.batch_id
  ),
  hits as (
    select p.id as product_id, p.owner_uid as admin_uid,
           s.store_name, s.city, p.name, p.brand, p.type,
           coalesce(nullif(p.category_key, ''), 'shoes') as category_key,
           p.category as audience, p.color, p.season, p.material,
           p.variant_note, p.articul, left(coalesce(p.description, ''), 400) as description,
           p.images[1] as image_url, p.images,
           mb.eff as price, mb.base_price, mb.batch_id, mb.warehouse_id,
           a.available_sizes, a.size_batches,
           coalesce(p.rating_avg, 0)::double precision as rating_avg,
           coalesce(p.rating_count, 0)::integer as rating_count
    from main_batch mb
    join agg a on a.product_id = mb.product_id
    join public.products p on p.id = mb.product_id
    join public.stores s on s.admin_uid = p.owner_uid
  )
  select h.*
  from hits h
  order by h.rating_avg desc, h.rating_count desc, h.price asc, h.product_id
  limit (select lim from params);
$function$;

revoke execute on function public.search_catalog(text, text[], text, text[], text, numeric, numeric, text, uuid, text, integer) from public, anon;
-- AI мүмкіндіктері тек кірген қолданушыға — anon-ға ӘДЕЙІ берілмейді.
grant execute on function public.search_catalog(text, text[], text, text[], text, numeric, numeric, text, uuid, text, integer) to authenticated;


-- ── 2. Күндік AI лимиті ─────────────────────────────────────────────────────
create table if not exists public.ai_usage (
  client_uid uuid not null references auth.users(id) on delete cascade,
  kind text not null check (kind in ('tryon', 'stylist', 'assistant')),
  day date not null,
  count integer not null default 0,
  primary key (client_uid, kind, day)
);

alter table public.ai_usage enable row level security;

-- Тек өз санағын оқиды. Жазу саясаты ӘДЕЙІ жоқ — санақ тек
-- consume_ai_quota() (SECURITY DEFINER) арқылы өзгереді.
drop policy if exists ai_usage_select_own on public.ai_usage;
create policy ai_usage_select_own on public.ai_usage
  for select to authenticated
  using (client_uid = auth.uid());

revoke insert, update, delete, truncate on public.ai_usage from anon, authenticated;
revoke all on public.ai_usage from anon;

insert into public.app_settings (key, value) values
  ('ai_tryon_daily_limit', '3'),
  ('ai_stylist_daily_limit', '10'),
  ('ai_assistant_daily_limit', '40')
on conflict (key) do nothing;


-- Санақты атомды арттырады; лимиттен асса 'ai_quota_exceeded'.
-- Қайтарады: бүгінге қалған сұрау саны.
create or replace function public.consume_ai_quota(p_kind text)
returns integer
language plpgsql
volatile
security definer
set search_path = public
as $function$
declare
  v_uid uuid := auth.uid();
  v_day date := (now() at time zone 'Asia/Almaty')::date;
  v_raw text;
  v_limit integer;
  v_count integer;
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;
  if p_kind is null or p_kind not in ('tryon', 'stylist', 'assistant') then
    raise exception 'invalid_kind';
  end if;

  -- Суперадмин жалауы (0067b): өшік функцияда квота да тұтынылмайды.
  if not public.feature_enabled('ai_' || p_kind) then
    raise exception 'feature_disabled';
  end if;

  select value into v_raw from public.app_settings
   where key = 'ai_' || p_kind || '_daily_limit';
  v_limit := case
    when btrim(coalesce(v_raw, '')) ~ '^\d{1,6}$' then btrim(v_raw)::integer
    when p_kind = 'tryon' then 3
    when p_kind = 'stylist' then 10
    else 40
  end;
  if v_limit <= 0 then
    raise exception 'ai_quota_exceeded';
  end if;

  -- ON CONFLICT … WHERE жолды құлыптап тексереді — қатар сұраулар лимиттен
  -- аса алмайды (оқы-сосын-жаз жоқ).
  insert into public.ai_usage as u (client_uid, kind, day, count)
  values (v_uid, p_kind, v_day, 1)
  on conflict (client_uid, kind, day)
  do update set count = u.count + 1
   where u.count < v_limit
  returning u.count into v_count;

  if v_count is null then
    raise exception 'ai_quota_exceeded';
  end if;
  return greatest(v_limit - v_count, 0);
end;
$function$;

revoke execute on function public.consume_ai_quota(text) from public, anon;
grant execute on function public.consume_ai_quota(text) to authenticated;


-- Қалған сұрау саны (тек оқу, өз санағы). INVOKER: ai_usage RLS + app_settings
-- (authenticated оқи алады) жеткілікті.
create or replace function public.ai_quota_remaining(p_kind text)
returns integer
language plpgsql
stable
security invoker
set search_path = public
as $function$
declare
  v_uid uuid := auth.uid();
  v_raw text;
  v_limit integer;
  v_count integer;
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;
  if p_kind is null or p_kind not in ('tryon', 'stylist', 'assistant') then
    raise exception 'invalid_kind';
  end if;
  select value into v_raw from public.app_settings
   where key = 'ai_' || p_kind || '_daily_limit';
  v_limit := case
    when btrim(coalesce(v_raw, '')) ~ '^\d{1,6}$' then btrim(v_raw)::integer
    when p_kind = 'tryon' then 3
    when p_kind = 'stylist' then 10
    else 40
  end;
  select count into v_count from public.ai_usage
   where client_uid = v_uid and kind = p_kind
     and day = (now() at time zone 'Asia/Almaty')::date;
  return greatest(v_limit - coalesce(v_count, 0), 0);
end;
$function$;

revoke execute on function public.ai_quota_remaining(text) from public, anon;
grant execute on function public.ai_quota_remaining(text) to authenticated;


-- Провайдер (FASHN / Anthropic) сәтсіз болса — квотаны қайтару.
-- ТЕК edge функция (service_role) шақырады: клиентке ашық болса, санағышты
-- қайта-қайта азайтып, шексіз AI алуға болар еді.
create or replace function public.refund_ai_quota(p_client uuid, p_kind text)
returns void
language plpgsql
volatile
security definer
set search_path = public
as $function$
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'not_authorized';
  end if;
  update public.ai_usage
     set count = greatest(count - 1, 0)
   where client_uid = p_client
     and kind = p_kind
     and day = (now() at time zone 'Asia/Almaty')::date;
end;
$function$;

revoke execute on function public.refund_ai_quota(uuid, text) from public, anon, authenticated;
grant execute on function public.refund_ai_quota(uuid, text) to service_role;

-- Тексеру (қолданғаннан кейін):
--   select proname, proacl from pg_proc
--    where proname in ('search_catalog','consume_ai_quota',
--                      'ai_quota_remaining','refund_ai_quota');
--   → ешқайсысында `=X/` те, `anon=X/` те болмауы тиіс.
--   select count(*) from information_schema.tables where table_name='ai_usage';
