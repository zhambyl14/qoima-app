-- ════════════════════════════════════════════════════════════════════════════
--  0051 · Курьер рөлі — жеткізуді платформа өзі орындайды
-- ────────────────────────────────────────────────────────────────────────────
--  Курьер ТІКЕЛЕЙ superadmin-ға бағынады (дүкенге емес): ол бір қалада бірнеше
--  дүкеннің тапсырысын алып жүреді. Сондықтан оның деректері users кестесінде
--  owner_id = null болып тұрады, ал модерация app-та superadmin арқылы.
--
--  ЖОЛЫ:  тіркеледі (pending) → superadmin бекітеді (active)
--         → «Алам» (assigned) → қоймадан pickup_code-пен алады (picked_up)
--         → клиентке береді (delivered → тапсырыс completed)
--
--  RLS ЕМЕС, RPC. Курьер бөтен дүкеннің тапсырысын көреді — оны policy-мен
--  сипаттау қалалар бойынша JOIN талап етеді әрі оңай тесіледі. 0006-дағы
--  seller-join идиомасын қайталаймыз: бәрі SECURITY DEFINER RPC, әр функция
--  шақырушының курьер әрі 'active' екенін өзі тексереді.
-- ════════════════════════════════════════════════════════════════════════════

-- ── 1) users: қала + курьер модерация күйі ───────────────────────────────────
alter table public.users
  add column if not exists city           text not null default '',
  add column if not exists courier_status text not null default '';

create index if not exists users_courier_idx
  on public.users(role, courier_status) where role = 'courier';

-- ── 2) Тіркелу: role='courier' бұтағы (қала signUp метадеректерінен) ─────────
create or replace function public.handle_new_user()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_role  text := coalesce(new.raw_user_meta_data->>'role', 'client');
  v_name  text := coalesce(new.raw_user_meta_data->>'name', '');
  v_phone text := coalesce(new.raw_user_meta_data->>'phone', '');
  v_city  text := coalesce(new.raw_user_meta_data->>'city', '');
  v_code  text;
begin
  if v_role = 'client' then
    insert into public.clients (id, phone, email, name, city, email_verified)
    values (new.id, v_phone, coalesce(new.email, ''), v_name, v_city, true);
  elsif v_role = 'admin' then
    v_code := lpad((floor(random() * 1000000))::int::text, 6, '0');
    insert into public.users (id, name, email, phone, role, owner_id, business_code, join_status,
      subscription_started_at, subscription_until, subscription_plan)
    values (new.id, v_name, coalesce(new.email, ''), v_phone, 'admin', new.id, v_code, 'active',
      now(), now() + interval '7 days', '7 күн (тегін)');
    insert into public.business_codes (code, admin_uid) values (v_code, new.id);
  elsif v_role = 'superadmin' then
    insert into public.users (id, name, email, phone, role, owner_id, join_status)
    values (new.id, v_name, coalesce(new.email, ''), v_phone, 'superadmin', new.id, 'active');
  elsif v_role = 'courier' then
    -- Модератор бекітпейінше жұмысқа кірмейді (courier_status = 'pending').
    insert into public.users (id, name, email, phone, role, owner_id, join_status, city, courier_status)
    values (new.id, v_name, coalesce(new.email, ''), v_phone, 'courier', null, 'none', v_city, 'pending');
  else
    insert into public.users (id, name, email, phone, role, owner_id, join_status)
    values (new.id, v_name, coalesce(new.email, ''), v_phone, 'seller', null, 'none');
  end if;
  return new;
end;
$$;

-- ── 3) orders: курьер бағандары ──────────────────────────────────────────────
alter table public.orders
  add column if not exists courier_uid          uuid references auth.users(id),
  add column if not exists courier_name         text not null default '',
  -- '' | assigned | picked_up | delivered
  add column if not exists courier_status       text not null default '',
  add column if not exists courier_taken_at     timestamptz,
  add column if not exists courier_picked_up_at timestamptz;

create index if not exists orders_courier_idx
  on public.orders(courier_uid) where courier_uid is not null;

-- ── 3.1) release_fitting_holds (0050) — енді курьер де босата алады ─────────
--  0050-де courier_uid бағаны әлі болмағандықтан ол жерде тексеруге кірмеген.
create or replace function public.release_fitting_holds(
  p_order uuid,
  p_except_index integer[] default '{}'
) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_order public.orders;
  v_items jsonb;
  v_item  jsonb;
  v_alt   text;
  i       integer;
begin
  select * into v_order from public.orders where id = p_order;
  if not found then return; end if;

  if not (
    v_order.client_uid = auth.uid()
    or v_order.admin_uid = auth.uid()
    or v_order.courier_uid = auth.uid()
    or v_order.admin_uid = public.app_owner_uid()
    or public.is_superadmin()
  ) then
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
$$;
grant execute on function public.release_fitting_holds(uuid, integer[]) to authenticated;

-- ── 4) Көмекші: шақырушы белсенді курьер ме? ────────────────────────────────
create or replace function public.active_courier_city()
returns text
language sql stable security definer set search_path = public as $$
  select city from public.users
   where id = auth.uid() and role = 'courier'
     and courier_status = 'active' and coalesce(blocked, false) = false;
$$;
grant execute on function public.active_courier_city() to authenticated;

-- ── 5) Бос тапсырыстар: өз қаласындағы, төлемі расталған, әлі алынбағандар ──
create or replace function public.courier_available_orders()
returns setof public.orders
language sql stable security definer set search_path = public as $$
  select o.* from public.orders o
    join public.stores s on s.admin_uid = o.admin_uid
   where o.order_type = 'delivery'
     and o.status = 'confirmed'
     and o.courier_uid is null
     and public.active_courier_city() is not null
     and s.city = public.active_courier_city()
   order by o.created_at;
$$;
grant execute on function public.courier_available_orders() to authenticated;

-- ── 6) Менің тапсырыстарым (белсендісі алда, аяқталғаны 30 күн) ─────────────
create or replace function public.courier_my_orders()
returns setof public.orders
language sql stable security definer set search_path = public as $$
  select o.* from public.orders o
   where o.courier_uid = auth.uid()
     and (o.status = 'confirmed' or o.created_at > now() - interval '30 days')
   order by (o.status = 'confirmed') desc, o.created_at desc;
$$;
grant execute on function public.courier_my_orders() to authenticated;

-- ── 7) «Алам» — тапсырысты өзіне бекіту ─────────────────────────────────────
create or replace function public.courier_take_order(p_order uuid)
returns public.orders
language plpgsql security definer set search_path = public as $$
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
$$;
grant execute on function public.courier_take_order(uuid) to authenticated;

-- ── 8) Бас тарту (әлі қоймадан алмаған болса) ───────────────────────────────
create or replace function public.courier_drop_order(p_order uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare v_order public.orders;
begin
  select * into v_order from public.orders where id = p_order for update;
  if not found then raise exception 'order_not_found'; end if;
  if v_order.courier_uid <> auth.uid() then raise exception 'not_your_order'; end if;
  if v_order.courier_status <> 'assigned' then raise exception 'already_picked_up'; end if;

  update public.orders set
    courier_uid = null, courier_name = '', courier_status = '', courier_taken_at = null
  where id = p_order;
end;
$$;
grant execute on function public.courier_drop_order(uuid) to authenticated;

-- ── 9) Қоймадан алу — pickup_code-пен растау ────────────────────────────────
create or replace function public.courier_pickup_order(p_order uuid, p_code text)
returns public.orders
language plpgsql security definer set search_path = public as $$
declare v_order public.orders;
begin
  select * into v_order from public.orders where id = p_order for update;
  if not found then raise exception 'order_not_found'; end if;
  if v_order.courier_uid <> auth.uid() then raise exception 'not_your_order'; end if;
  if v_order.courier_status <> 'assigned' then raise exception 'wrong_courier_state'; end if;
  if upper(trim(coalesce(p_code, ''))) <> upper(trim(v_order.pickup_code)) then
    raise exception 'wrong_pickup_code';
  end if;

  update public.orders set
    courier_status = 'picked_up', courier_picked_up_at = now()
  where id = p_order returning * into v_order;

  if v_order.client_uid is not null then
    perform public.notify_push(
      array[v_order.client_uid],
      'Курьер выехал / Курьер жолға шықты',
      coalesce(v_order.store_name, '') || ' — №' || v_order.order_number,
      jsonb_build_object('type', 'courier_on_way', 'orderId', v_order.id));
  end if;
  return v_order;
end;
$$;
grant execute on function public.courier_pickup_order(uuid, text) to authenticated;

-- ── 10) Клиентке беру ───────────────────────────────────────────────────────
--  p_swaps — «өлшеп көру» бойынша АУЫСТЫРЫЛҒАН позициялардың индекстері
--  (items массивіндегі орны). Мысалы клиент 38-ді емес 39-ды алса → [0].
--  Ауысқан позицияда: негізгі өлшем қоймаға ҚАЙТАДЫ, altSize броньнан
--  сатылымға айналады. Бағасы бірдей (сол тауар, сол партия) — ақша қозғалмайды.
create or replace function public.courier_complete_order(
  p_order uuid,
  p_swaps integer[] default '{}'
) returns public.orders
language plpgsql security definer set search_path = public as $$
declare
  v_order   public.orders;
  v_items   jsonb;
  v_item    jsonb;
  v_alt     text;
  v_qty     int;
  v_receipt text;
  v_factor  numeric := 1;
  v_total   numeric := 0;
  v_name    text;
  i         integer;
begin
  select name into v_name from public.users where id = auth.uid();

  select * into v_order from public.orders where id = p_order for update;
  if not found then raise exception 'order_not_found'; end if;
  if v_order.courier_uid <> auth.uid() then raise exception 'not_your_order'; end if;
  if v_order.courier_status <> 'picked_up' then raise exception 'wrong_courier_state'; end if;
  if v_order.status <> 'confirmed' then
    raise exception 'order_state_changed:%', v_order.status;
  end if;

  v_items := v_order.items;

  -- ── Своптар: негізгі өлшем қоймаға, alt броньнан сатылымға ────────────────
  foreach i in array coalesce(p_swaps, '{}'::integer[]) loop
    if i < 0 or i >= jsonb_array_length(v_items) then continue; end if;
    v_item := v_items -> i;
    v_alt  := coalesce(v_item ->> 'altSize', '');
    if v_alt = '' then continue; end if;
    v_qty  := coalesce((v_item ->> 'qty')::int, 1);

    -- негізгі өлшем қайта қоймаға
    perform public.adjust_batch_sizes((v_item ->> 'batchId')::uuid,
      jsonb_build_object(v_item ->> 'size', v_qty), 'sizes_quantity', false);
    -- alt: броньнан шығып, қоймадан сатылады
    perform public.adjust_batch_sizes((v_item ->> 'batchId')::uuid,
      jsonb_build_object(v_alt, -v_qty), 'reserved_sizes', false);
    perform public.adjust_batch_sizes((v_item ->> 'batchId')::uuid,
      jsonb_build_object(v_alt, -v_qty), 'sizes_quantity', false);

    v_items := jsonb_set(v_items, array[i::text],
      (v_item - 'altSize')
        || jsonb_build_object('size', v_alt, 'swappedFrom', v_item ->> 'size'));
  end loop;

  -- Ауыспаған позициялардың «өлшеп көру» броні босайды.
  update public.orders set items = v_items where id = p_order;
  perform public.release_fitting_holds(p_order, coalesce(p_swaps, '{}'::integer[]));

  v_receipt := case when v_order.order_number > 0
    then '#' || lpad(v_order.order_number::text, 5, '0')
    else '#' || lpad(public.next_counter(v_order.admin_uid, 'receipts')::text, 5, '0') end;

  update public.orders set
    status = 'completed',
    courier_status = 'delivered',
    delivered_by_uid = auth.uid()::text,
    delivered_by_name = coalesce(v_name, ''),
    receipt_number = v_receipt,
    deadline_at = null
  where id = p_order returning * into v_order;

  -- ── sales_history (Dart _completeOrder-мен бірдей пішім) ──────────────────
  select coalesce(sum((it ->> 'price')::numeric * coalesce((it ->> 'qty')::int, 1)), 0)
    into v_total from jsonb_array_elements(v_items) it;
  if v_total > 0 then
    v_factor := greatest(v_total - coalesce(v_order.promo_discount, 0), 0) / v_total;
  end if;

  insert into public.sales_history (
    owner_uid, product_id, batch_id, product_name, sale_date, sizes_sold,
    selected_size, quantity, base_price, total_price, discount_amount,
    purchase_price, seller_id, seller_name, warehouse_id, is_online, order_id,
    delivered_by_name, payment_method, receipt_number, type)
  select
    v_order.admin_uid,
    (it ->> 'productId')::uuid,
    (it ->> 'batchId')::uuid,
    coalesce(it ->> 'productName', ''),
    now(),
    jsonb_build_object(it ->> 'size', coalesce((it ->> 'qty')::int, 1)),
    coalesce(it ->> 'size', ''),
    coalesce((it ->> 'qty')::int, 1),
    coalesce(nullif((it ->> 'originalPrice')::numeric, 0), (it ->> 'price')::numeric)
      * coalesce((it ->> 'qty')::int, 1),
    (it ->> 'price')::numeric * coalesce((it ->> 'qty')::int, 1) * v_factor,
    coalesce(nullif((it ->> 'originalPrice')::numeric, 0), (it ->> 'price')::numeric)
      * coalesce((it ->> 'qty')::int, 1)
      - (it ->> 'price')::numeric * coalesce((it ->> 'qty')::int, 1) * v_factor,
    coalesce((select bc.purchase_price from public.batch_costs bc
               where bc.batch_id = (it ->> 'batchId')::uuid), 0),
    'онлайн', 'Онлайн',
    v_order.warehouse_id,
    true,
    v_order.id::text,
    coalesce(v_name, ''),
    case when coalesce(v_order.payment_bank, '') <> '' then v_order.payment_bank else 'card' end,
    v_receipt,
    'sale'
  from jsonb_array_elements(v_items) it;

  perform public.recompute_product_status(q.pid)
    from (select distinct (it ->> 'productId')::uuid as pid
            from jsonb_array_elements(v_items) it) q;

  return v_order;
end;
$$;
grant execute on function public.courier_complete_order(uuid, integer[]) to authenticated;

-- ── 11) Клиент бас тартты — тауар қоймаға оралады ───────────────────────────
--  Жеткізу ақысы ҚАЙТАРЫЛМАЙДЫ (клиент себетте келіскен) — жол шығыны
--  жабылуы керек. Ақшаны модератор қолмен қайтарады: тауар сомасы, жеткізу
--  ақысы емес. Сондықтан мұнда тек қойма/промокод қалпына келеді.
create or replace function public.courier_return_order(p_order uuid, p_reason text default '')
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_order public.orders;
  v_item  jsonb;
  v_name  text;
begin
  select name into v_name from public.users where id = auth.uid();

  select * into v_order from public.orders where id = p_order for update;
  if not found then raise exception 'order_not_found'; end if;
  if v_order.courier_uid <> auth.uid() then raise exception 'not_your_order'; end if;
  if v_order.status <> 'confirmed' then
    raise exception 'order_state_changed:%', v_order.status;
  end if;

  for v_item in select * from jsonb_array_elements(v_order.items) loop
    begin
      perform public.adjust_batch_sizes((v_item ->> 'batchId')::uuid,
        jsonb_build_object(v_item ->> 'size', coalesce((v_item ->> 'qty')::int, 1)),
        'sizes_quantity', false);
    exception when others then null;
    end;
  end loop;
  perform public.release_fitting_holds(p_order, '{}');

  if coalesce(v_order.promo_counts_usage, false)
     and coalesce(v_order.promo_id, '') ~*
         '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    begin
      perform public.adjust_promo_usage(
        v_order.promo_id::uuid, v_order.client_uid, -1);
    exception when others then null;
    end;
  end if;

  update public.orders set
    status = 'cancelled',
    courier_status = 'delivered',
    stock_restored = true,
    cancelled_by_role = 'courier',
    cancelled_by_uid = auth.uid()::text,
    cancelled_by_name = coalesce(v_name, ''),
    cancelled_at = now(),
    rejection_reason = coalesce(p_reason, ''),
    deadline_at = null
  where id = p_order;

  perform public.recompute_product_status(q.pid)
    from (select distinct (it ->> 'productId')::uuid as pid
            from jsonb_array_elements(v_order.items) it) q;
end;
$$;
grant execute on function public.courier_return_order(uuid, text) to authenticated;

-- ── 12) Курьер табысы (күн / апта / барлығы) ────────────────────────────────
create or replace function public.courier_stats()
returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'todayCount',  count(*) filter (where o.created_at::date = current_date),
    'todayFee',    coalesce(sum(o.delivery_fee + o.fitting_fee)
                     filter (where o.created_at::date = current_date), 0),
    'weekCount',   count(*) filter (where o.created_at > now() - interval '7 days'),
    'weekFee',     coalesce(sum(o.delivery_fee + o.fitting_fee)
                     filter (where o.created_at > now() - interval '7 days'), 0),
    'totalCount',  count(*),
    'totalFee',    coalesce(sum(o.delivery_fee + o.fitting_fee), 0))
  from public.orders o
  where o.courier_uid = auth.uid() and o.status = 'completed';
$$;
grant execute on function public.courier_stats() to authenticated;

-- ── 13) Superadmin: курьерлерді басқару ─────────────────────────────────────
--  users_update policy superadmin-ге рұқсат береді, бірақ бір ғана жерде
--  тұрған RPC артық баған тиюден сақтайды әрі аудитке ыңғайлы.
create or replace function public.superadmin_set_courier(
  p_uid uuid,
  p_status text,                 -- pending | active | blocked
  p_city text default null
) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_superadmin() then raise exception 'not_superadmin'; end if;
  if p_status not in ('pending', 'active', 'blocked') then
    raise exception 'bad_status';
  end if;

  update public.users set
    courier_status = p_status,
    city = coalesce(nullif(trim(p_city), ''), city),
    join_status = case when p_status = 'active' then 'active' else 'none' end
  where id = p_uid and role = 'courier';

  if p_status = 'active' then
    perform public.notify_push(array[p_uid],
      'Доступ курьера открыт / Курьер рұқсаты ашылды',
      'Можно принимать заказы / Тапсырыс қабылдауға болады',
      jsonb_build_object('type', 'courier_approved'));
  end if;
end;
$$;
grant execute on function public.superadmin_set_courier(uuid, text, text) to authenticated;
