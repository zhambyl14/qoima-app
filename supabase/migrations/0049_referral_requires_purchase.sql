-- ════════════════════════════════════════════════════════════════════════════
--  0049 · «Досыңды шақыр» әділдігі — шақыру коды тек САТЫП АЛҒАН дүкенде
-- ────────────────────────────────────────────────────────────────────────────
--  МӘСЕЛЕ: 0044-те кез келген клиент кез келген дүкеннің шақыру кодын ала
--  алатын — сол дүкеннен бір рет те зат алмаса да. Досы сол кодпен тапсырыс
--  берсе, шақырушы жеңілдік алады. Яғни дүкенге ешқашан ақша әкелмеген адам
--  сол дүкеннің жеңілдігін «өндіріп» отырды.
--
--  ТҮЗЕТУ: get_or_create_referral_code енді клиенттің осы дүкенде АЯҚТАЛҒАН
--  (completed) тапсырысы бар-жоғын тексереді. Жоқ болса — код берілмейді
--  (null). Клиент жағы да тексереді (UI құлыпталған күй көрсетеді), бірақ
--  RPC-ді тікелей шақыруға болатындықтан НАҒЫЗ шектеу осы жерде.
--
--  Ескерту: бұрын берілген кодтар күшінде қалады (жаңа жол жасалмайды, бар
--  жол қайтарылады) — тек ЖАҢА код беру шектеледі.
-- ════════════════════════════════════════════════════════════════════════════

create or replace function public.get_or_create_referral_code(p_admin uuid)
returns text
language plpgsql security definer set search_path = public as $$
declare
  v_uid     uuid := auth.uid();
  v_percent integer;
  v_code    text;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;

  select referral_percent into v_percent
    from public.stores
    where admin_uid = p_admin and is_published = true and status <> 'blocked';
  if coalesce(v_percent, 0) <= 0 then return null; end if; -- бағдарлама өшірулі

  -- Бұрын берілген код — сатып алу тексерусіз қайтарылады (кері үйлесімділік).
  select code into v_code from public.promos
    where admin_uid = p_admin and referral_owner_uid = v_uid;
  if v_code is not null then return v_code; end if;

  -- ЖАҢА код: осы дүкенде аяқталған тапсырыс болуы МІНДЕТТІ.
  if not exists (
    select 1 from public.orders
     where client_uid = v_uid and admin_uid = p_admin and status = 'completed'
  ) then
    return null;
  end if;

  -- Қайталанбайтын код: DOS- + 6 таңба (ұқсас таңбалар алынып тасталған).
  loop
    v_code := 'DOS-' || upper(substr(translate(md5(random()::text || clock_timestamp()::text),
                 'oil01', ''), 1, 6));
    exit when not exists (
      select 1 from public.promos where admin_uid = p_admin and code = v_code);
  end loop;

  insert into public.promos (admin_uid, code, type, value, scope, product_ids,
                             max_uses, per_user_limit, min_order, active,
                             referral_owner_uid)
  values (p_admin, v_code, 'percent', v_percent, 'all', '{}',
          null, 1, 0, true, v_uid);
  return v_code;
end;
$$;
grant execute on function public.get_or_create_referral_code(uuid) to authenticated;

-- ── Клиенттің «Промо» бөлімі үшін: мен сатып алған + шақыру бағдарламасы
--    қосулы дүкендер (admin_uid тізімі). Клиент өз orders жолдарын RLS
--    арқылы оқи алады, бірақ бір сұраныспен алған әлдеқайда арзан. ──────────
create or replace function public.my_referral_stores()
returns table (admin_uid uuid, referral_percent integer)
language sql stable security definer set search_path = public as $$
  select distinct s.admin_uid, s.referral_percent
    from public.orders o
    join public.stores s on s.admin_uid = o.admin_uid
   where o.client_uid = auth.uid()
     and o.status = 'completed'
     and s.referral_percent > 0
     and s.is_published = true
     and s.status <> 'blocked';
$$;
grant execute on function public.my_referral_stores() to authenticated;
