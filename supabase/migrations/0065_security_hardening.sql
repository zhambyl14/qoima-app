-- ═══════════════════════════════════════════════════════════════════════════
--  0065 — ҚАУІПСІЗДІК ҚАТАЙТУЫ (privilege escalation + anon RPC + RLS тесіктері)
-- ═══════════════════════════════════════════════════════════════════════════
--  Барлық тармақ ТІРІ БД-дан сұрау салып расталған (pg_policies, pg_proc,
--  has_function_privilege). Әрқайсысының жанында «неге» жазылған.
--
--  ЕҢ МАҢЫЗДЫСЫ: бұл миграция ҚОСЫМШАНЫҢ АҒЫМДАҒЫ АҒЫНДАРЫН СЫНДЫРМАУҒА
--  бағытталған. Сол себепті adjust_batch_sizes сияқты, Dart-тан 11 жерде
--  тікелей шақырылатын функциялардан `authenticated` құқығы АЛЫНБАЙДЫ —
--  оның орнына ішіне «кірген адам ба» тексерісі қосылады, ал нақты
--  «клиент қойманы тікелей жазбауы керек» деген түбегейлі түзету
--  2-толқында (мақсатты RPC-лер) жасалады.
-- ═══════════════════════════════════════════════════════════════════════════


-- ── 1. КРИТИКАЛЫҚ: signUp метадеректеріндегі role сеніледі ──────────────────
--  Бұрын: handle_new_user рөлді `new.raw_user_meta_data->>'role'` -тен алатын.
--  Ол өрісті КЛИЕНТ signUp кезінде өзі толтырады. Демек қосымшада ашық жүретін
--  anon key-мен POST /auth/v1/signup body-сына {"data":{"role":"superadmin"}}
--  жазған кез келген адам superadmin болып тіркеліп, бірден сессия алатын
--  (email растау өшірулі). Одан кейін is_superadmin() true → app_settings жазу,
--  кез келген дүкенді блоктау, БАРЛЫҚ клиенттің телефоны мен мекенжайын оқу.
--
--  Енді: рөл ақ тізіммен шектеледі, 'superadmin' МҮЛДЕ мүмкін емес.
--  Superadmin тек SQL арқылы қолмен беріледі (0004 сценарийі сияқты).
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_role  text := coalesce(new.raw_user_meta_data->>'role', 'client');
  v_name  text := coalesce(new.raw_user_meta_data->>'name', '');
  v_phone text := coalesce(new.raw_user_meta_data->>'phone', '');
  v_city  text := coalesce(new.raw_user_meta_data->>'city', '');
  v_code  text;
begin
  -- Ақ тізім: тіркелу арқылы АЛУҒА БОЛАТЫН рөлдер ғана.
  -- 'superadmin' осында ЖОҚ — сырттан беріле алмайды.
  if v_role not in ('client', 'seller', 'admin', 'courier') then
    v_role := 'client';
  end if;

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


-- ── 2. КРИТИКАЛЫҚ: users_update саясаты бағанды шектемейді ──────────────────
--  users_update: USING/WITH CHECK = (id = auth.uid() OR is_superadmin()).
--  Postgres RLS БАҒАН деңгейінде шектей алмайды, сондықтан кез келген
--  seller/admin/courier өзінің жолында мынаны жаза алатын:
--    update users set role='superadmin' where id = auth.uid();          → платформаны иелену
--    update users set owner_id='<басқа админ>' , join_status='active';  → бекітусіз бөтен дүкенге кіру
--    update users set subscription_until='2099-01-01';                  → мәңгі тегін жазылым
--    update users set blocked=false;                                    → модератор блогынан шығу
--
--  Шешім: BEFORE UPDATE триггері. Логика дәл: ТЕК «өз жолын өзі өңдегенде»
--  артықшылықты бағандарды бұғаттайды. Модератор (is_superadmin) және
--  БАСҚАНЫҢ жолын өзгертетін ағындар (approve_join_request, remove_seller,
--  reassign_seller_warehouse, superadmin_set_courier, блоктау, жазылым беру)
--  ЕШ ӨЗГЕРІССІЗ жұмыс істей береді — олар old.id <> auth.uid() жағдайы.
--
--  Заңды өзін-өзі өзгертулер АТАП АҚТАЛАДЫ:
--    • owner_id → NULL          (auth_service.detachFromOwner: дүкеннен шығу)
--    • join_status → 'none'     (сол детач / сұранысты болдырмау)
--    • join_status → 'pending'  (sendJoinRequest: қосылу сұранысын жіберу)
--    • shop_status / shop_request_id (shop_apply_screen: дүкен өтінімі) — тізімде жоқ
create or replace function public.guard_users_privileged_columns()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  -- Модератор бәрін өзгерте алады.
  if public.is_superadmin() then return new; end if;

  -- Басқаның жолы (иесі/RPC арқылы) — бұл триггердің қарауына жатпайды.
  if old.id is distinct from auth.uid() then return new; end if;

  -- ── Осыдан әрі: пайдаланушы ӨЗ жолын өңдеп отыр ──
  if new.role is distinct from old.role then
    raise exception 'privileged_column_denied:role';
  end if;
  if new.business_code is distinct from old.business_code then
    raise exception 'privileged_column_denied:business_code';
  end if;
  if new.blocked is distinct from old.blocked then
    raise exception 'privileged_column_denied:blocked';
  end if;
  if new.subscription_until is distinct from old.subscription_until
     or new.subscription_started_at is distinct from old.subscription_started_at
     or new.subscription_plan is distinct from old.subscription_plan then
    raise exception 'privileged_column_denied:subscription';
  end if;
  if new.courier_status is distinct from old.courier_status then
    raise exception 'privileged_column_denied:courier_status';
  end if;

  -- owner_id: өзін-өзі ТЕК ажырата алады (NULL-ге), тағайындай алмайды.
  if new.owner_id is distinct from old.owner_id and new.owner_id is not null then
    raise exception 'privileged_column_denied:owner_id';
  end if;

  -- join_status: өзі тек сұраныс жіберу/болдырмау күйлерін қоя алады.
  if new.join_status is distinct from old.join_status
     and coalesce(new.join_status, '') not in ('none', 'pending') then
    raise exception 'privileged_column_denied:join_status';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_guard_users_privileged_columns on public.users;
create trigger trg_guard_users_privileged_columns
  before update on public.users
  for each row execute function public.guard_users_privileged_columns();


-- ── 3. ЖОҒАРЫ: orders_update клиентке АҚША бағандарын жазуға рұқсат береді ──
--  orders_update: (client_uid = auth.uid() OR admin_uid = app_owner_uid()).
--  Баған шектеуі жоқ, сондықтан клиент өз тапсырысында мынаны жаза алатын:
--    delivery_fee=0, deposit_amount=0, promo_discount=<қалағанын>,
--    payment_confirmed_by=<өзі>, payment_confirmed_at=now()  → төлемей «төледім»,
--    pickup_code=<қалағанын>, courier_uid=null, items=<арзандатылған тізім>.
--
--  Шешім: клиент әрекет етіп отырғанда (auth.uid() = client_uid, бірақ ол
--  дүкен иесі де, модератор да емес) ақша/өкілет бағандарын бұғаттау.
--  Клиенттің ЗАҢДЫ жазатындары ашық қалады: address, note, client_phone,
--  client_name, client_city, receipt_url, receipt_submitted_at, stock_restored,
--  order_number, cart_group_id, status (ол claim_order_transition-де тексеріледі).
create or replace function public.guard_orders_client_money()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if public.is_superadmin() then return new; end if;
  -- Дүкен иесі / сатушы / курьер — бұл триггерге жатпайды.
  if auth.uid() is distinct from old.client_uid then return new; end if;
  if old.admin_uid = public.app_owner_uid() then return new; end if;
  if old.courier_uid is not null and old.courier_uid = auth.uid() then return new; end if;

  if new.items is distinct from old.items then
    raise exception 'client_cannot_change:items';
  end if;
  if new.delivery_fee is distinct from old.delivery_fee
     or new.deposit_amount is distinct from old.deposit_amount
     or new.fitting_fee is distinct from old.fitting_fee
     or new.promo_discount is distinct from old.promo_discount
     or new.promo_id is distinct from old.promo_id
     or new.promo_counts_usage is distinct from old.promo_counts_usage then
    raise exception 'client_cannot_change:money';
  end if;
  if new.payment_confirmed_by is distinct from old.payment_confirmed_by
     or new.payment_confirmed_at is distinct from old.payment_confirmed_at
     or new.delivery_fee_collected is distinct from old.delivery_fee_collected
     or new.delivery_fee_collected_at is distinct from old.delivery_fee_collected_at then
    raise exception 'client_cannot_change:payment_confirmation';
  end if;
  if new.pickup_code is distinct from old.pickup_code
     or new.admin_uid is distinct from old.admin_uid
     or new.client_uid is distinct from old.client_uid
     or new.warehouse_id is distinct from old.warehouse_id
     or new.seller_id is distinct from old.seller_id
     or new.courier_uid is distinct from old.courier_uid
     or new.courier_status is distinct from old.courier_status then
    raise exception 'client_cannot_change:authority';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_guard_orders_client_money on public.orders;
create trigger trg_guard_orders_client_money
  before update on public.orders
  for each row execute function public.guard_orders_client_money();


-- ── 4. ЖОҒАРЫ: claim_order_transition — авторизация ЖОҚ, anon-ға ашық ───────
--  Бұрын: кез келген адам (тіркелмесе де) кез келген тапсырыстың статусын
--  кез келген мәнге қоя алатын. guard_courier_order_lock тек курьер ұстап
--  тұрғанда қорғайды, қалған тапсырыстар ашық еді.
--  Енді: (а) әрекет етушінің осы тапсырысқа қатысы тексеріледі,
--        (б) жаңа статус ақ тізімнен ғана болады (қоқыс статус жазылмайды).
create or replace function public.claim_order_transition(
  p_order uuid,
  p_expected text[],
  p_new_status text,
  p_actor_role text default '',
  p_actor_uid text default '',
  p_actor_name text default ''
) returns public.orders
language plpgsql security definer set search_path = public as $$
declare
  v_order public.orders;
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;

  -- Ақ тізім OrderModel.status* тұрақтыларының ДӘЛ көшірмесі
  -- (lib/data/models/order_model.dart:141-148). Жаңа статус қосылса —
  -- екі жерде де қосу керек (guardrail: CI grep, төмендегі ЕСКЕРТПЕНІ оқы).
  if p_new_status not in (
    'reserved', 'pending', 'rejected', 'confirmed',
    'ready', 'completed', 'cancelled', 'returned'
  ) then
    raise exception 'invalid_status:%', p_new_status;
  end if;

  select * into v_order from public.orders where id = p_order for update;
  if not found then
    raise exception 'order_not_found';
  end if;

  -- Осы тапсырысқа қатысы бар ма: клиент / дүкен иесі (немесе сатушысы) /
  -- тағайындалған курьер / модератор.
  if not (
    v_order.client_uid = auth.uid()
    or v_order.admin_uid = public.app_owner_uid()
    or (v_order.courier_uid is not null and v_order.courier_uid = auth.uid())
    or public.is_superadmin()
  ) then
    raise exception 'not_your_order';
  end if;

  if not (v_order.status = any(p_expected)) then
    raise exception 'order_state_changed:%', v_order.status;
  end if;

  update public.orders set
    status = p_new_status,
    cancelled_by_role = case when p_new_status = 'cancelled' then p_actor_role else cancelled_by_role end,
    cancelled_by_uid  = case when p_new_status = 'cancelled' then p_actor_uid  else cancelled_by_uid  end,
    cancelled_by_name = case when p_new_status = 'cancelled' then p_actor_name else cancelled_by_name end,
    cancelled_at      = case when p_new_status = 'cancelled' then now() else cancelled_at end
  where id = p_order
  returning * into v_order;

  return v_order;
end;
$$;


-- ── 5. КРИТИКАЛЫҚ: adjust_batch_sizes — авторизация ЖОҚ, anon-ға ашық ──────
--  Бұрын: тіркелмеген адам да кез келген партияның sizes_quantity /
--  reserved_sizes мәндерін қалауынша қайта жаза алатын (қосымшадағы anon key
--  жеткілікті). Қойманы нөлге түсіру, минус қылу, бөтен дүкенді сату.
--
--  ЕСКЕРТУ: бұл функцияны Dart 11 жерден тікелей шақырады (себет броны,
--  сату, возврат, ревизия), сондықтан `authenticated`-тен АЛУҒА БОЛМАЙДЫ —
--  әйтпесе қосымша сынады. Қазір: anon бұғатталады. Түбегейлі шешім
--  (клиент қоймаға тікелей жазбауы) — 2-толқындағы мақсатты RPC-лер.
create or replace function public.adjust_batch_sizes(
  p_batch uuid, p_deltas jsonb, p_field text, p_guard boolean default false
) returns void language plpgsql security definer set search_path = public as $$
declare
  v_q jsonb; v_r jsonb; v_sizes jsonb; k text; d int;
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  if p_field not in ('sizes_quantity', 'reserved_sizes') then
    raise exception 'invalid_field:%', p_field;
  end if;

  select sizes_quantity, reserved_sizes into v_q, v_r
    from public.batches where id = p_batch for update;
  if not found then raise exception 'batch_not_found'; end if;

  v_sizes := case when p_field = 'reserved_sizes' then v_r else v_q end;
  for k, d in select key, value::int from jsonb_each_text(p_deltas) loop
    v_sizes := jsonb_set(v_sizes, array[k],
      to_jsonb(coalesce((v_sizes->>k)::int, 0) + d));
  end loop;

  if p_field = 'reserved_sizes' then
    update public.batches set reserved_sizes = v_sizes where id = p_batch;
    v_r := v_sizes;
  else
    update public.batches set sizes_quantity = v_sizes where id = p_batch;
    v_q := v_sizes;
  end if;

  if p_guard then
    for k in select key from jsonb_each_text(p_deltas) loop
      if coalesce((v_q->>k)::int, 0) - coalesce((v_r->>k)::int, 0) < 0 then
        raise exception 'insufficient_stock:%', k;
      end if;
    end loop;
  end if;
end;
$$;


-- ── 6. ОРТА: тексерісі жоқ есептегіш/жиынтық RPC-лер anon-ға ашық ──────────
--  next_counter → бөтен дүкеннің чек/тапсырыс нөмірлерін жағу (нөмір атап кету).
--  increment_warehouse_totals → қойма жиынтығын бүлдіру.
--  adjust_promo_usage → промокод есептегішін бүлдіру (лимиттен асыру).
--  recompute_product_status → жүкті арттыру (DoS-қа жақын).
--  Барлығын «кірген адам ба» тексерісімен қорғаймыз (Dart-тан шақырылады,
--  сондықтан authenticated қалады).
create or replace function public.next_counter(p_owner uuid, p_name text)
returns bigint language plpgsql security definer set search_path = public as $$
declare v bigint;
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  insert into public.counters(owner_uid, name, value) values (p_owner, p_name, 1)
  on conflict (owner_uid, name) do update set value = public.counters.value + 1
  returning value into v;
  return v;
end;
$$;

revoke execute on function public.next_counter(uuid, text) from anon;
revoke execute on function public.adjust_batch_sizes(uuid, jsonb, text, boolean) from anon;
revoke execute on function public.claim_order_transition(uuid, text[], text, text, text, text) from anon;
revoke execute on function public.increment_warehouse_totals(uuid, integer, integer) from anon;
revoke execute on function public.adjust_promo_usage(uuid, uuid, integer) from anon;
revoke execute on function public.recompute_product_status(uuid) from anon;
revoke execute on function public.release_fitting_holds(uuid, integer[]) from anon;
revoke execute on function public.store_handover_fitting(uuid, integer[]) from anon;
revoke execute on function public.store_confirm_return_leg(uuid) from anon;
revoke execute on function public.get_or_create_referral_code(uuid) from anon;
revoke execute on function public.my_referral_stores() from anon;
revoke execute on function public.superadmin_set_courier(uuid, text, text) from anon;

-- notify_push — Dart-тан ЕШҚАШАН шақырылмайды, тек триггерлерден.
-- Триггер орындалуында EXECUTE құқығы тексерілмейді, сондықтан екеуінен де
-- алу қауіпсіз. Бұрын: кез келген адам платформа атынан кез келген
-- пайдаланушыға push + notifications жазба жібере алатын (фишинг).
revoke execute on function public.notify_push(uuid[], text, text, jsonb) from anon, authenticated;

-- Триггер функциялары мен жоспарлы sweep-тер — қолмен шақырылмауы керек.
-- (sweep_returned_photos Dart-тан шақырылады, сондықтан ол тізімде ЖОҚ.)
revoke execute on function public.handle_new_user() from anon, authenticated;
revoke execute on function public.rls_auto_enable() from anon, authenticated;
revoke execute on function public.auto_confirm_email() from anon, authenticated;
revoke execute on function public.guard_courier_order_lock() from anon, authenticated;
revoke execute on function public.sweep_sold_out_images(integer) from anon, authenticated;
revoke execute on function public.sweep_expired_receipts(integer) from anon, authenticated;
revoke execute on function public.sweep_daily_digest() from anon, authenticated;
revoke execute on function public.sweep_review_reminders() from anon, authenticated;
revoke execute on function public.sweep_reservation_reminders() from anon, authenticated;
revoke execute on function public.sweep_subscription_expiry_reminders() from anon, authenticated;


-- ── 7. ЖОҒАРЫ: courier_deliveries — толық ашық (клиент PII + ақша) ──────────
--  Бұрын: courier_select USING(true) және courier_write ALL USING(true)
--  WITH CHECK(true) — `authenticated` рөліне. Демек кез келген тіркелген адам
--  (қарапайым сатып алушы да) БАРЛЫҚ жеткізудің client_name, client_phone,
--  address, amount мәндерін оқи алатын ЖӘНЕ өзгертіп/жойып жібере алатын.
drop policy if exists courier_select on public.courier_deliveries;
drop policy if exists courier_write  on public.courier_deliveries;

-- Оқу: тапсырыстың клиенті, дүкен иесі, тағайындалған курьер, модератор.
create policy courier_deliveries_read on public.courier_deliveries
  for select to authenticated using (
    public.is_superadmin()
    or exists (
      select 1 from public.orders o
      -- ⚠️ courier_deliveries.order_id — TEXT (orders.id — uuid, FK жоқ).
      -- Схема ақауы, сондықтан cast міндетті.
      where o.id::text = courier_deliveries.order_id
        and (o.client_uid = auth.uid()
             or o.admin_uid = public.app_owner_uid()
             or o.courier_uid = auth.uid())
    )
  );

-- Жазу: дүкен иесі (жеткізуді құрады) немесе тағайындалған курьер, модератор.
create policy courier_deliveries_write on public.courier_deliveries
  for all to authenticated using (
    public.is_superadmin()
    or exists (
      select 1 from public.orders o
      -- ⚠️ courier_deliveries.order_id — TEXT (orders.id — uuid, FK жоқ).
      -- Схема ақауы, сондықтан cast міндетті.
      where o.id::text = courier_deliveries.order_id
        and (o.admin_uid = public.app_owner_uid() or o.courier_uid = auth.uid())
    )
  ) with check (
    public.is_superadmin()
    or exists (
      select 1 from public.orders o
      -- ⚠️ courier_deliveries.order_id — TEXT (orders.id — uuid, FK жоқ).
      -- Схема ақауы, сондықтан cast міндетті.
      where o.id::text = courier_deliveries.order_id
        and (o.admin_uid = public.app_owner_uid() or o.courier_uid = auth.uid())
    )
  );


-- ── 8. ОРТА: business_codes — бәрі бәрінің кодын оқиды ─────────────────────
--  Бұрын: bc_select USING(true) — кез келген тіркелген адам БАРЛЫҚ дүкеннің
--  бизнес-кодын тізіп ала алатын. Бизнес-код — сатушының дүкенге қосылу
--  қақпасы, демек қақпа мағынасыз болатын.
--  Енді: иесі өз кодын көреді. Қосылу ағыны нақты кодты RPC арқылы тексереді
--  (тізім бермейді, тек дәл сәйкестікте иесінің uid-ін қайтарады).
drop policy if exists bc_select on public.business_codes;
create policy bc_select on public.business_codes
  for select to authenticated using (admin_uid = auth.uid() or public.is_superadmin());

create or replace function public.business_code_owner(p_code text)
returns uuid language sql security definer set search_path = public
stable as $$
  select admin_uid from public.business_codes
   where code = upper(trim(p_code)) limit 1;
$$;
revoke execute on function public.business_code_owner(text) from anon, public;
grant  execute on function public.business_code_owner(text) to authenticated;


-- ── 9. ТӨМЕН: search_path mutable (advisor) ────────────────────────────────
--  search_path бекітілмеген SECURITY DEFINER функцияға схема алмастыру
--  шабуылы жасауға болады.
alter function public.set_product_articul()      set search_path = public;
alter function public.check_question_rate_limit() set search_path = public;


-- ═══════════════════════════════════════════════════════════════════════════
--  ҚОЛМЕН ЖАСАЛАТЫН (SQL-мен жасалмайды — Dashboard):
--   1. Authentication → Policies → «Leaked password protection» ҚОСУ.
--   2. extension pg_net -ті `extensions` схемасына көшіру (advisor ескертуі;
--      notify_push ішіндегі net.http_post жолын да түзету керек — сондықтан
--      бөлек, жоспарланған терезеде).
--   3. superadmin рөлі енді тіркелу арқылы берілмейді. ЖАҢА модератор қосу:
--        update public.users set role = 'superadmin' where phone = '<нөмір>';
--      (0004 сценарийіндегідей, SQL editor-дан.)
-- ═══════════════════════════════════════════════════════════════════════════
