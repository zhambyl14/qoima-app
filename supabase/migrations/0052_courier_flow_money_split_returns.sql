-- ════════════════════════════════════════════════════════════════════════════
--  0052 · Курьер ағынын толық қайта қарау: ақшаның бөлінуі, айналымдағы
--         өлшем (примерка свопы), курьермен возврат, рөл шектеулері
-- ────────────────────────────────────────────────────────────────────────────
--  МӘСЕЛЕЛЕР (0051-ден кейін табылған):
--   1) Курьер тапсырысты алып кеткен соң да админ/сатушы «Выдать»/«Отменить»
--      баса алатын — тауар курьердің қолында тұрып, дүкен оны «бердім» деп
--      жабуы мүмкін еді.
--   2) Примерка свопында ЕКІНШІ өлшем БІРДЕН қоймаға қайтарылатын — ал ол
--      физикалық түрде курьердің қолында, жолда. Қойма шындықты көрсетпейді:
--      сол өлшемді басқа клиент сатып алса, оны беретін тауар жоқ.
--   3) Жеткізу ақысы курьердікі, ал ол дүкеннің/платформаның кірісіне
--      араласып тұрды (courier_stats примерка ақысын да курьерге санайтын).
--   4) Возврат курьермен рәсімделмейтін.
--
--  АҚША БӨЛІНУІ (енді қатаң):
--      тауар сомасы      → ДҮКЕН (sales_history)
--      жеткізу ақысы     → КУРЬЕР (delivery_fee)
--      «өлшеп көру»      → ДҮКЕН (fitting_fee — екінші жұп қоймадан шығады,
--                          тәуекел дүкендікі)
--      возврат жеткізуі  → КУРЬЕР (returns.delivery_fee), қайтарылатын
--                          тауар сомасынан ЕШҚАШАН шегерілмейді
-- ════════════════════════════════════════════════════════════════════════════

-- ── 1) Тариф: возврат жеткізуі ──────────────────────────────────────────────
insert into public.app_settings(key, value) values
  ('delivery_return_fee', '1500')
on conflict (key) do nothing;

-- ── 2) orders: айналымдағы (қайтып келе жатқан) позициялар ──────────────────
alter table public.orders
  -- [{productId, batchId, productName, size, qty, fromHold}] — примеркада
  -- клиент таңдамаған өлшем. fromHold=true → ол reserved_sizes-те тұр
  -- (қосалқы өлшем), false → sizes_quantity-ден алынған (негізгі өлшем).
  add column if not exists return_leg jsonb not null default '[]'::jsonb,
  -- '' (жоқ) | pending (курьерде, қоймаға бара жатыр) | returned (тапсырылды)
  add column if not exists return_leg_status text not null default '';

create index if not exists orders_return_leg_idx
  on public.orders(admin_uid) where return_leg_status = 'pending';

-- ── 3) returns: курьермен қайтару ───────────────────────────────────────────
alter table public.returns
  add column if not exists courier_uid          uuid references auth.users(id),
  add column if not exists courier_name         text not null default '',
  -- '' | assigned | picked_up (клиенттен алды) | delivered (дүкенге тапсырды)
  add column if not exists courier_status       text not null default '',
  -- Клиент курьерге төлейтін ақы. ҚАЙТАРЫЛАТЫН СОМАДАН ШЕГЕРІЛМЕЙДІ.
  add column if not exists delivery_fee         numeric not null default 0,
  add column if not exists courier_taken_at     timestamptz,
  add column if not exists courier_delivered_at timestamptz;

create index if not exists returns_courier_idx
  on public.returns(courier_uid) where courier_uid is not null;

-- ── 4) Курьер ұстап тұрған тапсырысты дүкен жаба алмайды ───────────────────
--  0030-дағы claim_order_transition SECURITY DEFINER, бірақ ішінде auth.uid()
--  бастапқы шақырушыныкі болып қалады — сондықтан триггер дұрыс ажыратады.
create or replace function public.guard_courier_order_lock()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.status is not distinct from old.status then return new; end if;
  if old.courier_uid is null then return new; end if;
  if old.courier_status not in ('assigned', 'picked_up') then return new; end if;
  -- Курьердің өзі және модератор ғана өзгерте алады.
  if auth.uid() = old.courier_uid or public.is_superadmin() then return new; end if;
  raise exception 'order_locked_by_courier';
end;
$$;

drop trigger if exists trg_guard_courier_order_lock on public.orders;
create trigger trg_guard_courier_order_lock before update on public.orders
  for each row execute function public.guard_courier_order_lock();

-- ── 5) Клиентке беру — АЙНАЛЫМДАҒЫ ӨЛШЕМ ҚОЙМАҒА БІРДЕН ҚАЙТПАЙДЫ ──────────
--  p_swaps — клиент ҚОСАЛҚЫ өлшемді алған позициялардың индекстері.
--  Әр примерка позициясында ӘРҚАШАН біреуі қалады, екіншісі қайтады
--  («екеуін де қабылдамау» деген сценарий жоқ).
--
--  Қойма қозғалысы:
--   · клиент негізгіні алды → негізгі бұрыннан sizes_quantity-ден шыққан
--     (сатылды), ҚОСАЛҚЫ өлшем reserved_sizes-те ҚАЛАДЫ — ол әлі курьерде.
--   · клиент қосалқыны алды → қосалқы reserved-тен шығып sizes_quantity-ден
--     де алынады (сатылды), ал НЕГІЗГІ өлшем sizes_quantity-де шығып тұр
--     күйінде ҚАЛАДЫ — ол әлі курьерде.
--  Екі жағдайда да қайтатын позиция return_leg-ке жазылады да, қоймаға тек
--  дүкен «қабылдадым» дегенде оралады (store_confirm_return_leg).
create or replace function public.courier_complete_order(
  p_order uuid,
  p_swaps integer[] default '{}'
) returns public.orders
language plpgsql security definer set search_path = public as $$
declare
  v_order    public.orders;
  v_items    jsonb;
  v_item     jsonb;
  v_alt      text;
  v_qty      int;
  v_swapped  boolean;
  v_leg      jsonb := '[]'::jsonb;
  v_receipt  text;
  v_factor   numeric := 1;
  v_total    numeric := 0;
  v_name     text;
  i          integer;
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

  for i in 0 .. jsonb_array_length(v_items) - 1 loop
    v_item := v_items -> i;
    v_alt  := coalesce(v_item ->> 'altSize', '');
    if v_alt = '' then continue; end if;          -- примеркасыз позиция
    v_qty     := coalesce((v_item ->> 'qty')::int, 1);
    v_swapped := i = any(coalesce(p_swaps, '{}'::integer[]));

    if v_swapped then
      -- Қосалқы өлшем САТЫЛДЫ: броньнан шығып, қоймадан да алынады.
      perform public.adjust_batch_sizes((v_item ->> 'batchId')::uuid,
        jsonb_build_object(v_alt, -v_qty), 'reserved_sizes', false);
      perform public.adjust_batch_sizes((v_item ->> 'batchId')::uuid,
        jsonb_build_object(v_alt, -v_qty), 'sizes_quantity', false);
      -- Негізгі өлшем ҚАЙТАДЫ (әлі курьерде — қоймаға қосылмайды).
      v_leg := v_leg || jsonb_build_array(jsonb_build_object(
        'productId', v_item ->> 'productId',
        'batchId',   v_item ->> 'batchId',
        'productName', v_item ->> 'productName',
        'size',      v_item ->> 'size',
        'qty',       v_qty,
        'fromHold',  false));
      -- Сатылған позиция — қосалқы өлшем.
      v_items := jsonb_set(v_items, array[i::text],
        (v_item - 'altSize')
          || jsonb_build_object('size', v_alt, 'swappedFrom', v_item ->> 'size'));
    else
      -- Негізгі өлшем қалды (ол тапсырыс кезінде сатылған).
      -- Қосалқы өлшем ҚАЙТАДЫ — броньда тұра береді, курьерде.
      v_leg := v_leg || jsonb_build_array(jsonb_build_object(
        'productId', v_item ->> 'productId',
        'batchId',   v_item ->> 'batchId',
        'productName', v_item ->> 'productName',
        'size',      v_alt,
        'qty',       v_qty,
        'fromHold',  true));
      v_items := jsonb_set(v_items, array[i::text],
        (v_item - 'altSize') || jsonb_build_object('returnedSize', v_alt));
    end if;
  end loop;

  v_receipt := case when v_order.order_number > 0
    then '#' || lpad(v_order.order_number::text, 5, '0')
    else '#' || lpad(public.next_counter(v_order.admin_uid, 'receipts')::text, 5, '0') end;

  update public.orders set
    items             = v_items,
    return_leg        = v_leg,
    return_leg_status = case when jsonb_array_length(v_leg) > 0 then 'pending' else '' end,
    status            = 'completed',
    courier_status    = 'delivered',
    delivered_by_uid  = auth.uid()::text,
    delivered_by_name = coalesce(v_name, ''),
    receipt_number    = v_receipt,
    deadline_at       = null
  where id = p_order returning * into v_order;

  -- ── sales_history: НАҚТЫ клиентте қалған өлшемдер ────────────────────────
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

  if v_order.client_uid is not null and jsonb_array_length(v_leg) > 0 then
    perform public.notify_push(
      array[v_order.client_uid],
      'Заказ доставлен / Тапсырыс жеткізілді',
      'Второй размер возвращается продавцу / Екінші өлшем сатушыға қайтарылуда',
      jsonb_build_object('type', 'order_status', 'orderId', v_order.id));
  end if;

  return v_order;
end;
$$;
grant execute on function public.courier_complete_order(uuid, integer[]) to authenticated;

-- ── 6) Дүкен айналымдағы өлшемді ҚАБЫЛДАДЫ → қоймаға оралады ───────────────
--  Тек осы сәтте қойма қалпына келеді: тауар физикалық түрде дүкенде.
create or replace function public.store_confirm_return_leg(p_order uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_order public.orders;
  v_item  jsonb;
begin
  select * into v_order from public.orders where id = p_order for update;
  if not found then raise exception 'order_not_found'; end if;
  if not (v_order.admin_uid = auth.uid()
          or v_order.admin_uid = public.app_owner_uid()
          or public.is_superadmin()) then
    raise exception 'not_your_order';
  end if;
  if v_order.return_leg_status <> 'pending' then
    raise exception 'nothing_to_return';
  end if;

  for v_item in select * from jsonb_array_elements(v_order.return_leg) loop
    begin
      if coalesce((v_item ->> 'fromHold')::boolean, false) then
        -- Броньдағы қосалқы өлшем — бронь босайды, қалдық қайта қолжетімді.
        perform public.adjust_batch_sizes((v_item ->> 'batchId')::uuid,
          jsonb_build_object(v_item ->> 'size',
            -coalesce((v_item ->> 'qty')::int, 1)),
          'reserved_sizes', false);
      else
        -- Негізгі өлшем қоймадан алынған еді — қайта қосамыз.
        perform public.adjust_batch_sizes((v_item ->> 'batchId')::uuid,
          jsonb_build_object(v_item ->> 'size',
            coalesce((v_item ->> 'qty')::int, 1)),
          'sizes_quantity', false);
      end if;
    exception when others then null; -- партия өшірілген болуы мүмкін
    end;
  end loop;

  update public.orders
     set return_leg_status = 'returned'
   where id = p_order;

  perform public.recompute_product_status(q.pid)
    from (select distinct (it ->> 'productId')::uuid as pid
            from jsonb_array_elements(v_order.return_leg) it) q;

  if v_order.client_uid is not null then
    perform public.notify_push(
      array[v_order.client_uid],
      'Размер возвращён продавцу / Өлшем сатушыға қайтарылды',
      coalesce(v_order.store_name, '') || ' — №' || v_order.order_number,
      jsonb_build_object('type', 'order_status', 'orderId', v_order.id));
  end if;
end;
$$;
grant execute on function public.store_confirm_return_leg(uuid) to authenticated;

-- ── 7) Курьермен ВОЗВРАТ ────────────────────────────────────────────────────
--  Клиент қайтаруды курьермен рәсімдеді (pickup='courier'). Курьер клиенттен
--  тауарды алып, дүкенге жеткізеді. Ақысы (returns.delivery_fee) КУРЬЕРДІКІ
--  әрі клиентке қайтарылатын тауар сомасынан ШЕГЕРІЛМЕЙДІ.
create or replace function public.courier_available_returns()
returns setof public.returns
language sql stable security definer set search_path = public as $$
  select r.* from public.returns r
    join public.stores s on s.admin_uid = r.admin_uid
   where r.pickup = 'courier'
     and r.status in ('requested', 'approved')
     and r.courier_uid is null
     and public.active_courier_city() is not null
     and s.city = public.active_courier_city()
   order by r.created_at;
$$;
grant execute on function public.courier_available_returns() to authenticated;

create or replace function public.courier_my_returns()
returns setof public.returns
language sql stable security definer set search_path = public as $$
  select r.* from public.returns r
   where r.courier_uid = auth.uid()
     and (r.courier_status <> 'delivered'
          or r.created_at > now() - interval '30 days')
   order by (r.courier_status <> 'delivered') desc, r.created_at desc;
$$;
grant execute on function public.courier_my_returns() to authenticated;

create or replace function public.courier_take_return(p_return text)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_ret  public.returns;
  v_city text := public.active_courier_city();
  v_name text;
  v_fee  numeric;
begin
  if v_city is null then raise exception 'not_active_courier'; end if;
  select name into v_name from public.users where id = auth.uid();
  select coalesce(nullif(value, '')::numeric, 1500) into v_fee
    from public.app_settings where key = 'delivery_return_fee';

  select * into v_ret from public.returns where id = p_return for update;
  if not found then raise exception 'return_not_found'; end if;
  if v_ret.pickup <> 'courier' then raise exception 'not_courier_return'; end if;
  if v_ret.courier_uid is not null then raise exception 'return_already_taken'; end if;
  if not exists (select 1 from public.stores
                  where admin_uid = v_ret.admin_uid and city = v_city) then
    raise exception 'other_city';
  end if;

  update public.returns set
    courier_uid = auth.uid(),
    courier_name = coalesce(v_name, ''),
    courier_status = 'assigned',
    courier_taken_at = now(),
    delivery_fee = coalesce(v_fee, 1500)
  where id = p_return;

  if v_ret.client_uid is not null then
    perform public.notify_push(array[v_ret.client_uid],
      'Курьер заберёт возврат / Курьер қайтарымды алады',
      coalesce(v_name, ''),
      jsonb_build_object('type', 'return_status', 'returnId', v_ret.id));
  end if;
end;
$$;
grant execute on function public.courier_take_return(text) to authenticated;

-- Клиенттен тауарды алды.
create or replace function public.courier_pickup_return(p_return text)
returns void
language plpgsql security definer set search_path = public as $$
declare v_ret public.returns;
begin
  select * into v_ret from public.returns where id = p_return for update;
  if not found then raise exception 'return_not_found'; end if;
  if v_ret.courier_uid <> auth.uid() then raise exception 'not_your_order'; end if;
  if v_ret.courier_status <> 'assigned' then raise exception 'wrong_courier_state'; end if;
  update public.returns set courier_status = 'picked_up' where id = p_return;
end;
$$;
grant execute on function public.courier_pickup_return(text) to authenticated;

-- Дүкенге тапсырды. Одан әрі бар қайтару ағыны (қабылдау → ақша қайтару)
-- дүкеннің экранында өз бетінше жүреді — оны өзгертпейміз.
create or replace function public.courier_deliver_return(p_return text)
returns void
language plpgsql security definer set search_path = public as $$
declare v_ret public.returns;
begin
  select * into v_ret from public.returns where id = p_return for update;
  if not found then raise exception 'return_not_found'; end if;
  if v_ret.courier_uid <> auth.uid() then raise exception 'not_your_order'; end if;
  if v_ret.courier_status <> 'picked_up' then raise exception 'wrong_courier_state'; end if;

  update public.returns set
    courier_status = 'delivered',
    courier_delivered_at = now()
  where id = p_return;

  perform public.notify_push(array[v_ret.admin_uid],
    'Курьер привёз возврат / Курьер қайтарымды әкелді',
    coalesce(v_ret.client_name, ''),
    jsonb_build_object('type', 'return_status', 'returnId', v_ret.id));
end;
$$;
grant execute on function public.courier_deliver_return(text) to authenticated;

-- ── 8) Курьер табысы — ТЕК жеткізу ақылары ─────────────────────────────────
--  ⚠️ ТҮЗЕТУ: 0051-де fitting_fee те курьерге саналатын. Ол қате: «өлшеп
--  көру» ақысы ДҮКЕНДІКІ (екінші жұп оның қоймасынан шығады, тәуекел де
--  соныкі). Курьерге тек жеткізу мен возврат жеткізуі тиесілі.
create or replace function public.courier_stats()
returns jsonb
language sql stable security definer set search_path = public as $$
  with d as (
    select o.created_at, o.delivery_fee as fee
      from public.orders o
     where o.courier_uid = auth.uid() and o.status = 'completed'
    union all
    select r.courier_delivered_at, r.delivery_fee
      from public.returns r
     where r.courier_uid = auth.uid() and r.courier_status = 'delivered'
  )
  select jsonb_build_object(
    'todayCount', count(*) filter (where created_at::date = current_date),
    'todayFee',   coalesce(sum(fee) filter (where created_at::date = current_date), 0),
    'weekCount',  count(*) filter (where created_at > now() - interval '7 days'),
    'weekFee',    coalesce(sum(fee) filter (where created_at > now() - interval '7 days'), 0),
    'totalCount', count(*),
    'totalFee',   coalesce(sum(fee), 0))
  from d;
$$;
grant execute on function public.courier_stats() to authenticated;

-- ── 9) Дүкеннің қызмет кірісі (примерка) — аналитикада бөлек көрінуі үшін ──
create or replace function public.store_service_income(p_from timestamptz default null)
returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'fittingFee', coalesce(sum(o.fitting_fee), 0),
    'orders',     count(*) filter (where o.fitting_fee > 0))
  from public.orders o
  where o.status = 'completed'
    and o.admin_uid = coalesce(public.app_owner_uid(), auth.uid())
    and (p_from is null or o.created_at >= p_from);
$$;
grant execute on function public.store_service_income(timestamptz) to authenticated;
