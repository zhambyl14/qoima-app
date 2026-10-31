-- 0083 · Тауар сипаттамасы екі тілде + көп маусым
--
-- Не өзгереді:
--  1) products.description_kk — қазақша сипаттама. Бұрынғы `description` өзгеріссіз
--     (орысша деп есептеледі). Қосымша ағымдағы тілге қарай біреуін көрсетеді,
--     сәйкесінше бос болса — екіншісіне қайтады (ProductModel.descriptionFor).
--  2) products.season енді үтірмен бөлінген тізім бола алады: 'Лето,Зима'
--     (канондық мәндер, бос орынсыз, kSeasons реті). Бір мәнді ескі жазбалар
--     ('Лето') өзгеріссіз жұмыс істейді — баған түрі text күйінде қалады.
--     Оны оқитын жалғыз SQL — search_catalog: сүзгі тізім қиылысуына ауысты,
--     ал іздеу мәтініне description_kk қосылды.
--
-- ⚠️ ҚОЛДАНУ ТӘРТІБІ: бұл миграция жаңа апп нұсқасынан БҰРЫН қолданылады.
--    Апп description_kk бағанына жазады (бос болса жібермейді, сондықтан
--    қазақша сипаттамасы жоқ тауарлар ескі БД-да да сақталады).
--
-- Тексерілген: products-тағы BEFORE триггерлер (set_product_articul,
-- clear_sold_out_on_stock, guard_products_non_returnable) жаңа бағанға тимейді.

-- ── 1. Қазақша сипаттама ────────────────────────────────────────────────────
alter table public.products
  add column if not exists description_kk text not null default '';

-- 2000 — AI сипаттама генераторының (ai-product-assist) бар шегі; қолмен жазылған
-- орысша description-да DB шегі жоқ, бірақ қазақшаға ақылға сыйымды шек қоямыз.
do $$
begin
  if not exists (
    select 1 from pg_constraint
     where conrelid = 'public.products'::regclass
       and conname = 'products_description_kk_len'
  ) then
    alter table public.products
      add constraint products_description_kk_len
      check (char_length(description_kk) <= 2000);
  end if;
end $$;

-- ── 2. search_catalog: көп маусым + description_kk ──────────────────────────
-- Қолтаңба 0068-мен бірдей (тірі БД-дағы дене репомен тексеріліп сәйкес болды),
-- тек екі шарт өзгерді. create or replace PUBLIC грантын қайта тудырады —
-- сондықтан revoke төменде қайта орындалады.
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
      -- 0083: season енді үтірмен бөлінген тізім ('Лето,Зима'). Тауардың кез келген
      -- маусымы сұралғанмен сәйкессе — өтеді; маусымы көрсетілмеген ('') тауар бұрынғыдай өтеді.
      and (x.season is null
           or coalesce(p.season, '') = ''
           or string_to_array(p.season, ',') && string_to_array(x.season, ','))
      and (x.q is null or not exists (
        select 1
        from regexp_split_to_table(x.q, '\s+') w(word)
        where length(w.word) > 0
          and position(w.word in lower(concat_ws(' ',
                p.name, p.brand, p.type, p.color, p.keywords,
                p.description, p.description_kk, p.material, p.variant_note))) = 0))
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
