-- ════════════════════════════════════════════════════════════════════════════
--  0044 · «Досыңды шақыр» (referral) — дүкен деңгейіндегі бағдарлама
-- ────────────────────────────────────────────────────────────────────────────
--  ЖҰМЫС ПРИНЦИПІ:
--   1) Дүкен иесі referral_percent орнатады (0 = өшірулі) — бұл ЕКІ жаққа да
--      берілетін жеңілдік пайызы (досы да, шақырушы да сонша алады).
--   2) Клиент дүкен бетінде өзінің ЖЕКЕ шақыру кодын алады (RPC арқылы,
--      бір рет жасалады да сақталады).
--   3) Досы сол кодты себетте енгізеді → жеңілдік алады (тек СОЛ ДҮКЕНДЕГІ
--      БІРІНШІ тапсырысында — клиент жағында тексеріледі).
--   4) Досының тапсырысы «completed» болғанда → шақырушыға ЖЕКЕ бір реттік
--      сыйлық промокоды автоматты жасалады + push жіберіледі.
--
--  ДИЗАЙН ШЕШІМІ: жаңа «referral_codes» кестесі жасалмады — шақыру коды да,
--  сыйлық коды да ҚАРАПАЙЫМ promos жолы. Сол себепті бүкіл қолданыстағы
--  логика (валидация, redemption есебі, тапсырыс болдырылмағанда қайтару)
--  еш өзгеріссіз жұмыс істейді. Екі жаңа баған ғана ажыратады.
-- ════════════════════════════════════════════════════════════════════════════

-- ── 1) Дүкен баптауы ─────────────────────────────────────────────────────────
alter table public.stores
  add column if not exists referral_percent integer not null default 0;

alter table public.stores
  drop constraint if exists stores_referral_percent_range;
alter table public.stores
  add constraint stores_referral_percent_range
    check (referral_percent between 0 and 50);

-- ── 2) promos кеңейтімі ──────────────────────────────────────────────────────
alter table public.promos
  -- Шақыру коды: осы клиентке тиесілі, оны БАСҚАЛАР қолданады.
  add column if not exists referral_owner_uid uuid,
  -- Сыйлық коды: ТЕК осы клиент қолдана алады.
  add column if not exists only_for_uid uuid,
  -- Сыйлық қай тапсырыс үшін берілді (қайта берілмеуін кепілдейді).
  add column if not exists referral_source_order_id uuid;

create unique index if not exists promos_referral_source_order_uidx
  on public.promos(referral_source_order_id)
  where referral_source_order_id is not null;

create unique index if not exists promos_referral_owner_uidx
  on public.promos(admin_uid, referral_owner_uid)
  where referral_owner_uid is not null;

create index if not exists promos_only_for_idx
  on public.promos(only_for_uid) where only_for_uid is not null;

-- ── 3) Клиенттің шақыру кодын алу/жасау (promos_write тек admin — сондықтан
--       SECURITY DEFINER RPC; 0006-дағы join RPC-лерімен бірдей идиома) ──────
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

  select code into v_code from public.promos
    where admin_uid = p_admin and referral_owner_uid = v_uid;
  if v_code is not null then return v_code; end if;

  -- Қайталанбайтын код: DOS- + 6 таңба (ұқсас таңбалар алынып тасталған).
  loop
    -- md5(random()) — тек ядро функциялары (gen_random_bytes pgcrypto-да,
    -- ол `search_path = public`-та КӨРІНБЕЙДІ → триггерді бұзатын еді).
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

-- ── 4) Досының тапсырысы аяқталды → шақырушыға сыйлық + push ────────────────
create or replace function public.on_referral_order_completed() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_promo   record;
  v_percent integer;
  v_code    text;
  v_store   text;
begin
  if new.status <> 'completed' or coalesce(old.status, '') = 'completed' then
    return new;
  end if;
  -- promo_id — TEXT бағаны; жарамсыз мән cast-та қате бермеуі үшін алдымен
  -- uuid пішімін тексереміз.
  if new.promo_id is null or new.promo_id !~*
     '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return new;
  end if;

  select id, referral_owner_uid, admin_uid into v_promo
    from public.promos where id = new.promo_id::uuid;
  if v_promo is null then return new; end if;
  if v_promo.referral_owner_uid is null then return new; end if;
  -- Өз кодын өзі қолдана алмайды (клиентте де тексеріледі — қос қорғаныс).
  if v_promo.referral_owner_uid = new.client_uid then return new; end if;

  select referral_percent into v_percent
    from public.stores where admin_uid = v_promo.admin_uid;
  if coalesce(v_percent, 0) <= 0 then return new; end if;

  loop
    v_code := 'RAHMET-' || upper(substr(translate(md5(random()::text || clock_timestamp()::text),
                 'oil01', ''), 1, 5));
    exit when not exists (
      select 1 from public.promos where admin_uid = v_promo.admin_uid and code = v_code);
  end loop;

  -- referral_source_order_id-дегі unique индекс қайта берілуден сақтайды.
  begin
    insert into public.promos (admin_uid, code, type, value, scope, product_ids,
                               max_uses, per_user_limit, min_order, active,
                               only_for_uid, referral_source_order_id)
    values (v_promo.admin_uid, v_code, 'percent', v_percent, 'all', '{}',
            1, 1, 0, true, v_promo.referral_owner_uid, new.id);
  exception when unique_violation then
    return new; -- бұл тапсырыс үшін сыйлық берілген
  end;

  select store_name into v_store from public.stores where admin_uid = v_promo.admin_uid;
  perform public.notify_push(
    array[v_promo.referral_owner_uid],
    'Спасибо! Ваш друг сделал заказ / Досыңыз тапсырыс берді',
    coalesce(v_store, '') || ' — промокод ' || v_code || ' (−' || v_percent || '%)',
    jsonb_build_object('type', 'referral_reward', 'adminUid', v_promo.admin_uid,
                       'code', v_code)
  );
  return new;
end;
$$;

drop trigger if exists trg_referral_order_completed on public.orders;
create trigger trg_referral_order_completed after update on public.orders
  for each row execute function public.on_referral_order_completed();
