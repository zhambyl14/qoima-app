-- ════════════════════════════════════════════════════════════════════════════
--  0069 · «Той тілек тізімі» (gift registry)
-- ────────────────────────────────────────────────────────────────────────────
--  Сатып алушы туған күн / үйлену тойы / сүндет той / бесік той т.б. үшін
--  тауарлар тізімін жасап, сілтемесін бөліседі. Қонақ сілтемені ашады
--  (кірмей-ақ көреді), бір тауарды таңдайды — ол СОЛ қонаққа брондалады
--  (екі адам бір сыйлықты алып келмейді), сосын кәдімгі себет/checkout арқылы
--  сатып алады. Дүкен төлемді растағанда позиция автоматты «сатып алынды».
--
--  Қауіпсіздік шешімдері (CLAUDE.md / 0065 аудиті):
--   • Тізімді жария оқу — ТЕК get_registry_public(token) RPC арқылы,
--     `using (true)` саясаты ЖОҚ. Тізім иесінің тек есімі (бірінші сөзі)
--     қайтады, қонақтардың кім екені ЕШҚАШАН қайтпайды (тосын сый).
--   • gift_registry_claims кестесіне клиенттің insert/update/delete саясаты
--     ЖОҚ — брондау/босату тек SECURITY DEFINER RPC-лер арқылы, тауар жолы
--     `for update` құлпымен (қос брондау болмайды).
--   • «Сатып алынды» статусын клиент өзі қоя алмайды: orders.status-ты клиент
--     тікелей жаза алады (guard_orders_client_money статусты қорғамайды),
--     сондықтан триггер «purchased»-ты тек клиенттің ӨЗІ емес әрекетінде
--     (дүкен иесі / курьер / модератор / cron) қояды.
--   • Тапсырысқа claim тек өз claim-ы болса ғана және тауары сәйкес келсе
--     байланады (бөтен claim id-ін items-ке жазу ештеңе бермейді).
--   • Суперадмин жалаушасы (0067b `gift_registry`): тізім/позиция жасау және
--     брондау өшік болса 'feature_disabled' қатесін береді. Бұрын жасалған
--     тізімді көру/броннан бас тарту/төлем триггері өшік күйде де жұмыс істейді.
--   • Триггер ішіндегі кез келген қате тапсырыстың өзін ҚҰЛАТПАЙДЫ
--     (exception → warning): төлем растау тілек тізіміне тәуелді болмауы тиіс.
-- ════════════════════════════════════════════════════════════════════════════


-- ── 1. Кестелер ─────────────────────────────────────────────────────────────
create table if not exists public.gift_registries (
  id          uuid primary key default gen_random_uuid(),
  owner_uid   uuid not null references auth.users(id) on delete cascade,
  title       text not null check (char_length(btrim(title)) between 1 and 80),
  occasion    text not null check (occasion in
                ('birthday','wedding','toi','sundet','besik','baby','other')),
  event_date  date,
  message     text check (message is null or char_length(message) <= 500),
  city        text check (city is null or char_length(city) <= 80),
  share_token uuid not null unique default gen_random_uuid(),
  is_active   boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index if not exists gift_registries_owner_idx
  on public.gift_registries (owner_uid, created_at desc);

create table if not exists public.gift_registry_items (
  id           uuid primary key default gen_random_uuid(),
  registry_id  uuid not null references public.gift_registries(id) on delete cascade,
  -- Тауар өшірілсе — позиция да кетеді (өлі карточка қалмайды).
  product_id   uuid not null references public.products(id) on delete cascade,
  admin_uid    uuid not null,
  product_name text not null default '',
  image_url    text not null default '',
  size         text not null default '',
  -- Тек көрсетілім снапшоты. Нақты баға checkout-та партиядан алынады.
  price        numeric not null default 0,
  qty_wanted   integer not null default 1 check (qty_wanted between 1 and 20),
  note         text check (note is null or char_length(note) <= 200),
  created_at   timestamptz not null default now()
);
create index if not exists gift_registry_items_registry_idx
  on public.gift_registry_items (registry_id);
-- Бір тізімде бір тауар+өлшем бір-ақ рет (қайталап қосса — саны көбейеді).
create unique index if not exists gift_registry_items_uniq
  on public.gift_registry_items (registry_id, product_id, size);

create table if not exists public.gift_registry_claims (
  id             uuid primary key default gen_random_uuid(),
  item_id        uuid not null references public.gift_registry_items(id) on delete cascade,
  registry_id    uuid not null references public.gift_registries(id) on delete cascade,
  guest_uid      uuid not null references auth.users(id) on delete cascade,
  qty            integer not null default 1 check (qty between 1 and 20),
  status         text not null default 'reserved'
                   check (status in ('reserved','purchased','released')),
  order_id       uuid references public.orders(id) on delete set null,
  reserved_until timestamptz,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create index if not exists gift_registry_claims_item_idx
  on public.gift_registry_claims (item_id, status);
create index if not exists gift_registry_claims_guest_idx
  on public.gift_registry_claims (guest_uid, status);
create index if not exists gift_registry_claims_order_idx
  on public.gift_registry_claims (order_id) where order_id is not null;
-- Бір қонақтың бір позицияда тапсырысқа әлі байланбаған БІР ғана броны.
create unique index if not exists gift_registry_claims_one_open
  on public.gift_registry_claims (item_id, guest_uid)
  where status = 'reserved' and order_id is null;


-- ── 2. RLS ──────────────────────────────────────────────────────────────────
alter table public.gift_registries      enable row level security;
alter table public.gift_registry_items  enable row level security;
alter table public.gift_registry_claims enable row level security;

-- Тізімдер: иесі өз жолдарын толық басқарады. Жария оқу саясаты ЖОҚ.
drop policy if exists gift_registries_owner on public.gift_registries;
create policy gift_registries_owner on public.gift_registries
  for all to authenticated
  using (owner_uid = auth.uid())
  with check (owner_uid = auth.uid());

drop policy if exists gift_registries_admin_read on public.gift_registries;
create policy gift_registries_admin_read on public.gift_registries
  for select to authenticated
  using (public.is_superadmin());

-- Позициялар: тізім иесі арқылы. Қосу/өзгерту кезінде тауар қолданушыға
-- КӨРІНУІ тиіс (products_read RLS осы subquery-де де қолданылады) және
-- admin_uid шынымен сол тауардың иесі болуы тиіс.
drop policy if exists gift_registry_items_owner on public.gift_registry_items;
create policy gift_registry_items_owner on public.gift_registry_items
  for all to authenticated
  using (exists (
    select 1 from public.gift_registries r
    where r.id = registry_id and r.owner_uid = auth.uid()))
  with check (
    exists (
      select 1 from public.gift_registries r
      where r.id = registry_id and r.owner_uid = auth.uid())
    and exists (
      select 1 from public.products p
      where p.id = product_id and p.owner_uid = admin_uid));

-- Брондар: қонақ тек ӨЗ брондарын көреді. Жазу саясаты мүлдем жоқ — тек RPC.
drop policy if exists gift_registry_claims_guest_read on public.gift_registry_claims;
create policy gift_registry_claims_guest_read on public.gift_registry_claims
  for select to authenticated
  using (guest_uid = auth.uid());


-- ── 3. Күзет триггерлері (тізім — invoker; позиция күзеті — definer, төменде) ─
--  Тізім: owner_uid / share_token / created_at өзгермейді, updated_at жаңарады.
create or replace function public.guard_gift_registry_update()
returns trigger language plpgsql set search_path = public as $$
begin
  if new.owner_uid is distinct from old.owner_uid
     or new.share_token is distinct from old.share_token
     or new.created_at is distinct from old.created_at then
    raise exception 'registry_immutable';
  end if;
  new.updated_at := now();
  return new;
end;
$$;
drop trigger if exists trg_guard_gift_registry_update on public.gift_registries;
create trigger trg_guard_gift_registry_update
  before update on public.gift_registries
  for each row execute function public.guard_gift_registry_update();

--  Бір қолданушыда 20-дан көп тізім болмайды (спам/шексіз жол).
create or replace function public.guard_gift_registry_insert()
returns trigger language plpgsql set search_path = public as $$
begin
  -- Суперадмин өшірген функцияда жаңа тізім жасалмайды (0067b).
  if not public.feature_enabled('gift_registry') then
    raise exception 'feature_disabled';
  end if;
  if (select count(*) from public.gift_registries where owner_uid = new.owner_uid) >= 20 then
    raise exception 'registry_limit';
  end if;
  new.share_token := gen_random_uuid(); -- токенді клиент таңдамайды
  new.is_active := true;
  return new;
end;
$$;
drop trigger if exists trg_guard_gift_registry_insert on public.gift_registries;
create trigger trg_guard_gift_registry_insert
  before insert on public.gift_registries
  for each row execute function public.guard_gift_registry_insert();

--  Позиция: тізімде ≤100 позиция; тауар/тізім/дүкен/өлшем кейін ауыстырылмайды
--  (брондар сол тауар+өлшемге байланған); атауы, суреті және бағасы тауардың
--  өзінен алынады (иесінің еркін мәтіні/суреті жария бетке шықпайды).
--  SECURITY DEFINER: бағаны партиялардан RLS-ке тәуелсіз оқу үшін. Тауардың
--  көрінуі мен admin_uid сәйкестігі INSERT саясатының with check-інде тексеріледі.
create or replace function public.guard_gift_registry_item()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_name text;
  v_img  text;
begin
  if tg_op = 'UPDATE' then
    if new.registry_id is distinct from old.registry_id
       or new.product_id is distinct from old.product_id
       or new.admin_uid is distinct from old.admin_uid
       or new.size is distinct from old.size
       or new.created_at is distinct from old.created_at
       -- Атау/сурет/баға — жария бетке шығады: иесі еркін мәтін/сурет жаза алмасын.
       or new.product_name is distinct from old.product_name
       or new.image_url is distinct from old.image_url
       or new.price is distinct from old.price then
      raise exception 'registry_item_immutable';
    end if;
    return new;
  end if;

  if not public.feature_enabled('gift_registry') then
    raise exception 'feature_disabled';
  end if;

  -- Қатар қосылған екі позиция лимитті айналып өтпеуі үшін тізімді құлыптаймыз.
  perform 1 from public.gift_registries where id = new.registry_id for update;
  if (select count(*) from public.gift_registry_items
      where registry_id = new.registry_id) >= 100 then
    raise exception 'registry_items_limit';
  end if;

  select p.name, coalesce(p.images[1], '') into v_name, v_img
  from public.products p where p.id = new.product_id;
  if found then
    new.product_name := coalesce(v_name, '');
  end if;
  -- Сурет пен баға клиенттен ЕШҚАШАН алынбайды (снапшот тек көрсетілім үшін;
  -- нақты баға get_registry_public-те партиядан тірідей есептеледі).
  new.image_url := coalesce(v_img, '');
  new.price := coalesce((select min(b.selling_price)::numeric
                         from public.batches b
                         where b.product_id = new.product_id), 0);
  return new;
end;
$$;
drop trigger if exists trg_guard_gift_registry_item on public.gift_registry_items;
create trigger trg_guard_gift_registry_item
  before insert or update on public.gift_registry_items
  for each row execute function public.guard_gift_registry_item();

-- Триггер-функцияларды тікелей шақыруға болмайды (0065c үлгісі).
-- ЕСКЕРТУ: public схемасындағы әдепкі ACL (pg_default_acl) жаңа функцияға
-- anon/authenticated/service_role-ге тікелей EXECUTE береді, сондықтан
-- `from public` ЖЕТКІЛІКСІЗ — anon/authenticated-ты да нақты алу керек.
revoke execute on function public.guard_gift_registry_update() from public, anon, authenticated;
revoke execute on function public.guard_gift_registry_insert() from public, anon, authenticated;
revoke execute on function public.guard_gift_registry_item() from public, anon, authenticated;


-- ── 4. Ішкі көмекші: позиция бойынша «алынған» сан ─────────────────────────
--  Белсенді бронь = purchased, НЕМЕСЕ reserved және (тапсырысқа байланған
--  НЕМЕСЕ мерзімі өтпеген). Тапсырысқа байланған бронь төлем күтіп тұрғанда
--  мерзімі өтсе де ұсталып тұрады — оны тек sweep (тапсырыс өлсе) босатады.
create or replace function public.registry_item_taken_qty(p_item uuid, p_exclude uuid default null)
returns integer language sql stable security invoker set search_path = public as $$
  select coalesce(sum(c.qty), 0)::int
  from public.gift_registry_claims c
  where c.item_id = p_item
    and (p_exclude is null or c.id <> p_exclude)
    and (c.status = 'purchased'
         or (c.status = 'reserved'
             and (c.order_id is not null or c.reserved_until > now())));
$$;
-- security invoker: өзі ештеңе ашпайды — тек definer-RPC-лер ішінен
-- (postgres атынан) шақырылады; клиентке тікелей ашық емес.
revoke execute on function public.registry_item_taken_qty(uuid, uuid) from public, anon, authenticated;


-- ── 4b. Ішкі көмекші: тауардың ағымдағы жария бағасы ───────────────────────
--  Жария дүкеннің көрінетін қоймасындағы, қажет өлшемі қолжетімді партиялардың
--  ең арзан тиімді бағасы (effectivePrice көшірмесі). null = қазір сатылмайды.
--  get_registry_public (көрсету) және reserve_registry_item (қолжетімділік
--  тексерісі) бірге қолданады. Клиентке ашық емес.
create or replace function public.registry_item_live_price(p_product uuid, p_size text)
returns numeric language sql stable security invoker set search_path = public as $$
  select min(
      case when coalesce((b.discount->>'active')::boolean, false)
             and coalesce(nullif(b.discount->>'starts_at','')::timestamptz, '-infinity') <= now()
             and coalesce(nullif(b.discount->>'ends_at','')::timestamptz, 'infinity') >= now()
           then greatest(0, round(case b.discount->>'type'
                  when 'percent' then b.selling_price::numeric
                                      * (1 - coalesce((b.discount->>'value')::numeric, 0) / 100)
                  else b.selling_price::numeric - coalesce((b.discount->>'value')::numeric, 0) end))
           else b.selling_price::numeric end) as price
    from public.batches b
    join public.products p on p.id = b.product_id
    join public.stores s on s.admin_uid = b.owner_uid
    where b.product_id = p_product
      and p.status = 'В наличии' and not p.storefront_hidden
      and s.is_published and s.status <> 'blocked'
      and b.warehouse_id::text = any(s.visible_warehouse_ids)
      and exists (
        select 1 from jsonb_each_text(case when jsonb_typeof(b.sizes_quantity) = 'object'
                                           then b.sizes_quantity else '{}'::jsonb end) e(k, v)
        where (coalesce(p_size, '') = '' or e.k = p_size)
          and coalesce(nullif(e.v, '')::numeric, 0)
              - coalesce(nullif(b.reserved_sizes->>e.k, '')::numeric, 0) > 0);
$$;
revoke execute on function public.registry_item_live_price(uuid, text) from public, anon, authenticated;


-- ── 5. get_registry_public(token) ───────────────────────────────────────────
--  ӘДЕЙІ ЖАРИЯ (anon + authenticated): қонақ сілтемені кірмей-ақ ашады.
--  Авторизацияның орнына — болжап табу мүмкін емес uuid токен. Қайтатыны тек
--  көрсетілім өрістері; иесінің тек есімі (бірінші сөзі); қонақтардың
--  идентификаторы ЕШҚАШАН қайтпайды. Белсенді емес тізімді тек иесі көреді.
create or replace function public.get_registry_public(p_token uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_uid   uuid := auth.uid();
  v_reg   public.gift_registries;
  v_owner text;
  v_items jsonb;
  v_mine  jsonb;
begin
  if p_token is null then return null; end if;

  select * into v_reg from public.gift_registries where share_token = p_token;
  if not found then return null; end if;
  if not v_reg.is_active and v_reg.owner_uid is distinct from v_uid then
    return null;
  end if;

  select split_part(btrim(coalesce(
           nullif(btrim(c.name), ''),
           (select nullif(btrim(u.name), '') from public.users u where u.id = v_reg.owner_uid),
           '')), ' ', 1)
    into v_owner
  from (select 1) d
  left join public.clients c on c.id = v_reg.owner_uid;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', i.id,
           'product_id', i.product_id,
           'admin_uid', i.admin_uid,
           'product_name', i.product_name,
           -- Витринадан жасырылған / дүкені жабық тауардың суреті мен бағасы
           -- жария бетке шықпайды (тек атауы қалады).
           'image_url', case when vis.ok then i.image_url else '' end,
           'size', i.size,
           'price', case when vis.ok then coalesce(lp.price, i.price) else 0 end,
           'in_stock', lp.price is not null,
           'qty_wanted', i.qty_wanted,
           'qty_taken', t.taken,
           'qty_purchased', t.purchased,
           'remaining', greatest(i.qty_wanted - t.taken, 0),
           'note', coalesce(i.note, '')
         ) order by i.created_at), '[]'::jsonb)
    into v_items
  from public.gift_registry_items i
  cross join lateral (
    select public.registry_item_taken_qty(i.id) as taken,
           coalesce((select sum(c.qty) from public.gift_registry_claims c
                     where c.item_id = i.id and c.status = 'purchased'), 0)::int as purchased
  ) t
  -- Ағымдағы баға: registry_item_live_price (жоғарыдағы көмекші); жоқ болса —
  -- снапшот баға, in_stock=false.
  left join lateral (
    select public.registry_item_live_price(i.product_id, i.size) as price
  ) lp on true
  cross join lateral (
    select exists (
      select 1 from public.products p
      join public.stores s on s.admin_uid = p.owner_uid
      where p.id = i.product_id
        and not p.storefront_hidden
        and s.is_published and s.status <> 'blocked'
    ) as ok
  ) vis
  where i.registry_id = v_reg.id;

  if v_uid is not null then
    select coalesce(jsonb_agg(jsonb_build_object(
             'id', c.id,
             'item_id', c.item_id,
             'qty', c.qty,
             'status', c.status,
             'reserved_until', c.reserved_until,
             'in_order', c.order_id is not null
           ) order by c.created_at), '[]'::jsonb)
      into v_mine
    from public.gift_registry_claims c
    where c.registry_id = v_reg.id
      and c.guest_uid = v_uid
      and (c.status = 'purchased'
           or (c.status = 'reserved'
               and (c.order_id is not null or c.reserved_until > now())));
  end if;

  return jsonb_build_object(
    'id', v_reg.id,
    'title', v_reg.title,
    'occasion', v_reg.occasion,
    'event_date', v_reg.event_date,
    'message', coalesce(v_reg.message, ''),
    'owner_name', coalesce(v_owner, ''),
    'city', coalesce(v_reg.city, ''),
    'is_active', v_reg.is_active,
    'items', v_items,
    'is_owner', v_uid is not null and v_uid = v_reg.owner_uid,
    'my_claims', coalesce(v_mine, '[]'::jsonb)
  );
end;
$$;
revoke execute on function public.get_registry_public(uuid) from public;  -- anon қайта беріледі (төменде, әдейі)
-- anon — әдейі: қонақ тіркелмей тұрып сілтемені ашады (жоғарыдағы түсінікті қара).
grant execute on function public.get_registry_public(uuid) to anon, authenticated;


-- ── 6. get_my_registries_summary() — иесіне тек САНДАР ─────────────────────
--  Иесі claims кестесін оқи алмайды (тосын сый), сондықтан прогресс
--  (алынды/барлығы) осы RPC арқылы, қонақ идентификаторынсыз.
create or replace function public.get_my_registries_summary()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'registry_id', r.id,
             'items_count', coalesce(x.items_count, 0),
             'qty_total', coalesce(x.qty_total, 0),
             'qty_taken', coalesce(x.qty_taken, 0)))
    from public.gift_registries r
    left join lateral (
      select count(*)::int as items_count,
             sum(i.qty_wanted)::int as qty_total,
             sum(least(i.qty_wanted, public.registry_item_taken_qty(i.id)))::int as qty_taken
      from public.gift_registry_items i
      where i.registry_id = r.id
    ) x on true
    where r.owner_uid = v_uid
  ), '[]'::jsonb);
end;
$$;
revoke execute on function public.get_my_registries_summary() from public, anon;
grant execute on function public.get_my_registries_summary() to authenticated;


-- ── 7. reserve_registry_item(item, qty) → claim id ─────────────────────────
--  Позиция жолы `for update` құлпымен — қатар басқан екі қонақтың бірі ғана
--  үлгереді. Қонақтың тапсырысқа әлі байланбаған броны болса — сол түзетіледі.
create or replace function public.reserve_registry_item(p_item uuid, p_qty integer default 1)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_uid      uuid := auth.uid();
  v_item     public.gift_registry_items;
  v_reg      public.gift_registries;
  v_existing public.gift_registry_claims;
  v_taken    integer;
  v_open     integer;
  v_id       uuid;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;
  if not public.feature_enabled('gift_registry') then
    raise exception 'feature_disabled';
  end if;
  if p_qty is null or p_qty < 1 or p_qty > 20 then raise exception 'invalid_qty'; end if;

  select * into v_item from public.gift_registry_items where id = p_item for update;
  if not found then raise exception 'registry_item_not_found'; end if;

  select * into v_reg from public.gift_registries where id = v_item.registry_id;
  if not found or not v_reg.is_active then raise exception 'registry_inactive'; end if;
  if v_reg.owner_uid = v_uid then raise exception 'registry_own_item'; end if;

  select * into v_existing from public.gift_registry_claims
  where item_id = p_item and guest_uid = v_uid
    and status = 'reserved' and order_id is null
  for update;

  -- Сатылмайтын/жасырын/қоймада жоқ тауарды брондауға болмайды.
  if public.registry_item_live_price(v_item.product_id, v_item.size) is null then
    raise exception 'registry_item_unavailable';
  end if;

  v_taken := public.registry_item_taken_qty(p_item, v_existing.id);
  if v_taken + p_qty > v_item.qty_wanted then
    raise exception 'registry_item_taken';
  end if;

  if v_existing.id is not null then
    -- Мерзімді шексіз ұзартуға болмайды: ең көбі бастапқы брондан 7 күн.
    update public.gift_registry_claims
       set qty = p_qty,
           reserved_until = greatest(
             coalesce(reserved_until, now()),
             least(now() + interval '48 hours', created_at + interval '7 days')),
           updated_at = now()
     where id = v_existing.id;
    return v_existing.id;
  end if;

  -- Бір қонақ бүкіл платформада 30-дан көп белсенді бронь ұстай алмайды
  -- (біреу бәрін «брондап» тастап, тізімді бұғаттамауы үшін).
  select count(*) into v_open from public.gift_registry_claims
  where guest_uid = v_uid and status = 'reserved'
    and (order_id is not null or reserved_until > now());
  if v_open >= 30 then raise exception 'registry_claim_limit'; end if;

  insert into public.gift_registry_claims
    (item_id, registry_id, guest_uid, qty, status, reserved_until)
  values
    (p_item, v_item.registry_id, v_uid, p_qty, 'reserved', now() + interval '48 hours')
  returning id into v_id;
  return v_id;
end;
$$;
revoke execute on function public.reserve_registry_item(uuid, integer) from public, anon;
grant execute on function public.reserve_registry_item(uuid, integer) to authenticated;


-- ── 7b. registry_claims_still_valid(ids[]) ─────────────────────────────────
--  Себеттегі тілек-жол ескіріп қалуы мүмкін (бронь sweep-пен немесе «Бас
--  тарту» арқылы босаған). Себет/төлем алдында осыны шақырып, әлі жарамды
--  брондарды ғана аламыз. Тек шақырушының ӨЗ брондары қайтады.
create or replace function public.registry_claims_still_valid(p_ids uuid[])
returns uuid[] language plpgsql stable security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;
  return coalesce((
    select array_agg(c.id)
    from public.gift_registry_claims c
    where c.id = any(coalesce(p_ids, '{}'::uuid[]))
      and c.guest_uid = v_uid
      and (c.status = 'purchased'
           or (c.status = 'reserved'
               and (c.order_id is not null or c.reserved_until > now())))
  ), '{}'::uuid[]);
end;
$$;
revoke execute on function public.registry_claims_still_valid(uuid[]) from public, anon;
grant execute on function public.registry_claims_still_valid(uuid[]) to authenticated;


-- ── 8. release_registry_claim(claim) ───────────────────────────────────────
--  Тек сол бронның қонағы, тек 'reserved'. Тапсырысқа байланған болса —
--  тапсырыс бас тартылған/қайтарылған (немесе өшірілген) кезде ғана.
create or replace function public.release_registry_claim(p_claim uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_uid   uuid := auth.uid();
  v_claim public.gift_registry_claims;
  v_ostat text;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;

  select * into v_claim from public.gift_registry_claims where id = p_claim for update;
  if not found or v_claim.guest_uid <> v_uid then raise exception 'not_your_claim'; end if;
  if v_claim.status <> 'reserved' then raise exception 'registry_claim_not_active'; end if;

  if v_claim.order_id is not null then
    select status into v_ostat from public.orders where id = v_claim.order_id;
    if found and v_ostat not in ('cancelled', 'returned') then
      raise exception 'registry_claim_in_order';
    end if;
  end if;

  update public.gift_registry_claims
     set status = 'released', order_id = null, updated_at = now()
   where id = p_claim;
end;
$$;
revoke execute on function public.release_registry_claim(uuid) from public, anon;
grant execute on function public.release_registry_claim(uuid) to authenticated;


-- ── 9. orders триггері: бронь ↔ тапсырыс ───────────────────────────────────
--  items[i].registryClaimId (CartItemModel) бойынша:
--   • INSERT          → claim.order_id = тапсырыс (төлем күтілгенде мерзімі
--                        өтіп кетпейді), reserved_until ≥ now()+48h. Тек бронь
--                        әлі тірі (немесе орын бос) және жолдың саны/өлшемі
--                        броньға сәйкес болса; сан азайтылса — бронь соған дейін
--                        кемиді.
--   • confirmed/ready/completed (төлем расталды / берілді) → 'purchased'
--                        + тізім иесіне push. Тек осы тапсырысқа байланған
--                        бронь (немесе sweep босатқан, бірақ орын әлі бос бронь)
--                        'purchased' болады. Клиенттің ӨЗ әрекеті есепке
--                        алынбайды (ол статусты тікелей жаза алады).
--   • cancelled/returned → 'released' (позиция қайта бос).
--   • 'rejected' — чек қабылданбады, бірақ қайта жіберуге болады → ТИМЕЙМІЗ.
--   • 'reserved' (бронь депозиті расталды) — ұстап тұрамыз, өзгеріс жоқ.
create or replace function public.on_order_registry_claims()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  e        jsonb;
  v_cid    uuid;
  v_iid    uuid;
  v_claim  public.gift_registry_claims;
  v_item   public.gift_registry_items;
  v_owner  uuid;
  v_lqty   integer;
  v_fits   boolean;
  v_buy    boolean;
  v_newqty integer;
begin
  if new.items is null or jsonb_typeof(new.items) <> 'array' then return new; end if;
  if tg_op = 'UPDATE' and new.status is not distinct from old.status then return new; end if;
  if not exists (
    select 1 from jsonb_array_elements(new.items) x
    where coalesce(x->>'registryClaimId', '') <> ''
  ) then
    return new;
  end if;

  begin
    for e in select * from jsonb_array_elements(new.items) loop
      if coalesce(e->>'registryClaimId', '') !~*
         '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
        continue;
      end if;
      v_cid := (e->>'registryClaimId')::uuid;

      -- Құлып реті reserve_registry_item-мен бірдей: алдымен позиция, сосын
      -- бронь (қарсы тәртіп deadlock берер еді).
      select item_id into v_iid from public.gift_registry_claims
      where id = v_cid and guest_uid = new.client_uid;
      if not found then continue; end if;

      select * into v_item from public.gift_registry_items
      where id = v_iid for update;
      if not found or v_item.product_id::text is distinct from (e->>'productId') then
        continue;
      end if;

      select * into v_claim from public.gift_registry_claims
      where id = v_cid and guest_uid = new.client_uid
      for update;
      if not found then continue; end if;

      -- Тапсырыс жолының саны/өлшемі броньға сәйкес пе: сан азайтылған (себетте
      -- «минус») немесе өлшем басқа болса — толық «сыйлық» болып есептелмейді.
      v_lqty := case when coalesce(e->>'qty', '') ~ '^[0-9]{1,4}$'
                     then (e->>'qty')::int else 0 end;
      v_fits := v_lqty >= 1
                and (v_item.size = '' or coalesce(e->>'size', '') = v_item.size);

      if tg_op = 'INSERT' then
        -- Байлау: бронь әлі тірі және бос; ескірген себет жолы (мерзімі өтіп,
        -- sweep-ке дейін 'reserved' боп тұрған бронь) басқа қонақтың орнын
        -- басып кетпеуі үшін — мерзімі өткен болса сыйымдылық қайта тексеріледі.
        if v_claim.status = 'reserved' and v_claim.order_id is null and v_fits
           and (v_claim.reserved_until > now()
                or public.registry_item_taken_qty(v_claim.item_id, v_claim.id)
                   + least(v_claim.qty, v_lqty) <= v_item.qty_wanted) then
          update public.gift_registry_claims
             set order_id = new.id,
                 qty = least(qty, v_lqty),
                 reserved_until = greatest(coalesce(reserved_until, now()),
                                           now() + interval '48 hours'),
                 updated_at = now()
           where id = v_cid;
        end if;

      elsif new.status in ('confirmed', 'ready', 'completed') then
        -- Клиент өз тапсырысын өзі «расталды» қыла алмайды.
        if auth.uid() is not null and auth.uid() = new.client_uid
           and not public.is_superadmin() then
          continue;
        end if;
        v_buy := false;
        v_newqty := v_claim.qty;
        if v_claim.status = 'reserved' and v_claim.order_id = new.id then
          v_buy := true;               -- осы тапсырысқа байланған бронь
        elsif v_claim.status = 'released' and v_claim.order_id is null
              and v_fits
              and public.registry_item_taken_qty(v_claim.item_id, v_claim.id)
                  + least(v_claim.qty, v_lqty) <= v_item.qty_wanted then
          -- Бронь sweep-пен босап кеткен, бірақ төлем кеш расталды: позицияда
          -- орын әлі бос болса ғана қайта «сатып алынды» қыламыз.
          v_buy := true;
          v_newqty := least(v_claim.qty, v_lqty);
        elsif v_claim.status <> 'purchased' then
          -- Ақша түскен, бірақ орын бос емес — автоматты өзгертпейміз, қолмен
          -- қарау керек (support-қа белгі).
          raise warning 'on_order_registry_claims: paid order % could not take claim % (item full or mismatch)',
            new.id, v_cid;
        end if;
        if v_buy then
          update public.gift_registry_claims
             set status = 'purchased', order_id = new.id, qty = v_newqty,
                 updated_at = now()
           where id = v_cid;
          select owner_uid into v_owner from public.gift_registries
          where id = v_claim.registry_id;
          if v_owner is not null then
            perform public.notify_push(
              array[v_owner],
              '🎁 Тілек тізіміңізден сыйлық алынды / Подарок из вашего списка куплен',
              coalesce(nullif(v_item.product_name, ''), 'Qoima'),
              jsonb_build_object('type', 'registry_item_bought',
                                 'registryId', v_claim.registry_id)
            );
          end if;
        end if;

      elsif new.status in ('cancelled', 'returned') then
        -- Клиент статусты тікелей жаза алады: өз тапсырысын «cancelled» қылып,
        -- сатып алынған (purchased) броньды қайта ашып, қос сыйлық жасамасын.
        -- Сатып алынғанды тек иесі/курьер/суперадмин/cron босата алады.
        if v_claim.status = 'purchased'
           and auth.uid() is not null and auth.uid() = new.client_uid
           and not public.is_superadmin() then
          continue;
        end if;
        if v_claim.order_id = new.id and v_claim.status in ('reserved', 'purchased') then
          update public.gift_registry_claims
             set status = 'released', order_id = null, updated_at = now()
           where id = v_cid;
        end if;
      end if;
    end loop;
  exception when others then
    -- Тілек тізімінің қатесі тапсырысты/төлем растауды құлатпауы тиіс.
    raise warning 'on_order_registry_claims: %', sqlerrm;
  end;
  return new;
end;
$$;
revoke execute on function public.on_order_registry_claims() from public, anon, authenticated;

drop trigger if exists trg_order_registry_claims on public.orders;
create trigger trg_order_registry_claims
  after insert or update of status on public.orders
  for each row execute function public.on_order_registry_claims();


-- ── 10. Сағат сайынғы sweep: өлі брондарды босату ──────────────────────────
--  • тапсырысқа байланбаған, мерзімі өткен брондар;
--  • тапсырысы бас тартылған/қайтарылған брондар;
--  • тапсырысы чексіз ілініп қалғандар: auto-cancel тек экран ашылғанда
--    болады (серверде sweep жоқ), сондықтан pending/rejected тапсырыстың
--    deadline_at-ы 6 сағаттан бұрын өтсе — бронь босатылады. Чек жіберілсе
--    deadline_at = null болады, ондай тапсырыс тиіспейді.
create or replace function public.sweep_registry_claims() returns void
language plpgsql security definer set search_path = public as $$
begin
  update public.gift_registry_claims c
     set status = 'released', order_id = null, updated_at = now()
   where c.status = 'reserved'
     and (
       (c.order_id is null and c.reserved_until < now())
       or exists (
         select 1 from public.orders o
         where o.id = c.order_id
           and (o.status in ('cancelled', 'returned')
                or (o.status in ('pending', 'rejected')
                    and o.deadline_at is not null
                    and o.deadline_at < now() - interval '6 hours')
                -- Абсолютті жас шегі: клиент deadline_at-ты өзі жаза алады
                -- (null/алыс болашақ), сондықтан 3 күннен асқан төленбеген
                -- тапсырыс броньды ұстамайды ('reserved' депозит тапсырысы да).
                or (o.status in ('pending', 'rejected', 'reserved')
                    and o.created_at < now() - interval '3 days')))
     );
end;
$$;
revoke all on function public.sweep_registry_claims() from public, anon, authenticated;

select cron.unschedule('registry-claim-sweep')
  where exists (select 1 from cron.job where jobname = 'registry-claim-sweep');
select cron.schedule(
  'registry-claim-sweep',
  '7 * * * *',
  $$select public.sweep_registry_claims()$$
);


-- ── 11. Realtime: «Менің тізімдерім» экраны тірі жаңарады ─────────────────
--  DELETE оқиғасы owner_uid сүзгісімен жетуі үшін replica identity full (0063).
alter table public.gift_registries replica identity full;
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public'
      and tablename = 'gift_registries'
  ) then
    alter publication supabase_realtime add table public.gift_registries;
  end if;
end;
$$;

-- Тексеру (қолданғаннан кейін, read-only):
--   select oid::regprocedure, proacl from pg_proc
--   where proname in ('get_registry_public','reserve_registry_item',
--     'release_registry_claim','get_my_registries_summary',
--     'registry_item_taken_qty','on_order_registry_claims','sweep_registry_claims');
--   → get_registry_public-те ғана anon=X болуы тиіс, ешқайсында `=X/` жоқ.
