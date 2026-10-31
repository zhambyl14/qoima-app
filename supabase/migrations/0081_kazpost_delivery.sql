-- ════════════════════════════════════════════════════════════════════════════
--  0081 · Қалааралық жеткізу: Казпочта
-- ────────────────────────────────────────────────────────────────────────────
--  Сценарий: дүкен Астанада, клиент Таразда. Клиент тауарды өз қаласына
--  Казпочтамен алады. Бағаны модератор бағыт бойынша қояды.
--
--  ЖАЛАУША: 'kazpost_delivery' (0067b). Әдепкіде ӨШІК — модератор алдымен
--  тарифтерді толтырады, сосын қосады. Дүкен өзі де бас тарта алады
--  (stores.kazpost_enabled).
--
--  ТАРИФ: kazpost_tariffs (қайдан → қайда, бағытталған: Астана→Тараз пен
--  Тараз→Астана әртүрлі болуы мүмкін). Кестеде жоқ бағытқа app_settings
--  'delivery_kazpost_default_fee' қолданылады; ол бос болса бағыт ЖАБЫҚ.
--  is_active=false — бағыт ашық түрде жабық (әдепкі баға да жүрмейді).
--
--  АҚША (0053 ережесінен ЕРЕКШЕ): курьер ақысы клиенттен курьерге тікелей
--  барады, ал почтаға дүкен өзі төлейді. Сондықтан:
--    orders.kazpost_fee — БӨЛЕК баған (delivery_fee ЕМЕС, ол «курьерге» деп
--      көрсетіледі және курьер есептеріне кіреді);
--    orders.deposit_amount = тауар (− промо) + kazpost_fee — бір аударым;
--    sales_history-ге ЖАЗЫЛМАЙДЫ: бұл дүкеннің кірісі емес, почтаға өтетін
--    транзит ақша. Возвратта да қайтарылмайды (сома тек тауар бағасынан).
--
--  СЕРВЕР ТЕКСЕРЕДІ: orders_insert клиентке ақша бағандарын жазуға рұқсат
--  береді (RLS баған деңгейінде шектемейді), сондықтан бағаны BEFORE INSERT
--  триггері тарифпен салыстырады. Клиентке сенбейміз.
--
--  АҒЫН: pending → (чек) → confirmed → дүкен трек енгізеді (post_status =
--  'shipped') → клиент «алдым» дейді НЕМЕСЕ дүкен 7 күннен кейін жабады
--  НЕМЕСЕ 30 күннен кейін cron жабады → completed + sales_history.
--  Статус тізімі ӨЗГЕРМЕДІ (claim_order_transition ақ тізімін қозғамаймыз):
--  «жолда» күйі post_status-та, courier_status үлгісімен.
-- ════════════════════════════════════════════════════════════════════════════

-- ── 1. Бағандар ──────────────────────────────────────────────────────────────
alter table public.orders
  add column if not exists kazpost_fee          numeric     not null default 0,
  add column if not exists post_recipient_name  text        not null default '',
  add column if not exists post_recipient_phone text        not null default '',
  add column if not exists post_index           text        not null default '',
  add column if not exists post_tracking        text        not null default '',
  -- '' | shipped | delivered
  add column if not exists post_status          text        not null default '',
  add column if not exists post_shipped_at      timestamptz,
  add column if not exists post_delivered_at    timestamptz;

alter table public.stores
  add column if not exists kazpost_enabled boolean not null default true;

-- Клиент тауарды почтамен қайтарғанда өзі енгізетін трек (міндетті емес).
alter table public.returns
  add column if not exists post_tracking text not null default '';

create index if not exists orders_kazpost_shipped_idx
  on public.orders (post_shipped_at)
  where delivery_mode = 'kazpost' and post_status = 'shipped';

-- ── 2. Тариф кестесі ─────────────────────────────────────────────────────────
create table if not exists public.kazpost_tariffs (
  from_city  text        not null,
  to_city    text        not null,
  price      numeric     not null check (price >= 0),
  is_active  boolean     not null default true,
  updated_at timestamptz not null default now(),
  primary key (from_city, to_city),
  check (from_city <> to_city)
);

alter table public.kazpost_tariffs enable row level security;

-- Клиенттер кестені оқымайды — тек kazpost_quote RPC арқылы өз бағытын.
drop policy if exists kazpost_tariffs_superadmin on public.kazpost_tariffs;
create policy kazpost_tariffs_superadmin on public.kazpost_tariffs
  for all to authenticated
  using (public.is_superadmin())
  with check (public.is_superadmin());

insert into public.app_settings (key, value) values
  ('feature_kazpost_delivery',     'false'),
  ('delivery_kazpost_default_fee', '')
on conflict (key) do nothing;

-- ── 3. Баға есебі ────────────────────────────────────────────────────────────
-- NULL = бұл бағытта Казпочта жоқ. Триггер де, kazpost_quote да осыны қолданады
-- — ереже бір жерде.
create or replace function public.kazpost_fee_for(p_from text, p_to text)
returns numeric
language plpgsql stable security definer set search_path = public as $$
declare
  v_from    text := lower(btrim(coalesce(p_from, '')));
  v_to      text := lower(btrim(coalesce(p_to, '')));
  v_price   numeric;
  v_active  boolean;
  v_default numeric;
begin
  if v_from = '' or v_to = '' or v_from = v_to then
    return null;
  end if;

  select t.price, t.is_active into v_price, v_active
    from public.kazpost_tariffs t
   where lower(btrim(t.from_city)) = v_from
     and lower(btrim(t.to_city))   = v_to
   limit 1;
  if found then
    return case when v_active then v_price end;
  end if;

  begin
    select nullif(btrim(value::text), '')::numeric into v_default
      from public.app_settings where key = 'delivery_kazpost_default_fee';
  exception when others then
    v_default := null;
  end;
  if v_default is null or v_default < 0 then
    return null;
  end if;
  return v_default;
end;
$$;
revoke execute on function public.kazpost_fee_for(text, text) from public, anon, authenticated;

-- Себет үшін: дүкендер → баға. Дүкеннің қаласы мен келісімін сервер өзі қарайды,
-- клиентке қала жолын салыстыртпаймыз. Жауапта жоқ дүкен = Казпочта жоқ.
create or replace function public.kazpost_quote(p_admins uuid[], p_to text)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_out jsonb := '{}'::jsonb;
  v_row record;
  v_fee numeric;
begin
  if auth.uid() is null then
    raise exception 'not_authorized';
  end if;
  if not public.feature_enabled('kazpost_delivery') then
    return v_out;
  end if;
  for v_row in
    select s.admin_uid, s.city
      from public.stores s
     where s.admin_uid = any(coalesce(p_admins, '{}'::uuid[]))
       and s.kazpost_enabled
  loop
    v_fee := public.kazpost_fee_for(v_row.city, p_to);
    if v_fee is not null then
      v_out := v_out || jsonb_build_object(v_row.admin_uid::text, v_fee);
    end if;
  end loop;
  return v_out;
end;
$$;
revoke execute on function public.kazpost_quote(uuid[], text) from public;
grant execute on function public.kazpost_quote(uuid[], text) to authenticated;

-- ── 4. orders триггері ───────────────────────────────────────────────────────
create or replace function public.guard_orders_kazpost()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_city    text;
  v_enabled boolean;
  v_fee     numeric;
begin
  if tg_op = 'INSERT' then
    if coalesce(new.delivery_mode, '') <> 'kazpost' then
      new.kazpost_fee          := 0;
      new.post_recipient_name  := '';
      new.post_recipient_phone := '';
      new.post_index           := '';
      new.post_tracking        := '';
      new.post_status          := '';
      new.post_shipped_at      := null;
      new.post_delivered_at    := null;
      return new;
    end if;

    if not public.feature_enabled('kazpost_delivery') then
      raise exception 'kazpost_disabled';
    end if;
    if new.order_type <> 'delivery' or coalesce(new.is_gift, false) then
      raise exception 'kazpost_invalid_order';
    end if;

    select s.city, s.kazpost_enabled into v_city, v_enabled
      from public.stores s where s.admin_uid = new.admin_uid;
    if not found or not v_enabled then
      raise exception 'kazpost_store_disabled';
    end if;

    v_fee := public.kazpost_fee_for(v_city, new.client_city);
    if v_fee is null then
      raise exception 'kazpost_route_unavailable';
    end if;
    -- Тарифті модератор себет ашық тұрғанда өзгертуі мүмкін: клиент көрген
    -- санмен келіспесе үнсіз түзетпейміз, ол көрмеген сомаға аудармауы тиіс.
    if abs(coalesce(new.kazpost_fee, 0) - v_fee) > 0.01 then
      raise exception 'kazpost_fee_changed';
    end if;
    if coalesce(new.deposit_amount, 0) < v_fee then
      raise exception 'kazpost_deposit_mismatch';
    end if;
    if coalesce(new.post_index, '') !~ '^[0-9]{6}$' then
      raise exception 'kazpost_index_invalid';
    end if;
    if btrim(coalesce(new.address, '')) = ''
       or btrim(coalesce(new.post_recipient_name, '')) = ''
       or btrim(coalesce(new.post_recipient_phone, '')) = '' then
      raise exception 'kazpost_recipient_required';
    end if;

    new.kazpost_fee       := v_fee;
    new.delivery_fee      := 0;
    new.fitting_fee       := 0;
    -- Казпочта тапсырысын курьер ұстамайды: клиент жазған courier_* бағандары
    -- guard_courier_order_lock арқылы тапсырысты мәңгі жауып тастар еді.
    new.courier_uid       := null;
    new.courier_status    := '';
    new.post_tracking     := '';
    new.post_status       := '';
    new.post_shipped_at   := null;
    new.post_delivered_at := null;
    return new;
  end if;

  -- UPDATE. auth.uid() бос = cron / service_role.
  if auth.uid() is null
     or public.is_superadmin()
     or current_setting('qoima.kazpost_rpc', true) = '1' then
    return new;
  end if;

  if new.kazpost_fee          is distinct from old.kazpost_fee
     or new.post_recipient_name  is distinct from old.post_recipient_name
     or new.post_recipient_phone is distinct from old.post_recipient_phone
     or new.post_index           is distinct from old.post_index
     or new.post_tracking        is distinct from old.post_tracking
     or new.post_status          is distinct from old.post_status
     or new.post_shipped_at      is distinct from old.post_shipped_at
     or new.post_delivered_at    is distinct from old.post_delivered_at then
    raise exception 'kazpost_fields_locked';
  end if;

  if new.delivery_mode is distinct from old.delivery_mode
     and (old.delivery_mode = 'kazpost' or new.delivery_mode = 'kazpost') then
    raise exception 'kazpost_fields_locked';
  end if;

  if old.delivery_mode = 'kazpost' then
    -- Баға бағытқа байланған: төленген соң қала/мекенжай ауыспайды.
    if new.client_city is distinct from old.client_city
       or new.address  is distinct from old.address then
      raise exception 'kazpost_fields_locked';
    end if;
    -- Аяқталған тапсырыс тек возвратпен ғана күйін ауыстырады: claim_order_transition
    -- кез келген ауысуды жібереді, ал кері қайтса посылка жолда емес, ілініп қалады.
    if old.status = 'completed' and new.status is distinct from old.status
       and new.status <> 'returned' then
      raise exception 'kazpost_fields_locked';
    end if;
    if new.status is distinct from old.status and old.status <> 'completed' then
      -- Аяқтау тек kazpost_complete_order арқылы (sales_history сонда жазылады).
      if new.status = 'completed' then
        raise exception 'kazpost_use_rpc';
      end if;
      -- Почтаға кетіп қойған тапсырысты болдырмау мүмкін емес.
      if old.post_status = 'shipped' then
        raise exception 'kazpost_already_shipped';
      end if;
    end if;
  end if;

  return new;
end;
$$;
revoke all on function public.guard_orders_kazpost() from public, anon, authenticated;

drop trigger if exists trg_guard_orders_kazpost on public.orders;
create trigger trg_guard_orders_kazpost
  before insert or update on public.orders
  for each row execute function public.guard_orders_kazpost();

-- ── 5. Дүкен: трек енгізу ────────────────────────────────────────────────────
-- Қате терілген тректі түзетуге болады (клиентке push қайта кетпейді).
create or replace function public.kazpost_mark_shipped(p_order uuid, p_tracking text)
returns public.orders
language plpgsql security definer set search_path = public as $$
declare
  v_order public.orders;
  v_track text := upper(regexp_replace(coalesce(p_tracking, ''), '\s', '', 'g'));
  v_first boolean;
begin
  if auth.uid() is null then
    raise exception 'not_authorized';
  end if;
  select * into v_order from public.orders where id = p_order for update;
  if not found then
    raise exception 'order_not_found';
  end if;
  if v_order.admin_uid is distinct from public.app_owner_uid()
     and not public.is_superadmin() then
    raise exception 'not_your_order';
  end if;
  if coalesce(v_order.delivery_mode, '') <> 'kazpost' then
    raise exception 'not_kazpost_order';
  end if;
  -- 'delivered' — бір рет аяқталған: қайта «жіберілді» болса, сатылым екі рет жазылар еді.
  if v_order.status <> 'confirmed' or v_order.post_status = 'delivered' then
    raise exception 'order_state_changed:%', v_order.status;
  end if;
  if v_track !~ '^[A-Z0-9]{8,30}$' then
    raise exception 'kazpost_tracking_invalid';
  end if;

  v_first := v_order.post_status = '';
  perform set_config('qoima.kazpost_rpc', '1', true);
  update public.orders set
    post_tracking   = v_track,
    post_status     = 'shipped',
    post_shipped_at = coalesce(post_shipped_at, now()),
    deadline_at     = null
  where id = p_order
  returning * into v_order;
  perform set_config('qoima.kazpost_rpc', '', true);

  if v_first and v_order.client_uid is not null then
    perform public.notify_push(
      array[v_order.client_uid],
      '📦 Посылка отправлена / Сәлемдеме жіберілді',
      coalesce(nullif(v_order.store_name, ''), 'Магазин')
        || ' · №' || v_order.order_number || E'\n'
        || 'Казпочта: ' || v_track,
      jsonb_build_object('type', 'order_status', 'orderId', v_order.id,
                         'status', v_order.status));
  end if;
  return v_order;
end;
$$;
revoke execute on function public.kazpost_mark_shipped(uuid, text) from public;
grant execute on function public.kazpost_mark_shipped(uuid, text) to authenticated;

-- ── 6. Аяқтау: ортақ ішкі функция ────────────────────────────────────────────
-- courier_complete_order (0053) үлгісімен: статус + sales_history бір транзакцияда.
-- kazpost_fee sales_history-ге ӘДЕЙІ кірмейді (бас жағын қара).
-- p_actor_name — delivered_by_name: посылканы табыстаған ПОЧТА, жапқан адам емес
-- (бұл мән иесінің push-ында «Выдал(а): …» болып шығады). Жапқан адам —
-- delivered_by_uid.
create or replace function public._kazpost_finish(p_order uuid, p_actor_name text)
returns public.orders
language plpgsql security definer set search_path = public as $$
declare
  v_order   public.orders;
  v_receipt text;
  v_seq     bigint;
  v_total   numeric := 0;
  v_factor  numeric := 1;
begin
  select * into v_order from public.orders where id = p_order for update;
  if not found then
    raise exception 'order_not_found';
  end if;

  -- Күй ҚҰЛЫПТАН КЕЙІН тексеріледі: sweep id-лерді құлыпсыз таңдайды, сол арада
  -- клиент не дүкен жауып үлгерсе, сатылым екі рет жазылмасын.
  if coalesce(v_order.delivery_mode, '') <> 'kazpost'
     or v_order.status <> 'confirmed'
     or v_order.post_status <> 'shipped' then
    return v_order;
  end if;

  if v_order.order_number > 0 then
    v_seq := v_order.order_number;
  else
    -- next_counter емес: ол auth.uid() талап етеді (0065), ал cron-да uid жоқ.
    insert into public.counters (owner_uid, name, value)
    values (v_order.admin_uid, 'receipts', 1)
    on conflict (owner_uid, name) do update set value = public.counters.value + 1
    returning value into v_seq;
  end if;
  v_receipt := '#' || lpad(v_seq::text, 5, '0');

  perform set_config('qoima.kazpost_rpc', '1', true);
  update public.orders set
    status            = 'completed',
    post_status       = 'delivered',
    post_delivered_at = now(),
    delivered_by_uid  = coalesce(auth.uid()::text, ''),
    delivered_by_name = coalesce(p_actor_name, ''),
    receipt_number    = v_receipt,
    deadline_at       = null
  where id = p_order
  returning * into v_order;
  perform set_config('qoima.kazpost_rpc', '', true);

  select coalesce(sum((it ->> 'price')::numeric * coalesce((it ->> 'qty')::int, 1)), 0)
    into v_total from jsonb_array_elements(v_order.items) it;
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
    jsonb_build_object(coalesce(it ->> 'size', ''), coalesce((it ->> 'qty')::int, 1)),
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
    coalesce(p_actor_name, ''),
    case when coalesce(v_order.payment_bank, '') <> '' then v_order.payment_bank else 'card' end,
    v_receipt,
    'sale'
  from jsonb_array_elements(v_order.items) it;

  perform public.recompute_product_status(q.pid)
    from (select distinct (it ->> 'productId')::uuid as pid
            from jsonb_array_elements(v_order.items) it) q;

  return v_order;
end;
$$;
revoke all on function public._kazpost_finish(uuid, text) from public, anon, authenticated;

-- Клиент — кез келген уақытта; дүкен — жіберген соң 7 күннен кейін (клиент
-- алмай тұрып «жабылды» деп, қайтару мерзімін бастап жібермеуі үшін).
create or replace function public.kazpost_complete_order(p_order uuid)
returns public.orders
language plpgsql security definer set search_path = public as $$
declare
  v_order public.orders;
begin
  if auth.uid() is null then
    raise exception 'not_authorized';
  end if;
  select * into v_order from public.orders where id = p_order for update;
  if not found then
    raise exception 'order_not_found';
  end if;
  if coalesce(v_order.delivery_mode, '') <> 'kazpost' then
    raise exception 'not_kazpost_order';
  end if;

  if v_order.client_uid is distinct from auth.uid()
     and not public.is_superadmin() then
    if v_order.admin_uid is distinct from public.app_owner_uid() then
      raise exception 'not_your_order';
    end if;
    if v_order.post_shipped_at is null
       or v_order.post_shipped_at > now() - interval '7 days' then
      raise exception 'kazpost_too_early';
    end if;
  end if;

  -- Екінші басу (клиент пен дүкен бір мезгілде) — қате емес, бірақ қайта жазбаймыз.
  if v_order.status = 'completed' then
    return v_order;
  end if;
  if v_order.status <> 'confirmed' or v_order.post_status <> 'shipped' then
    raise exception 'order_state_changed:%', v_order.status;
  end if;

  return public._kazpost_finish(p_order, 'Казпочта');
end;
$$;
revoke execute on function public.kazpost_complete_order(uuid) from public;
grant execute on function public.kazpost_complete_order(uuid) to authenticated;

-- Клиент те, дүкен де баспаса — 30 күннен кейін автоматты жабылады.
create or replace function public.sweep_kazpost_autocomplete()
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_id uuid;
begin
  for v_id in
    select o.id from public.orders o
     where o.delivery_mode = 'kazpost'
       and o.post_status = 'shipped'
       and o.status = 'confirmed'
       and o.post_shipped_at < now() - interval '30 days'
  loop
    -- Бір тапсырыстың қатесі бүкіл жүрісті кері айналдырмасын: әйтпесе ол жол
    -- күн сайын барлық дүкеннің авто-жабылуын тоқтатып тұрар еді.
    begin
      perform public._kazpost_finish(v_id, 'Казпочта (авто)');
    exception when others then
      raise warning 'kazpost_autocomplete_failed order=% sqlstate=% error=%',
        v_id, sqlstate, sqlerrm;
    end;
  end loop;
end;
$$;
revoke all on function public.sweep_kazpost_autocomplete() from public, anon, authenticated;

select cron.schedule('kazpost-autocomplete', '15 6 * * *',
  $$select public.sweep_kazpost_autocomplete()$$);

-- ── 6б. Возвратқа клиенттің трегі ────────────────────────────────────────────
-- Клиент посылканы дүкен мақұлдаған соң жібереді, сондықтан трек өтініш кезінде
-- әлі жоқ: кейін осы RPC-мен жазылады. Дүкенге бірінші жазылғанда ғана push барады.
create or replace function public.return_set_post_tracking(p_return text, p_tracking text)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_ret   public.returns;
  v_track text := upper(regexp_replace(coalesce(p_tracking, ''), '\s', '', 'g'));
begin
  if auth.uid() is null then
    raise exception 'not_authorized';
  end if;
  select * into v_ret from public.returns where id = p_return for update;
  if not found then
    raise exception 'return_not_found';
  end if;
  if v_ret.client_uid is distinct from auth.uid() then
    raise exception 'not_your_return';
  end if;
  if coalesce(v_ret.pickup, '') <> 'post'
     or v_ret.status not in ('requested', 'approved') then
    raise exception 'return_state_changed:%', v_ret.status;
  end if;
  if v_track !~ '^[A-Z0-9]{8,30}$' then
    raise exception 'kazpost_tracking_invalid';
  end if;

  update public.returns set post_tracking = v_track where id = p_return;

  if coalesce(v_ret.post_tracking, '') = '' then
    perform public.notify_push(
      array[v_ret.admin_uid],
      '📦 Возврат отправлен Казпочтой / Қайтарым Казпочтамен жіберілді',
      v_ret.id || ' · ' || v_track,
      jsonb_build_object('type', 'return_status', 'returnId', v_ret.id));
  end if;
end;
$$;
revoke execute on function public.return_set_post_tracking(text, text) from public;
grant execute on function public.return_set_post_tracking(text, text) to authenticated;

-- ── 7. Возврат: клиент басқа қалада — тауарды почтамен жібереді ──────────────
-- returns.pickup-қа 'post' қосылды (ReturnPickup.post). Сервердегі тексерістер
-- тек pickup = 'courier' салыстырады, сондықтан ақ тізім өзгермейді. Өзгерген
-- жалғыз нәрсе — 0058-дегі push мәтіні: «дүкенге әкеліңіз» деп жазбау.
create or replace function public.on_return_status_push()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_title text;
  v_body  text;
  v_first text := coalesce(new.items->0->>'product_title',
                           new.items->0->>'productName', '');
  v_uids  uuid[];
  v_city  text;
begin
  if new.status is not distinct from old.status then return new; end if;

  -- ── Клиентке ────────────────────────────────────────────────────────────
  if new.client_uid is not null then
    if new.status = 'approved' then
      v_title := '✅ Возврат одобрен / Қайтарым мақұлданды';
      v_body  := case when new.pickup = 'courier'
                   then 'Курьер заберёт товар / Курьер тауарды алады'
                   when new.pickup = 'post'
                   then 'Отправьте товар Казпочтой в магазин / Тауарды Казпочтамен дүкенге жіберіңіз'
                   else 'Принесите товар в магазин / Тауарды дүкенге әкеліңіз'
                 end;
    elsif new.status = 'rejected' then
      v_title := '❌ Возврат отклонён / Қайтарым қабылданбады';
      v_body  := coalesce(nullif(new.rejection_reason, ''), v_first);
    elsif new.status = 'received' then
      v_title := '📦 Магазин принял товар / Дүкен тауарды қабылдады';
      v_body  := 'Возврат денег готовится / Ақша қайтару дайындалуда';
    elsif new.status = 'refunded' then
      v_title := '💸 Деньги возвращены / Ақша қайтарылды';
      v_body  := new.total_amount::int || ' ₸'
                 || case when coalesce(new.refund_method, '') = 'cash'
                      then ' — наличными / қолма-қол'
                      else ' — на карту / картаға' end;
    end if;

    if v_title is not null then
      perform public.notify_push(
        array[new.client_uid], v_title, v_body,
        jsonb_build_object('type', 'return_status', 'returnId', new.id));
    end if;
  end if;

  -- ── Курьерлерге: қалада жаңа возврат тасымалы шықты ─────────────────────
  --  Дүкен растаған, курьермен алынатын, әлі ешкім алмаған возврат.
  if new.status = 'approved'
     and new.pickup = 'courier'
     and new.courier_uid is null then
    select s.city into v_city from public.stores s
     where s.admin_uid = new.admin_uid;
    if public.courier_city_enabled(v_city) then
      select array_agg(u.id) into v_uids from public.users u
       where u.role = 'courier' and u.courier_status = 'active'
         and coalesce(u.blocked, false) = false and u.city = v_city;
      perform public.notify_push(
        coalesce(v_uids, '{}'::uuid[]),
        '↩️ Новый возврат / Жаңа қайтарым',
        coalesce(nullif(v_city, ''), '') || ' — забрать у клиента / клиенттен алу',
        jsonb_build_object('type', 'courier_work', 'returnId', new.id));
    end if;
  end if;

  return new;
end;
$$;
revoke all on function public.on_return_status_push() from public, anon, authenticated;
