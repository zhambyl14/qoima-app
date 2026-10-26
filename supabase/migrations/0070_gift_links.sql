-- ════════════════════════════════════════════════════════════════════════════
--  0070 · «Сыйлау» — сыйлық сатып алу + сілтеме арқылы тапсыру + ауыстыру
-- ────────────────────────────────────────────────────────────────────────────
--  Не істейді: сыйлаушы (giver) тауарды кәдімгі тапсырыс сияқты төлейді де,
--  әдемі сілтеме алады (WhatsApp/Telegram). Алушы сілтемені ашып, кіріп/тіркеліп,
--  өлшемін (курьер болса мекенжайын) растайды — сонда тапсырыс дүкенге жалғасады.
--
--  Дизайн (жаңа кесте ЖОҚ — сыйлық = кәдімгі `orders` жолы):
--   • orders-қа gift_* бағандары қосылады (is_gift, gift_token, …).
--   • create_gift_order — тапсырысты СЕРВЕРДЕ жасайды (placeOrder емес): баға
--     batches-тен есептеледі (клиент бағасына сенбейміз).
--       – Өлшем МІНДЕТТІ ЕМЕС. Сыйлаушы «Өлшемін білемін» деп таңдаса — баға =
--         сол өлшемі бар ЕҢ АРЗАН партияның бағасы, ал қойма ДӘЛ СОЛ СӘТТЕ
--         азаяды (stock_restored = false → бас тарту/мерзім өту жолдары бәрі
--         қойманы қайтарады). Таңдамаса — баға = ең қымбат өлшем, қойма
--         ұсталмайды (stock_restored = true).
--       – Қайтарылмайтын тауарда (products.non_returnable + флаг) өлшем
--         МІНДЕТТІ: 'gift_size_required'.
--       – Курьер болса «өлшеп көру» ақысын (delivery_fitting_fee) СЫЙЛАУШЫ
--         төлейді: orders.fitting_fee, ақшасы дүкенге (кәдімгі примерка сияқты).
--   • claim_gift — алушы өлшемді растайды НЕМЕСЕ ауыстырады: сол тауардың басқа
--     өлшемі, не СОЛ дүкеннің басқа тауары. Курьер болса — примеркаға екінші
--     өлшем (reserved_sizes, кәдімгі altSize ағыны өзгеріссіз жұмыс істейді).
--   • gift_store_exchange — дүкен кассада ауыстырады: (а) дүкеннен алатын сыйлық
--     берілгенге дейін; (б) АЛЫНҒАН сыйлық 14 күн ішінде (кез келген жеткізу).
--   • Баға ережесі (екі жолда бірдей, gift_apply_item):
--       жаңа баға ≤ төленген → рұқсат, айырма ҚАЙТАРЫЛМАЙДЫ;
--       жаңа баға > төленген → тек дүкеннен алғанда (айырма gift_extra_due —
--       беру кезінде дүкенде төленеді); курьерде 'gift_exchange_over_amount'.
--   • Сыйлық = ТЕК АУЫСТЫРУ: қайтару (returns) ағыны сыйлық тапсырысына
--     бөгелген ('gift_exchange_only') — ақша ешкімге қолданба арқылы қайтпайды.
--   • get_gift_public — токен бойынша ПУБЛИКТІК оқу (anon да): сілтемені ашқан
--     қонақ сыйлықты көреді. Токен — болжанбайтын uuid. Баға жасырылса, тек
--     сыйлаушыға көрсетіледі.
--
--  Қауіпсіздік шешімдері:
--   • guard_orders_client_money-ге ТИМЕЙМІЗ. Ол клиент емес адамды (алушыны)
--     өткізіп жібереді, ал сыйлаушының (client_uid) gift_* бағандарына тиюін
--     жаңа триггер guard_gift_orders бөгейді: оларды тек definer RPC-лер
--     (транзакция-жергілікті `qoima.gift_rpc` жалауымен) өзгерте алады.
--     INSERT-те де жалауша жоқ болса is_gift/gift_* тазаланады (клиент
--     orders_insert арқылы жалған «сыйлық» жаза алмайды).
--   • Расталмаған (алушы таңдамаған) сыйлықты «ready/completed» қылуға және
--     курьерге тағайындауға БОЛМАЙДЫ — триггер + курьер RPC-лері тексереді.
--   • Алушыға `orders` кестесін оқу құқығы БЕРІЛМЕЙДІ (orders_select өзгермейді):
--     RLS бағанды шектемейді, сонда алушы сыйлаушының чек суретін, төлем
--     деректерін және жасырылған бағаны API арқылы оқып алар еді. Орнына
--     get_my_received_gifts() — тазартылған (чек/карта/жасырын баға жоқ) jsonb.
--   • Сыйлаушы өз сыйлығында төлемді «расталды» деп белгілей алмайды: claim_gift
--     пен get_gift_public тек иесі жазатын payment_confirmed_by толған болса
--     ғана «төленді» деп санайды; guard_gift_orders сыйлаушының status/тапсыру
--     түрі/мекенжай/stock_restored өзгертуін бөгейді.
--   • Қойма қозғалысы ТЕК серверде, бір транзакцияда: тапсырыс жолы `for update`,
--     содан кейін партиялар id бойынша ТҰРАҚТЫ РЕТПЕН құлыпталады (deadlock жоқ).
--   • Жаңа статус ЖОҚ: OrderModel.status* ↔ claim_order_transition ақ тізімі
--     өзгермейді.
--   • Суперадмин жалаушасы gift_links (0067b): create_gift_order өшік болса
--     'feature_disabled' береді. Төленіп қойған сыйлықты алу (claim), ауыстыру
--     және оқу өшік күйде де жұмыс істейді — ақша төленген.
--   • Курьер қоймасы (courier_available_orders / courier_take_order /
--     courier_take_group / on_courier_job_push): алушы мекенжай бермей тұрып
--     сыйлық курьерге көрінбейді. Claim кезінде курьерлерге push осында жіберіледі.
--
--  Ақша: жеткізу ақысы (delivery_fee) бұрынғыдай КУРЬЕРДІКІ — дүкенге
--  аударылатын deposit_amount-қа кірмейді (0053). deposit_amount = тауар
--  (gift_paid_amount) + fitting_fee. Қосымша төлем (gift_extra_due) дүкенде
--  беру кезінде алынады: items[0].price = төленген + қосымша, сондықтан
--  OrderModel.remainingAmount = gift_extra_due.
-- ════════════════════════════════════════════════════════════════════════════

-- ── 1. Баған ───────────────────────────────────────────────────────────────
alter table public.orders
  add column if not exists is_gift              boolean     not null default false,
  add column if not exists gift_token           uuid,
  add column if not exists gift_recipient_uid   uuid references auth.users(id) on delete set null,
  add column if not exists gift_recipient_name  text        not null default '',
  add column if not exists gift_recipient_phone text        not null default '',
  add column if not exists gift_message         text        not null default '',
  add column if not exists gift_hide_price      boolean     not null default false,
  add column if not exists gift_claimed_at      timestamptz,
  add column if not exists gift_expires_at      timestamptz,
  add column if not exists gift_giver_name      text        not null default '',
  add column if not exists gift_reminder_sent   boolean     not null default false,
  -- сыйлаушы төлеген ТАУАР сомасы (fitting/жеткізусіз) — ауыстыру ережесінің өлшемі
  add column if not exists gift_paid_amount     numeric,
  -- алушы дүкенде беру кезінде төлейтін қосымша (қымбатырақ тауарға ауысса)
  add column if not exists gift_extra_due       numeric     not null default 0,
  -- ауыстырулар тарихы: [{at, by, from_*, to_*, extra, after_handover}]
  add column if not exists gift_exchange_log    jsonb       not null default '[]'::jsonb;

do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'orders_gift_message_len') then
    alter table public.orders
      add constraint orders_gift_message_len check (char_length(gift_message) <= 300);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'orders_gift_extra_due_nonneg') then
    alter table public.orders
      add constraint orders_gift_extra_due_nonneg check (gift_extra_due >= 0);
  end if;
end $$;

create unique index if not exists orders_gift_token_uidx
  on public.orders (gift_token) where gift_token is not null;
create index if not exists orders_gift_recipient_idx
  on public.orders (gift_recipient_uid) where gift_recipient_uid is not null;
create index if not exists orders_gift_expiry_idx
  on public.orders (gift_expires_at) where is_gift and gift_claimed_at is null;

-- ── 2. Алушының оқуы: orders_select-ке ТИМЕЙМІЗ ───────────────────────────
--  Алушы өз сыйлықтарын get_my_received_gifts() (6а бөлімі) арқылы оқиды.

-- ── 3. Баға көмекшісі: Dart effectivePrice(batch) көшірмесі ────────────────
--  Ішкі функция (тек definer RPC-лер шақырады) — ешкімге grant берілмейді.
create or replace function public.batch_effective_price(
  p_price double precision, p_discount jsonb
) returns double precision
language plpgsql stable set search_path = public as $$
declare
  v_start timestamptz;
  v_end   timestamptz;
  v_val   double precision;
  v_raw   double precision;
begin
  if p_discount is null or jsonb_typeof(p_discount) <> 'object'
     or coalesce(p_discount ->> 'active', 'false') <> 'true' then
    return p_price;
  end if;
  begin v_start := nullif(p_discount ->> 'starts_at', '')::timestamptz;
  exception when others then v_start := null; end;
  begin v_end := nullif(p_discount ->> 'ends_at', '')::timestamptz;
  exception when others then v_end := null; end;
  if v_start is not null and now() < v_start then return p_price; end if;
  if v_end is not null and now() > v_end then return p_price; end if;
  begin v_val := coalesce((p_discount ->> 'value')::double precision, 0);
  exception when others then v_val := 0; end;
  v_raw := case when coalesce(p_discount ->> 'type', 'percent') = 'percent'
                then p_price * (1 - v_val / 100)
                else p_price - v_val end;
  if v_raw < 0 then return 0; end if;
  -- numeric round = «жартысы жоғары» (Dart roundToDouble сияқты)
  return round(v_raw::numeric)::double precision;
end;
$$;
revoke all on function public.batch_effective_price(double precision, jsonb) from public, anon, authenticated;

-- ── 3а. Өлшем нұсқалары: бір тауардың қолжетімді өлшемдері + бағасы ─────────
--  Ішкі функция (get_gift_public / get_gift_exchange_options шақырады).
--  Әр өлшем: ең арзан партия бағасы (claim/exchange дәл соны алады), қосымша
--  төлем (extra = баға − p_credit, ≥0), рұқсат (курьерде тек ≤ p_credit),
--  примеркаға болатын қосалқы өлшемдер (сол партияда нақты бар өлшемдер).
--  p_keep_* — сыйлаушы брондаған өлшем: оның қалдығы 0 болса да тізімде қалады.
create or replace function public.gift_size_options(
  p_pid        uuid,
  p_wh         text[],
  p_credit     double precision,
  p_limit      boolean,
  p_keep_batch uuid,
  p_keep_size  text,
  p_with_alts  boolean,
  p_hide       boolean
) returns jsonb
language sql stable set search_path = public as $$
  with av as (
    select b.id as batch_id,
           kv.key as size,
           public.batch_effective_price(b.selling_price, b.discount) as price,
           (case when kv.value ~ '^-?[0-9]+$' then kv.value::int else 0 end)
             - coalesce((b.reserved_sizes ->> kv.key)::int, 0) > 0 as real_avail
      from public.batches b
      cross join lateral jsonb_each_text(coalesce(b.sizes_quantity, '{}'::jsonb)) kv
     where b.product_id = p_pid
       and b.warehouse_id::text = any (coalesce(p_wh, '{}'::text[]))
  ),
  cand as (
    select * from av
     where real_avail
        or (batch_id = p_keep_batch and size = coalesce(p_keep_size, ''))
  ),
  per as (
    select size, min(price) as price from cand group by size
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'size', per.size,
           'price', case when p_hide then null else per.price end,
           'extra', greatest(per.price - p_credit, 0),
           'allowed', (not p_limit) or per.price <= p_credit,
           'alts', case when p_with_alts then coalesce((
               select jsonb_agg(distinct a2.size)
                 from cand a1
                 join av a2 on a2.batch_id = a1.batch_id
                           and a2.size <> a1.size
                           and a2.real_avail
                where a1.size = per.size
                  and ((not p_limit) or a1.price <= p_credit)
             ), '[]'::jsonb) else '[]'::jsonb end
         ) order by per.size), '[]'::jsonb)
    from per;
$$;
revoke all on function public.gift_size_options(uuid, text[], double precision, boolean, uuid, text, boolean, boolean) from public, anon, authenticated;

-- ── 4. Қорғаныс триггері: gift_* бағандары + расталмаған сыйлық ────────────
create or replace function public.guard_gift_orders()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_rpc boolean := coalesce(current_setting('qoima.gift_rpc', true), '') = 'on';
begin
  if tg_op = 'INSERT' then
    if not v_rpc then
      -- клиент orders_insert арқылы жалған сыйлық жаза алмайды
      new.is_gift := false;
      new.gift_token := null;
      new.gift_recipient_uid := null;
      new.gift_recipient_name := '';
      new.gift_recipient_phone := '';
      new.gift_message := '';
      new.gift_hide_price := false;
      new.gift_claimed_at := null;
      new.gift_expires_at := null;
      new.gift_giver_name := '';
      new.gift_reminder_sent := false;
      new.gift_paid_amount := null;
      new.gift_extra_due := 0;
      new.gift_exchange_log := '[]'::jsonb;
    end if;
    return new;
  end if;

  -- UPDATE: gift_* бағандарын тек RPC (немесе модератор) өзгерте алады.
  -- gift_reminder_sent-ті cron (auth.uid() бос) жаңартады — оған тиіспейміз.
  if not v_rpc and not coalesce(public.is_superadmin(), false) then
    if new.is_gift is distinct from old.is_gift
       or new.gift_token is distinct from old.gift_token
       or new.gift_recipient_uid is distinct from old.gift_recipient_uid
       or new.gift_recipient_name is distinct from old.gift_recipient_name
       or new.gift_recipient_phone is distinct from old.gift_recipient_phone
       or new.gift_message is distinct from old.gift_message
       or new.gift_hide_price is distinct from old.gift_hide_price
       or new.gift_claimed_at is distinct from old.gift_claimed_at
       or new.gift_expires_at is distinct from old.gift_expires_at
       or new.gift_giver_name is distinct from old.gift_giver_name
       or new.gift_paid_amount is distinct from old.gift_paid_amount
       or new.gift_extra_due is distinct from old.gift_extra_due
       or new.gift_exchange_log is distinct from old.gift_exchange_log then
      raise exception 'gift_columns_locked';
    end if;
  end if;

  -- Сыйлаушы (client_uid; иесі/модератор емес) өз сыйлығында: төлемді өзі
  -- «расталды» қыла алмайды, тапсыру түрін/мекенжайды/байланысты өзгерте алмайды,
  -- stock_restored-ты тек бас тартқаннан кейін қайтарым ретінде ғана true қоя алады.
  if old.is_gift and not v_rpc
     and auth.uid() is not null and auth.uid() = old.client_uid
     and old.admin_uid is distinct from public.app_owner_uid()
     and not coalesce(public.is_superadmin(), false) then
    -- Сыйлаушы тек ТӨЛЕНБЕГЕН, алушы алмаған сыйлықтан бас тарта алады.
    -- Төленген/алынған/берілген сыйлықтың статусын өзгерту (бас тарту, 'returned',
    -- кері қайтару) — алушының сыйлығын жояды, қойманы ағызады және «тек
    -- ауыстыру» ережесін айналып өтеді.
    if new.status is distinct from old.status
       and not (old.status in ('pending', 'reserved', 'rejected')
                and new.status = 'cancelled'
                and old.gift_claimed_at is null) then
      raise exception 'gift_status_forbidden';
    end if;
    if new.order_type is distinct from old.order_type
       or new.delivery_mode is distinct from old.delivery_mode
       or new.address is distinct from old.address
       or new.client_city is distinct from old.client_city
       or new.client_name is distinct from old.client_name
       or new.client_phone is distinct from old.client_phone
       or new.warehouse_address is distinct from old.warehouse_address then
      raise exception 'gift_columns_locked';
    end if;
    if new.stock_restored is distinct from old.stock_restored
       and not (new.stock_restored and new.status in ('cancelled', 'rejected', 'returned')) then
      raise exception 'gift_columns_locked';
    end if;
  end if;

  -- Алушы өлшем таңдамаған сыйлықты беруге/курьерге беруге болмайды.
  if old.is_gift and old.gift_claimed_at is null and not v_rpc then
    if new.status is distinct from old.status
       and new.status in ('ready', 'completed') then
      raise exception 'gift_not_claimed';
    end if;
    if new.courier_uid is distinct from old.courier_uid
       and new.courier_uid is not null then
      raise exception 'gift_not_claimed';
    end if;
  end if;
  return new;
end;
$$;
revoke all on function public.guard_gift_orders() from public, anon, authenticated;

drop trigger if exists trg_guard_gift_orders on public.orders;
create trigger trg_guard_gift_orders
  before insert or update on public.orders
  for each row execute function public.guard_gift_orders();

-- ── 5. create_gift_order ───────────────────────────────────────────────────
--  Ескі (өлшемсіз) қолтаңба тірі БД-да жоқ, бірақ қайта іске қосқанда overload
--  қалмасын деп алдымен алынады.
drop function if exists public.create_gift_order(uuid, text, text, text, boolean);

create or replace function public.create_gift_order(
  p_product        uuid,
  p_delivery_mode  text,
  p_recipient_name text,
  p_message        text,
  p_hide_price     boolean,
  p_size           text default null
) returns public.orders
language plpgsql security definer set search_path = public as $$
declare
  v_uid     uuid := auth.uid();
  v_client  public.clients;
  v_prod    public.products;
  v_store   public.stores;
  v_b       public.batches;
  v_price   double precision;
  v_orig    double precision := 0;
  v_fee     double precision := 0;
  v_fit     double precision := 0;
  v_base    double precision;
  v_reduced double precision;
  v_from    double precision;
  v_courier boolean := (p_delivery_mode = 'courier');
  v_size    text := left(trim(coalesce(p_size, '')), 20);
  v_nr      boolean;
  v_wh_id   uuid;
  v_wh_addr text := '';
  v_num     bigint;
  v_item    jsonb;
  v_order   public.orders;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;
  select * into v_client from public.clients where id = v_uid;
  if not found then raise exception 'not_a_client'; end if;
  if not public.feature_enabled('gift_links') then
    raise exception 'feature_disabled';
  end if;
  if p_delivery_mode is null or p_delivery_mode not in ('store', 'courier') then
    raise exception 'invalid_delivery_mode';
  end if;

  select * into v_prod from public.products where id = p_product;
  if not found or coalesce(v_prod.storefront_hidden, false) then
    raise exception 'product_unavailable';
  end if;
  select * into v_store from public.stores where admin_uid = v_prod.owner_uid;
  if not found or not coalesce(v_store.is_published, false)
     or v_store.status = 'blocked'
     or exists (select 1 from public.users u
                 where u.id = v_store.admin_uid and coalesce(u.blocked, false)) then
    raise exception 'store_unavailable';
  end if;
  if v_uid = v_store.admin_uid then raise exception 'not_a_client'; end if;

  -- Қайтарылмайтын тауарды алушы ауыстыра алмайды → өлшемін біліп сыйлау керек.
  -- (to_jsonb — 0073 бағаны жоқ ортада да функция құламасын.)
  v_nr := public.feature_enabled('non_returnable')
          and coalesce((to_jsonb(v_prod) ->> 'non_returnable')::boolean, false);
  if v_nr and v_size = '' then raise exception 'gift_size_required'; end if;

  if v_size <> '' then
    -- Өлшем белгілі: осы тауардың партияларын id ретімен құлыптап, сол өлшемі
    -- бар ЕҢ АРЗАН партиядан бір данасын ДӘЛ ҚАЗІР қоймадан шығарамыз.
    perform 1 from public.batches b
     where b.product_id = v_prod.id
       and b.warehouse_id::text = any (coalesce(v_store.visible_warehouse_ids, '{}'::text[]))
     order by b.id
     for update;
    select b.* into v_b
      from public.batches b
     where b.product_id = v_prod.id
       and b.warehouse_id::text = any (coalesce(v_store.visible_warehouse_ids, '{}'::text[]))
       and coalesce((b.sizes_quantity ->> v_size)::int, 0)
           - coalesce((b.reserved_sizes ->> v_size)::int, 0) >= 1
     order by public.batch_effective_price(b.selling_price, b.discount), b.date_arrived
     limit 1
     for update of b;
    if not found then raise exception 'gift_size_unavailable'; end if;

    v_price := public.batch_effective_price(v_b.selling_price, v_b.discount);
    if v_price <= 0 then raise exception 'price_invalid'; end if;
    if v_b.selling_price > v_price then v_orig := v_b.selling_price; end if;

    update public.batches
       set sizes_quantity = jsonb_set(coalesce(sizes_quantity, '{}'::jsonb), array[v_size],
             to_jsonb(coalesce((sizes_quantity ->> v_size)::int, 0) - 1))
     where id = v_b.id;
    v_wh_id := v_b.warehouse_id;
    select coalesce(w.address, '') into v_wh_addr
      from public.warehouses w where w.id = v_b.warehouse_id;
    v_wh_addr := coalesce(v_wh_addr, '');
  else
    -- Баға = қолда бары бар партиялардағы ЕҢ ЖОҒАРЫ тиімді баға: өлшем белгісіз,
    -- сондықтан кез келген өлшемге жетуі керек. Клиент бағасына сенбейміз.
    select max(public.batch_effective_price(b.selling_price, b.discount))
      into v_price
      from public.batches b
     where b.product_id = v_prod.id
       and b.warehouse_id::text = any (coalesce(v_store.visible_warehouse_ids, '{}'::text[]))
       and public.batch_available_qty(b.sizes_quantity, b.reserved_sizes) > 0;
    if v_price is null then raise exception 'gift_out_of_stock'; end if;
    if v_price <= 0 then raise exception 'price_invalid'; end if;

    -- «Бастапқы баға» (сызылған): осы бағаны берген партияның жеңілдіксіз бағасы.
    select b.selling_price into v_orig
      from public.batches b
     where b.product_id = v_prod.id
       and b.warehouse_id::text = any (coalesce(v_store.visible_warehouse_ids, '{}'::text[]))
       and public.batch_available_qty(b.sizes_quantity, b.reserved_sizes) > 0
       and public.batch_effective_price(b.selling_price, b.discount) = v_price
     order by b.selling_price desc limit 1;
    if v_orig is null or v_orig <= v_price then v_orig := 0; end if;
  end if;

  if v_courier then
    if not public.courier_city_enabled(v_store.city) then
      raise exception 'courier_unavailable';
    end if;
    -- DeliveryTariff.feeForSubOrder(index 0) көшірмесі
    select coalesce(nullif((select value from public.app_settings where key = 'delivery_base_fee'), '')::double precision, 690),
           coalesce(nullif((select value from public.app_settings where key = 'delivery_reduced_fee'), '')::double precision, 390),
           coalesce(nullif((select value from public.app_settings where key = 'delivery_reduced_from'), '')::double precision, 15000)
      into v_base, v_reduced, v_from;
    v_fee := case when v_from > 0 and v_price >= v_from then v_reduced else v_base end;
    -- «Өлшеп көру» ақысын СЫЙЛАУШЫ төлейді (DeliveryTariff.fittingFee, кілт
    -- delivery_fitting_fee). Ақшасы дүкенге — кәдімгі примерка сияқты
    -- (storeAmount = тауар + fitting). Қайтарылмайтын тауарда примерка жоқ.
    if not v_nr then
      v_fit := greatest(coalesce(nullif((select value from public.app_settings
                                          where key = 'delivery_fitting_fee'), '')::double precision, 300), 0);
    end if;
  end if;

  v_item := jsonb_build_object(
    'productId', v_prod.id, 'productName', v_prod.name,
    'batchId', coalesce(v_b.id::text, ''), 'size', v_size, 'qty', 1,
    'price', v_price, 'originalPrice', v_orig,
    'adminUid', v_store.admin_uid, 'storeName', coalesce(v_store.store_name, ''),
    'imageUrl', coalesce(v_prod.images[1], ''),
    'warehouseId', coalesce(v_wh_id::text, ''), 'warehouseAddress', v_wh_addr,
    'selected', true);
  if coalesce(v_prod.brand, '') <> '' then v_item := v_item || jsonb_build_object('brand', v_prod.brand); end if;
  if coalesce(v_prod.type, '') <> '' then v_item := v_item || jsonb_build_object('type', v_prod.type); end if;
  if coalesce(v_prod.color, '') <> '' then v_item := v_item || jsonb_build_object('color', v_prod.color); end if;
  if coalesce(v_prod.variant_note, '') <> '' then v_item := v_item || jsonb_build_object('variantNote', v_prod.variant_note); end if;
  if coalesce(v_prod.articul, '') <> '' then v_item := v_item || jsonb_build_object('articul', v_prod.articul); end if;

  v_num := public.next_counter(v_store.admin_uid, 'orders');

  perform set_config('qoima.gift_rpc', 'on', true);
  insert into public.orders (
    admin_uid, client_uid, client_phone, client_name, store_name, store_phone,
    warehouse_id, warehouse_address,
    items, status, order_type, delivery_mode, deposit_amount, delivery_fee, fitting_fee,
    pickup_code, order_number, seller_id, seller_name, deadline_at,
    stock_restored, payment_card_number, payment_card_holder, payment_bank,
    is_gift, gift_token, gift_recipient_name, gift_message, gift_hide_price,
    gift_expires_at, gift_giver_name, gift_paid_amount, gift_extra_due
  ) values (
    v_store.admin_uid, v_uid, coalesce(v_client.phone, ''), coalesce(v_client.name, ''),
    coalesce(v_store.store_name, ''), coalesce(v_store.phone, ''),
    v_wh_id, v_wh_addr,
    jsonb_build_array(v_item), 'pending',
    case when v_courier then 'delivery' else 'click_collect' end,
    case when v_courier then 'courier' else 'store' end,
    v_price + v_fit, v_fee, v_fit,
    lpad((('x' || substr(md5(gen_random_uuid()::text), 1, 7))::bit(28)::int % 1000000)::text, 6, '0'),
    v_num::int, 'онлайн', 'Онлайн', now() + interval '30 minutes',
    -- өлшем брондалса — қойма ұсталды (бас тартқанда қайтарылуы керек)
    (v_size = ''),
    coalesce(v_store.payment_card_number, ''), coalesce(v_store.payment_card_holder, ''),
    coalesce(v_store.payment_bank, ''),
    true, gen_random_uuid(),
    left(trim(coalesce(p_recipient_name, '')), 60),
    left(trim(coalesce(p_message, '')), 300),
    coalesce(p_hide_price, false),
    now() + interval '30 days',
    left(trim(coalesce(v_client.name, '')), 60),
    v_price, 0
  ) returning * into v_order;
  perform set_config('qoima.gift_rpc', 'off', true);

  if v_size <> '' then
    perform public.recompute_product_status(v_prod.id);
  end if;

  return v_order;
end;
$$;
revoke all on function public.create_gift_order(uuid, text, text, text, boolean, text) from public, anon;
grant execute on function public.create_gift_order(uuid, text, text, text, boolean, text) to authenticated;

-- ── 6. get_gift_public ─────────────────────────────────────────────────────
--  ӘДЕЙІ ПУБЛИКТІК (anon + authenticated): сілтемені ашқан қонақ (әлі тіркелмеген
--  алушы да) сыйлықты көруі керек. Қорғаныс — токеннің өзі (болжанбайтын uuid,
--  токенсіз тізім/іздеу жоқ). Тек сыйлау парағына қажет өрістер қайтады:
--  сыйлаушының ТЕК аты, телефон/мекенжай/чек жоқ. Баға жасырылса — сыйлаушыға ғана.
create or replace function public.get_gift_public(p_token uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_uid     uuid := auth.uid();
  o         public.orders;
  v_store   public.stores;
  v_prod    public.products;
  v_item    jsonb;
  v_status  text;
  v_sizes   jsonb := '[]'::jsonb;
  v_opts    jsonb := '[]'::jsonb;
  v_giver   boolean;
  v_recip   boolean;
  v_paid    boolean;
  v_credit  double precision;
  v_courier boolean;
  v_nr      boolean := false;
  v_fit     boolean;
  v_chosen  text;
begin
  select * into o from public.orders where gift_token = p_token and is_gift;
  if not found then return null; end if;

  v_item := coalesce(o.items -> 0, '{}'::jsonb);
  v_giver := v_uid is not null and o.client_uid = v_uid;
  v_recip := v_uid is not null and o.gift_recipient_uid = v_uid;
  select * into v_store from public.stores where admin_uid = o.admin_uid;
  select * into v_prod from public.products
   where id = nullif(v_item ->> 'productId', '')::uuid;

  -- «Төленді» = иесі растады (payment_confirmed_by-ді клиент жаза алмайды, 0065).
  -- Тек status = 'confirmed'-ке сенуге болмайды: сыйлаушы оны өзі қоя алатын еді.
  v_paid := o.status = 'confirmed' and coalesce(o.payment_confirmed_by, '') <> '';

  v_status := case
    when o.status in ('cancelled', 'returned') then 'cancelled'
    when o.gift_claimed_at is not null then 'claimed'
    when v_paid and o.gift_expires_at is not null
         and o.gift_expires_at < now() then 'expired'
    when v_paid then 'ready_to_claim'
    else 'awaiting_payment'
  end;

  v_courier := o.order_type = 'delivery' and coalesce(o.delivery_mode, 'courier') = 'courier';
  v_nr := v_prod.id is not null
          and public.feature_enabled('non_returnable')
          and coalesce((to_jsonb(v_prod) ->> 'non_returnable')::boolean, false);
  v_fit := v_courier and not v_nr;
  -- Сыйлаушы таңдаған (брондалған) өлшем — алушы әлі растамаған кезде
  v_chosen := case when o.gift_claimed_at is null then nullif(v_item ->> 'size', '') end;

  if v_status = 'ready_to_claim' and v_prod.id is not null then
    v_credit := coalesce(o.gift_paid_amount::double precision,
                         (v_item ->> 'price')::double precision, 0);
    v_opts := public.gift_size_options(
      v_prod.id, v_store.visible_warehouse_ids, v_credit, v_courier,
      nullif(v_item ->> 'batchId', '')::uuid, coalesce(v_item ->> 'size', ''),
      v_fit, o.gift_hide_price and not v_giver);
    -- Қайтарылмайтын тауар: тек сыйлаушы таңдаған өлшем (ауыстыруға болмайды)
    if v_nr and v_chosen is not null then
      select coalesce(jsonb_agg(e), '[]'::jsonb) into v_opts
        from jsonb_array_elements(v_opts) e where e ->> 'size' = v_chosen;
    end if;
    select coalesce(jsonb_agg(e ->> 'size'), '[]'::jsonb) into v_sizes
      from jsonb_array_elements(v_opts) e where (e ->> 'allowed')::boolean;
  end if;

  return jsonb_build_object(
    'status', v_status,
    'giver_first_name', split_part(trim(o.gift_giver_name), ' ', 1),
    'recipient_name', o.gift_recipient_name,
    'message', o.gift_message,
    'product', jsonb_build_object(
      'id', v_prod.id, 'name', coalesce(v_prod.name, v_item ->> 'productName'),
      'brand', coalesce(v_prod.brand, ''), 'color', coalesce(v_prod.color, ''),
      'category_key', coalesce(v_prod.category_key, ''),
      'image_url', coalesce(v_prod.images[1], v_item ->> 'imageUrl', ''),
      'images', to_jsonb(coalesce(v_prod.images, '{}'::text[]))),
    'store', jsonb_build_object(
      'admin_uid', v_store.admin_uid,
      'name', coalesce(v_store.store_name, ''),
      'city', coalesce(v_store.city, ''),
      'address', coalesce(v_store.address, '')),
    'price', case when o.gift_hide_price and not v_giver then null
                  else (v_item ->> 'price')::double precision end,
    'hide_price', o.gift_hide_price,
    'delivery_mode', o.delivery_mode,
    'delivery_fee', case when o.delivery_mode = 'courier' then o.delivery_fee else 0 end,
    'available_sizes', v_sizes,
    'size_options', v_opts,
    'chosen_size', v_chosen,
    'non_returnable', v_nr,
    'fitting_available', v_fit,
    'fitting_fee', case when v_courier then coalesce(o.fitting_fee, 0) else 0 end,
    'extra_due', case when v_giver or v_recip then coalesce(o.gift_extra_due, 0) else 0 end,
    'exchange_until', case when (v_giver or v_recip) and o.status = 'completed'
                           then coalesce(o.completed_at, o.created_at) + interval '14 days' end,
    'exchanged', jsonb_array_length(coalesce(o.gift_exchange_log, '[]'::jsonb)) > 0,
    'claimed_size', case when o.gift_claimed_at is not null then v_item ->> 'size' else null end,
    'expires_at', o.gift_expires_at,
    'is_giver', v_giver,
    'is_recipient', v_recip,
    'order_id', case when v_giver or v_recip then to_jsonb(o.id) else null end,
    'order_status', case when v_giver or v_recip then to_jsonb(o.status) else null end
  );
end;
$$;
revoke all on function public.get_gift_public(uuid) from public;
grant execute on function public.get_gift_public(uuid) to anon, authenticated;

-- ── 6а. get_my_received_gifts ──────────────────────────────────────────────
--  Алушы өз сыйлықтарын осы арқылы оқиды (orders-ке тікелей құқық жоқ).
--  Тазартылған: чек суреті, карта/төлем деректері жоқ; баға жасырылса — 0
--  (төленген сома мен ауыстыру тарихындағы бағалар да алынады).
--  Тазарту бір ғана көзде — gift_recipient_view (claim_gift жауабы да сол).
create or replace function public.gift_recipient_view(o public.orders)
returns jsonb
language sql stable set search_path = public as $$
  select case when o.gift_hide_price then
           (to_jsonb(o)
             - 'receipt_url' - 'receipt_submitted_at' - 'payment_card_number'
             - 'payment_card_holder' - 'payment_bank' - 'payment_confirmed_by'
             - 'in_store_payment_method' - 'gift_paid_amount')
           || jsonb_build_object(
                'deposit_amount', 0,
                'items', coalesce((
                  select jsonb_agg(i || jsonb_build_object('price', 0, 'originalPrice', 0))
                    from jsonb_array_elements(o.items) i), '[]'::jsonb),
                'gift_exchange_log', coalesce((
                  select jsonb_agg(l - 'from_price' - 'to_price')
                    from jsonb_array_elements(o.gift_exchange_log) l), '[]'::jsonb))
         else
           to_jsonb(o)
             - 'receipt_url' - 'receipt_submitted_at' - 'payment_card_number'
             - 'payment_card_holder' - 'payment_bank' - 'payment_confirmed_by'
             - 'in_store_payment_method'
         end;
$$;
revoke all on function public.gift_recipient_view(public.orders) from public, anon, authenticated;

create or replace function public.get_my_received_gifts()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  r     jsonb;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;
  select coalesce(jsonb_agg(public.gift_recipient_view(o) order by o.created_at desc), '[]'::jsonb)
    into r
    from public.orders o
   where o.is_gift
     and o.gift_recipient_uid = v_uid
     and o.client_uid is distinct from v_uid;
  return r;
end;
$$;
revoke all on function public.get_my_received_gifts() from public, anon;
grant execute on function public.get_my_received_gifts() to authenticated;

-- ── 6б. get_gift_exchange_options ──────────────────────────────────────────
--  Ауыстыру парақшасына: сыйлық тауарының өлшемдері + СОЛ дүкеннің витринадағы
--  қолда бар басқа тауарлары (әр өлшемнің бағасы, қосымша төлемі, рұқсаты).
--  Кім шақыра алады:
--   • дүкен қызметкері (admin_uid = app_owner_uid()) / superadmin → mode 'store';
--   • алушы БОЛАТЫН адам: сыйлық төленген, алынбаған, мерзімі өтпеген, шақырушы
--     сыйлаушының өзі емес → mode 'claim' (токен — құпия сілтеменің өзі).
--  Алушыға баға жасырылса — бағалар null, тек «қосымша төлем» көрінеді.
create or replace function public.get_gift_exchange_options(p_token uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_uid       uuid := auth.uid();
  o           public.orders;
  v_store     public.stores;
  v_item      jsonb;
  v_pid       uuid;
  v_batch     uuid;
  v_size      text;
  v_mode      text;
  v_completed boolean;
  v_courier   boolean;
  v_limit     boolean;
  v_paid      double precision;
  v_credit    double precision;
  v_hide      boolean;
  v_feat_nr   boolean := public.feature_enabled('non_returnable');
  v_locked    boolean := false;
  v_fit       boolean;
  v_products  jsonb;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;
  select * into o from public.orders where gift_token = p_token and is_gift;
  if not found then raise exception 'gift_not_found'; end if;

  if coalesce(o.admin_uid = public.app_owner_uid(), false)
     or coalesce(public.is_superadmin(), false) then
    v_mode := 'store';
  elsif o.client_uid is distinct from v_uid
        and o.gift_claimed_at is null
        and o.status = 'confirmed' and coalesce(o.payment_confirmed_by, '') <> ''
        and (o.gift_expires_at is null or o.gift_expires_at >= now()) then
    v_mode := 'claim';
  else
    raise exception 'not_your_order';
  end if;

  select * into v_store from public.stores where admin_uid = o.admin_uid;
  v_item      := coalesce(o.items -> 0, '{}'::jsonb);
  v_pid       := nullif(v_item ->> 'productId', '')::uuid;
  v_batch     := nullif(v_item ->> 'batchId', '')::uuid;
  v_size      := coalesce(v_item ->> 'size', '');
  v_completed := o.status = 'completed';
  v_courier   := o.order_type = 'delivery' and coalesce(o.delivery_mode, 'courier') = 'courier';
  v_limit     := v_courier and not v_completed;
  v_paid      := coalesce(o.gift_paid_amount::double precision,
                          (v_item ->> 'price')::double precision, 0);
  v_credit    := case when v_completed
                      then greatest(coalesce((v_item ->> 'price')::double precision, 0), v_paid)
                      else v_paid end;
  v_hide      := v_mode = 'claim' and o.gift_hide_price;
  v_fit       := v_mode = 'claim' and v_courier;

  if v_size <> '' and v_pid is not null then
    v_locked := coalesce(v_item -> 'nonReturnable' = 'true'::jsonb, false)
      or (v_feat_nr and exists (
            select 1 from public.products p
             where p.id = v_pid
               and coalesce((to_jsonb(p) ->> 'non_returnable')::boolean, false)));
  end if;

  select coalesce(jsonb_agg(x.j order by x.cur desc, x.nm), '[]'::jsonb)
    into v_products
    from (
      select (p.id = v_pid) as cur,
             coalesce(p.name, '') as nm,
             jsonb_build_object(
               'id', p.id,
               'name', coalesce(p.name, ''),
               'brand', coalesce(p.brand, ''),
               'color', coalesce(p.color, ''),
               'category_key', coalesce(p.category_key, ''),
               'image_url', coalesce(p.images[1], ''),
               'non_returnable', f.nr,
               'is_current', p.id = v_pid,
               'sizes', s.opts) as j
        from public.products p
        cross join lateral (
          select v_feat_nr and coalesce((to_jsonb(p) ->> 'non_returnable')::boolean, false) as nr
        ) f
        cross join lateral (
          select public.gift_size_options(
                   p.id, v_store.visible_warehouse_ids, v_credit, v_limit,
                   case when p.id = v_pid then v_batch end,
                   case when p.id = v_pid then v_size else '' end,
                   v_fit and not f.nr, v_hide) as opts
        ) s
       where p.owner_uid = o.admin_uid
         and (p.id = v_pid
              or (not v_locked
                  and not coalesce(p.storefront_hidden, false)
                  and coalesce(array_length(p.images, 1), 0) > 0))
         and jsonb_array_length(s.opts) > 0
       order by (p.id = v_pid) desc, p.name
       limit 150
    ) x;

  return jsonb_build_object(
    'mode', v_mode,
    'courier', v_courier,
    'completed', v_completed,
    'credit', case when v_hide then null else v_credit end,
    'hide_price', v_hide,
    'extra_due', coalesce(o.gift_extra_due, 0),
    'locked', v_locked,
    'fitting_available', v_fit,
    'current_product_id', v_pid,
    'current_size', v_size,
    'exchange_until', case when v_completed
                           then coalesce(o.completed_at, o.created_at) + interval '14 days' end,
    'products', v_products);
end;
$$;
revoke all on function public.get_gift_exchange_options(uuid) from public, anon;
grant execute on function public.get_gift_exchange_options(uuid) to authenticated;

-- ── 7. gift_apply_item — позицияны ауыстырудың ЖАЛҒЫЗ көзі (ішкі) ──────────
--  claim_gift (алушы) пен gift_store_exchange (дүкен) шақырады; авторизация мен
--  тапсырыс жолының `for update` құлпы СОЛАРДА. Бір транзакцияда:
--   1) тапсырыс жолы + тауардың партиялары + ескі партия id ретімен құлыпталады;
--   2) ескі өлшем (брондалған/берілген) қоймаға +1 қайтады;
--   3) жаңа өлшемі бар ең арзан партиядан −1 (курьер примеркасы болса — қосалқы
--      өлшем reserved_sizes-ке +1, кәдімгі altSize ағыны);
--   4) баға: жаңа ≤ кредит → айырма қайтарылмайды; жаңа > кредит → курьерде
--      (берілгенге дейін) тыйым, әйтпесе айырма gift_extra_due (беру кезінде
--      дүкенде) немесе алынған тапсырыста дәл қазір кассада алынады;
--   5) items[0] жаңа тауар снапшотымен ауыстырылады; алынған тапсырыста
--      sales_history-ге «қайтару» (ескі) + «сату» (жаңа) жазбасы түседі.
--  Кредит: берілгенге дейін = gift_paid_amount (қосымша әлі төленбеген);
--  алынған соң = items[0].price (қосымшасымен бірге төленіп қойған).
create or replace function public.gift_apply_item(
  p_order   uuid,
  p_product uuid,
  p_size    text,
  p_alt     text,
  p_actor   text
) returns public.orders
language plpgsql security definer set search_path = public as $$
declare
  o           public.orders;
  v_store     public.stores;
  v_prod      public.products;
  v_item      jsonb;
  v_old_pid   uuid;
  v_old_batch uuid;
  v_held      boolean;
  v_old_size  text;
  v_old_alt   text;
  v_old_price double precision;
  v_size      text := left(trim(coalesce(p_size, '')), 20);
  v_alt       text := left(trim(coalesce(p_alt, '')), 20);
  v_completed boolean;
  v_courier   boolean;
  v_limit     boolean;
  v_feat_nr   boolean := public.feature_enabled('non_returnable');
  v_nr_old    boolean := false;
  v_nr_new    boolean;
  v_paid      double precision;
  v_credit    double precision;
  v_b         public.batches;
  v_q         double precision;
  v_price     double precision;
  v_orig      double precision := 0;
  v_extra     double precision := 0;
  v_collect   double precision := 0;
  v_wh_addr   text := '';
  v_new       jsonb;
  v_log       jsonb;
  v_staff     text;
  v_cost_old  double precision;
  v_cost_new  double precision;
begin
  select * into o from public.orders where id = p_order and is_gift for update;
  if not found then raise exception 'gift_not_found'; end if;
  if v_size = '' then raise exception 'gift_size_required'; end if;
  if v_alt = v_size then v_alt := ''; end if;

  select * into v_store from public.stores where admin_uid = o.admin_uid;
  if not found then raise exception 'store_unavailable'; end if;

  v_item      := coalesce(o.items -> 0, '{}'::jsonb);
  v_old_pid   := nullif(v_item ->> 'productId', '')::uuid;
  v_old_batch := nullif(v_item ->> 'batchId', '')::uuid;
  v_old_size  := coalesce(v_item ->> 'size', '');
  v_old_alt   := coalesce(v_item ->> 'altSize', '');
  v_old_price := coalesce((v_item ->> 'price')::double precision, 0);
  v_completed := o.status = 'completed';
  v_courier   := o.order_type = 'delivery' and coalesce(o.delivery_mode, 'courier') = 'courier';
  v_limit     := v_courier and not v_completed;
  v_paid      := coalesce(o.gift_paid_amount::double precision, v_old_price);
  v_credit    := case when v_completed then greatest(v_old_price, v_paid) else v_paid end;
  -- Ескі өлшем шынымен ұсталып тұр ма: берілген тауар клиентте (қоймаға қайтады),
  -- әйтпесе — бас тартылып қоймаға қайтарылмаған болса ғана (stock_restored=false).
  -- Бас тартылған соң қайта ашылған тапсырыста ескі өлшемді екінші рет қоспаймыз.
  v_held      := v_old_batch is not null
                 and (v_completed or not coalesce(o.stock_restored, false));

  if v_completed and v_old_batch is null then raise exception 'gift_exchange_closed'; end if;

  -- Жаңа тауар: СОЛ дүкеннің, витринада көрінетін (сыйлықтың өз тауары — әрқашан)
  select * into v_prod from public.products where id = p_product;
  if not found or v_prod.owner_uid is distinct from o.admin_uid
     or (p_product is distinct from v_old_pid
         and (coalesce(v_prod.storefront_hidden, false)
              or coalesce(array_length(v_prod.images, 1), 0) = 0)) then
    raise exception 'gift_product_unavailable';
  end if;
  v_nr_new := v_feat_nr and coalesce((to_jsonb(v_prod) ->> 'non_returnable')::boolean, false);

  -- Қайтарылмайтын тауар (сыйлаушы өлшемін біліп алған) ауыстырылмайды.
  if v_old_pid is not null and v_old_size <> '' then
    v_nr_old := coalesce(v_item -> 'nonReturnable' = 'true'::jsonb, false)
      or (v_feat_nr and exists (
            select 1 from public.products p
             where p.id = v_old_pid
               and coalesce((to_jsonb(p) ->> 'non_returnable')::boolean, false)));
    if v_nr_old and (p_product is distinct from v_old_pid or v_size <> v_old_size) then
      raise exception 'gift_non_returnable';
    end if;
  end if;

  -- Примерка: тек курьер, тауар берілгенге дейін, қайтарылмайтын емес тауар
  if v_alt <> '' and (not v_courier or v_completed or v_nr_new) then
    raise exception 'gift_fitting_unavailable';
  end if;

  -- Ештеңе өзгермейді: сол тауар, сол өлшем (сыйлаушы брондаған), примеркасыз
  if v_held and p_product = v_old_pid
     and v_size = v_old_size and v_old_alt = '' and v_alt = '' then
    if p_actor = 'store' then raise exception 'gift_exchange_same'; end if;
    return o;
  end if;

  -- Құлып: тауардың барлық партиялары + ескі партия — id ретімен (deadlock жоқ)
  perform 1 from public.batches b
   where (b.product_id = p_product
          and b.warehouse_id::text = any (coalesce(v_store.visible_warehouse_ids, '{}'::text[])))
      or b.id = v_old_batch
   order by b.id
   for update;

  -- Сол өлшем сақталып, тек примерка қосылса және ескі партияда қосалқы өлшем
  -- бар болса — қоймаға тиіспей, қосалқыны ғана брондаймыз.
  if v_held and p_product = v_old_pid
     and v_size = v_old_size and v_old_alt = '' and v_alt <> '' then
    select * into v_b from public.batches where id = v_old_batch;
    if found and coalesce((v_b.sizes_quantity ->> v_alt)::int, 0)
                 - coalesce((v_b.reserved_sizes ->> v_alt)::int, 0) >= 1 then
      update public.batches
         set reserved_sizes = jsonb_set(coalesce(reserved_sizes, '{}'::jsonb), array[v_alt],
               to_jsonb(coalesce((reserved_sizes ->> v_alt)::int, 0) + 1))
       where id = v_b.id;
      perform set_config('qoima.gift_rpc', 'on', true);
      update public.orders
         set items = jsonb_set(items, '{0}', v_item || jsonb_build_object('altSize', v_alt))
       where id = o.id
       returning * into o;
      perform set_config('qoima.gift_rpc', 'off', true);
      return o;
    end if;
    -- бұл партияда қосалқы өлшем жоқ → төменде екеуі де бар партияға көшеміз
  end if;

  -- Ескі өлшем қоймаға қайтады (брондалған немесе клиенттен қайтып келген)
  if v_held and v_old_size <> '' then
    update public.batches
       set sizes_quantity = jsonb_set(coalesce(sizes_quantity, '{}'::jsonb), array[v_old_size],
             to_jsonb(coalesce((sizes_quantity ->> v_old_size)::int, 0) + 1))
     where id = v_old_batch;
    if v_old_alt <> '' then
      update public.batches
         set reserved_sizes = jsonb_set(coalesce(reserved_sizes, '{}'::jsonb), array[v_old_alt],
               to_jsonb(greatest(coalesce((reserved_sizes ->> v_old_alt)::int, 0) - 1, 0)))
       where id = v_old_batch;
    end if;
  end if;

  -- Жаңа өлшемі (және примерка болса қосалқысы) бар ең арзан партия
  select b.* into v_b
    from public.batches b
   where b.product_id = p_product
     and b.warehouse_id::text = any (coalesce(v_store.visible_warehouse_ids, '{}'::text[]))
     and coalesce((b.sizes_quantity ->> v_size)::int, 0)
         - coalesce((b.reserved_sizes ->> v_size)::int, 0) >= 1
     and (v_alt = ''
          or coalesce((b.sizes_quantity ->> v_alt)::int, 0)
             - coalesce((b.reserved_sizes ->> v_alt)::int, 0) >= 1)
     and (not v_limit
          or public.batch_effective_price(b.selling_price, b.discount) <= v_credit)
   order by public.batch_effective_price(b.selling_price, b.discount), b.date_arrived
   limit 1
   for update of b;
  if not found then
    -- Себебін дәл айтамыз: негізгі өлшем сомаға сыятын партияда бар болса,
    -- жетіспейтіні — примеркаға екінші өлшем (қымбат деп айтпаймыз).
    if v_alt <> '' and exists (
         select 1 from public.batches b
          where b.product_id = p_product
            and b.warehouse_id::text = any (coalesce(v_store.visible_warehouse_ids, '{}'::text[]))
            and coalesce((b.sizes_quantity ->> v_size)::int, 0)
                - coalesce((b.reserved_sizes ->> v_size)::int, 0) >= 1
            and (not v_limit
                 or public.batch_effective_price(b.selling_price, b.discount) <= v_credit)) then
      raise exception 'gift_alt_size_unavailable';
    elsif v_limit and exists (
         select 1 from public.batches b
          where b.product_id = p_product
            and b.warehouse_id::text = any (coalesce(v_store.visible_warehouse_ids, '{}'::text[]))
            and coalesce((b.sizes_quantity ->> v_size)::int, 0)
                - coalesce((b.reserved_sizes ->> v_size)::int, 0) >= 1) then
      raise exception 'gift_exchange_over_amount';
    end if;
    raise exception 'gift_size_unavailable';
  end if;

  update public.batches
     set sizes_quantity = jsonb_set(coalesce(sizes_quantity, '{}'::jsonb), array[v_size],
           to_jsonb(coalesce((sizes_quantity ->> v_size)::int, 0) - 1)),
         reserved_sizes = case when v_alt = '' then reserved_sizes
           else jsonb_set(coalesce(reserved_sizes, '{}'::jsonb), array[v_alt],
                  to_jsonb(coalesce((reserved_sizes ->> v_alt)::int, 0) + 1)) end
   where id = v_b.id;

  -- Баға (Dart effectivePrice көшірмесі; клиент бағасына сенбейміз)
  v_q := public.batch_effective_price(v_b.selling_price, v_b.discount);
  if v_q <= 0 then raise exception 'price_invalid'; end if;
  v_price := greatest(v_q, v_credit);
  if v_completed then
    v_collect := greatest(v_q - v_credit, 0);   -- дәл қазір кассада алынады
  else
    v_extra := greatest(v_q - v_paid, 0);       -- беру кезінде дүкенде
  end if;
  if v_b.selling_price > v_price then v_orig := v_b.selling_price; end if;

  select coalesce(w.address, '') into v_wh_addr
    from public.warehouses w where w.id = v_b.warehouse_id;
  v_wh_addr := coalesce(v_wh_addr, '');

  v_new := jsonb_build_object(
    'productId', v_prod.id, 'productName', coalesce(v_prod.name, ''),
    'batchId', v_b.id, 'size', v_size, 'qty', 1,
    'price', v_price, 'originalPrice', v_orig,
    'adminUid', o.admin_uid, 'storeName', coalesce(v_store.store_name, ''),
    'imageUrl', coalesce(v_prod.images[1], ''),
    'warehouseId', v_b.warehouse_id, 'warehouseAddress', v_wh_addr,
    'selected', true);
  if coalesce(v_prod.brand, '') <> '' then v_new := v_new || jsonb_build_object('brand', v_prod.brand); end if;
  if coalesce(v_prod.type, '') <> '' then v_new := v_new || jsonb_build_object('type', v_prod.type); end if;
  if coalesce(v_prod.color, '') <> '' then v_new := v_new || jsonb_build_object('color', v_prod.color); end if;
  if coalesce(v_prod.variant_note, '') <> '' then v_new := v_new || jsonb_build_object('variantNote', v_prod.variant_note); end if;
  if coalesce(v_prod.articul, '') <> '' then v_new := v_new || jsonb_build_object('articul', v_prod.articul); end if;
  if v_alt <> '' then v_new := v_new || jsonb_build_object('altSize', v_alt); end if;

  -- Тарих: тауар ауысса немесе брондалған өлшем өзгерсе
  if p_product is distinct from v_old_pid or (v_old_size <> '' and v_size <> v_old_size) then
    v_log := jsonb_build_object(
      'at', now(), 'by', p_actor,
      'from_product', coalesce(v_item ->> 'productName', ''), 'from_size', v_old_size,
      'from_price', v_old_price,
      'to_product', coalesce(v_prod.name, ''), 'to_size', v_size, 'to_price', v_price,
      'extra', case when v_completed then v_collect else v_extra end,
      'after_handover', v_completed);
  end if;

  perform set_config('qoima.gift_rpc', 'on', true);
  update public.orders set
    items             = jsonb_build_array(v_new),
    warehouse_id      = v_b.warehouse_id,
    warehouse_address = v_wh_addr,
    gift_extra_due    = v_extra,
    -- жаңа өлшем қоймадан дәл қазір шықты → кез келген бас тарту оны қайтарады
    stock_restored    = false,
    gift_exchange_log = case when v_log is null then gift_exchange_log
                             else coalesce(gift_exchange_log, '[]'::jsonb) || jsonb_build_array(v_log) end
  where id = o.id
  returning * into o;
  perform set_config('qoima.gift_rpc', 'off', true);

  -- Алынған сыйлықты ауыстыру: сатылым тарихы нақты қалпына келуі үшін
  -- ескі позиция «қайтару» (теріс), жаңасы «сату» болып жазылады.
  if v_completed then
    select coalesce(name, '') into v_staff from public.users where id = auth.uid();
    select bc.purchase_price into v_cost_old from public.batch_costs bc where bc.batch_id = v_old_batch;
    select bc.purchase_price into v_cost_new from public.batch_costs bc where bc.batch_id = v_b.id;
    insert into public.sales_history (
      owner_uid, product_id, batch_id, product_name, sale_date, sizes_sold,
      selected_size, quantity, base_price, total_price, discount_amount,
      purchase_price, seller_id, seller_name, warehouse_id, is_online, order_id,
      delivered_by_name, payment_method, receipt_number, type)
    values
      (o.admin_uid, v_old_pid, v_old_batch, coalesce(v_item ->> 'productName', ''), now(),
       jsonb_build_object(v_old_size, 1), v_old_size, 1,
       -v_old_price, -v_old_price, 0,
       coalesce(v_cost_old, 0), 'онлайн', 'Онлайн',
       nullif(v_item ->> 'warehouseId', '')::uuid, true, o.id::text,
       coalesce(v_staff, ''), 'exchange', coalesce(o.receipt_number, ''), 'return'),
      (o.admin_uid, v_prod.id, v_b.id, coalesce(v_prod.name, ''), now(),
       jsonb_build_object(v_size, 1), v_size, 1,
       greatest(v_b.selling_price, v_price), v_price, greatest(v_b.selling_price, v_price) - v_price,
       coalesce(v_cost_new, 0), 'онлайн', 'Онлайн',
       v_b.warehouse_id, true, o.id::text,
       coalesce(v_staff, ''), 'exchange', coalesce(o.receipt_number, ''), 'sale');
  end if;

  if v_old_pid is not null then perform public.recompute_product_status(v_old_pid); end if;
  if v_old_pid is distinct from v_prod.id then perform public.recompute_product_status(v_prod.id); end if;

  return o;
end;
$$;
revoke all on function public.gift_apply_item(uuid, uuid, text, text, text) from public, anon, authenticated;

-- ── 7а. claim_gift ─────────────────────────────────────────────────────────
--  p_product — басқа тауар (сол дүкеннен), null = сыйлықтың өз тауары.
--  p_alt_size — курьер примеркасына екінші өлшем (міндетті емес).
drop function if exists public.claim_gift(uuid, text, text, text, text);
-- қайтару түрі orders → jsonb (тазартылған) болып өзгерді — қайта іске қосқанда
drop function if exists public.claim_gift(uuid, text, text, text, text, uuid, text);

create or replace function public.claim_gift(
  p_token    uuid,
  p_size     text,
  p_address  text,
  p_city     text,
  p_phone    text,
  p_product  uuid default null,
  p_alt_size text default null
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid      uuid := auth.uid();
  o          public.orders;
  v_client   public.clients;
  v_store    public.stores;
  v_item     jsonb;
  v_old_pid  uuid;
  v_old_size text;
  v_pid      uuid;
  v_size     text := trim(coalesce(p_size, ''));
  v_courier  boolean;
  v_rname    text;
  v_phone    text := left(trim(coalesce(p_phone, '')), 30);
  v_staff    uuid[];
  v_pname    text;
  v_alt_now  text;
  v_title    text;
  v_body     text;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;
  select * into v_client from public.clients where id = v_uid;
  if not found then raise exception 'not_a_client'; end if;

  select * into o from public.orders where gift_token = p_token and is_gift for update;
  if not found then raise exception 'gift_not_found'; end if;
  if o.client_uid = v_uid then raise exception 'gift_self_claim'; end if;
  if o.gift_claimed_at is not null then raise exception 'gift_already_claimed'; end if;
  if o.status in ('cancelled', 'returned') then raise exception 'gift_cancelled'; end if;
  -- иесі растаған төлем ғана (payment_confirmed_by-ді клиент жаза алмайды)
  if o.status <> 'confirmed' or coalesce(o.payment_confirmed_by, '') = '' then
    raise exception 'gift_not_paid';
  end if;
  if o.gift_expires_at is not null and o.gift_expires_at < now() then
    raise exception 'gift_expired';
  end if;
  if v_size = '' then raise exception 'gift_size_required'; end if;
  if length(regexp_replace(v_phone, '\D', '', 'g')) < 7 then
    raise exception 'gift_phone_required';
  end if;

  select * into v_store from public.stores where admin_uid = o.admin_uid;
  if not found or not coalesce(v_store.is_published, false) or v_store.status = 'blocked' then
    raise exception 'store_unavailable';
  end if;

  v_courier := (o.order_type = 'delivery' and coalesce(o.delivery_mode, 'courier') = 'courier');
  if v_courier then
    if length(trim(coalesce(p_address, ''))) < 4 then raise exception 'gift_address_required'; end if;
    if lower(trim(coalesce(p_city, ''))) <> lower(trim(coalesce(v_store.city, '')))
       or not public.courier_city_enabled(v_store.city) then
      raise exception 'gift_city_unsupported';
    end if;
  elsif trim(coalesce(p_alt_size, '')) <> '' then
    raise exception 'gift_fitting_unavailable';
  end if;

  v_item     := coalesce(o.items -> 0, '{}'::jsonb);
  v_old_pid  := nullif(v_item ->> 'productId', '')::uuid;
  v_old_size := coalesce(v_item ->> 'size', '');
  v_pid      := coalesce(p_product, v_old_pid);
  if v_pid is null then raise exception 'gift_not_found'; end if;

  -- Қойма/баға/позиция — бір ғана көзде (бір транзакция, for update)
  o := public.gift_apply_item(o.id, v_pid, v_size, p_alt_size, 'recipient');

  v_item    := coalesce(o.items -> 0, '{}'::jsonb);
  v_pname   := coalesce(v_item ->> 'productName', '');
  v_alt_now := coalesce(v_item ->> 'altSize', '');
  v_rname   := coalesce(nullif(trim(o.gift_recipient_name), ''), nullif(trim(v_client.name), ''), '');

  perform set_config('qoima.gift_rpc', 'on', true);
  update public.orders set
    address = case when v_courier then trim(p_address) else '' end,
    client_city = left(trim(coalesce(p_city, '')), 80),
    -- дүкенге/курьерге ТАПСЫРАТЫН адамның байланысы (сыйлаушы gift_giver_name-де)
    client_name = case when v_rname <> '' then v_rname else client_name end,
    client_phone = v_phone,
    gift_recipient_uid = v_uid,
    gift_recipient_name = v_rname,
    gift_recipient_phone = v_phone,
    gift_claimed_at = now(),
    stock_restored = false
  where id = o.id
  returning * into o;
  perform set_config('qoima.gift_rpc', 'off', true);

  -- Дүкен иесі + сатушылар (on_order_push-пен бірдей алушылар). Алушы өлшемді
  -- немесе тауарды ауыстырса — тақырыпта айтылады, қосымша төлем де көрсетіледі.
  v_title := case
    when v_pid is distinct from v_old_pid
      then '🎁 Подарок: выбран другой товар / Сыйлық: басқа тауар таңдалды'
    when v_old_size <> '' and v_old_size <> v_size
      then '🎁 Подарок: размер изменён / Сыйлық: өлшем ауыстырылды'
    else '🎁 Подарок: размер выбран / Сыйлық: өлшем таңдалды' end;
  v_body := '№' || o.order_number || ' · ' || v_pname || ' · ' || v_size
    || case when v_alt_now <> '' then ' (+' || v_alt_now || ' примерка/өлшеп көру)' else '' end
    || case when coalesce(o.gift_extra_due, 0) > 0
            then ' · доплата/қосымша ' || round(o.gift_extra_due)::bigint || ' ₸' else '' end;
  select array_agg(id) into v_staff
    from public.users
   where id = o.admin_uid or (owner_id = o.admin_uid and role = 'seller');
  perform public.notify_push(
    coalesce(v_staff, array[o.admin_uid]), v_title, v_body,
    jsonb_build_object('type', 'order', 'orderId', o.id));
  -- Сыйлаушыға
  perform public.notify_push(
    array[o.client_uid],
    '🎁 Подарок принят / Сыйлығыңыз қабылданды',
    coalesce(nullif(v_rname, ''), 'Получатель') || ' — ' || v_size,
    jsonb_build_object('type', 'gift_claimed', 'orderId', o.id));

  -- Курьерлерге: on_courier_job_push статус өзгермегендіктен жанбайды, сондықтан осында.
  if v_courier then
    declare v_couriers uuid[];
    begin
      select array_agg(u.id) into v_couriers from public.users u
       where u.role = 'courier' and u.courier_status = 'active'
         and coalesce(u.blocked, false) = false and u.city = v_store.city;
      if v_couriers is not null then
        perform public.notify_push(
          v_couriers,
          '🚚 Новый заказ / Жаңа тапсырыс',
          coalesce(nullif(v_store.city, ''), '') || ' · '
            || coalesce(o.delivery_fee, 0)::int || ' ₸ · '
            || coalesce(nullif(o.store_name, ''), 'магазин'),
          jsonb_build_object('type', 'courier_work', 'orderId', o.id));
      end if;
    end;
  end if;

  -- Алушыға шикі жол емес, тазартылған көрініс (жасырын баға, чек, карта жоқ)
  return public.gift_recipient_view(o);
end;
$$;
revoke all on function public.claim_gift(uuid, text, text, text, text, uuid, text) from public, anon;
grant execute on function public.claim_gift(uuid, text, text, text, text, uuid, text) to authenticated;

-- ── 7б. gift_store_exchange — дүкен кассадағы ауыстыру ─────────────────────
--  Тек сол дүкеннің қызметкері (app_owner_uid()) / superadmin. Рұқсат:
--   • дүкеннен алатын сыйлық, алушы растаған, әлі берілмеген (confirmed/ready) —
--     өлшеп көрді, келмеді / ойы өзгерді;
--   • АЛЫНҒАН сыйлық (кез келген жеткізу) — completed_at-тан 14 күн ішінде
--     (OrderModel.returnWindow). Сыйлық ақшалай қайтарылмайды — тек ауыстыру.
create or replace function public.gift_store_exchange(
  p_order   uuid,
  p_product uuid,
  p_size    text
) returns public.orders
language plpgsql security definer set search_path = public as $$
declare
  o public.orders;
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  select * into o from public.orders where id = p_order for update;
  if not found then raise exception 'order_not_found'; end if;
  if not o.is_gift then raise exception 'not_a_gift'; end if;
  -- coalesce: клиентте app_owner_uid() = NULL → `not (NULL or false)` = NULL
  -- болып, тексеріс өтіп кетер еді (кез келген клиент ауыстыра алатын).
  if not coalesce(o.admin_uid = public.app_owner_uid(), false)
     and not coalesce(public.is_superadmin(), false) then
    raise exception 'not_your_order';
  end if;
  if o.gift_claimed_at is null then raise exception 'gift_not_claimed'; end if;

  if o.status in ('confirmed', 'ready') then
    -- берілгенге дейін тек дүкеннен алатын сыйлық (курьерде тауар жолда болуы мүмкін)
    if o.order_type = 'delivery' or o.courier_uid is not null then
      raise exception 'gift_exchange_courier';
    end if;
  elsif o.status = 'completed' then
    if coalesce(o.completed_at, o.created_at) + interval '14 days' < now() then
      raise exception 'gift_exchange_expired';
    end if;
    -- Беру есебі (sales_history «сату») әлі жазылмаса — беру жүріп жатыр
    -- (_completeOrder статусты алдымен, сатылымды кейін жазады). Сол аралықта
    -- ауыстырсақ, ескі тауар «қайтарылып», жаңасы екі рет сатылған болып жазылар еді.
    if not exists (select 1 from public.sales_history sh
                    where sh.order_id = o.id::text and sh.type = 'sale') then
      raise exception 'gift_handover_in_progress';
    end if;
  else
    raise exception 'gift_exchange_closed';
  end if;

  if p_product is null or trim(coalesce(p_size, '')) = '' then
    raise exception 'gift_size_required';
  end if;

  return public.gift_apply_item(o.id, p_product, p_size, null, 'store');
end;
$$;
revoke all on function public.gift_store_exchange(uuid, uuid, text) from public, anon;
grant execute on function public.gift_store_exchange(uuid, uuid, text) to authenticated;

-- ── 8. Курьер қоймасынан расталмаған сыйлықты жасыру ──────────────────────
--  Тірі анықтамалар (2026-10) дәл көшірілді + бір шарт:
--  `not (is_gift and gift_claimed_at is null)`.
create or replace function public.courier_available_orders()
 returns setof orders
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select o.* from public.orders o
    join public.stores s on s.admin_uid = o.admin_uid
   where o.order_type = 'delivery'
     and o.status = 'confirmed'
     and o.courier_uid is null
     and coalesce(o.delivery_mode, 'courier') = 'courier'
     and not (o.is_gift and o.gift_claimed_at is null)
     and public.active_courier_city() is not null
     and s.city = public.active_courier_city()
   order by o.cart_group_id nulls last, o.created_at;
$function$;

create or replace function public.courier_take_order(p_order uuid)
 returns orders
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_order public.orders;
  v_city  text := public.active_courier_city();
  v_name  text;
begin
  if v_city is null then raise exception 'not_active_courier'; end if;
  select name into v_name from public.users where id = auth.uid();

  select * into v_order from public.orders where id = p_order for update;
  if not found then raise exception 'order_not_found'; end if;
  if v_order.order_type <> 'delivery' or v_order.status <> 'confirmed' then
    raise exception 'order_state_changed:%', v_order.status;
  end if;
  if coalesce(v_order.delivery_mode, 'courier') <> 'courier' then
    raise exception 'store_delivers_itself';
  end if;
  if v_order.is_gift and v_order.gift_claimed_at is null then
    raise exception 'gift_not_claimed';
  end if;
  if v_order.courier_uid is not null then raise exception 'order_already_taken'; end if;
  if not exists (select 1 from public.stores
                  where admin_uid = v_order.admin_uid and city = v_city) then
    raise exception 'other_city';
  end if;

  update public.orders set
    courier_uid = auth.uid(),
    courier_name = coalesce(v_name, ''),
    courier_status = 'assigned',
    courier_taken_at = now()
  where id = p_order returning * into v_order;

  perform public.notify_push(
    array[v_order.admin_uid],
    'Курьер назначен / Курьер тағайындалды',
    coalesce(v_name, '') || ' — №' || v_order.order_number,
    jsonb_build_object('type', 'courier_assigned', 'orderId', v_order.id));
  return v_order;
end;
$function$;

create or replace function public.courier_take_group(p_group uuid)
 returns integer
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_city  text := public.active_courier_city();
  v_name  text;
  v_row   public.orders;
  v_taken int := 0;
begin
  if v_city is null then raise exception 'not_active_courier'; end if;
  select name into v_name from public.users where id = auth.uid();

  for v_row in
    select o.* from public.orders o
      join public.stores s on s.admin_uid = o.admin_uid
     where o.cart_group_id = p_group
       and o.order_type = 'delivery'
       and o.status = 'confirmed'
       and o.courier_uid is null
       and coalesce(o.delivery_mode, 'courier') = 'courier'
       and not (o.is_gift and o.gift_claimed_at is null)
       and s.city = v_city
     order by o.created_at
     for update of o
  loop
    update public.orders set
      courier_uid      = auth.uid(),
      courier_name     = coalesce(v_name, ''),
      courier_status   = 'assigned',
      courier_taken_at = now()
    where id = v_row.id;
    v_taken := v_taken + 1;

    perform public.notify_push(
      array[v_row.admin_uid],
      'Курьер назначен / Курьер тағайындалды',
      coalesce(v_name, '') || ' — №' || v_row.order_number,
      jsonb_build_object('type', 'courier_assigned', 'orderId', v_row.id));
  end loop;

  if v_taken = 0 then raise exception 'group_already_taken'; end if;
  return v_taken;
end;
$function$;

create or replace function public.on_courier_job_push()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_city text;
  v_uids uuid[];
begin
  if new.status is not distinct from old.status then return new; end if;
  if new.status <> 'confirmed' then return new; end if;
  if new.order_type <> 'delivery' then return new; end if;
  if coalesce(new.delivery_mode, 'courier') <> 'courier' then return new; end if;
  if new.courier_uid is not null then return new; end if;
  -- Расталмаған сыйлық: мекенжай жоқ, курьер әлі керек емес (claim_gift жібереді)
  if new.is_gift and new.gift_claimed_at is null then return new; end if;

  select s.city into v_city from public.stores s where s.admin_uid = new.admin_uid;
  if not public.courier_city_enabled(v_city) then return new; end if;

  select array_agg(u.id) into v_uids from public.users u
   where u.role = 'courier' and u.courier_status = 'active'
     and coalesce(u.blocked, false) = false and u.city = v_city;
  if v_uids is null then return new; end if;

  perform public.notify_push(
    v_uids,
    '🚚 Новый заказ / Жаңа тапсырыс',
    coalesce(nullif(v_city, ''), '') || ' · '
      || coalesce(new.delivery_fee, 0)::int || ' ₸ · '
      || coalesce(nullif(new.store_name, ''), 'магазин'),
    jsonb_build_object('type', 'courier_work', 'orderId', new.id));
  return new;
end;
$function$;

-- create or replace PUBLIC грантын қайта тудыруы мүмкін → қайта revoke (CLAUDE.md).
-- Курьер RPC-лері тек кірген қолданушыға (auth.uid() ішінде тексеріледі).
-- (Supabase әдепкі привилегиясы anon-ға да ЕРЕКШЕ грант береді → public + anon екеуі де алынады)
revoke all on function public.courier_available_orders() from public, anon;
revoke all on function public.courier_take_order(uuid) from public, anon;
revoke all on function public.courier_take_group(uuid) from public, anon;
revoke all on function public.on_courier_job_push() from public, anon, authenticated;
grant execute on function public.courier_available_orders() to authenticated;
grant execute on function public.courier_take_order(uuid) to authenticated;
grant execute on function public.courier_take_group(uuid) to authenticated;

-- ── 8а. release_fitting_holds: сыйлаушы алушының примеркасын босата алмайды ──
--  Тірі анықтама (2026-10) дәл көшірілді + бір шарт: алынған сыйлықта client_uid —
--  сыйлаушы, оның бұл тапсырыста рөлі жоқ. Ол қосалқы өлшемнің бронын босатса,
--  кейін courier_complete_order / store_confirm_return_leg reserved_sizes-ті
--  ЕКІНШІ рет азайтып, қалдық теріс кетер еді.
create or replace function public.release_fitting_holds(p_order uuid, p_except_index integer[] DEFAULT '{}'::integer[])
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_order public.orders;
  v_items jsonb;
  v_item  jsonb;
  v_alt   text;
  i       integer;
begin
  select * into v_order from public.orders where id = p_order;
  if not found then return; end if;

  -- coalesce: тірі нұсқада courier_uid/app_owner_uid() NULL болғанда бүкіл
  -- өрнек NULL болып, `if not NULL` тексерісі ӨТІП кететін (кез келген адам
  -- басқаның бронын босата алатын) — енді NULL = рұқсат жоқ.
  if not coalesce(
    (v_order.client_uid = auth.uid()
       and not (coalesce(v_order.is_gift, false) and v_order.gift_claimed_at is not null))
    or v_order.admin_uid = auth.uid()
    or v_order.courier_uid = auth.uid()
    or v_order.admin_uid = public.app_owner_uid()
    or public.is_superadmin(), false) then
    raise exception 'not_your_order';
  end if;

  v_items := v_order.items;
  if v_items is null then return; end if;

  for i in 0 .. jsonb_array_length(v_items) - 1 loop
    if i = any(p_except_index) then continue; end if;
    v_item := v_items -> i;
    v_alt  := coalesce(v_item ->> 'altSize', '');
    if v_alt = '' then continue; end if;
    begin
      perform public.adjust_batch_sizes(
        (v_item ->> 'batchId')::uuid,
        jsonb_build_object(v_alt, -coalesce((v_item ->> 'qty')::int, 1)),
        'reserved_sizes',
        false);
    exception when others then
      null; -- партия өшірілген болуы мүмкін — тапсырысты жабу бөгелмейді
    end;
  end loop;
end;
$function$;
revoke all on function public.release_fitting_holds(uuid, integer[]) from public, anon;
grant execute on function public.release_fitting_holds(uuid, integer[]) to authenticated;

-- ── 9. Алушыға push: тапсырыс статусы өзгергенде ──────────────────────────
--  on_order_status_push тек client_uid-ке (сыйлаушыға) жібереді; алушы да
--  «дайын / аяқталды / бас тартылды» білуі керек.
create or replace function public.on_gift_recipient_push()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_title text;
begin
  if not new.is_gift or new.gift_recipient_uid is null then return new; end if;
  if new.status is not distinct from old.status then return new; end if;
  v_title := case new.status
    when 'ready'     then '📦 Подарок готов к выдаче / Сыйлық беруге дайын'
    when 'completed' then '🎉 Подарок получен / Сыйлық тапсырылды'
    when 'cancelled' then '❌ Заказ отменён / Тапсырыс бас тартылды'
    else null end;
  if v_title is null then return new; end if;
  perform public.notify_push(
    array[new.gift_recipient_uid], v_title,
    coalesce(nullif(new.store_name, ''), 'Магазин') || ' · №' || new.order_number,
    jsonb_build_object('type', 'order_status', 'orderId', new.id, 'status', new.status,
                       'gift', 'recipient'));
  return new;
end;
$$;
revoke all on function public.on_gift_recipient_push() from public, anon, authenticated;

drop trigger if exists trg_gift_recipient_push on public.orders;
create trigger trg_gift_recipient_push
  after update on public.orders
  for each row execute function public.on_gift_recipient_push();

-- ── 10. Күнделікті еске салғыш: сыйлау мерзімі біту қарсаңында ─────────────
--  Алынбаған (расталған, бірақ алушы өлшем таңдамаған) сыйлау — мерзімі
--  бітуіне ≤3 күн қалғанда сыйлаушыға бір рет push жіберіледі.
create or replace function public.sweep_gift_reminders() returns void
language plpgsql security definer set search_path = public as $$
declare
  r record;
begin
  for r in
    select id, client_uid, order_number
      from public.orders
     where is_gift
       and gift_claimed_at is null
       and status = 'confirmed'
       and gift_reminder_sent = false
       and client_uid is not null
       and gift_expires_at is not null
       and gift_expires_at between now() and now() + interval '3 days'
  loop
    perform public.notify_push(
      array[r.client_uid],
      '🎁 Подарок ещё не получен / Сыйлық әлі алынбады',
      'Заказ №' || r.order_number ||
        ' — напомните получателю открыть ссылку / алушыға сілтемені ашуды еске салыңыз',
      jsonb_build_object('type', 'gift_reminder', 'orderId', r.id));
    update public.orders set gift_reminder_sent = true where id = r.id;
  end loop;
end;
$$;
revoke all on function public.sweep_gift_reminders() from public, anon, authenticated;

select cron.unschedule('gift-reminders')
  where exists (select 1 from cron.job where jobname = 'gift-reminders');
select cron.schedule(
  'gift-reminders',
  '0 5 * * *',
  $$select public.sweep_gift_reminders()$$
);

-- ── 11. Сыйлық = ТЕК АУЫСТЫРУ: қайтару (returns) ағыны бөгеледі ────────────
--  Клиент returns жазбасын тікелей енгізеді (RLS returns_insert — client_uid =
--  auth.uid()). Сыйлаушы (client_uid) сыйлық тапсырысына возврат ашса, ақша
--  қолданба арқылы қайтып кетер еді — сыйлық тек дүкенде ауыстырылады
--  (gift_store_exchange, 14 күн). Superadmin / service_role ғана өткізіледі.
create or replace function public.guard_return_gift()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or coalesce(public.is_superadmin(), false) then
    return new;
  end if;
  if tg_op = 'UPDATE' and new.order_id is not distinct from old.order_id then
    return new;
  end if;
  if coalesce(new.order_id, '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
     and exists (select 1 from public.orders o
                  where o.id = new.order_id::uuid and o.is_gift) then
    raise exception 'gift_exchange_only';
  end if;
  return new;
end;
$$;
revoke all on function public.guard_return_gift() from public, anon, authenticated;

drop trigger if exists trg_guard_return_gift on public.returns;
create trigger trg_guard_return_gift
  before insert or update of order_id on public.returns
  for each row execute function public.guard_return_gift();
