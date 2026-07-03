-- ════════════════════════════════════════════════════════════════════════════
--  0004 · Верификациясыз тіркелу + superadmin аккаунты
-- ────────────────────────────────────────────────────────────────────────────
--  Осы скриптті Supabase Dashboard → SQL Editor-ға толық көшіріп, RUN басыңыз.
--
--  ⚠️ МІНДЕТТІ қадам (Dashboard-та, SQL-мен жасалмайды):
--     Authentication → Sign In / Providers → Email → «Confirm email» → ӨШІРУ.
--     Сонда signUp бірден сессия ашады және ешқандай OTP хат жіберілмейді.
-- ════════════════════════════════════════════════════════════════════════════

-- ── 1) Жаңа қолданушыларды автоматты растау (қосымша сақтандыру) ─────────────
--  «Confirm email» кездейсоқ қосулы қалса да аккаунт бірден расталған болады,
--  сондықтан fallback signInWithPassword «email not confirmed» қатесін бермейді.
create or replace function public.auto_confirm_email()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.email_confirmed_at := coalesce(new.email_confirmed_at, now());
  return new;
end;
$$;

drop trigger if exists on_auth_user_autoconfirm on auth.users;
create trigger on_auth_user_autoconfirm
  before insert on auth.users
  for each row execute function public.auto_confirm_email();

-- Бұрын тіркеліп, растала қоймаған аккаунттарды да растаймыз.
update auth.users
   set email_confirmed_at = coalesce(email_confirmed_at, now());

update public.clients set email_verified = true where email_verified = false;

-- ── 2) handle_new_user: superadmin рөлі + клиент бірден расталған ─────────────
create or replace function public.handle_new_user()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_role text := coalesce(new.raw_user_meta_data->>'role', 'client');
  v_name text := coalesce(new.raw_user_meta_data->>'name', '');
  v_code text;
begin
  if v_role = 'client' then
    insert into public.clients (id, phone, email, name, city, email_verified)
    values (
      new.id,
      coalesce(new.raw_user_meta_data->>'phone', ''),
      coalesce(new.email, ''),
      v_name,
      coalesce(new.raw_user_meta_data->>'city', ''),
      true  -- верификация жоқ — бірден расталған
    );
  elsif v_role = 'admin' then
    -- 6-цифрлы бизнес коды (seller қосылу үшін).
    v_code := lpad((floor(random() * 1000000))::int::text, 6, '0');
    insert into public.users (id, name, email, role, owner_id, business_code, join_status)
    values (new.id, v_name, coalesce(new.email, ''), 'admin', new.id, v_code, 'active');
    insert into public.business_codes (code, admin_uid) values (v_code, new.id);
  elsif v_role = 'superadmin' then
    insert into public.users (id, name, email, role, owner_id, join_status)
    values (new.id, v_name, coalesce(new.email, ''), 'superadmin', new.id, 'active');
  else
    insert into public.users (id, name, email, role, owner_id, join_status)
    values (new.id, v_name, coalesce(new.email, ''), 'seller', null, 'none');
  end if;
  return new;
end;
$$;

-- ── 3) SUPERADMIN (модератор) аккаунтын жасау ────────────────────────────────
--  ⬇️ ЕКІ ЖОЛДЫ ӨЗ ДЕРЕКТЕРІҢІЗГЕ АУЫСТЫРЫҢЫЗ ⬇️
--  Қосымшада «Дүкен иесі / Сатушы» кіру экранында осы email+пароль арқылы кіреді.
do $$
declare
  v_email text := 'superadmin@qoima.kz';   -- ← superadmin email
  v_pass  text := 'Qoima2026!';            -- ← superadmin құпиясөзі
  v_name  text := 'Модератор';
  v_id    uuid := gen_random_uuid();
begin
  -- Бұл email бұрын тіркелген болса — қайталамаймыз.
  if exists (select 1 from auth.users where lower(email) = lower(v_email)) then
    raise notice 'superadmin бұрыннан бар: %', v_email;
    return;
  end if;

  -- Auth қолданушысы. handle_new_user триггері public.users жолын
  -- role=superadmin етіп өзі жасайды.
  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at,
    confirmation_token, recovery_token,
    email_change, email_change_token_new, email_change_token_current
  ) values (
    '00000000-0000-0000-0000-000000000000', v_id, 'authenticated', 'authenticated',
    lower(v_email), extensions.crypt(v_pass, extensions.gen_salt('bf')),
    now(), '{"provider":"email","providers":["email"]}'::jsonb,
    jsonb_build_object('role', 'superadmin', 'name', v_name),
    now(), now(),
    '', '', '', '', ''
  );

  -- Email провайдерінің identity жазбасы (онсыз кіру жұмыс істемейді).
  insert into auth.identities (
    id, user_id, provider_id, identity_data, provider,
    last_sign_in_at, created_at, updated_at
  ) values (
    gen_random_uuid(), v_id, v_id::text,
    jsonb_build_object(
      'sub', v_id::text,
      'email', lower(v_email),
      'email_verified', true,
      'phone_verified', false
    ),
    'email', now(), now(), now()
  );

  raise notice 'superadmin жасалды: % (id=%)', v_email, v_id;
end $$;
