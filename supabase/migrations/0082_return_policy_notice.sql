-- ════════════════════════════════════════════════════════════════════════════
--  0082 · Дүкеннің қайтару шарттары + тауар қолға тигендегі хабарлама
-- ────────────────────────────────────────────────────────────────────────────
--  Клиент тауарды алған сәтте сол дүкеннің шартын БІР РЕТ көреді: қайтарылмайды
--  ма, қайтарылса қандай жағдайда.
--
--  0076-дағы шешім ӨЗГЕРМЕДІ: «қайтара аласыз» деп ЕСКЕ САЛМАЙМЫЗ. Хабарлама тек
--  бір рет, тауар тиген сәтте шарттарды хабарлайды; кейінгі еске салғыш жоқ,
--  «Оформить возврат» батырмасы парақшада жоқ, өнім карточкасы бұрынғыдай.
--
--  ДҮКЕН: stores.return_policy_mode ('accept' | 'none'), return_days,
--  return_conditions, return_policy_note (0073).
--   • Мерзім тек 14/21/30: заң бойынша ең кемі 14 күн, дүкен тек ұзарта алады.
--   • 'none' тек модератор рұқсатымен (stores.allow_non_returnable, 0073) —
--     бұл заңға әсер ететін шешім, иесі өз бетінше қоя алмайды.
--
--  СНАПШОТ: orders.return_policy — сату сәтінде сервер жазады, кейін өзгермейді
--  (0073 үлгісі: клиент келіскен шарт күшінде қалады). Сыйлықтарда NULL: оларда
--  өз ережесі бар («тек ауыстыру», 0070). Ескі тапсырыстарда да NULL — хабарлама
--  оларға шықпайды.
--
--  ЖАЛАУША: 'return_notice' (әдепкіде ҚОСУЛЫ). Өшірілсе жаңа тапсырысқа снапшот
--  жазылмайды, парақша шықпайды.
-- ════════════════════════════════════════════════════════════════════════════

-- ── 1. Бағандар ──────────────────────────────────────────────────────────────
alter table public.stores
  add column if not exists return_policy_mode text    not null default 'accept',
  add column if not exists return_days        integer not null default 14,
  add column if not exists return_conditions  text[]  not null default '{}';

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'stores_return_policy_mode_chk') then
    alter table public.stores add constraint stores_return_policy_mode_chk
      check (return_policy_mode in ('accept', 'none'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'stores_return_days_chk') then
    alter table public.stores add constraint stores_return_days_chk
      check (return_days in (14, 21, 30));
  end if;
  -- Ақ тізім екі жерде: lib/data/models/return_policy.dart ↔ осы жер.
  -- «Тек ауыстыру» / «тек ақау болса» ӘДЕЙІ жоқ: қайтару ағыны оларды орындамайды
  -- (айырбас жолы жоқ), әрі бұл 'none'-дың модератор рұқсатын айналып өтер еді.
  if not exists (select 1 from pg_constraint where conname = 'stores_return_conditions_chk') then
    alter table public.stores add constraint stores_return_conditions_chk
      check (return_conditions <@ array['tags','unused','packaging','receipt']::text[]);
  end if;
end $$;

alter table public.orders
  add column if not exists return_policy        jsonb,
  add column if not exists return_notice_ack_at timestamptz;

create index if not exists orders_return_notice_pending_idx
  on public.orders (client_uid)
  where status = 'completed'
    and return_policy is not null
    and return_notice_ack_at is null;

insert into public.app_settings (key, value)
values ('feature_return_notice', 'true')
on conflict (key) do nothing;

-- ── 2. 'none' — тек рұқсатпен ────────────────────────────────────────────────
-- stores_write иесіне бүкіл жолды жаңартуға рұқсат береді, сондықтан RPC-ден
-- тыс тікелей UPDATE-ті де осы триггер бөгейді.
create or replace function public.guard_stores_privileged_columns()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or public.is_superadmin() then
    return new;
  end if;
  if tg_op = 'INSERT' then
    if coalesce(new.allow_non_returnable, false) then
      raise exception 'privileged_column_denied:allow_non_returnable';
    end if;
  elsif new.allow_non_returnable is distinct from old.allow_non_returnable then
    raise exception 'privileged_column_denied:allow_non_returnable';
  end if;
  if new.return_policy_mode = 'none' and not coalesce(new.allow_non_returnable, false) then
    raise exception 'non_returnable_not_allowed';
  end if;
  return new;
end;
$$;
revoke all on function public.guard_stores_privileged_columns() from public, anon, authenticated;

create or replace function public.guard_store_edit_privileged_fields()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if public.is_superadmin() then
    return new;
  end if;
  if jsonb_typeof(new.changes) = 'array' and exists (
    select 1
      from jsonb_array_elements(new.changes) c
     where jsonb_typeof(c) = 'object'
       and lower(replace(coalesce(c->>'field', ''), '_', ''))
           in ('allownonreturnable', 'returnpolicymode')
  ) then
    raise exception 'privileged_column_denied:allow_non_returnable';
  end if;
  return new;
end;
$$;
revoke all on function public.guard_store_edit_privileged_fields() from public, anon, authenticated;

-- Рұқсат алынса, дүкен режимі де 'accept'-ке оралады.
create or replace function public.set_store_non_returnable_permission(
  p_admin_uid uuid, p_allowed boolean)
returns integer
language plpgsql security definer set search_path = public as $$
declare
  v_count integer := 0;
begin
  if not public.is_superadmin() then
    raise exception 'not_authorized';
  end if;

  update public.stores
     set allow_non_returnable = coalesce(p_allowed, false),
         return_policy_mode = case when coalesce(p_allowed, false)
                                   then return_policy_mode else 'accept' end,
         updated_at = now()
   where admin_uid = p_admin_uid;
  if not found then
    raise exception 'store_not_found';
  end if;

  if not coalesce(p_allowed, false) then
    update public.products
       set non_returnable = false
     where owner_uid = p_admin_uid
       and non_returnable;
    get diagnostics v_count = row_count;
  end if;

  return v_count;
end;
$$;
revoke execute on function public.set_store_non_returnable_permission(uuid, boolean) from public;
grant execute on function public.set_store_non_returnable_permission(uuid, boolean) to authenticated;

-- ── 3. Иесінің RPC-і ─────────────────────────────────────────────────────────
create or replace function public.set_store_return_policy(
  p_mode text, p_days integer, p_conditions text[], p_note text)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_owner uuid := public.app_owner_uid();
  v_note  text := btrim(coalesce(p_note, ''));
  v_mode  text := coalesce(p_mode, 'accept');
  v_conds text[] := coalesce(p_conditions, '{}'::text[]);
begin
  if auth.uid() is null or v_owner is null or public.app_role() <> 'admin' then
    raise exception 'not_authorized';
  end if;
  if not (public.feature_enabled('return_notice')
          or public.feature_enabled('non_returnable')) then
    raise exception 'feature_disabled';
  end if;
  if v_mode not in ('accept', 'none')
     or coalesce(p_days, 0) not in (14, 21, 30)
     or not (v_conds <@ array['tags','unused','packaging','receipt']::text[]) then
    raise exception 'invalid_policy';
  end if;
  if char_length(v_note) > 500 then
    raise exception 'note_too_long';
  end if;
  if v_mode = 'none' and not public.feature_enabled('non_returnable') then
    raise exception 'feature_disabled';
  end if;

  update public.stores
     set return_policy_mode = v_mode,
         return_days        = case when v_mode = 'none' then 14 else p_days end,
         return_conditions  = case when v_mode = 'none' then '{}'::text[] else v_conds end,
         return_policy_note = v_note,
         updated_at         = now()
   where admin_uid = v_owner;
  if not found then
    raise exception 'store_not_found';
  end if;
end;
$$;
revoke execute on function public.set_store_return_policy(text, integer, text[], text) from public;
grant execute on function public.set_store_return_policy(text, integer, text[], text) to authenticated;

-- ── 4. Снапшот ───────────────────────────────────────────────────────────────
-- 0073-тегі функция + дүкен режимі 'none' болса тапсырыстың бәрі белгіленеді,
-- сонда guard_return_non_returnable өзгеріссіз жұмыс істей береді.
create or replace function public.snapshot_order_non_returnable()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_nr text[];
begin
  if new.items is null or jsonb_typeof(new.items) <> 'array' then
    return new;
  end if;

  if tg_op = 'INSERT' then
    if not public.feature_enabled('non_returnable') then
      new.items := (
        select coalesce(jsonb_agg(
                 case when jsonb_typeof(e) = 'object' then e - 'nonReturnable'
                      else e end order by ord), '[]'::jsonb)
          from jsonb_array_elements(new.items) with ordinality as t(e, ord));
      return new;
    end if;
    -- Сыйлықта өз ережесі бар (0070: алушы ауыстыра алады, тек жеке белгіленген
    -- тауардан басқа), сондықтан дүкен режимі оларға таралмайды.
    if not coalesce(new.is_gift, false)
       and exists (select 1 from public.stores s
                    where s.admin_uid = new.admin_uid
                      and s.return_policy_mode = 'none'
                      and s.allow_non_returnable) then
      select coalesce(array_agg(e->>'productId'), '{}'::text[]) into v_nr
        from jsonb_array_elements(new.items) e
       where jsonb_typeof(e) = 'object';
    else
      select coalesce(array_agg(p.id::text), '{}'::text[]) into v_nr
        from public.products p
       where p.non_returnable
         and p.id::text in (
           select e->>'productId'
             from jsonb_array_elements(new.items) e
            where jsonb_typeof(e) = 'object');
    end if;
  else
    if new.items is not distinct from old.items then
      return new;
    end if;
    select coalesce(array_agg(distinct e->>'productId'), '{}'::text[]) into v_nr
      from jsonb_array_elements(
             case when jsonb_typeof(old.items) = 'array'
                  then old.items else '[]'::jsonb end) e
     where jsonb_typeof(e) = 'object'
       and e->'nonReturnable' = 'true'::jsonb;
  end if;

  new.items := (
    select coalesce(jsonb_agg(
             case
               when jsonb_typeof(e) <> 'object' then e
               when (e->>'productId') = any(v_nr)
                 then e || jsonb_build_object('nonReturnable', true)
               else e - 'nonReturnable'
             end order by ord), '[]'::jsonb)
      from jsonb_array_elements(new.items) with ordinality as t(e, ord)
  );
  return new;
end;
$$;
revoke all on function public.snapshot_order_non_returnable() from public, anon, authenticated;

-- Клиент жіберген мән елеусіз қалады; жаңартуда ескісі сақталады.
create or replace function public.snapshot_order_return_policy()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_store public.stores;
  v_mode  text;
  v_notes jsonb;
begin
  if tg_op = 'UPDATE' then
    if not public.is_superadmin() then
      new.return_policy := old.return_policy;
      -- «Түсіндім» — клиенттің өз белгісі. RLS баған деңгейінде шектемейді:
      -- әйтпесе дүкен өз тапсырыстарында парақшаны жасырып тастай алар еді.
      if auth.uid() is distinct from old.client_uid then
        new.return_notice_ack_at := old.return_notice_ack_at;
      end if;
    end if;
    return new;
  end if;

  new.return_policy := null;
  new.return_notice_ack_at := null;
  if coalesce(new.is_gift, false) or not public.feature_enabled('return_notice') then
    return new;
  end if;

  select * into v_store from public.stores s where s.admin_uid = new.admin_uid;
  if not found then
    return new;
  end if;

  v_mode := case when v_store.return_policy_mode = 'none'
                  and v_store.allow_non_returnable
                  and public.feature_enabled('non_returnable')
                 then 'none' else 'accept' end;

  select coalesce(jsonb_object_agg(p.id::text, p.return_note), '{}'::jsonb) into v_notes
    from public.products p
   where btrim(p.return_note) <> ''
     and p.id::text in (
       select e->>'productId'
         from jsonb_array_elements(
                case when jsonb_typeof(new.items) = 'array'
                     then new.items else '[]'::jsonb end) e
        where jsonb_typeof(e) = 'object');

  new.return_policy := jsonb_build_object(
    'mode',          v_mode,
    'days',          v_store.return_days,
    'conditions',    to_jsonb(v_store.return_conditions),
    'note',          v_store.return_policy_note,
    'product_notes', v_notes);
  return new;
end;
$$;
revoke all on function public.snapshot_order_return_policy() from public, anon, authenticated;

drop trigger if exists trg_snapshot_order_return_policy on public.orders;
create trigger trg_snapshot_order_return_policy
  before insert or update of return_policy, return_notice_ack_at on public.orders
  for each row execute function public.snapshot_order_return_policy();

-- completed_at (0045) — қайтару мерзімі мен хабарламаның 30 күндік сүзгісі осыдан
-- есептеледі, сондықтан тек триггердің өзі жазады. Дүкен кері жазып хабарламаны
-- жасыра алмасын, клиент алға жазып мерзімді ұзарта алмасын.
create or replace function public.set_order_completed_at() returns trigger
language plpgsql set search_path = public as $$
begin
  if new.status = 'completed' and coalesce(old.status, '') <> 'completed' then
    new.completed_at := now();
  elsif new.completed_at is distinct from old.completed_at
        and auth.uid() is not null
        and not public.is_superadmin() then
    new.completed_at := old.completed_at;
  end if;
  return new;
end;
$$;
revoke all on function public.set_order_completed_at() from public, anon, authenticated;

-- ── 5. Клиент «түсіндім» деді ────────────────────────────────────────────────
create or replace function public.ack_return_notice(p_order uuid)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then
    raise exception 'not_authorized';
  end if;
  update public.orders
     set return_notice_ack_at = coalesce(return_notice_ack_at, now())
   where id = p_order
     and client_uid = auth.uid();
end;
$$;
revoke execute on function public.ack_return_notice(uuid) from public;
grant execute on function public.ack_return_notice(uuid) to authenticated;

-- ── 6. Push: аяқталғанда шарттарға апаратын жол ──────────────────────────────
-- Бөлек push ЕМЕС (клиентке екі хабар бармасын) — бар хабарға бір жол қосылады.
-- Барлық аяқталу жолы (дүкен, курьер, Казпочта) осы бір триггерден өтеді.
create or replace function public.on_order_status_push() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_title  text;
  v_first  text;
  v_notice boolean;
  v_data   jsonb;
begin
  if new.status is not distinct from old.status or new.client_uid is null then
    return new;
  end if;
  v_title := case new.status
    when 'reserved'  then '✅ Бронь подтверждена'
    when 'confirmed' then '✅ Оплата подтверждена'
    when 'ready'     then '📦 Заказ готов к выдаче'
    when 'completed' then '🎉 Заказ выполнен'
    when 'rejected'  then '⚠️ Чек отклонён — прикрепите новый'
    when 'cancelled' then '❌ Заказ отменён'
    else null
  end;
  if v_title is null then return new; end if;

  v_notice := new.status = 'completed' and new.return_policy is not null;
  v_data := jsonb_build_object('type', 'order_status', 'orderId', new.id, 'status', new.status);
  if v_notice then
    v_data := v_data || jsonb_build_object('notice', 'return_policy');
  end if;

  v_first := coalesce(new.items->0->>'productName', '');
  perform public.notify_push(
    array[new.client_uid],
    v_title,
    coalesce(nullif(new.store_name, ''), 'Магазин') || ' · Заказ №' || new.order_number
      || coalesce(E'\n' || nullif(v_first, ''), '')
      || case when v_notice
              then E'\nУсловия возврата — в заказе / Қайтару шарттары — тапсырыста'
              else '' end,
    v_data
  );
  return new;
end;
$$;
revoke all on function public.on_order_status_push() from public, anon, authenticated;
