-- ════════════════════════════════════════════════════════════════════════════
--  0014 · Жаңа дүкен иесіне (admin) тіркелуде 1 айлық жазылым АВТО беріледі
-- ────────────────────────────────────────────────────────────────────────────
--  ⚠️ БАЗАҒА ҚОЛДАНУ КЕРЕК (MCP apply_migration немесе Supabase SQL editor).
--
--  Мақсат: жаңа admin тіркелген бойда superadmin-нің SubscriptionsScreen-інде
--  бірден белсенді жазылыммен (1 ай) көрінсін — модератор мерзімді бақылап,
--  кейін қолмен ұзартады/блоктайды.
--
--  Бұл файл 0011-дің subscription бағандарын да идемпотентті түрде қосады
--  (тірі БД-да 0011 бұрын қолданылмаған болатын — db_schema_drift қараңыз).
-- ════════════════════════════════════════════════════════════════════════════

-- ── 1) 0011 subscription бағандары (қауіпсіз: if not exists) ──────────────────
alter table public.users
  add column if not exists subscription_until      timestamptz,
  add column if not exists subscription_started_at timestamptz,
  add column if not exists subscription_plan       text default '',
  add column if not exists subscription_note       text default '';

create index if not exists users_subscription_until_idx
  on public.users(subscription_until)
  where role = 'admin';

-- ── 2) handle_new_user: admin бұтағында 1 айлық жазылым қоямыз ────────────────
-- 0012-дегі нұсқаны алмастырады (тек admin insert-іне subscription_* қосылды).
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
      new.id, v_phone, coalesce(new.email, ''), v_name,
      coalesce(new.raw_user_meta_data->>'city', ''), true);
  elsif v_role = 'admin' then
    v_code := lpad((floor(random() * 1000000))::int::text, 6, '0');
    insert into public.users (id, name, email, phone, role, owner_id, business_code, join_status,
      subscription_started_at, subscription_until, subscription_plan)
    values (new.id, v_name, coalesce(new.email, ''), v_phone, 'admin', new.id, v_code, 'active',
      now(), now() + interval '1 month', '1 ай');
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
