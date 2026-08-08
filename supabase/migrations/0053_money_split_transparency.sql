-- ════════════════════════════════════════════════════════════════════════════
--  0053 · Ақшаның АЙҚЫН бөлінуі: курьер ақысы дүкеннің кассасына кірмейді
-- ────────────────────────────────────────────────────────────────────────────
--  МӘСЕЛЕЛЕР (0052-ден кейін табылған):
--   1) Клиент жеткізу ақысын ДҮКЕННІҢ картасына аударатын (deposit_amount
--      ішінде) — сосын дүкен оны курьерге қайтаруы керек еді. Ешкім
--      бақыламайды, есеп бұзылады. Енді жеткізу ақысы КУРЬЕРГЕ ТІКЕЛЕЙ
--      төленеді (тапсырысты алған сәтте), дүкеннің ақшасына мүлде тимейді.
--   2) «Өлшеп көру» ақысы (fitting_fee) ЕШҚАЙДА кіріс болып жазылмайтын —
--      дүкен қызмет көрсетті, ақша алды, бірақ аналитикада көрінбейтін.
--      Енді ол sales_history-ге type='service' жолы болып түседі.
--   3) Возврат жеткізуі де ешқайда белгіленбейтін — курьер алды ма, жоқ па
--      білінбейтін.
--   4) courier_available_returns 'requested' күйдегі қайтарымдарды да
--      көрсететін — дүкен әлі келіспеген қайтарымға курьер барып қалатын.
--      Енді тек 'approved' (дүкен растаған) қайтарым ғана шығады.
--
--  АҚША ЕРЕЖЕСІ (толық, жасырын баптар ЖОҚ):
--    тауар сомасы (− промо)  → ДҮКЕН   · алдын ала, дүкен картасына + чек
--    «өлшеп көру» ақысы      → ДҮКЕН   · сол аударымның ішінде (қызмет соныкі)
--    жеткізу ақысы           → КУРЬЕР  · тапсырысты берген сәтте, тікелей
--    возврат жеткізуі        → КУРЬЕР  · тауарды алған сәтте, тікелей;
--                                        қайтарылатын сомадан ШЕГЕРІЛМЕЙДІ
-- ════════════════════════════════════════════════════════════════════════════

-- ── 1) Жеткізу ақысы жиналды ма (курьер клиенттен алды ма) ─────────────────
alter table public.orders
  add column if not exists delivery_fee_collected    boolean not null default false,
  add column if not exists delivery_fee_collected_at timestamptz;

alter table public.returns
  add column if not exists delivery_fee_collected    boolean not null default false,
  add column if not exists delivery_fee_collected_at timestamptz;

-- ── 2) Клиентке беру: жеткізу ақысын белгілеу + «өлшеп көру» кірісі ────────
--  p_fee_collected — курьер жеткізу ақысын клиенттен НАҚТЫ алды ма.
--  Қалғаны 0052-дегідей: своп, айналымдағы өлшем (return_leg), sales_history.
--
--  ⚠️ Ескі 2-аргументті нұсқа ӨШІРІЛУІ керек: жаңасында үшінші аргумент
--  DEFAULT-пен келеді де, екеуі қатар тұрса шақыру ambiguous болып қалады.
drop function if exists public.courier_complete_order(uuid, integer[]);

create or replace function public.courier_complete_order(
  p_order uuid,
  p_swaps integer[] default '{}',
  p_fee_collected boolean default true
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
      v_items := jsonb_set(v_items, array[i::text],
        (v_item - 'altSize')
          || jsonb_build_object('size', v_alt, 'swappedFrom', v_item ->> 'size'));
    else
      -- Негізгі өлшем қалды. Қосалқы өлшем ҚАЙТАДЫ — броньда, курьерде.
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
    items                     = v_items,
    return_leg                = v_leg,
    return_leg_status         = case when jsonb_array_length(v_leg) > 0 then 'pending' else '' end,
    status                    = 'completed',
    courier_status            = 'delivered',
    delivered_by_uid          = auth.uid()::text,
    delivered_by_name         = coalesce(v_name, ''),
    receipt_number            = v_receipt,
    deadline_at               = null,
    delivery_fee_collected    = coalesce(p_fee_collected, true),
    delivery_fee_collected_at = case when coalesce(p_fee_collected, true)
                                     then now() else null end
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

  -- ── «Өлшеп көру» — ДҮКЕННІҢ ҚЫЗМЕТ КІРІСІ ────────────────────────────────
  --  quantity = 0 → «сатылған дана» санағына кірмейді, бірақ түсімге кіреді.
  --  purchase_price = 0 → таза пайда (қоймадан тауар шықпайды).
  --  ⚠️ Жеткізу ақысы (delivery_fee) мұнда ӘДЕЙІ ЖОҚ — ол курьердікі.
  if coalesce(v_order.fitting_fee, 0) > 0 then
    insert into public.sales_history (
      owner_uid, product_id, batch_id, product_name, sale_date, sizes_sold,
      selected_size, quantity, base_price, total_price, discount_amount,
      purchase_price, seller_id, seller_name, warehouse_id, is_online, order_id,
      delivered_by_name, payment_method, receipt_number, type)
    values (
      v_order.admin_uid, null, null, 'Примерка / Өлшеп көру', now(), '{}'::jsonb,
      '', 0, v_order.fitting_fee, v_order.fitting_fee, 0,
      0, 'онлайн', 'Онлайн', v_order.warehouse_id, true, v_order.id::text,
      coalesce(v_name, ''),
      case when coalesce(v_order.payment_bank, '') <> '' then v_order.payment_bank else 'card' end,
      v_receipt, 'service');
  end if;

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
grant execute on function public.courier_complete_order(uuid, integer[], boolean) to authenticated;

-- ── 3) Возврат: тек ДҮКЕН РАСТАҒАН (approved) қайтарым курьерге көрінеді ───
--  Бұрын 'requested' де шығатын — дүкен әлі келіспеген қайтарымға курьер
--  барып, кейін дүкен қабылдамай қалуы мүмкін еді.
create or replace function public.courier_available_returns()
returns setof public.returns
language sql stable security definer set search_path = public as $$
  select r.* from public.returns r
    join public.stores s on s.admin_uid = r.admin_uid
   where r.pickup = 'courier'
     and r.status = 'approved'
     and r.courier_uid is null
     and public.active_courier_city() is not null
     and s.city = public.active_courier_city()
   order by r.created_at;
$$;
grant execute on function public.courier_available_returns() to authenticated;

-- ── 4) Клиенттен алу: возврат жеткізу ақысы да сол сәтте жиналады ──────────
drop function if exists public.courier_pickup_return(text);

create or replace function public.courier_pickup_return(
  p_return text,
  p_fee_collected boolean default true
) returns void
language plpgsql security definer set search_path = public as $$
declare v_ret public.returns;
begin
  select * into v_ret from public.returns where id = p_return for update;
  if not found then raise exception 'return_not_found'; end if;
  if v_ret.courier_uid <> auth.uid() then raise exception 'not_your_order'; end if;
  if v_ret.courier_status <> 'assigned' then raise exception 'wrong_courier_state'; end if;

  update public.returns set
    courier_status            = 'picked_up',
    delivery_fee_collected    = coalesce(p_fee_collected, true),
    delivery_fee_collected_at = case when coalesce(p_fee_collected, true)
                                     then now() else null end
  where id = p_return;

  if v_ret.admin_uid is not null then
    perform public.notify_push(array[v_ret.admin_uid],
      'Курьер забрал возврат / Курьер қайтарымды алды',
      coalesce(v_ret.client_name, ''),
      jsonb_build_object('type', 'return_status', 'returnId', v_ret.id));
  end if;
end;
$$;
grant execute on function public.courier_pickup_return(text, boolean) to authenticated;

-- ── 5) Курьер табысы — БӨЛШЕКТЕЛГЕН, жасырын жол жоқ ──────────────────────
--  Жеткізу мен возврат ақысы бөлек көрсетіледі, «жиналмаған» (клиент әлі
--  төлемеген) сома да бөлек — курьер нақты нені алғанын көреді.
create or replace function public.courier_stats()
returns jsonb
language sql stable security definer set search_path = public as $$
  with d as (
    select o.created_at as at, o.delivery_fee as fee,
           coalesce(o.delivery_fee_collected, false) as got, 'delivery' as kind
      from public.orders o
     where o.courier_uid = auth.uid() and o.status = 'completed'
    union all
    select r.courier_delivered_at, r.delivery_fee,
           coalesce(r.delivery_fee_collected, false), 'return'
      from public.returns r
     where r.courier_uid = auth.uid() and r.courier_status = 'delivered'
  )
  select jsonb_build_object(
    'todayCount',   (select count(*) from d where at::date = current_date),
    'todayFee',     (select coalesce(sum(fee) filter (where got), 0) from d
                      where at::date = current_date),
    'weekCount',    (select count(*) from d where at > now() - interval '7 days'),
    'weekFee',      (select coalesce(sum(fee) filter (where got), 0) from d
                      where at > now() - interval '7 days'),
    'totalCount',   (select count(*) from d),
    'totalFee',     (select coalesce(sum(fee) filter (where got), 0) from d),
    'deliveryFee',  (select coalesce(sum(fee) filter (where got and kind = 'delivery'), 0) from d),
    'returnFee',    (select coalesce(sum(fee) filter (where got and kind = 'return'), 0) from d),
    'uncollected',  (select coalesce(sum(fee) filter (where not got), 0) from d),
    'pendingLegs',  (select count(*) from public.orders o
                      where o.courier_uid = auth.uid()
                        and o.return_leg_status = 'pending'));
$$;
grant execute on function public.courier_stats() to authenticated;

-- ── 6) Дүкеннің қызмет кірісі — «өлшеп көру» ──────────────────────────────
--  Аналитика sales_history-ден оқиды (type='service'), бұл RPC жедел
--  тексеру/салыстыру үшін қалады.
create or replace function public.store_service_income(p_from timestamptz default null)
returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'fittingFee', coalesce(sum(o.fitting_fee), 0),
    'orders',     count(*) filter (where o.fitting_fee > 0),
    -- Курьерге кеткен ақша: дүкеннің кірісіне КІРМЕЙДІ, тек мәлімет үшін.
    'courierFee', coalesce(sum(o.delivery_fee), 0))
  from public.orders o
  where o.status = 'completed'
    and o.admin_uid = coalesce(public.app_owner_uid(), auth.uid())
    and (p_from is null or o.created_at >= p_from);
$$;
grant execute on function public.store_service_income(timestamptz) to authenticated;

-- ── 7) Ескі деректерді түзету ─────────────────────────────────────────────
--  0053-ке дейін аяқталған тапсырыстардың жеткізу ақысы дүкен аударымының
--  ішінде келген — оларды «жиналған» деп белгілейміз, әйтпесе курьердің
--  тарихы нөл болып қалады.
update public.orders
   set delivery_fee_collected    = true,
       delivery_fee_collected_at = coalesce(delivery_fee_collected_at, created_at)
 where status = 'completed'
   and courier_uid is not null
   and delivery_fee > 0
   and delivery_fee_collected = false;

update public.returns
   set delivery_fee_collected    = true,
       delivery_fee_collected_at = coalesce(delivery_fee_collected_at, courier_taken_at)
 where courier_status in ('picked_up', 'delivered')
   and delivery_fee > 0
   and delivery_fee_collected = false;
