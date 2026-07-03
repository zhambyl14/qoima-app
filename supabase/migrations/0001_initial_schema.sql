-- ════════════════════════════════════════════════════════════════════════════
--  Qoima · Supabase бастапқы схемасы (Firestore → Postgres)
-- ────────────────────────────────────────────────────────────────────────────
--  Таза бастау (деректер көшірілмейді). Firestore иерархиясы
--  `users/{adminUid}/...` Postgres-те `owner_uid`/`admin_uid` сыртқы кілттеріне
--  айналады. Кірістірілген map/array өрістер JSONB / text[] болады.
--
--  ⚠️ RLS саясаттары негізгі қолжетімділік үлгілерін қамтиды. Өндіріске
--     шығармас бұрын әр саясатты қайта қарап шығыңыз.
-- ════════════════════════════════════════════════════════════════════════════

-- ════════════════════════════════════════════════════════════════════════════
--  КЕСТЕЛЕР
-- ════════════════════════════════════════════════════════════════════════════

-- ── users: admin / seller / superadmin профильдері ───────────────────────────
create table public.users (
  id                    uuid primary key references auth.users(id) on delete cascade,
  name                  text not null default '',
  email                 text not null default '',
  role                  text not null default 'admin',      -- admin|seller|superadmin
  owner_id              uuid references auth.users(id),      -- seller → admin id; admin → өз id
  active                boolean not null default true,
  business_code         text default '',
  assigned_warehouse_id uuid,
  join_status           text not null default 'none',        -- none|pending|active
  terms_accepted        boolean not null default false,
  terms_accepted_at     timestamptz,
  shop_request_id       text default '',
  shop_status           text not null default 'approved',    -- approved|none|pending|rejected
  created_at            timestamptz not null default now()
);

-- ── clients: клиент профильдері (телефон + email + пароль) ────────────────────
create table public.clients (
  id             uuid primary key references auth.users(id) on delete cascade,
  phone          text not null unique,
  email          text not null default '',
  name           text not null default '',
  city           text default '',
  email_verified boolean not null default false,
  created_at     timestamptz not null default now()
);

-- ── business_codes: seller қосылу кодтары ────────────────────────────────────
create table public.business_codes (
  code       text primary key,
  admin_uid  uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

-- ── warehouses ───────────────────────────────────────────────────────────────
create table public.warehouses (
  id             uuid primary key default gen_random_uuid(),
  owner_uid      uuid not null references auth.users(id) on delete cascade,
  name           text not null default '',
  address        text,
  note           text,
  is_main        boolean not null default false,
  total_pairs    integer not null default 0,
  total_products integer not null default 0,
  created_at     timestamptz not null default now()
);
create index warehouses_owner_idx on public.warehouses(owner_uid);

-- ── stores: дүкен парақшасы (admin басына бір) ───────────────────────────────
create table public.stores (
  admin_uid               uuid primary key references auth.users(id) on delete cascade,
  store_name              text not null default '',
  store_slug              text default '',
  logo_url                text default '',
  city                    text default '',
  phone                   text default '',
  description             text default '',
  address                 text default '',
  visible_warehouse_ids   text[] not null default '{}',
  is_published            boolean not null default false,
  delivery_fee_city       double precision not null default 1500,
  delivery_free_threshold double precision not null default 0,
  payment_card_number     text default '',
  payment_card_holder     text default '',
  payment_bank            text default '',
  owner_name              text default '',
  owner_iin               text default '',
  category                text default '',
  status                  text not null default 'active',     -- active|blocked
  block_reason            text default '',
  blocked_at              timestamptz,
  blocked_by              text default '',
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now()
);
create index stores_published_idx on public.stores(is_published);

-- ── products (каталог) ───────────────────────────────────────────────────────
create table public.products (
  id           uuid primary key default gen_random_uuid(),
  owner_uid    uuid not null references auth.users(id) on delete cascade,
  name         text not null default '',
  brand        text default '',
  type         text default '',
  material     text default '',
  category     text default '',
  category_key text default '',                              -- shoes|tshirt|outer|...
  color        text default '',
  articul      text default '',
  status       text not null default 'В наличии',            -- В наличии|Продано
  images       text[] not null default '{}',
  created_at   timestamptz not null default now()
);
create index products_owner_idx on public.products(owner_uid);
create index products_category_idx on public.products(category_key);

-- ── batches (тауардың партиясы) — публичті (өзіндік құн БӨЛЕК сақталады) ──────
create table public.batches (
  id              uuid primary key default gen_random_uuid(),
  product_id      uuid not null references public.products(id) on delete cascade,
  owner_uid       uuid not null references auth.users(id) on delete cascade,
  warehouse_id    uuid,
  date_arrived    timestamptz not null default now(),
  selling_price   double precision not null default 0,
  sizes_quantity  jsonb not null default '{}',               -- {"42": 3, ...}
  reserved_sizes  jsonb not null default '{}',
  discount        jsonb,                                     -- {active,type,value,starts_at,ends_at}
  created_at      timestamptz not null default now()
);
create index batches_product_idx on public.batches(product_id);
create index batches_owner_idx on public.batches(owner_uid);

-- ── batch_costs: жасырын өзіндік құн (тек admin/seller оқиды) ─────────────────
create table public.batch_costs (
  batch_id       uuid primary key references public.batches(id) on delete cascade,
  owner_uid      uuid not null references auth.users(id) on delete cascade,
  product_id     uuid references public.products(id) on delete cascade,
  purchase_price double precision not null default 0
);

-- ── sales_history (сатылым журналы) ──────────────────────────────────────────
create table public.sales_history (
  id                     uuid primary key default gen_random_uuid(),
  owner_uid              uuid not null references auth.users(id) on delete cascade,
  product_id             uuid,
  batch_id               uuid,
  product_name           text default '',
  sale_date              timestamptz not null default now(),
  sizes_sold             jsonb not null default '{}',
  selected_size          text default '',
  quantity               integer not null default 0,
  base_price             double precision not null default 0,
  total_price            double precision not null default 0,
  discount_percent       double precision not null default 0,
  discount_amount        double precision not null default 0,
  purchase_price         double precision not null default 0,
  seller_id              text default '',
  seller_name            text default '',
  warehouse_id           uuid,
  is_online              boolean not null default false,
  order_id               text default '',
  delivered_by_name      text default '',
  payment_method         text default '',
  deposit_payment_method text default '',
  receipt_number         text default '',
  return_id              text default '',
  type                   text not null default 'sale'        -- sale|return
);
create index sales_owner_date_idx on public.sales_history(owner_uid, sale_date);

-- ── orders (онлайн тапсырыстар, top-level) ───────────────────────────────────
create table public.orders (
  id                     uuid primary key default gen_random_uuid(),
  admin_uid              uuid not null references auth.users(id) on delete cascade,
  client_uid             uuid references auth.users(id) on delete set null,
  client_phone           text default '',
  client_name            text default '',
  store_name             text default '',
  store_phone            text default '',
  warehouse_id           uuid,
  warehouse_address      text default '',
  items                  jsonb not null default '[]',
  status                 text not null default 'pending',
  order_type             text not null default 'click_collect',
  address                text default '',
  note                   text default '',
  deposit_amount         double precision not null default 0,
  delivery_fee           double precision not null default 0,
  pickup_code            text default '',
  order_number           integer not null default 0,
  seller_id              text default 'онлайн',
  seller_name            text default 'Онлайн',
  delivered_by_uid       text default '',
  delivered_by_name      text default '',
  receipt_number         text default '',
  receipt_url            text default '',
  receipt_submitted_at   timestamptz,
  payment_confirmed_by   text default '',
  payment_confirmed_at   timestamptz,
  rejection_reason       text default '',
  rejected_at            timestamptz,
  deadline_at            timestamptz,
  stock_restored         boolean not null default false,
  payment_card_number    text default '',
  payment_card_holder    text default '',
  payment_bank           text default '',
  in_store_payment_method text default '',
  promo_id               text default '',
  promo_code             text default '',
  promo_discount         double precision not null default 0,
  promo_counts_usage     boolean not null default false,
  created_at             timestamptz not null default now()
);
create index orders_admin_idx on public.orders(admin_uid);
create index orders_client_idx on public.orders(client_uid);

-- ── reservations (қойма бронь) ───────────────────────────────────────────────
create table public.reservations (
  id           uuid primary key default gen_random_uuid(),
  admin_uid    uuid not null references auth.users(id) on delete cascade,
  product_id   uuid,
  batch_id     uuid,
  size         text default '',
  quantity     integer not null default 0,
  reserved_by  uuid,
  client_phone text default '',
  warehouse_id uuid,
  order_type   text default '',
  status       text not null default 'active',               -- active|completed|expired
  expires_at   timestamptz not null default now(),
  created_at   timestamptz not null default now()
);
create index reservations_admin_idx on public.reservations(admin_uid);

-- ── promos + promo_redemptions ───────────────────────────────────────────────
create table public.promos (
  id             uuid primary key default gen_random_uuid(),
  admin_uid      uuid not null references auth.users(id) on delete cascade,
  code           text not null,
  type           text not null default 'percent',            -- percent|amount
  value          double precision not null default 0,
  scope          text not null default 'all',                -- all|products
  product_ids    text[] not null default '{}',
  max_uses       integer,
  used_count     integer not null default 0,
  per_user_limit integer default 1,
  min_order      double precision not null default 0,
  starts_at      timestamptz,
  ends_at        timestamptz,
  active         boolean not null default true,
  created_at     timestamptz not null default now(),
  unique (admin_uid, code)
);

create table public.promo_redemptions (
  promo_id    uuid not null references public.promos(id) on delete cascade,
  client_uid  uuid not null references auth.users(id) on delete cascade,
  count       integer not null default 1,
  updated_at  timestamptz not null default now(),
  primary key (promo_id, client_uid)
);

-- ── returns + returns_index ──────────────────────────────────────────────────
create table public.returns (
  id               text primary key,                          -- RET-YYYY-NNNN
  admin_uid        uuid not null references auth.users(id) on delete cascade,
  client_uid       uuid references auth.users(id) on delete set null,
  seller_id        text,
  warehouse_id     uuid,
  client_name      text default '',
  client_phone     text default '',
  order_id         text,
  sale_id          text,
  type             text not null default 'online',           -- online|offline
  items            jsonb not null default '[]',
  total_amount     double precision not null default 0,
  reason           text default 'other',
  reason_note      text,
  photo_urls       text[] not null default '{}',
  pickup           text default 'selfBring',
  refund_method    text default 'cash',
  status           text not null default 'requested',
  rejection_reason text,
  seller_note      text,
  item_condition_ok boolean,
  condition_photos text[] not null default '{}',
  created_at       timestamptz not null default now(),
  approved_at      timestamptz,
  received_at      timestamptz,
  refunded_at      timestamptz,
  rejected_at      timestamptz
);
create index returns_admin_idx on public.returns(admin_uid);
create index returns_client_idx on public.returns(client_uid);

-- клиенттің барлық дүкендердегі қайтаруларын тізу үшін жеңіл индекс
create table public.returns_index (
  return_id  text primary key references public.returns(id) on delete cascade,
  client_uid uuid not null references auth.users(id) on delete cascade,
  admin_uid  uuid not null references auth.users(id) on delete cascade,
  status     text not null default 'requested',
  created_at timestamptz not null default now()
);
create index returns_index_client_idx on public.returns_index(client_uid);

-- ── shop_requests (дүкен ашу заявкасы) ───────────────────────────────────────
create table public.shop_requests (
  id                uuid primary key default gen_random_uuid(),
  owner_uid         uuid not null references auth.users(id) on delete cascade,
  owner_name        text default '',
  owner_phone       text default '',
  owner_iin         text default '',
  shop_name         text default '',
  city              text default '',
  category          text default '',
  description       text default '',
  card_number       text default '',
  card_holder       text default '',
  card_bank         text default '',
  contract_accepted boolean not null default false,
  status            text not null default 'pending',          -- pending|approved|rejected
  reviewed_at       timestamptz,
  reviewed_by       text default '',
  review_note       text default '',
  created_at        timestamptz not null default now()
);
create index shop_requests_owner_idx on public.shop_requests(owner_uid);
create index shop_requests_status_idx on public.shop_requests(status);

-- ── store_edit_requests (дүкен деректерін өзгерту заявкасы) ───────────────────
create table public.store_edit_requests (
  id            uuid primary key default gen_random_uuid(),
  owner_uid     uuid not null references auth.users(id) on delete cascade,
  shop_name     text default '',
  changes       jsonb not null default '[]',                 -- [{field,label,oldValue,newValue}]
  owner_comment text default '',
  status        text not null default 'pending',             -- pending|approved|rejected|cancelled
  reviewed_at   timestamptz,
  reviewed_by   text default '',
  review_note   text default '',
  created_at    timestamptz not null default now()
);
create index store_edit_owner_idx on public.store_edit_requests(owner_uid);

-- ── banners (клиент басты беті, superadmin басқарады) ────────────────────────
create table public.banners (
  id             uuid primary key default gen_random_uuid(),
  title          text default '',
  subtitle       text default '',
  badge          text default '',
  gradient_start text default '#00713F',
  gradient_end   text default '#12C97A',
  "order"        integer not null default 0,
  active         boolean not null default true,
  starts_at      timestamptz,
  ends_at        timestamptz,
  created_at     timestamptz not null default now()
);

-- ── courier_deliveries ───────────────────────────────────────────────────────
create table public.courier_deliveries (
  id                  uuid primary key default gen_random_uuid(),
  order_id            text default '',
  order_number        integer not null default 0,
  amount              double precision not null default 0,
  address             text default '',
  client_name         text default '',
  client_phone        text default '',
  warehouse_addresses text[] not null default '{}',
  status              text not null default 'new',            -- new|assigned|picked|delivered|cancelled
  created_at          timestamptz not null default now()
);
create index courier_status_idx on public.courier_deliveries(status);

-- ── join_requests (seller → admin қосылу) ────────────────────────────────────
create table public.join_requests (
  id                    uuid primary key default gen_random_uuid(),
  admin_uid             uuid not null references auth.users(id) on delete cascade,
  seller_uid            uuid not null references auth.users(id) on delete cascade,
  seller_name           text default '',
  seller_email          text default '',
  assigned_warehouse_id uuid,
  status                text not null default 'pending',       -- pending|approved|rejected
  created_at            timestamptz not null default now()
);
create index join_requests_admin_idx on public.join_requests(admin_uid);
create index join_requests_seller_idx on public.join_requests(seller_uid);

-- ── transfers (қоймалар арасында тауар ауыстыру) ─────────────────────────────
create table public.transfers (
  id                uuid primary key default gen_random_uuid(),
  owner_uid         uuid not null references auth.users(id) on delete cascade,
  product_id        uuid,
  product_name      text default '',
  from_warehouse_id uuid,
  to_warehouse_id   uuid,
  sizes             jsonb not null default '{}',
  total_quantity    integer not null default 0,
  performed_by      uuid,
  created_at        timestamptz not null default now()
);
create index transfers_owner_idx on public.transfers(owner_uid);

-- ── store_discounts (дүкен жеңілдіктері) ─────────────────────────────────────
create table public.store_discounts (
  id                 uuid primary key default gen_random_uuid(),
  store_id           uuid not null references auth.users(id) on delete cascade,
  type               text not null default 'percent',         -- percent|fixed
  value              double precision not null default 0,
  scope              text not null default 'product',         -- product|category|store
  scope_id           text default '',
  scope_label        text default '',
  target_product_ids text[] not null default '{}',
  has_date_limit     boolean not null default false,
  starts_at          timestamptz,
  ends_at            timestamptz,
  is_active          boolean not null default true,
  created_at         timestamptz not null default now()
);
create index store_discounts_store_idx on public.store_discounts(store_id);

-- ── favorites (клиент таңдаулылары) ──────────────────────────────────────────
create table public.favorites (
  client_uid   uuid not null references auth.users(id) on delete cascade,
  product_id   uuid not null,
  product_name text default '',
  image_url    text default '',
  admin_uid    uuid,
  store_name   text default '',
  price        double precision default 0,
  created_at   timestamptz not null default now(),
  primary key (client_uid, product_id)
);

-- ── addresses (клиент мекенжайлары) ──────────────────────────────────────────
create table public.addresses (
  id         uuid primary key default gen_random_uuid(),
  client_uid uuid not null references auth.users(id) on delete cascade,
  label      text default '',
  address    text default '',
  city       text default '',
  is_default boolean not null default false,
  created_at timestamptz not null default now()
);
create index addresses_client_idx on public.addresses(client_uid);

-- ── counters (реттік нөмірлер: ЧЕК-NNNNN т.б.) ───────────────────────────────
create table public.counters (
  owner_uid uuid not null references auth.users(id) on delete cascade,
  name      text not null,
  value     bigint not null default 0,
  primary key (owner_uid, name)
);

-- ════════════════════════════════════════════════════════════════════════════
--  RPC (атомдық операциялар, anon кіру логикасы)
-- ════════════════════════════════════════════════════════════════════════════

-- Телефон → email (кіруден бұрын anon шақырады). phoneIndex орнына.
create or replace function public.client_email_for_phone(p_phone text)
returns text
language sql stable security definer set search_path = public as $$
  select email from public.clients where phone = p_phone limit 1;
$$;
grant execute on function public.client_email_for_phone(text) to anon, authenticated;

-- Реттік есептегішті атомдық арттырып, жаңа мәнді қайтарады (чек нөмірлері).
create or replace function public.next_counter(p_owner uuid, p_name text)
returns bigint
language plpgsql security definer set search_path = public as $$
declare v bigint;
begin
  insert into public.counters(owner_uid, name, value) values (p_owner, p_name, 1)
  on conflict (owner_uid, name) do update set value = public.counters.value + 1
  returning value into v;
  return v;
end;
$$;
grant execute on function public.next_counter(uuid, text) to authenticated;

-- ── Жаңа auth қолданушысы тіркелгенде профиль жасау (signUp метадеректерінен) ─
-- App signUp кезінде options.data арқылы береді: { role, name, phone, city }.
-- Профильді клиент емес, осы trigger (SECURITY DEFINER) жасайды (RLS айналып өтеді).
create or replace function public.handle_new_user()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_role text := coalesce(new.raw_user_meta_data->>'role', 'client');
  v_name text := coalesce(new.raw_user_meta_data->>'name', '');
  v_code text;
begin
  if v_role = 'client' then
    insert into public.clients (id, phone, email, name, city, email_verified)
    values (
      new.id,
      coalesce(new.raw_user_meta_data->>'phone', ''),
      coalesce(new.email, ''),
      v_name,
      coalesce(new.raw_user_meta_data->>'city', ''),
      true  -- верификация жоқ — бірден расталған
    );
  elsif v_role = 'admin' then
    -- 6-цифрлы бизнес коды (seller қосылу үшін), register() логикасындай.
    v_code := lpad((floor(random() * 1000000))::int::text, 6, '0');
    insert into public.users (id, name, email, role, owner_id, business_code, join_status)
    values (new.id, v_name, coalesce(new.email, ''), 'admin', new.id, v_code, 'active');
    insert into public.business_codes (code, admin_uid) values (v_code, new.id);
  elsif v_role = 'superadmin' then
    insert into public.users (id, name, email, role, owner_id, join_status)
    values (new.id, v_name, coalesce(new.email, ''), 'superadmin', new.id, 'active');
  else
    insert into public.users (id, name, email, role, owner_id, join_status)
    values (new.id, v_name, coalesce(new.email, ''), 'seller', null, 'none');
  end if;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ── Email-ді автоматты растау (верификация жоқ) ──────────────────────────────
-- Dashboard-та «Confirm email» ӨШІРУЛІ болуы керек; бұл триггер — қосымша
-- сақтандыру: кез келген жаңа auth қолданушысы бірден расталған болады.
create or replace function public.auto_confirm_email()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.email_confirmed_at := coalesce(new.email_confirmed_at, now());
  return new;
end;
$$;

drop trigger if exists on_auth_user_autoconfirm on auth.users;
create trigger on_auth_user_autoconfirm
  before insert on auth.users
  for each row execute function public.auto_confirm_email();

-- ════════════════════════════════════════════════════════════════════════════
--  Көмекші функциялар (RLS) — кестелерден КЕЙІН жасалады (forward-ref болмауы үшін)
-- ════════════════════════════════════════════════════════════════════════════

-- Ағымдағы пайдаланушының рөлі: 'admin' | 'seller' | 'superadmin' | 'client' | 'anon'
create or replace function public.app_role()
returns text
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select role from public.users   where id = auth.uid()),
    (select 'client' from public.clients where id = auth.uid()),
    'anon'
  );
$$;

-- Бизнес иесінің uid-і: admin → өз id; seller → бекітілген admin id.
create or replace function public.app_owner_uid()
returns uuid
language sql stable security definer set search_path = public as $$
  select coalesce(u.owner_id, u.id) from public.users u where u.id = auth.uid();
$$;

create or replace function public.is_superadmin()
returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.users where id = auth.uid() and role = 'superadmin');
$$;

-- ════════════════════════════════════════════════════════════════════════════
--  ROW LEVEL SECURITY
-- ════════════════════════════════════════════════════════════════════════════

alter table public.users               enable row level security;
alter table public.clients             enable row level security;
alter table public.business_codes      enable row level security;
alter table public.warehouses          enable row level security;
alter table public.stores              enable row level security;
alter table public.products            enable row level security;
alter table public.batches             enable row level security;
alter table public.batch_costs         enable row level security;
alter table public.sales_history       enable row level security;
alter table public.orders              enable row level security;
alter table public.reservations        enable row level security;
alter table public.promos              enable row level security;
alter table public.promo_redemptions   enable row level security;
alter table public.returns             enable row level security;
alter table public.returns_index       enable row level security;
alter table public.shop_requests       enable row level security;
alter table public.store_edit_requests enable row level security;
alter table public.banners             enable row level security;
alter table public.courier_deliveries  enable row level security;
alter table public.join_requests       enable row level security;
alter table public.transfers           enable row level security;
alter table public.store_discounts     enable row level security;
alter table public.favorites           enable row level security;
alter table public.addresses           enable row level security;
alter table public.counters            enable row level security;

-- ── users ────────────────────────────────────────────────────────────────────
create policy users_select on public.users for select using (
  id = auth.uid() or owner_id = auth.uid() or public.is_superadmin()
);
create policy users_insert on public.users for insert with check (id = auth.uid());
create policy users_update on public.users for update using (
  id = auth.uid() or public.is_superadmin()
) with check (id = auth.uid() or public.is_superadmin());

-- ── clients ──────────────────────────────────────────────────────────────────
create policy clients_select on public.clients for select using (
  id = auth.uid() or public.is_superadmin()
);
create policy clients_insert on public.clients for insert with check (id = auth.uid());
create policy clients_update on public.clients for update using (id = auth.uid())
  with check (id = auth.uid());

-- ── business_codes (авторизацияланған оқу: seller код тексереді) ──────────────
create policy bc_select on public.business_codes for select to authenticated using (true);
create policy bc_write on public.business_codes for all using (admin_uid = auth.uid())
  with check (admin_uid = auth.uid());

-- ── warehouses (каталог үшін публичті оқу; жазу — иесі) ───────────────────────
create policy wh_read on public.warehouses for select using (true);
create policy wh_write on public.warehouses for all
  using (owner_uid = public.app_owner_uid())
  with check (owner_uid = public.app_owner_uid());

-- ── stores (жарияланғандар публичті; жазу — иесі) ────────────────────────────
create policy stores_read on public.stores for select using (
  is_published = true or admin_uid = public.app_owner_uid() or public.is_superadmin()
);
create policy stores_write on public.stores for all
  using (admin_uid = public.app_owner_uid() or public.is_superadmin())
  with check (admin_uid = public.app_owner_uid() or public.is_superadmin());

-- ── products / batches (каталог публичті; жазу — бизнес) ─────────────────────
create policy products_read on public.products for select using (true);
create policy products_write on public.products for all
  using (owner_uid = public.app_owner_uid())
  with check (owner_uid = public.app_owner_uid());

create policy batches_read on public.batches for select using (true);
create policy batches_write on public.batches for all
  using (owner_uid = public.app_owner_uid())
  with check (owner_uid = public.app_owner_uid());

-- ── batch_costs (тек бизнес оқиды/жазады) ────────────────────────────────────
create policy costs_rw on public.batch_costs for all
  using (owner_uid = public.app_owner_uid())
  with check (owner_uid = public.app_owner_uid());

-- ── sales_history (тек бизнес) ───────────────────────────────────────────────
create policy sales_rw on public.sales_history for all
  using (owner_uid = public.app_owner_uid())
  with check (owner_uid = public.app_owner_uid());

-- ── orders ───────────────────────────────────────────────────────────────────
create policy orders_select on public.orders for select using (
  client_uid = auth.uid() or admin_uid = public.app_owner_uid() or public.is_superadmin()
);
create policy orders_insert on public.orders for insert with check (client_uid = auth.uid());
create policy orders_update on public.orders for update using (
  client_uid = auth.uid() or admin_uid = public.app_owner_uid()
) with check (
  client_uid = auth.uid() or admin_uid = public.app_owner_uid()
);
create policy orders_delete on public.orders for delete using (admin_uid = public.app_owner_uid());

-- ── reservations (бизнес + бронь жасаған клиент) ─────────────────────────────
create policy resv_select on public.reservations for select using (
  admin_uid = public.app_owner_uid() or reserved_by = auth.uid()
);
create policy resv_write on public.reservations for all
  using (admin_uid = public.app_owner_uid() or reserved_by = auth.uid())
  with check (admin_uid = public.app_owner_uid() or reserved_by = auth.uid());

-- ── promos (авторизацияланған оқу: клиент промокод тексереді; жазу — бизнес) ──
create policy promos_read on public.promos for select to authenticated using (true);
create policy promos_write on public.promos for all
  using (admin_uid = public.app_owner_uid())
  with check (admin_uid = public.app_owner_uid());

create policy promo_red_select on public.promo_redemptions for select using (
  client_uid = auth.uid()
  or exists (select 1 from public.promos p where p.id = promo_id and p.admin_uid = public.app_owner_uid())
);
create policy promo_red_write on public.promo_redemptions for all
  using (client_uid = auth.uid())
  with check (client_uid = auth.uid());

-- ── returns ──────────────────────────────────────────────────────────────────
create policy returns_select on public.returns for select using (
  client_uid = auth.uid() or admin_uid = public.app_owner_uid()
);
create policy returns_insert on public.returns for insert with check (
  client_uid = auth.uid() or admin_uid = public.app_owner_uid()
);
create policy returns_update on public.returns for update using (
  client_uid = auth.uid() or admin_uid = public.app_owner_uid()
) with check (
  client_uid = auth.uid() or admin_uid = public.app_owner_uid()
);

create policy returns_idx_select on public.returns_index for select using (
  client_uid = auth.uid() or admin_uid = public.app_owner_uid()
);
create policy returns_idx_write on public.returns_index for all
  using (client_uid = auth.uid() or admin_uid = public.app_owner_uid())
  with check (client_uid = auth.uid() or admin_uid = public.app_owner_uid());

-- ── shop_requests / store_edit_requests (иесі + superadmin) ──────────────────
create policy shopreq_select on public.shop_requests for select using (
  owner_uid = auth.uid() or public.is_superadmin()
);
create policy shopreq_insert on public.shop_requests for insert with check (owner_uid = auth.uid());
create policy shopreq_update on public.shop_requests for update using (
  owner_uid = auth.uid() or public.is_superadmin()
) with check (owner_uid = auth.uid() or public.is_superadmin());

create policy editreq_select on public.store_edit_requests for select using (
  owner_uid = auth.uid() or public.is_superadmin()
);
create policy editreq_insert on public.store_edit_requests for insert with check (owner_uid = auth.uid());
create policy editreq_update on public.store_edit_requests for update using (
  owner_uid = auth.uid() or public.is_superadmin()
) with check (owner_uid = auth.uid() or public.is_superadmin());

-- ── banners (публичті оқу; жазу — superadmin) ────────────────────────────────
create policy banners_read on public.banners for select using (true);
create policy banners_write on public.banners for all
  using (public.is_superadmin()) with check (public.is_superadmin());

-- ── courier_deliveries (курьер + бизнес) ─────────────────────────────────────
create policy courier_select on public.courier_deliveries for select to authenticated using (true);
create policy courier_write on public.courier_deliveries for all to authenticated
  using (true) with check (true);

-- ── join_requests (admin + seller) ───────────────────────────────────────────
create policy joinreq_select on public.join_requests for select using (
  admin_uid = auth.uid() or seller_uid = auth.uid()
);
create policy joinreq_insert on public.join_requests for insert with check (seller_uid = auth.uid());
create policy joinreq_update on public.join_requests for update using (
  admin_uid = auth.uid() or seller_uid = auth.uid()
) with check (admin_uid = auth.uid() or seller_uid = auth.uid());

-- ── transfers / store_discounts ──────────────────────────────────────────────
create policy transfers_rw on public.transfers for all
  using (owner_uid = public.app_owner_uid())
  with check (owner_uid = public.app_owner_uid());

create policy sd_read on public.store_discounts for select using (true);
create policy sd_write on public.store_discounts for all
  using (store_id = public.app_owner_uid())
  with check (store_id = public.app_owner_uid());

-- ── favorites / addresses (клиент өзінікі) ───────────────────────────────────
create policy fav_rw on public.favorites for all
  using (client_uid = auth.uid()) with check (client_uid = auth.uid());

create policy addr_rw on public.addresses for all
  using (client_uid = auth.uid()) with check (client_uid = auth.uid());

-- ── counters (тек RPC арқылы; тікелей оқу — иесі) ────────────────────────────
create policy counters_select on public.counters for select using (owner_uid = public.app_owner_uid());
