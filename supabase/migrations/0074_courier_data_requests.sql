-- ════════════════════════════════════════════════════════════════════════════
--  0074 · Курьер деректері: superadmin өңдейді, курьер өзгеріс СҰРАЙДЫ
-- ────────────────────────────────────────────────────────────────────────────
--  Курьердің деректері users кестесінде (0051): name, phone, city. Олар:
--    • name  → orders.courier_name-ге көшіріледі (дүкен мен клиент көреді);
--    • phone → КІРУ нөмірі (email_for_phone + tg-reset-password сол бойынша
--              аккаунт табады);
--    • city  → курьер ҚАЙ ҚАЛАНЫҢ тапсырысын (клиент мекенжайы, телефоны)
--              көретінін анықтайды — модерацияланатын өріс.
--
--  1) admin_update_courier(...) — superadmin кез келген курьердің деректерін
--     тікелей түзейді.
--  2) courier_change_requests + courier_request_change(...) — курьер өзгеріс
--     сұрайды (тек ақ тізімдегі кілттер: name/city), бір уақытта бір ғана
--     күтудегі сұраныс. ТЕЛЕФОН сұранысқа кірмейді: нөмір иелігін тексеру жоқ
--     (ол tg-reset-password кілті), сондықтан курьер нөмірді тек Telegram-мен
--     расталған ағынмен (AccountSecurityScreen) өзгертеді, ал superadmin
--     admin_update_courier арқылы өзгерте алады.
--  3) review_courier_change(...) — superadmin бекітеді/қабылдамайды; бекіткенде
--     ӨЗГЕРІС СОЛ ТРАНЗАКЦИЯДА, сұраныс жолы `for update` құлпымен қолданылады.
--
--  ТЕЛЕФОН ЖӘНЕ КІРУ (тек admin_update_courier): синтетикалық email (`<цифрлар>@qoima.app`) тіркелгенде
--  БІР РЕТ жасалады да, ЕШҚАШАН өзгермейді. Қолданыстағы Telegram арқылы нөмір
--  ауыстыру (auth_service.changePhoneVerified) де тек users.phone-ды жаңартады:
--  кіру телефон → email_for_phone → users.email (ескі синтетикалық) →
--  signInWithPassword. Сондықтан мұнда да auth.users-ке ТИМЕЙМІЗ — тек
--  users.phone, әрі нөмір users-те де, clients-те де бос болуы шарт (әйтпесе
--  email_for_phone/tg-reset-password басқа аккаунтқа апарады).
--
--  ТЕСІК ЖАБУ: guard_users_privileged_columns (0065) курьердің ӨЗ жолындағы
--  city-ді қорғамайтын — курьер `update users set city=...` деп модераторсыз
--  басқа қаланың тапсырыстарын көре алатын. Енді role='courier' үшін city
--  тек superadmin/RPC арқылы өзгереді (тірі анықтамаға бір ғана шарт қосылды).
-- ════════════════════════════════════════════════════════════════════════════

-- ── 0) guard_users_privileged_columns: курьердің city-ін құлыптау ───────────
--  Тірі БД анықтамасы (pg_get_functiondef, 2026-10-25) ДӘЛ қайталанды, тек
--  «курьер city» шарты қосылды. Админ/сатушы/суперадмин city-іне әсері жоқ.
create or replace function public.guard_users_privileged_columns()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if public.is_superadmin() then return new; end if;
  if old.id is distinct from auth.uid() then return new; end if;

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
  -- 0074: курьердің жұмыс қаласы — модерацияланатын өріс (сұраныс арқылы ғана).
  if old.role = 'courier' and new.city is distinct from old.city then
    raise exception 'privileged_column_denied:city';
  end if;
  if new.owner_id is distinct from old.owner_id and new.owner_id is not null then
    raise exception 'privileged_column_denied:owner_id';
  end if;
  if new.join_status is distinct from old.join_status
     and coalesce(new.join_status, '') not in ('none', 'pending') then
    raise exception 'privileged_column_denied:join_status';
  end if;

  return new;
end;
$function$;
-- 0065c инварианты: триггер функциясын клиент рөлі шақыра алмайды.
revoke execute on function public.guard_users_privileged_columns() from public, anon, authenticated;


-- ── 1) Сұраныстар кестесі ────────────────────────────────────────────────────
create table if not exists public.courier_change_requests (
  id            uuid primary key default gen_random_uuid(),
  courier_uid   uuid not null references auth.users(id) on delete cascade,
  -- Тек ақ тізімдегі кілттер: {"name": "...", "phone": "+7...", "city": "..."}
  changes       jsonb not null,
  -- Сұраныс сәтіндегі ескі мәндер (diff көрсету үшін, тарих та сақталады).
  old_values    jsonb not null default '{}'::jsonb,
  reason        text not null default '',
  -- pending | approved | rejected | cancelled (курьер өзі қайтарып алды)
  status        text not null default 'pending'
                check (status in ('pending', 'approved', 'rejected', 'cancelled')),
  reviewed_by   uuid references auth.users(id) on delete set null,
  reviewed_at   timestamptz,
  reject_reason text not null default '',
  created_at    timestamptz not null default now()
);

create index if not exists courier_change_requests_courier_idx
  on public.courier_change_requests(courier_uid, created_at desc);
create index if not exists courier_change_requests_status_idx
  on public.courier_change_requests(status, created_at desc);
-- Бір курьерде бір уақытта бір ғана күтудегі сұраныс (жарыс күйін де жабады).
create unique index if not exists courier_change_requests_one_pending
  on public.courier_change_requests(courier_uid) where status = 'pending';

alter table public.courier_change_requests enable row level security;

-- Оқу: курьер — өзінікін, superadmin — барлығын. Жазу саясаты ЖОҚ:
-- insert/update тек төмендегі SECURITY DEFINER RPC-лер арқылы.
drop policy if exists courier_change_requests_select on public.courier_change_requests;
create policy courier_change_requests_select on public.courier_change_requests
  for select to authenticated
  using (courier_uid = auth.uid() or public.is_superadmin());

-- Realtime (.stream()): superadmin тізімі мен курьердің «күтуде» күйі.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public'
      and tablename = 'courier_change_requests'
  ) then
    alter publication supabase_realtime add table public.courier_change_requests;
  end if;
end;
$$;


-- ── 2) Ішкі көмекші: өзгерістерді тексеріп, қалыпқа келтіру ─────────────────
--  SECURITY INVOKER әрі execute ешкімге берілмейді: тек төмендегі DEFINER
--  RPC-лердің ішінен (иесі postgres атынан) шақырылады.
--  Қайтарады: ағымдағы мәннен ШЫНЫМЕН өзгеше кілттер ғана ({} = өзгеріс жоқ).
create or replace function public.courier_changes_normalize(
  p_courier uuid,
  p_changes jsonb,
  p_allow_phone boolean default false
) returns jsonb
language plpgsql
set search_path = public
as $$
declare
  v_user public.users;
  v_out  jsonb := '{}'::jsonb;
  v_key  text;
  v_val  text;
  -- Қолдау көрсетілетін қалалар (kzCities Dart тізімімен БІР коммитте жаңарту!).
  v_cities constant text[] := array['Алматы','Астана','Шымкент','Қарағанды',
    'Атырау','Ақтөбе','Тараз','Павлодар','Өскемен','Семей','Ақтау','Қостанай',
    'Орал','Петропавл','Қызылорда'];
begin
  select * into v_user from public.users where id = p_courier and role = 'courier';
  if not found then raise exception 'courier_not_found'; end if;

  if p_changes is null or jsonb_typeof(p_changes) <> 'object' then
    raise exception 'bad_changes';
  end if;

  for v_key in select jsonb_object_keys(p_changes) loop
    -- Ақ тізім: басқа кілт (role, courier_status, owner_id...) — бірден қате.
    if v_key not in ('name', 'phone', 'city')
       or (v_key = 'phone' and not p_allow_phone) then
      raise exception 'bad_key:%', v_key;
    end if;
    if jsonb_typeof(p_changes -> v_key) <> 'string' then
      raise exception 'bad_value:%', v_key;
    end if;
    v_val := btrim(p_changes ->> v_key);

    if v_key = 'name' then
      if char_length(v_val) < 2 or char_length(v_val) > 60 then
        raise exception 'bad_name';
      end if;
      if v_val is distinct from v_user.name then
        v_out := v_out || jsonb_build_object('name', v_val);
      end if;

    elsif v_key = 'phone' then
      -- Қосымша форматы: E.164, Қазақстан (+7 және 10 цифр).
      v_val := regexp_replace(v_val, '[^0-9+]', '', 'g');
      if v_val !~ '^\+7[0-9]{10}$' then
        raise exception 'bad_phone';
      end if;
      if v_val is distinct from v_user.phone then
        if exists (select 1 from public.users where phone = v_val and id <> p_courier)
           or exists (select 1 from public.clients where phone = v_val and id <> p_courier) then
          raise exception 'phone_in_use';
        end if;
        v_out := v_out || jsonb_build_object('phone', v_val);
      end if;

    elsif v_key = 'city' then
      -- Бос орын/регистр айырмасы курьерді жұмыссыз қалдырмасын (жұмыс дәл
      -- сәйкестік бойынша таратылады): канондық жазылуға келтіреміз.
      v_val := regexp_replace(v_val, '\s+', ' ', 'g');
      select c into v_val from unnest(v_cities) c
       where lower(c) = lower(v_val) limit 1;
      if v_val is null then
        raise exception 'bad_city';
      end if;
      if v_val is distinct from v_user.city then
        v_out := v_out || jsonb_build_object('city', v_val);
      end if;
    end if;
  end loop;

  return v_out;
end;
$$;
revoke execute on function public.courier_changes_normalize(uuid, jsonb, boolean) from public, anon, authenticated;


-- ── 3) Ішкі көмекші: қалыпқа келтірілген өзгерістерді users-ке жазу ─────────
--  Бір ғана көз: admin_update_courier де, review_courier_change де осыны
--  шақырады. Курьердің аты белсенді (confirmed) тапсырыстарда да жаңарады —
--  дүкен мен клиент ескі есімді көрмесін.
create or replace function public.courier_apply_changes(
  p_courier uuid,
  p_changes jsonb,
  p_allow_phone boolean default false
) returns jsonb
language plpgsql
set search_path = public
as $$
declare
  v_norm jsonb;
  v_user public.users;
begin
  -- Курьер жолын құлыптаймыз: қатар екі өзгеріс бір-бірін баспасын.
  perform 1 from public.users where id = p_courier and role = 'courier' for update;
  if not found then raise exception 'courier_not_found'; end if;

  v_norm := public.courier_changes_normalize(p_courier, p_changes, p_allow_phone);

  if v_norm <> '{}'::jsonb then
    update public.users set
      name  = coalesce(v_norm ->> 'name',  name),
      phone = coalesce(v_norm ->> 'phone', phone),
      city  = coalesce(v_norm ->> 'city',  city)
    where id = p_courier and role = 'courier';

    if v_norm ? 'name' then
      update public.orders set courier_name = v_norm ->> 'name'
       where courier_uid = p_courier and status = 'confirmed';
    end if;
  end if;

  select * into v_user from public.users where id = p_courier;
  return jsonb_build_object(
    'id', v_user.id, 'name', v_user.name, 'phone', v_user.phone,
    'city', v_user.city, 'courier_status', v_user.courier_status,
    'applied', v_norm);
end;
$$;
revoke execute on function public.courier_apply_changes(uuid, jsonb, boolean) from public, anon, authenticated;


-- ── 4) Superadmin: курьер деректерін тікелей өңдеу ──────────────────────────
--  null параметр = өзгертпеу. Курьерге пуш барады (әсіресе телефон — кіру
--  нөмірі ауысқанын білуі керек).
create or replace function public.admin_update_courier(
  p_courier uuid,
  p_name    text default null,
  p_phone   text default null,
  p_city    text default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_changes jsonb := '{}'::jsonb;
  v_res     jsonb;
begin
  if not public.is_superadmin() then raise exception 'not_superadmin'; end if;

  if p_name  is not null then v_changes := v_changes || jsonb_build_object('name',  p_name);  end if;
  if p_phone is not null then v_changes := v_changes || jsonb_build_object('phone', p_phone); end if;
  if p_city  is not null then v_changes := v_changes || jsonb_build_object('city',  p_city);  end if;

  v_res := public.courier_apply_changes(p_courier, v_changes, true);

  -- Күтудегі сұраныс ескірмесін: superadmin дәл сол өрістерді өзгертсе, ол
  -- сұраныс жабылады (кейін бекітілсе жаңа мәнді басып кетер еді).
  if (v_res -> 'applied') <> '{}'::jsonb then
    update public.courier_change_requests
       set status = 'cancelled'
     where courier_uid = p_courier and status = 'pending'
       and changes ?| (select array_agg(k) from jsonb_object_keys(v_res -> 'applied') k);
  end if;

  if (v_res -> 'applied') <> '{}'::jsonb then
    perform public.notify_push(
      array[p_courier],
      'Данные обновлены / Деректер жаңартылды',
      case when (v_res -> 'applied') ? 'phone'
        then 'Новый номер для входа: ' || (v_res ->> 'phone')
             || ' / Кіру нөмірі: ' || (v_res ->> 'phone')
        else 'Модератор изменил ваши данные / Модератор деректеріңізді өзгертті'
      end,
      jsonb_build_object('type', 'courier_change_reviewed', 'approved', 'true'));
  end if;

  return v_res;
end;
$$;
revoke execute on function public.admin_update_courier(uuid, text, text, text) from public, anon;
grant execute on function public.admin_update_courier(uuid, text, text, text) to authenticated;


-- ── 5) Курьер: өзгеріс сұрау ─────────────────────────────────────────────────
create or replace function public.courier_request_change(
  p_changes jsonb,
  p_reason  text default ''
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user public.users;
  v_norm jsonb;
  v_old  jsonb := '{}'::jsonb;
  v_key  text;
  v_id   uuid;
  v_reason text := btrim(coalesce(p_reason, ''));
begin
  select * into v_user from public.users
   where id = auth.uid() and role = 'courier'
   for update;
  if not found then raise exception 'not_courier'; end if;
  if coalesce(v_user.blocked, false) then raise exception 'blocked'; end if;

  if char_length(v_reason) > 500 then raise exception 'reason_too_long'; end if;

  if exists (select 1 from public.courier_change_requests
              where courier_uid = v_user.id and status = 'pending') then
    raise exception 'pending_exists';
  end if;

  v_norm := public.courier_changes_normalize(v_user.id, p_changes, false);
  if v_norm = '{}'::jsonb then raise exception 'no_changes'; end if;

  for v_key in select jsonb_object_keys(v_norm) loop
    v_old := v_old || jsonb_build_object(v_key,
      case v_key when 'name' then v_user.name
                 when 'phone' then v_user.phone
                 else v_user.city end);
  end loop;

  insert into public.courier_change_requests (courier_uid, changes, old_values, reason)
  values (v_user.id, v_norm, v_old, v_reason)
  returning id into v_id;

  perform public.notify_push(
    (select array_agg(id) from public.users where role = 'superadmin'),
    'Курьер просит изменить данные / Курьер деректерді өзгертуді сұрайды',
    coalesce(nullif(v_user.name, ''), v_user.phone),
    jsonb_build_object('type', 'courier_change_request', 'requestId', v_id));

  return v_id;
exception
  when unique_violation then raise exception 'pending_exists';
end;
$$;
revoke execute on function public.courier_request_change(jsonb, text) from public, anon;
grant execute on function public.courier_request_change(jsonb, text) to authenticated;


-- ── 6) Курьер: күтудегі сұранысты қайтарып алу ──────────────────────────────
create or replace function public.courier_cancel_change_request(p_request uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'not_authorized'; end if;
  update public.courier_change_requests
     set status = 'cancelled'
   where id = p_request and courier_uid = auth.uid() and status = 'pending';
  if not found then raise exception 'request_not_pending'; end if;
end;
$$;
revoke execute on function public.courier_cancel_change_request(uuid) from public, anon;
grant execute on function public.courier_cancel_change_request(uuid) to authenticated;


-- ── 7) Superadmin: сұранысты қарау ──────────────────────────────────────────
create or replace function public.review_courier_change(
  p_request       uuid,
  p_approve       boolean,
  p_reject_reason text default ''
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_req    public.courier_change_requests;
  v_reason text := btrim(coalesce(p_reject_reason, ''));
begin
  if not public.is_superadmin() then raise exception 'not_superadmin'; end if;

  select * into v_req from public.courier_change_requests
   where id = p_request for update;
  if not found then raise exception 'request_not_found'; end if;
  if v_req.status <> 'pending' then raise exception 'already_reviewed'; end if;

  if p_approve then
    -- Сол транзакцияда: қайта тексеру (телефон бос па т.б.) + қолдану.
    perform public.courier_apply_changes(v_req.courier_uid, v_req.changes, false);
    update public.courier_change_requests set
      status = 'approved', reviewed_by = auth.uid(), reviewed_at = now(),
      reject_reason = ''
    where id = p_request;
  else
    if v_reason = '' then raise exception 'reject_reason_required'; end if;
    if char_length(v_reason) > 300 then raise exception 'reason_too_long'; end if;
    update public.courier_change_requests set
      status = 'rejected', reviewed_by = auth.uid(), reviewed_at = now(),
      reject_reason = v_reason
    where id = p_request;
  end if;

  perform public.notify_push(
    array[v_req.courier_uid],
    case when p_approve
      then 'Изменения одобрены / Өзгерістер мақұлданды'
      else 'Запрос отклонён / Сұраныс қабылданбады' end,
    case when p_approve
      then 'Ваши данные обновлены / Деректеріңіз жаңартылды'
      else v_reason end,
    jsonb_build_object('type', 'courier_change_reviewed',
                       'requestId', v_req.id,
                       'approved', case when p_approve then 'true' else 'false' end));
end;
$$;
revoke execute on function public.review_courier_change(uuid, boolean, text) from public, anon;
grant execute on function public.review_courier_change(uuid, boolean, text) to authenticated;

-- ── Тексеру (қолданғаннан кейін, қолмен) ────────────────────────────────────
--  select proname, proacl from pg_proc where proname in
--    ('admin_update_courier','courier_request_change','courier_cancel_change_request',
--     'review_courier_change','courier_changes_normalize','courier_apply_changes',
--     'guard_users_privileged_columns');
--  → ешқайсысында `=X/` (PUBLIC) да, `anon=` да болмауы тиіс (Supabase әдепкі
--    привилегиялары anon/authenticated-ке ашық грант береді); ішкі көмекшілерде
--    authenticated та жоқ.
--  Қосымша: select proname from pg_proc where proname in (...) and
--    proacl::text like '%anon=%';  → бос қайтуы тиіс.
