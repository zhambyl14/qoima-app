-- ════════════════════════════════════════════════════════════════════════════
--  0012 · Барлық рөл ТЕЛЕФОН + ҚҰПИЯСӨЗБЕН тіркеледі/кіреді (email жасырын)
-- ────────────────────────────────────────────────────────────────────────────
--  ✅ Базаға MCP арқылы қолданылды (apply_migration: phone_auth).
--
--  Неге: бұрын клиент телефон+email+пароль, ал сатушы/админ email+парольмен
--  кіретін. Енді БАРЛЫҚ рөл (client/seller/admin/superadmin) тек ТЕЛЕФОН +
--  парольмен жұмыс істейді. Email қолданушыға көрінбейді — Supabase Auth
--  password логині идентификатор талап еткендіктен, тіркелуде телефоннан
--  «синтетикалық» email жасалады: `<цифрлар>@qoima.app`
--  (мыс. +77001234567 → 77001234567@qoima.app). Кіру:
--  телефон → email_for_phone RPC → signInWithPassword(email).
--
--  Телефон E.164 (`+7XXXXXXXXXX`) түрінде БҰРЫННАН clients.phone-да; енді
--  users кестесіне де қосылады (админ/сатушы/суперадмин үшін).
--
--  Ескі email-мен тіркелген админдер: email өзгермейді, тек users.phone
--  толтырылады (0014 көр.) — RPC олардың нақты email-ін қайтарады, ескі
--  пароль жұмыс істей береді.
-- ════════════════════════════════════════════════════════════════════════════

-- ── 1) users.phone (админ/сатушы/суперадмин телефоны) ────────────────────────
alter table public.users
  add column if not exists phone text not null default '';

-- Бос емес телефон бірегей болуы керек (екі аккаунт бір нөмірге кірмесін).
create unique index if not exists users_phone_uidx
  on public.users(phone) where phone <> '';

-- ── 2) Телефон → email (БАРЛЫҚ рөл): кіруден бұрын anon шақырады ──────────────
-- users-те де, clients-те де іздейді. Синтетикалық email де, ескі нақты email
-- де болса — сол қайтарылады (signInWithPassword сонымен жұмыс істейді).
create or replace function public.email_for_phone(p_phone text)
returns text
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select email from public.users   where phone = p_phone and email <> '' limit 1),
    (select email from public.clients where phone = p_phone and email <> '' limit 1)
  );
$$;
grant execute on function public.email_for_phone(text) to anon, authenticated;

-- Кері үйлесімділік: ескі client_email_for_phone енді жаңасына делегат етеді.
create or replace function public.client_email_for_phone(p_phone text)
returns text
language sql stable security definer set search_path = public as $$
  select public.email_for_phone(p_phone);
$$;
grant execute on function public.client_email_for_phone(text) to anon, authenticated;

-- ── 3) handle_new_user: телефонды users кестесіне де жазады ───────────────────
-- 0001/0008-дегі нұсқаны алмастырады. Google/OAuth жойылғандықтан «role жоқ →
-- профиль жасамау» бұтағы да алынды (енді рөл әрқашан метадеректе болады;
-- бос болса — клиент деп есептейміз).
create or replace function public.handle_new_user()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_role  text := coalesce(new.raw_user_meta_data->>'role', 'client');
  v_name  text := coalesce(new.raw_user_meta_data->>'name', '');
  v_phone text := coalesce(new.raw_user_meta_data->>'phone', '');
  v_code  text;
begin
  if v_role = 'client' then
    insert into public.clients (id, phone, email, name, city, email_verified)
    values (
      new.id,
      v_phone,
      coalesce(new.email, ''),
      v_name,
      coalesce(new.raw_user_meta_data->>'city', ''),
      true  -- верификация жоқ — бірден расталған
    );
  elsif v_role = 'admin' then
    v_code := lpad((floor(random() * 1000000))::int::text, 6, '0');
    insert into public.users (id, name, email, phone, role, owner_id, business_code, join_status)
    values (new.id, v_name, coalesce(new.email, ''), v_phone, 'admin', new.id, v_code, 'active');
    insert into public.business_codes (code, admin_uid) values (v_code, new.id);
  elsif v_role = 'superadmin' then
    insert into public.users (id, name, email, phone, role, owner_id, join_status)
    values (new.id, v_name, coalesce(new.email, ''), v_phone, 'superadmin', new.id, 'active');
  else
    insert into public.users (id, name, email, phone, role, owner_id, join_status)
    values (new.id, v_name, coalesce(new.email, ''), v_phone, 'seller', null, 'none');
  end if;
  return new;
end;
$$;
