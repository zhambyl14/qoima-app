-- ════════════════════════════════════════════════════════════════════════════
-- 0088 — Басқа қаладағы дүкеннен «Бронь» / «Самовывоз» жасауға болмайды
-- ════════════════════════════════════════════════════════════════════════════
--  Клиент Алматыда, дүкен Астанада болса — «10% төлеп, қалғанын дүкенде»
--  (smart_reservation) да, «толық төлеп, дүкеннен өзім аламын» (click_collect)
--  да мағынасыз: клиент дүкенге бара алмайды. Мұндай себетке тек «Жеткізу»
--  (delivery, 100% алдын ала) қалады. Қосымша (client_cart_screen.dart,
--  cart_receiving_rules.dart) бұл тәсілдерді көрсетпейді; бұл триггер — ескі
--  немесе өзгертілген қосымшаға қарсы сервер күзеті.
--
--  ЕРЕЖЕ (Dart-тағы pickupAvailability-мен БІРДЕЙ):
--    order_type IN ('smart_reservation','click_collect')
--    AND clients.city   (тапсырыс берушінің профилі) бос емес
--    AND stores.city    (тапсырыс дүкені)            бос емес
--    AND norm(clients.city) <> norm(stores.city)
--    → raise 'pickup_city_mismatch'
--  norm = lower + шеттегі бос орындарды алу. Dart `String.trim()` ТЕК бос орын
--  емес, таб/жол ауысуы/NBSP т.б. Unicode бос белгілерін де алады, ал `btrim`
--  тек ' '-ты алады: «Астана\t» қосымшада «Астана» болып, серверде басқа қала
--  болып шығатын (клиент Броньді көреді де, сервер бас тартады). Сондықтан
--  мұнда Dart-тың trim() жиынымен бірдей regexp қолданылады.
--
--  INSERT + UPDATE OF order_type: бұрын тек INSERT тексерілетін — өзгертілген
--  қосымша «Жеткізу» жасап, кейін өз тапсырысының order_type-ын
--  'smart_reservation'-ға ауыстырып, күзетті айналып өтетін (guard_orders_
--  client_money order_type-ты құлыптамайды). UPDATE-те тек order_type НАҚТЫ
--  өзгергенде ғана тексеріледі — ескі тапсырыстардың басқа өзгерістері,
--  иесі/модератор/курьер/cron ешқашан бөгелмейді.
--
--  ӘДЕЙІ ЖІБЕРІЛЕТІНДЕР (жалған бөгеудің алдын алу):
--    • UPDATE-те order_type өзгермесе — ескі/ашық тапсырыстар бөгелмейді;
--    • сыйлық (create_gift_order / тілек тізімі): qoima.gift_rpc = 'on' —
--      сыйлаушы басқа қалада болуы қалыпты, алушы тәсілді өзі таңдайды;
--    • auth.uid() бос (service_role / cron) немесе тапсырыс берушінің өзі емес
--      (orders_insert RLS-і бұған жол бермейді, бірақ қызметкер/модератор
--      ағыны пайда болса — оған тиіспейміз);
--    • клиенттің немесе дүкеннің қаласы белгісіз (бос / жол жоқ) — бұрынғыдай.
--  delivery тапсырыстарына тиіспейді (олар 100% алдын ала).
--
--  SECURITY DEFINER: дүкен жарияланбаған/RLS жасырған болса да stores.city
--  сенімді оқылуы үшін. Функция тек триггер (returns trigger), тікелей
--  шақыруға болмайды; бәрібір CLAUDE.md ережесі бойынша PUBLIC-тен алынады.
--
--  IDEMPOTENT: create or replace + drop trigger if exists + revoke қайта.
--  0084-тің қай нұсқасы қолданылғанына тәуелді емес (оған тиіспейді).
-- ════════════════════════════════════════════════════════════════════════════

create or replace function public.guard_orders_pickup_city()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_uid         uuid := auth.uid();
  v_client_city text;
  v_store_city  text;
  -- Dart String.trim() алатын бос белгілер (0009–000D, 0020, 0085, 00A0, 1680,
  -- 2000–200A, 2028, 2029, 202F, 205F, 3000, FEFF) — локальге тәуелсіз тізім.
  v_ws constant text :=
    '[\t\n\v\f\r \u0085\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000\ufeff]';
begin
  if coalesce(new.order_type, '') not in ('smart_reservation', 'click_collect') then
    return new;
  end if;
  -- UPDATE: тек order_type НАҚТЫ өзгергенде (ескі тапсырыстың басқа өзгерісі —
  -- ескертпе, статус, чек — ешқашан бөгелмейді).
  if tg_op = 'UPDATE' and new.order_type is not distinct from old.order_type then
    return new;
  end if;
  -- Сыйлық RPC-лері (0070/0078/0079): тәсілді алушы кейін өзі таңдайды.
  if coalesce(current_setting('qoima.gift_rpc', true), '') = 'on' then
    return new;
  end if;
  -- Тек клиенттің өз тапсырысы: service_role/cron/қызметкер ағындары тиіспейді.
  if v_uid is null or new.client_uid is distinct from v_uid then
    return new;
  end if;

  select lower(regexp_replace(coalesce(c.city, ''),
                              '^' || v_ws || '+|' || v_ws || '+$', '', 'g'))
    into v_client_city
    from public.clients c where c.id = new.client_uid;
  select lower(regexp_replace(coalesce(s.city, ''),
                              '^' || v_ws || '+|' || v_ws || '+$', '', 'g'))
    into v_store_city
    from public.stores s where s.admin_uid = new.admin_uid;

  -- Белгісіз қала — бұрынғы мінез (жол жоқ болса select null қалдырады).
  if coalesce(v_client_city, '') = '' or coalesce(v_store_city, '') = '' then
    return new;
  end if;

  if v_client_city <> v_store_city then
    raise exception 'pickup_city_mismatch'
      using hint = 'Store is in another city: only delivery with full prepayment is allowed';
  end if;
  return new;
end;
$$;
-- Триггер функциясы: ешкімге тікелей EXECUTE қажет емес.
-- `create or replace` PUBLIC грантын қайта тудыратындықтан revoke әр жолы қайта.
revoke all on function public.guard_orders_pickup_city() from public, anon, authenticated;

drop trigger if exists trg_guard_orders_pickup_city on public.orders;
create trigger trg_guard_orders_pickup_city
  before insert or update of order_type on public.orders
  for each row execute function public.guard_orders_pickup_city();

-- Тексеру (тірі БД-да, тек оқу):
--   select proacl from pg_proc where proname = 'guard_orders_pickup_city';
--     → ішінде '=X/' болмауы тиіс
--   select tgname, tgenabled from pg_trigger
--    where tgrelid = 'public.orders'::regclass and tgname = 'trg_guard_orders_pickup_city';
