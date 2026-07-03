-- ════════════════════════════════════════════════════════════════════════════
--  0007 · Cloudinary суреттерін жинау (image garbage collection)
-- ────────────────────────────────────────────────────────────────────────────
--  ✅ 2026-07-02 базаға қолданылды (MCP: cloudinary_image_gc).
--
--  Сатылып біткен тауар 14 күн бойы жаңа поступление алмаса — фотосы Cloudinary-
--  ден өшіріледі (память орын алмасын). Нақты өшіруді Edge Function
--  `cloudinary-cleanup` жасайды (секрет серверде: CLOUDINARY_API_KEY/SECRET);
--  бұл жерде тек кезекке қоямыз да products.images-ті тазалаймыз.
--
--  ⚙️ ҚОЛМЕН БІР ҚАДАМ: Supabase Dashboard → Edge Functions → cloudinary-cleanup
--     → Secrets: CLOUDINARY_API_KEY, CLOUDINARY_API_SECRET қосу
--     (CLOUDINARY_CLOUD_NAME берілмесе 'divynstru' алынады).
-- ════════════════════════════════════════════════════════════════════════════

-- ── 1) Тауар қашан сатылып бітті (14 күн таймері осыдан басталады) ────────────
alter table public.products add column if not exists sold_out_at timestamptz;

-- ── 2) Cloudinary өшіру кезегі (тек service_role/Edge Function қолданады) ─────
create table if not exists public.cloudinary_delete_queue (
  id         bigint generated always as identity primary key,
  url        text not null,
  created_at timestamptz not null default now()
);
alter table public.cloudinary_delete_queue enable row level security;
-- Саясат жоқ → RLS барлық клиентті бұғаттайды; тек Edge Function (service_role).

-- ── 3) recompute_product_status: sold_out_at-ты қолдайды ─────────────────────
create or replace function public.recompute_product_status(p_product uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare v_in boolean;
begin
  select exists(
    select 1 from public.batches b, jsonb_each_text(b.sizes_quantity) s
    where b.product_id = p_product
      and (s.value)::int - coalesce((b.reserved_sizes->>s.key)::int, 0) > 0
  ) into v_in;
  update public.products
    set status = case when v_in then 'В наличии' else 'Продано' end,
        sold_out_at = case
          when v_in then null
          when sold_out_at is null then now()
          else sold_out_at
        end
    where id = p_product;
end;
$$;

-- ── 4) Поступление статусты in-stock етсе — таймерді тазалайтын триггер ───────
create or replace function public.clear_sold_out_on_stock()
returns trigger
language plpgsql set search_path = public as $$
begin
  if new.status = 'В наличии' and new.sold_out_at is not null then
    new.sold_out_at := null;
  end if;
  return new;
end;
$$;
drop trigger if exists trg_clear_sold_out on public.products;
create trigger trg_clear_sold_out
  before update of status on public.products
  for each row execute function public.clear_sold_out_on_stock();

-- ── 5) Sweep: 14+ күн сатулы тұрғандардың фотосын кезекке қойып тазалау ───────
--   ҚАУІПСІЗДІК КҮЗЕТІ: фото тек қоймада БІРДЕ-БІР нақты дана қалмағанда ғана
--   өшеді. Брондалып тұрған (бірақ физикалық бар) тауар «Продано» көрінсе де
--   фотосы САҚТАЛАДЫ — бронь босаса тауар қайта тірілуі мүмкін.
create or replace function public.sweep_sold_out_images(p_days int default 14)
returns int
language plpgsql security definer set search_path = public as $$
declare v_count int := 0;
begin
  insert into public.cloudinary_delete_queue(url)
  select unnest(p.images)
    from public.products p
   where p.status = 'Продано'
     and p.sold_out_at is not null
     and p.sold_out_at < now() - make_interval(days => p_days)
     and coalesce(array_length(p.images, 1), 0) > 0
     and not exists (
       select 1 from public.batches b, jsonb_each_text(b.sizes_quantity) s
       where b.product_id = p.id and (s.value)::int > 0
     );
  get diagnostics v_count = row_count;

  update public.products p
     set images = '{}'
   where p.status = 'Продано'
     and p.sold_out_at is not null
     and p.sold_out_at < now() - make_interval(days => p_days)
     and coalesce(array_length(p.images, 1), 0) > 0
     and not exists (
       select 1 from public.batches b, jsonb_each_text(b.sizes_quantity) s
       where b.product_id = p.id and (s.value)::int > 0
     );

  return v_count;
end;
$$;
revoke all on function public.sweep_sold_out_images(int) from public, authenticated;

-- Ескі деректер: қазір сатулы тұрғандарға таймер қоямыз.
update public.products
   set sold_out_at = coalesce(sold_out_at, now())
 where status = 'Продано';
