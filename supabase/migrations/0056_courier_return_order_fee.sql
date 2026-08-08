-- ════════════════════════════════════════════════════════════════════════════
--  0056 · «Клиент бас тартты» жолындағы жеткізу ақысының есебі
-- ────────────────────────────────────────────────────────────────────────────
--  МӘСЕЛЕ: courier_return_order (клиент есік алдында бас тартты) жеткізу
--  ақысын ЕШҚАЙДА белгілемейтін. Клиентке «бас тартсаңыз жеткізу ақысы
--  қайтарылмайды» деп жазылған, курьер жолға шыққан — бірақ ол ақы курьердің
--  есебінде көрінбейтін. Енді курьер алды/алмады дегенді өзі белгілейді.
--
--  ⚠️ Жеткізу ақысы бұл жерде де ДҮКЕНГЕ тимейді: ол курьердікі. Тапсырыс
--  болдырылады, тауар қоймаға оралады, тауар ақысын дүкен клиентке қайтарады.
-- ════════════════════════════════════════════════════════════════════════════

drop function if exists public.courier_return_order(uuid, text);

create or replace function public.courier_return_order(
  p_order uuid,
  p_reason text default '',
  p_fee_collected boolean default true
) returns void
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
    status                    = 'cancelled',
    courier_status            = 'delivered',
    stock_restored            = true,
    cancelled_by_role         = 'courier',
    cancelled_by_uid          = auth.uid()::text,
    cancelled_by_name         = coalesce(v_name, ''),
    cancelled_at              = now(),
    rejection_reason          = coalesce(p_reason, ''),
    delivery_fee_collected    = coalesce(p_fee_collected, false),
    delivery_fee_collected_at = case when coalesce(p_fee_collected, false)
                                     then now() else null end
  where id = p_order;

  if v_order.client_uid is not null then
    perform public.notify_push(array[v_order.client_uid],
      'Заказ отменён / Тапсырыс болдырылмады',
      coalesce(p_reason, ''),
      jsonb_build_object('type', 'order_status', 'orderId', v_order.id));
  end if;

  perform public.notify_push(array[v_order.admin_uid],
    'Клиент отказался / Клиент бас тартты',
    '№' || v_order.order_number || ' — ' || coalesce(p_reason, ''),
    jsonb_build_object('type', 'order_status', 'orderId', v_order.id));
end;
$$;
grant execute on function public.courier_return_order(uuid, text, boolean) to authenticated;

-- ── Курьер табысына «бас тартылған» бару да кіреді ─────────────────────────
--  Курьер жолға шықты, жүкті апарды — ақысы жиналған болса, ол оның табысы.
create or replace function public.courier_stats()
returns jsonb
language sql stable security definer set search_path = public as $$
  with d as (
    select o.created_at as at, o.delivery_fee as fee,
           coalesce(o.delivery_fee_collected, false) as got, 'delivery' as kind
      from public.orders o
     where o.courier_uid = auth.uid()
       and o.status in ('completed', 'cancelled')
       and o.courier_status = 'delivered'
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
