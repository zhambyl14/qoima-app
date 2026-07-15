-- ════════════════════════════════════════════════════════════════════════════
--  0015 · Отзывы (тек сатып алғандар) + контент шағымдары + дүкенді жасыру
-- ────────────────────────────────────────────────────────────────────────────
--  App Store / Play Market UGC талаптары (Guideline 1.2):
--   1) product_reviews — тауар пікірлері. Жазу тек РАСТАЛҒАН сатып алушыға
--      (completed тапсырыста осы тауар бар). Оқу — публичті.
--   2) content_reports — кез келген авторизацияланған қолданушы тауарға /
--      дүкенге / пікірге шағымдана алады. Қарайтын — superadmin.
--   3) hidden_stores — клиент дүкенді (сатушыны) өзі үшін жасырады (block).
--   4) products.rating_avg / rating_count — денормализацияланған рейтинг
--      (триггер жаңартады; N+1 сұраныссыз карточкада көрсетіледі).
-- ════════════════════════════════════════════════════════════════════════════

-- ── 1) product_reviews ────────────────────────────────────────────────────────
create table if not exists public.product_reviews (
  id          uuid primary key default gen_random_uuid(),
  product_id  uuid not null references public.products(id) on delete cascade,
  admin_uid   uuid not null,                       -- дүкен иесі (сүзу үшін)
  client_uid  uuid not null references auth.users(id) on delete cascade,
  client_name text not null default '',
  rating      integer not null check (rating between 1 and 5),
  comment     text not null default '',
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (product_id, client_uid)                  -- бір тауарға бір пікір
);
create index if not exists product_reviews_product_idx
  on public.product_reviews(product_id);
create index if not exists product_reviews_admin_idx
  on public.product_reviews(admin_uid);

-- ── 2) Расталған сатып алу тексерісі ─────────────────────────────────────────
-- Клиенттің АЯҚТАЛҒАН (completed) тапсырысында осы тауар бар ма?
-- items JSONB ішінде элементтер camelCase: [{"productId": "...", ...}].
create or replace function public.client_purchased_product(p_product uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.orders o
    where o.client_uid = auth.uid()
      and o.status = 'completed'
      and o.items @> jsonb_build_array(
            jsonb_build_object('productId', p_product::text))
  );
$$;
grant execute on function public.client_purchased_product(uuid) to authenticated;

-- ── 3) products: денормализацияланған рейтинг ────────────────────────────────
alter table public.products
  add column if not exists rating_avg   double precision not null default 0,
  add column if not exists rating_count integer          not null default 0;

-- Триггер SECURITY DEFINER: products_write RLS-ін айналып өтіп рейтингті
-- қайта есептейді (пікір жазған клиент products-қа тікелей жаза алмайды).
create or replace function public.refresh_product_rating()
returns trigger
language plpgsql security definer set search_path = public as $$
declare pid uuid;
begin
  pid := coalesce(new.product_id, old.product_id);
  update public.products p set
    rating_avg = coalesce(
      (select round(avg(r.rating)::numeric, 2)::double precision
         from public.product_reviews r where r.product_id = pid), 0),
    rating_count = coalesce(
      (select count(*) from public.product_reviews r
         where r.product_id = pid), 0)
  where p.id = pid;
  return null;
end;
$$;

drop trigger if exists product_reviews_rating on public.product_reviews;
create trigger product_reviews_rating
  after insert or update or delete on public.product_reviews
  for each row execute function public.refresh_product_rating();

-- ── 4) content_reports (шағымдар) ─────────────────────────────────────────────
create table if not exists public.content_reports (
  id              uuid primary key default gen_random_uuid(),
  reporter_uid    uuid not null references auth.users(id) on delete cascade,
  reporter_name   text default '',
  reporter_phone  text default '',
  target_type     text not null check (target_type in ('product','store','review')),
  target_id       text not null,
  target_name     text default '',                 -- тауар/дүкен атауы (снапшот)
  admin_uid       uuid,                            -- байланысты дүкен иесі
  store_name      text default '',
  reason          text not null default 'other',   -- канондық кілт (UI аударады)
  comment         text default '',
  status          text not null default 'new',     -- new|resolved|dismissed
  resolved_by     text default '',
  resolution_note text default '',
  resolved_at     timestamptz,
  created_at      timestamptz not null default now()
);
create index if not exists content_reports_status_idx
  on public.content_reports(status);
create index if not exists content_reports_created_idx
  on public.content_reports(created_at);

-- ── 5) hidden_stores (клиент дүкенді өзі үшін жасырады) ──────────────────────
create table if not exists public.hidden_stores (
  client_uid uuid not null references auth.users(id) on delete cascade,
  admin_uid  uuid not null,
  store_name text default '',
  created_at timestamptz not null default now(),
  primary key (client_uid, admin_uid)
);

-- ── 6) RLS ────────────────────────────────────────────────────────────────────
alter table public.product_reviews enable row level security;
alter table public.content_reports enable row level security;
alter table public.hidden_stores   enable row level security;

-- Пікірлер: оқу публичті (guest те көреді); жазу — тек сатып алған клиент;
-- өзгерту — өз пікірі; өшіру — өзі немесе superadmin (модерация).
drop policy if exists reviews_select on public.product_reviews;
create policy reviews_select on public.product_reviews for select using (true);

drop policy if exists reviews_insert on public.product_reviews;
create policy reviews_insert on public.product_reviews for insert with check (
  client_uid = auth.uid() and public.client_purchased_product(product_id)
);

drop policy if exists reviews_update on public.product_reviews;
create policy reviews_update on public.product_reviews for update
  using (client_uid = auth.uid())
  with check (client_uid = auth.uid());

drop policy if exists reviews_delete on public.product_reviews;
create policy reviews_delete on public.product_reviews for delete using (
  client_uid = auth.uid() or public.is_superadmin()
);

-- Шағымдар: жазу — кез келген авторизацияланған; оқу — өзінікі + superadmin;
-- өңдеу — тек superadmin.
drop policy if exists reports_insert on public.content_reports;
create policy reports_insert on public.content_reports for insert
  to authenticated with check (reporter_uid = auth.uid());

drop policy if exists reports_select on public.content_reports;
create policy reports_select on public.content_reports for select using (
  reporter_uid = auth.uid() or public.is_superadmin()
);

drop policy if exists reports_update on public.content_reports;
create policy reports_update on public.content_reports for update
  using (public.is_superadmin()) with check (public.is_superadmin());

-- Жасырылған дүкендер: клиент тек өзінікін көреді/басқарады.
drop policy if exists hidden_rw on public.hidden_stores;
create policy hidden_rw on public.hidden_stores for all
  using (client_uid = auth.uid()) with check (client_uid = auth.uid());

-- ── 7) Realtime ───────────────────────────────────────────────────────────────
-- Superadmin шағымдарды `.stream()` арқылы көреді → публикацияға қосамыз.
alter publication supabase_realtime add table public.content_reports;
