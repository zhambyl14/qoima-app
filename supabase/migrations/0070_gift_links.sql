-- ════════════════════════════════════════════════════════════════════════════
--  0070 · «Сыйлау» — өлшемін білмей сыйлық сатып алу + сілтеме арқылы тапсыру
-- ────────────────────────────────────────────────────────────────────────────
--  Не істейді: сыйлаушы (giver) тауарды алушының өлшемін білмей-ақ кәдімгі
--  тапсырыс сияқты төлейді де, әдемі сілтеме алады (WhatsApp/Telegram). Алушы
--  сілтемені ашып, кіріп/тіркеліп, өлшемін (курьер болса мекенжайын) таңдайды —
--  сонда тапсырыс дүкенге жалғасады.
--
--  Дизайн (жаңа кесте ЖОҚ — сыйлық = кәдімгі `orders` жолы):
--   • orders-қа gift_* бағандары қосылады (is_gift, gift_token, …).
--   • create_gift_order — тапсырысты СЕРВЕРДЕ жасайды (placeOrder емес): баға
--     batches-тен есептеледі (клиент бағасына сенбейміз), қойма әлі ұсталмайды
--     (өлшем белгісіз) → stock_restored = true болып жазылады.
--   • claim_gift — алушы өлшем таңдағанда партияны `for update` құлпымен алып,
--     қойманы бір транзакцияда азайтады, items-ті толтырады, stock_restored =
--     false қояды (енді бас тартса — қойма дұрыс қайтады).
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
--   • orders_select-ке тек `gift_recipient_uid = auth.uid()` қосылды (оқу).
--     Алушыға update құқығы берілмейді.
--   • Жаңа статус ЖОҚ: OrderModel.status* ↔ claim_order_transition ақ тізімі
--     өзгермейді.
--   • Суперадмин жалаушасы gift_links (0067b): create_gift_order өшік болса
--     'feature_disabled' береді. Төленіп қойған сыйлықты алу (claim) және
--     оқу өшік күйде де жұмыс істейді — алушының ақшасы төленген.
--   • Курьер қоймасы (courier_available_orders / courier_take_order /
--     courier_take_group / on_courier_job_push): алушы мекенжай бермей тұрып
--     сыйлық курьерге көрінбейді. Claim кезінде курьерлерге push осында жіберіледі.
--
--  Ақша: жеткізу ақысы (delivery_fee) бұрынғыдай КУРЬЕРДІКІ — дүкенге
--  аударылатын deposit_amount-қа кірмейді (0053).
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
  add column if not exists gift_reminder_sent   boolean     not null default false;

do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'orders_gift_message_len') then
    alter table public.orders
      add constraint orders_gift_message_len check (char_length(gift_message) <= 300);
  end if;
end $$;

create unique index if not exists orders_gift_token_uidx
  on public.orders (gift_token) where gift_token is not null;
create index if not exists orders_gift_recipient_idx
  on public.orders (gift_recipient_uid) where gift_recipient_uid is not null;
create index if not exists orders_gift_expiry_idx
  on public.orders (gift_expires_at) where is_gift and gift_claimed_at is null;

-- ── 2. orders_select: алушы оқи алады (өзгерту құқығы ЖОҚ) ─────────────────
--  Тірі анықтама (pg_policies): (client_uid = auth.uid()) OR
--  (admin_uid = app_owner_uid()) OR is_superadmin() — дәл сол + бір тармақ.
drop policy if exists orders_select on public.orders;
create policy orders_select on public.orders for select using (
  client_uid = auth.uid()
  or admin_uid = public.app_owner_uid()
  or public.is_superadmin()
  or gift_recipient_uid = auth.uid()
);

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
       or new.gift_giver_name is distinct from old.gift_giver_name then
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
create or replace function public.create_gift_order(
  p_product        uuid,
  p_delivery_mode  text,
  p_recipient_name text,
  p_message        text,
  p_hide_price     boolean
) returns public.orders
language plpgsql security definer set search_path = public as $$
declare
  v_uid     uuid := auth.uid();
  v_client  public.clients;
  v_prod    public.products;
  v_store   public.stores;
  v_price   double precision;
  v_orig    double precision := 0;
  v_fee     double precision := 0;
  v_base    double precision;
  v_reduced double precision;
  v_from    double precision;
  v_courier boolean := (p_delivery_mode = 'courier');
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

  -- Баға = қолда бары бар партиялардағы ЕҢ ЖОҒАРЫ тиімді баға: өлшем белгісіз,
  -- сондықтан кез келген өлшемге жетуі керек. Клиент бағасына сенбейміз.
  select max(public.batch_effective_price(b.selling_price, b.discount))
    into v_price
    from public.batches b
   where b.product_id = v_prod.id
     and b.warehouse_id = any (coalesce(v_store.visible_warehouse_ids, '{}'::uuid[]))
     and public.batch_available_qty(b.sizes_quantity, b.reserved_sizes) > 0;
  if v_price is null then raise exception 'gift_out_of_stock'; end if;
  if v_price <= 0 then raise exception 'price_invalid'; end if;

  -- «Бастапқы баға» (сызылған): осы бағаны берген партияның жеңілдіксіз бағасы.
  select b.selling_price into v_orig
    from public.batches b
   where b.product_id = v_prod.id
     and b.warehouse_id = any (coalesce(v_store.visible_warehouse_ids, '{}'::uuid[]))
     and public.batch_available_qty(b.sizes_quantity, b.reserved_sizes) > 0
     and public.batch_effective_price(b.selling_price, b.discount) = v_price
   order by b.selling_price desc limit 1;
  if v_orig is null or v_orig <= v_price then v_orig := 0; end if;

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
  end if;

  v_item := jsonb_build_object(
    'productId', v_prod.id, 'productName', v_prod.name,
    'batchId', '', 'size', '', 'qty', 1,
    'price', v_price, 'originalPrice', v_orig,
    'adminUid', v_store.admin_uid, 'storeName', coalesce(v_store.store_name, ''),
    'imageUrl', coalesce(v_prod.images[1], ''),
    'warehouseId', '', 'warehouseAddress', '', 'selected', true);
  if coalesce(v_prod.brand, '') <> '' then v_item := v_item || jsonb_build_object('brand', v_prod.brand); end if;
  if coalesce(v_prod.type, '') <> '' then v_item := v_item || jsonb_build_object('type', v_prod.type); end if;
  if coalesce(v_prod.color, '') <> '' then v_item := v_item || jsonb_build_object('color', v_prod.color); end if;
  if coalesce(v_prod.variant_note, '') <> '' then v_item := v_item || jsonb_build_object('variantNote', v_prod.variant_note); end if;
  if coalesce(v_prod.articul, '') <> '' then v_item := v_item || jsonb_build_object('articul', v_prod.articul); end if;

  v_num := public.next_counter(v_store.admin_uid, 'orders');

  perform set_config('qoima.gift_rpc', 'on', true);
  insert into public.orders (
    admin_uid, client_uid, client_phone, client_name, store_name, store_phone,
    items, status, order_type, delivery_mode, deposit_amount, delivery_fee,
    pickup_code, order_number, seller_id, seller_name, deadline_at,
    stock_restored, payment_card_number, payment_card_holder, payment_bank,
    is_gift, gift_token, gift_recipient_name, gift_message, gift_hide_price,
    gift_expires_at, gift_giver_name
  ) values (
    v_store.admin_uid, v_uid, coalesce(v_client.phone, ''), coalesce(v_client.name, ''),
    coalesce(v_store.store_name, ''), coalesce(v_store.phone, ''),
    jsonb_build_array(v_item), 'pending',
    case when v_courier then 'delivery' else 'click_collect' end,
    case when v_courier then 'courier' else 'store' end,
    v_price, v_fee,
    lpad((('x' || substr(md5(gen_random_uuid()::text), 1, 7))::bit(28)::int % 1000000)::text, 6, '0'),
    v_num::int, 'онлайн', 'Онлайн', now() + interval '30 minutes',
    true,
    coalesce(v_store.payment_card_number, ''), coalesce(v_store.payment_card_holder, ''),
    coalesce(v_store.payment_bank, ''),
    true, gen_random_uuid(),
    left(trim(coalesce(p_recipient_name, '')), 60),
    left(trim(coalesce(p_message, '')), 300),
    coalesce(p_hide_price, false),
    now() + interval '30 days',
    left(trim(coalesce(v_client.name, '')), 60)
  ) returning * into v_order;
  perform set_config('qoima.gift_rpc', 'off', true);

  return v_order;
end;
$$;
revoke all on function public.create_gift_order(uuid, text, text, text, boolean) from public, anon;
grant execute on function public.create_gift_order(uuid, text, text, text, boolean) to authenticated;

-- ── 6. get_gift_public ─────────────────────────────────────────────────────
--  ӘДЕЙІ ПУБЛИКТІК (anon + authenticated): сілтемені ашқан қонақ (әлі тіркелмеген
--  алушы да) сыйлықты көруі керек. Қорғаныс — токеннің өзі (болжанбайтын uuid,
--  токенсіз тізім/іздеу жоқ). Тек сыйлау парағына қажет өрістер қайтады:
--  сыйлаушының ТЕК аты, телефон/мекенжай/чек жоқ. Баға жасырылса — сыйлаушыға ғана.
create or replace function public.get_gift_public(p_token uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_uid    uuid := auth.uid();
  o        public.orders;
  v_store  public.stores;
  v_prod   public.products;
  v_item   jsonb;
  v_status text;
  v_sizes  jsonb := '[]'::jsonb;
  v_giver  boolean;
  v_recip  boolean;
  v_price  double precision;
begin
  select * into o from public.orders where gift_token = p_token and is_gift;
  if not found then return null; end if;

  v_item := o.items -> 0;
  v_giver := v_uid is not null and o.client_uid = v_uid;
  v_recip := v_uid is not null and o.gift_recipient_uid = v_uid;
  select * into v_store from public.stores where admin_uid = o.admin_uid;
  select * into v_prod from public.products
   where id = nullif(v_item ->> 'productId', '')::uuid;

  v_status := case
    when o.status in ('cancelled', 'returned') then 'cancelled'
    when o.gift_claimed_at is not null then 'claimed'
    when o.status = 'confirmed' and o.gift_expires_at is not null
         and o.gift_expires_at < now() then 'expired'
    when o.status = 'confirmed' then 'ready_to_claim'
    else 'awaiting_payment'
  end;

  if v_status = 'ready_to_claim' then
    v_price := coalesce((v_item ->> 'price')::double precision, 0);
    select coalesce(jsonb_agg(q.k), '[]'::jsonb) into v_sizes
      from (
        select distinct kv.key as k
          from public.batches b,
               jsonb_each_text(b.sizes_quantity) kv
         where b.product_id = v_prod.id
           and b.warehouse_id = any (coalesce(v_store.visible_warehouse_ids, '{}'::uuid[]))
           and kv.value::int - coalesce((b.reserved_sizes ->> kv.key)::int, 0) > 0
           and public.batch_effective_price(b.selling_price, b.discount) <= v_price
      ) q;
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

-- ── 7. claim_gift ──────────────────────────────────────────────────────────
create or replace function public.claim_gift(
  p_token   uuid,
  p_size    text,
  p_address text,
  p_city    text,
  p_phone   text
) returns public.orders
language plpgsql security definer set search_path = public as $$
declare
  v_uid     uuid := auth.uid();
  o         public.orders;
  v_client  public.clients;
  v_store   public.stores;
  v_item    jsonb;
  v_pid     uuid;
  v_paid    double precision;
  v_size    text := trim(coalesce(p_size, ''));
  v_courier boolean;
  v_b       public.batches;
  v_wh_addr text := '';
  v_rname   text;
  v_phone   text := left(trim(coalesce(p_phone, '')), 30);
  v_staff   uuid[];
  v_pname   text;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;
  select * into v_client from public.clients where id = v_uid;
  if not found then raise exception 'not_a_client'; end if;

  select * into o from public.orders where gift_token = p_token and is_gift for update;
  if not found then raise exception 'gift_not_found'; end if;
  if o.client_uid = v_uid then raise exception 'gift_self_claim'; end if;
  if o.gift_claimed_at is not null then raise exception 'gift_already_claimed'; end if;
  if o.status in ('cancelled', 'returned') then raise exception 'gift_cancelled'; end if;
  if o.status <> 'confirmed' then raise exception 'gift_not_paid'; end if;
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
  end if;

  v_item := o.items -> 0;
  v_pid := (v_item ->> 'productId')::uuid;
  v_paid := coalesce((v_item ->> 'price')::double precision, 0);
  v_pname := coalesce(v_item ->> 'productName', '');

  -- Ең арзан сәйкес партия (төленген бағадан қымбат емес), қатарды құлыптаймыз.
  select b.* into v_b
    from public.batches b
   where b.product_id = v_pid
     and b.warehouse_id = any (coalesce(v_store.visible_warehouse_ids, '{}'::uuid[]))
     and coalesce((b.sizes_quantity ->> v_size)::int, 0)
         - coalesce((b.reserved_sizes ->> v_size)::int, 0) > 0
     and public.batch_effective_price(b.selling_price, b.discount) <= v_paid
   order by public.batch_effective_price(b.selling_price, b.discount), b.date_arrived
   limit 1
   for update of b;
  if not found then raise exception 'gift_size_unavailable'; end if;

  -- Құлыптан кейін қайта тексеру (қатар сатып алу болуы мүмкін).
  if coalesce((v_b.sizes_quantity ->> v_size)::int, 0)
     - coalesce((v_b.reserved_sizes ->> v_size)::int, 0) < 1 then
    raise exception 'gift_size_unavailable';
  end if;

  update public.batches
     set sizes_quantity = jsonb_set(sizes_quantity, array[v_size],
           to_jsonb(coalesce((sizes_quantity ->> v_size)::int, 0) - 1))
   where id = v_b.id;

  select coalesce(w.address, '') into v_wh_addr
    from public.warehouses w where w.id = v_b.warehouse_id;
  v_wh_addr := coalesce(v_wh_addr, '');

  v_rname := coalesce(nullif(trim(o.gift_recipient_name), ''), nullif(trim(v_client.name), ''), '');

  perform set_config('qoima.gift_rpc', 'on', true);
  update public.orders set
    items = jsonb_build_array(v_item || jsonb_build_object(
              'size', v_size, 'batchId', v_b.id,
              'warehouseId', v_b.warehouse_id, 'warehouseAddress', v_wh_addr)),
    warehouse_id = v_b.warehouse_id,
    warehouse_address = v_wh_addr,
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

  perform public.recompute_product_status(v_pid);

  -- Дүкен иесі + сатушылар (on_order_push-пен бірдей алушылар)
  select array_agg(id) into v_staff
    from public.users
   where id = o.admin_uid or (owner_id = o.admin_uid and role = 'seller');
  perform public.notify_push(
    coalesce(v_staff, array[o.admin_uid]),
    '🎁 Подарок: размер выбран / Сыйлық: өлшем таңдалды',
    '№' || o.order_number || ' · ' || v_pname || ' · ' || v_size,
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

  return o;
end;
$$;
revoke all on function public.claim_gift(uuid, text, text, text, text) from public, anon;
grant execute on function public.claim_gift(uuid, text, text, text, text) to authenticated;

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
    jsonb_build_object('type', 'order_status', 'orderId', new.id, 'status', new.status));
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
