-- ════════════════════════════════════════════════════════════════════════════
--  0018 · Тегін кезең 1 ай → 1 АПТА · жазылым статусы RPC · баннер → дүкен
-- ────────────────────────────────────────────────────────────────────────────
--  1) Жаңа дүкен иесіне авто-жазылым енді 7 күн (бұрын 1 ай еді).
--  2) my_subscription_status() — admin/seller өз бизнесінің жазылым мерзімін
--     көреді (seller иесінің users жолын RLS бойынша оқи алмайды → DEFINER).
--     Клиент жағында: мерзім өткен күні ескерту, 3 күннен кейін «заморозка».
--  3) banners.store_admin_uid — баннер нақты дүкенге сілтей алады (клиент
--     баннерді басқанда сол дүкеннің каталогы ашылады).
-- ════════════════════════════════════════════════════════════════════════════

-- ── 1) handle_new_user: admin бұтағында 7 КҮНДІК тегін кезең ─────────────────
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
      now(), now() + interval '7 days', '7 күн (тегін)');
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

-- ── 2) my_subscription_status(): бизнес иесінің жазылым мерзімі ───────────────
-- admin → өз жолы; seller → иесінің жолы (SECURITY DEFINER — RLS айналып өтеді).
-- until null = жазылым тағайындалмаған (ескі иелер) — қолданба блоктамайды.
create or replace function public.my_subscription_status()
returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce((
    select jsonb_build_object(
      'role', u.role,
      'until', o.subscription_until,
      'plan', coalesce(o.subscription_plan, ''))
    from public.users u
    join public.users o on o.id = coalesce(u.owner_id, u.id)
    where u.id = auth.uid()
  ), jsonb_build_object('role', null, 'until', null, 'plan', ''));
$$;
grant execute on function public.my_subscription_status() to authenticated;

-- ── 3) banners → дүкен сілтемесі ──────────────────────────────────────────────
alter table public.banners
  add column if not exists store_admin_uid uuid,
  add column if not exists store_name text default '';
