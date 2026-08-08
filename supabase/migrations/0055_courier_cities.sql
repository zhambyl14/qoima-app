-- ════════════════════════════════════════════════════════════════════════════
--  0055 · Курьерлік қызмет ҚАЛА БОЙЫНША қосылады/өшіріледі (модератор)
-- ────────────────────────────────────────────────────────────────────────────
--  Платформаның курьері әр қалада бірдей жоқ. Модератор қай қалада қызмет
--  іске қосылғанын өзі белгілейді:
--
--    ҚОСУЛЫ қалада  → жеткізуді де, возврат тасымалын да ПЛАТФОРМА КУРЬЕРІ
--                     орындайды (ақысы курьерге тікелей — 0053).
--    ӨШІРУЛІ қалада → курьер жоқ. Дүкен тауарды өзі жеткізеді немесе жөнелту
--                     қызметімен жібереді, шартын клиентпен өзі келіседі.
--                     Возратты да клиент өзі әкеледі/жібереді.
--
--  Тізім `app_settings.delivery_courier_cities` кілтінде JSON массив болып
--  жатады. `delivery_%` үлгісіне түскендіктен ол бұрыннан бар публичті
--  `delivery_tariff()` RPC-і арқылы қонаққа да көрінеді — бөлек RPC керек емес.
--
--  ⚠️ БОС ТІЗІМ = ШЕКТЕУ ЖОҚ (барлық қалада қосулы). Жаңарту сәтінде қызмет
--  кенет тоқтап қалмауы үшін әдейі осылай: модератор шектеуді өзі енгізеді.
-- ════════════════════════════════════════════════════════════════════════════

insert into public.app_settings(key, value) values
  ('delivery_courier_cities', '[]')
on conflict (key) do nothing;

-- ── Қалада курьерлік қызмет бар ма? ────────────────────────────────────────
create or replace function public.courier_city_enabled(p_city text)
returns boolean
language sql stable security definer set search_path = public as $$
  select case
    when coalesce(p_city, '') = '' then false
    else coalesce(
      (select v.value = '[]'::jsonb
           or exists (select 1
                        from jsonb_array_elements_text(v.value) c
                       where lower(trim(c)) = lower(trim(p_city)))
         from (select coalesce(nullif(value, ''), '[]')::jsonb as value
                 from public.app_settings
                where key = 'delivery_courier_cities') v),
      true)
  end;
$$;
grant execute on function public.courier_city_enabled(text) to anon, authenticated;

-- ── orders: жеткізуді кім орындайды ────────────────────────────────────────
--  'courier' — платформа курьері; 'store' — дүкен өзі жеткізеді/жібереді.
alter table public.orders
  add column if not exists delivery_mode text not null default 'courier';

-- ── Курьерге көрінетін жұмыс: қаласы ӨШІРУЛІ болса — ештеңе көрінбейді ─────
create or replace function public.courier_available_orders()
returns setof public.orders
language sql stable security definer set search_path = public as $$
  select o.* from public.orders o
    join public.stores s on s.admin_uid = o.admin_uid
   where o.order_type = 'delivery'
     and o.status = 'confirmed'
     and o.courier_uid is null
     and coalesce(o.delivery_mode, 'courier') = 'courier'
     and public.active_courier_city() is not null
     and s.city = public.active_courier_city()
     and public.courier_city_enabled(s.city)
   order by o.created_at;
$$;
grant execute on function public.courier_available_orders() to authenticated;

create or replace function public.courier_available_returns()
returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(public.courier_return_row(r) order by r.created_at),
                  '[]'::jsonb)
    from public.returns r
    join public.stores s on s.admin_uid = r.admin_uid
   where r.pickup = 'courier'
     and r.status = 'approved'
     and r.courier_uid is null
     and public.active_courier_city() is not null
     and s.city = public.active_courier_city()
     and public.courier_city_enabled(s.city);
$$;
grant execute on function public.courier_available_returns() to authenticated;

-- ── «Алам» батырмалары да тексереді (тізім ескірген болуы мүмкін) ──────────
create or replace function public.courier_take_order(p_order uuid)
returns public.orders
language plpgsql security definer set search_path = public as $$
declare
  v_order public.orders;
  v_city  text := public.active_courier_city();
  v_name  text;
begin
  if v_city is null then raise exception 'not_active_courier'; end if;
  if not public.courier_city_enabled(v_city) then
    raise exception 'courier_service_off';
  end if;
  select name into v_name from public.users where id = auth.uid();

  select * into v_order from public.orders where id = p_order for update;
  if not found then raise exception 'order_not_found'; end if;
  if v_order.order_type <> 'delivery' or v_order.status <> 'confirmed' then
    raise exception 'order_state_changed:%', v_order.status;
  end if;
  if coalesce(v_order.delivery_mode, 'courier') <> 'courier' then
    raise exception 'store_delivers_itself';
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
  if not public.courier_city_enabled(v_city) then
    raise exception 'courier_service_off';
  end if;
  select name into v_name from public.users where id = auth.uid();
  select coalesce(nullif(value, '')::numeric, 1500) into v_fee
    from public.app_settings where key = 'delivery_return_fee';

  select * into v_ret from public.returns where id = p_return for update;
  if not found then raise exception 'return_not_found'; end if;
  if v_ret.pickup <> 'courier' then raise exception 'not_courier_return'; end if;
  if v_ret.status <> 'approved' then raise exception 'return_not_approved'; end if;
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
