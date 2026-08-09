-- ════════════════════════════════════════════════════════════════════════════
--  0060 · Модератор курьерлік тапсырыстарды БАСҚАРАДЫ
-- ────────────────────────────────────────────────────────────────────────────
--  Курьер модераторға бағынады, дүкенге емес. Бірақ модераторда курьерлердің
--  ТІЗІМІ ғана бар еді — олардың нақты жұмысы мүлде көрінбейтін. Содан:
--    · курьер тапсырысты алып, жоғалып кетсе — оны ешкім босата алмайтын
--      (дүкен `guard_courier_order_lock` себебінен тие алмайды), тапсырыс
--      мәңгі «курьерде» болып қалатын;
--    · қай қалада жұмыс жиналып қалғанын модератор көрмейтін.
--
--  Енді екеуі де бар: толық тізім + тапсырысты курьерден БОСАТУ.
-- ════════════════════════════════════════════════════════════════════════════

-- ── Барлық курьерлік жеткізу (30 күн) — модераторға ───────────────────────
create or replace function public.superadmin_courier_orders()
returns jsonb
language sql stable security definer set search_path = public as $$
  select case when not public.is_superadmin() then '[]'::jsonb
         else coalesce(jsonb_agg(row order by row->>'createdAt' desc), '[]'::jsonb)
         end
    from (
      select jsonb_build_object(
               'id',            o.id,
               'orderNumber',   o.order_number,
               'status',        o.status,
               'courierStatus', coalesce(o.courier_status, ''),
               'courierUid',    coalesce(o.courier_uid::text, ''),
               'courierName',   coalesce(o.courier_name, ''),
               'storeName',     coalesce(o.store_name, ''),
               'city',          coalesce(s.city, ''),
               'clientName',    coalesce(o.client_name, ''),
               'clientPhone',   coalesce(o.client_phone, ''),
               'clientCity',    coalesce(o.client_city, ''),
               'address',       coalesce(o.address, ''),
               'deliveryFee',   coalesce(o.delivery_fee, 0),
               'cartGroupId',   coalesce(o.cart_group_id::text, ''),
               'takenAt',       o.courier_taken_at,
               'createdAt',     o.created_at
             ) as row
        from public.orders o
        join public.stores s on s.admin_uid = o.admin_uid
       where o.order_type = 'delivery'
         and coalesce(o.delivery_mode, 'courier') = 'courier'
         and o.created_at > now() - interval '30 days'
    ) q;
$$;
grant execute on function public.superadmin_courier_orders() to authenticated;

-- ── Тапсырысты курьерден БОСАТУ ───────────────────────────────────────────
--  Курьер алып, жоғалып кетті (телефоны өшік, ауырып қалды). Дүкен оны
--  түртe алмайды — `guard_courier_order_lock` тыйым салады. Босатқан соң
--  тапсырыс қайтадан «бос жұмыс» тізіміне түседі де, басқа курьер алады.
--
--  ⚠️ Тауар қоймадан ШЫҚҚАН болса (courier_status = 'picked_up') — босату
--  тауарды қайтармайды: ол физикалық түрде курьерде. Сондықтан ондай
--  жағдайда әдейі тыйым: алдымен курьер тауарды дүкенге тапсыруы керек.
create or replace function public.superadmin_release_order(
  p_order  uuid,
  p_reason text default ''
) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_order public.orders;
  v_prev  uuid;
begin
  if not public.is_superadmin() then raise exception 'not_superadmin'; end if;

  select * into v_order from public.orders where id = p_order for update;
  if not found then raise exception 'order_not_found'; end if;
  if v_order.courier_uid is null then raise exception 'order_has_no_courier'; end if;
  if coalesce(v_order.courier_status, '') = 'delivered' then
    raise exception 'order_already_delivered';
  end if;
  if coalesce(v_order.courier_status, '') = 'picked_up' then
    -- Тауар курьердің қолында — «босату» оны ауада қалдырар еді.
    raise exception 'courier_holds_goods';
  end if;

  v_prev := v_order.courier_uid;

  update public.orders set
    courier_uid      = null,
    courier_name     = '',
    courier_status   = '',
    courier_taken_at = null
  where id = p_order;

  perform public.notify_push(array[v_prev],
    '⚠️ Заказ снят / Тапсырыс алынды',
    '№' || v_order.order_number || ' — ' || coalesce(nullif(p_reason, ''),
      'модератор передал другому курьеру / модератор басқа курьерге берді'),
    jsonb_build_object('type', 'courier_work', 'orderId', v_order.id));

  perform public.notify_push(array[v_order.admin_uid],
    'Курьер снят с заказа / Курьер тапсырыстан алынды',
    '№' || v_order.order_number || ' — ищем нового / жаңасын іздеудеміз',
    jsonb_build_object('type', 'order_status', 'orderId', v_order.id));
end;
$$;
grant execute on function public.superadmin_release_order(uuid, text)
  to authenticated;
