-- ════════════════════════════════════════════════════════════════════════════
--  0073 · Қайтарылмайтын тауарлар саясаты + жеке (private) сұрақ-жауап
-- ────────────────────────────────────────────────────────────────────────────
--  (1) ҚАЙТАРЫЛМАЙТЫН ТАУАРЛАР
--   • stores.allow_non_returnable — дүкенге «қайтарылмайтын тауар» белгісін
--     қоюға РҰҚСАТ. Тек superadmin өзгертеді: set_store_non_returnable_permission
--     RPC. stores_write саясаты иесіне бүкіл жолды жаңартуға рұқсат береді
--     (RLS баған деңгейінде шектемейді!) — сондықтан BEFORE INSERT/UPDATE
--     guard триггері қойылды. «Данные магазина» өзгерту запросы арқылы
--     (store_edit_requests.changes) бұл бағанды жіберу де триггермен бөгеледі
--     — әйтпесе superadmin «қабылдау» басқанда өзі қолданып жіберер еді.
--   • Рұқсат алынып тасталғанда сол дүкеннің products.non_returnable
--     белгілері ТАЗАЛАНАДЫ (шешім: «рұқсат жоқ, бірақ белгі тұр» деген
--     екіұшты күй болмауы үшін; иесі қайта рұқсат алса, белгіні қайта қояды).
--     Бұрын сатылған тапсырыстардағы снапшот ӨЗГЕРМЕЙДІ — клиент сатып алу
--     кезінде келіскен шарт күшінде қалады.
--   • stores.return_policy_note (≤500) — дүкеннің жалпы қайтару ережесі.
--     Иесі өзі, модерациясыз жазады (set_store_return_note RPC).
--   • products.non_returnable / products.return_note (≤300) — иесі өз
--     тауарына қояды, бірақ non_returnable=true тек дүкенге рұқсат болса
--     (guard триггері: 'non_returnable_not_allowed').
--   • Сату сәтіндегі СНАПШОТ: orders.items[] әр элементіне сервер өзі
--     "nonReturnable": true қосады (клиентке СЕНБЕЙМІЗ). Кейінгі items
--     жаңартуларында белгі ескі жолдан көшіріледі (жоғалмайды, қосылмайды).
--   • Возврат: клиент returns жазбасын тікелей енгізеді (RLS returns_insert)
--     — BEFORE INSERT/UPDATE триггері тапсырыс жолы nonReturnable болған
--     тауарды бөгейді ('item_non_returnable'). Дүкен қызметкері/superadmin
--     өз шешімімен қабылдай алады (триггер оларға кедергі жасамайды).
--
--   • FEATURE FLAG (0067b): 'non_returnable' өшірулі болса — иесі жаңа белгі /
--     ереже жаза алмайды ('feature_disabled'), жаңа тапсырыс снапшотталмайды.
--     Superadmin басқару RPC-і бөгелмейді. Бұрынғы снапшот қорғанысы қалады.
--
--  (2) ЖЕКЕ СҰРАҚ-ЖАУАП
--   • 0046-да product_questions_select = using (true) еді (бәріне ашық).
--     Енді: сұрақ иесі (клиент), дүкен қызметкерлері, superadmin — әрқашан;
--     қалғандары — тек app_settings 'qa_public' = 'true' болғанда.
--     Әдепкісі 'false' = сұрақ тек клиент пен дүкен арасында.
--   • qa_is_public() — публичті (anon да шақырады): мұнда құпия жоқ, тек
--     бір баптаудың мәні; app_settings кестесін қонақ оқи алмайды.
-- ════════════════════════════════════════════════════════════════════════════

-- ── 1. Бағандар ──────────────────────────────────────────────────────────────
alter table public.stores
  add column if not exists allow_non_returnable boolean not null default false;
alter table public.stores
  add column if not exists return_policy_note text not null default '';

alter table public.products
  add column if not exists non_returnable boolean not null default false;
alter table public.products
  add column if not exists return_note text not null default '';

do $$
begin
  if not exists (select 1 from pg_constraint
                  where conname = 'stores_return_policy_note_len') then
    alter table public.stores add constraint stores_return_policy_note_len
      check (char_length(return_policy_note) <= 500);
  end if;
  if not exists (select 1 from pg_constraint
                  where conname = 'products_return_note_len') then
    alter table public.products add constraint products_return_note_len
      check (char_length(return_note) <= 300);
  end if;
end $$;

-- ── 2. stores: allow_non_returnable — тек superadmin ─────────────────────────
-- auth.uid() бос = service_role / SQL editor (anon-ға stores жазу RLS-пен
-- жабық), оларға кедергі жасамаймыз.
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
  return new;
end;
$$;
revoke all on function public.guard_stores_privileged_columns() from public, anon, authenticated;

drop trigger if exists trg_guard_stores_privileged_columns on public.stores;
create trigger trg_guard_stores_privileged_columns
  before insert or update on public.stores
  for each row execute function public.guard_stores_privileged_columns();

-- «Данные магазина» запросы арқылы рұқсат бағанын жіберуге болмайды.
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
       and lower(replace(coalesce(c->>'field', ''), '_', '')) = 'allownonreturnable'
  ) then
    raise exception 'privileged_column_denied:allow_non_returnable';
  end if;
  return new;
end;
$$;
revoke all on function public.guard_store_edit_privileged_fields() from public, anon, authenticated;

drop trigger if exists trg_guard_store_edit_privileged_fields on public.store_edit_requests;
create trigger trg_guard_store_edit_privileged_fields
  before insert or update of changes on public.store_edit_requests
  for each row execute function public.guard_store_edit_privileged_fields();

-- ── 3. products: non_returnable тек рұқсат болса ─────────────────────────────
-- Тек false→true ауысуы тексеріледі: рұқсат алынғанда superadmin RPC-і
-- белгілерді тазалайды, ал басқа өрістерді өңдеу кедергісіз қалады.
create or replace function public.guard_products_non_returnable()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if coalesce(new.non_returnable, false)
     and (tg_op = 'INSERT' or not coalesce(old.non_returnable, false)) then
    -- Superadmin функцияны өшірсе (0067b), жаңа белгі қойылмайды.
    if not public.feature_enabled('non_returnable') then
      raise exception 'feature_disabled';
    end if;
    if not exists (
      select 1 from public.stores s
       where s.admin_uid = new.owner_uid
         and s.allow_non_returnable
    ) then
      raise exception 'non_returnable_not_allowed';
    end if;
  end if;
  return new;
end;
$$;
revoke all on function public.guard_products_non_returnable() from public, anon, authenticated;

drop trigger if exists trg_guard_products_non_returnable on public.products;
create trigger trg_guard_products_non_returnable
  before insert or update of non_returnable on public.products
  for each row execute function public.guard_products_non_returnable();

-- ── 4. Superadmin RPC: дүкенге рұқсат беру/алу ───────────────────────────────
-- Қайтарады: тазаланған тауар саны (рұқсат алынғанда), әйтпесе 0.
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

-- ── 5. Иесінің RPC-і: дүкеннің қайтару ережесі (модерациясыз) ────────────────
create or replace function public.set_store_return_note(p_note text)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_owner uuid := public.app_owner_uid();
  v_note  text := btrim(coalesce(p_note, ''));
begin
  if auth.uid() is null or v_owner is null or public.app_role() <> 'admin' then
    raise exception 'not_authorized';
  end if;
  if not public.feature_enabled('non_returnable') then
    raise exception 'feature_disabled';
  end if;
  if char_length(v_note) > 500 then
    raise exception 'note_too_long';
  end if;

  update public.stores
     set return_policy_note = v_note,
         updated_at = now()
   where admin_uid = v_owner;
  if not found then
    raise exception 'store_not_found';
  end if;
end;
$$;
revoke execute on function public.set_store_return_note(text) from public;
grant execute on function public.set_store_return_note(text) to authenticated;

-- ── 6. orders: сату сәтіндегі снапшот ────────────────────────────────────────
--  INSERT: products.non_returnable бойынша әр жолға белгі қойылады/алынады.
--  UPDATE OF items: белгі ЕСКІ items-тен көшіріледі (productId бойынша) —
--  своп/өлшем ауысуы кезінде жоғалмайды, ал кейін қосылмайды (шарт — сатып
--  алу сәтіндегі). Басқа кілттер өзгеріссіз, реті сақталады.
--  orders-те бұған дейін BEFORE INSERT триггері жоқ еді (тексерілді).
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
    -- Функция өшірулі болса жаңа тапсырыс белгіленбейді (superadmin қосқыш).
    -- Бұрын сатылған снапшоттар (UPDATE тармағы) өзгермейді.
    if not public.feature_enabled('non_returnable') then
      new.items := (
        select coalesce(jsonb_agg(
                 case when jsonb_typeof(e) = 'object' then e - 'nonReturnable'
                      else e end order by ord), '[]'::jsonb)
          from jsonb_array_elements(new.items) with ordinality as t(e, ord));
      return new;
    end if;
    select coalesce(array_agg(p.id::text), '{}'::text[]) into v_nr
      from public.products p
     where p.non_returnable
       and p.id::text in (
         select e->>'productId'
           from jsonb_array_elements(new.items) e
          where jsonb_typeof(e) = 'object');
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

drop trigger if exists trg_snapshot_order_non_returnable on public.orders;
create trigger trg_snapshot_order_non_returnable
  before insert or update of items on public.orders
  for each row execute function public.snapshot_order_non_returnable();

-- ── 7. returns: қайтарылмайтын тауарды клиент қайтара алмайды ───────────────
--  returns.items[] элементі: {product_id, batch_id, size, ...}; orders.items[]:
--  {productId, batchId, nonReturnable, ...}. returns.order_id — text.
--  RLS (returns_insert/update) клиентке тек client_uid = auth.uid() талап
--  етеді, ал order_id мен items — клиент бақылайтын өрістер. Сондықтан
--  қызметкер емес жағдайда триггер БӘРІН өзі тексереді:
--   (1) order_id міндетті ('order_required');
--   (2) тапсырыс осы клиенттікі және осы дүкенніңкі ('order_mismatch');
--   (3) әр қайтарылатын жол тапсырыстың бір жолымен batch_id арқылы
--       сәйкес келеді ('item_not_in_order') — product_id-ді өзгертіп/
--       жасырып айналып өту мүмкін емес;
--   (4) тапсырыс жолы productId НЕМЕСЕ batchId бойынша сәйкес келіп,
--       nonReturnable=true болса — 'item_non_returnable'.
create or replace function public.guard_return_non_returnable()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_order_items  jsonb;
  v_order_client uuid;
  v_order_admin  uuid;
begin
  -- Дүкен қызметкері / superadmin — өз шешімімен қабылдай алады.
  if public.is_superadmin() or new.admin_uid = public.app_owner_uid() then
    return new;
  end if;
  -- auth.uid() бос = service_role / SQL editor: кедергі жасамаймыз.
  if auth.uid() is null then
    return new;
  end if;
  if tg_op = 'UPDATE'
     and new.items is not distinct from old.items
     and new.order_id is not distinct from old.order_id then
    return new;
  end if;

  if coalesce(new.order_id, '') = '' then
    raise exception 'order_required';
  end if;

  select o.items, o.client_uid, o.admin_uid
    into v_order_items, v_order_client, v_order_admin
    from public.orders o
   where o.id::text = new.order_id;

  if not found
     or v_order_client is distinct from new.client_uid
     or v_order_admin  is distinct from new.admin_uid then
    raise exception 'order_mismatch';
  end if;

  if jsonb_typeof(v_order_items) <> 'array'
     or jsonb_typeof(new.items) <> 'array' then
    raise exception 'item_not_in_order';
  end if;

  -- (3) әр қайтарылатын жол тапсырыста бар болуы тиіс
  if exists (
    select 1
      from jsonb_array_elements(new.items) r
     where jsonb_typeof(r) <> 'object'
        or coalesce(r->>'batch_id', '') = ''
        or not exists (
          select 1
            from jsonb_array_elements(v_order_items) oi
           where jsonb_typeof(oi) = 'object'
             and oi->>'batchId' = r->>'batch_id')
  ) then
    raise exception 'item_not_in_order';
  end if;

  -- (4) снапшот бойынша қайтарылмайтын жол
  if exists (
    select 1
      from jsonb_array_elements(new.items) r,
           jsonb_array_elements(v_order_items) oi
     where jsonb_typeof(oi) = 'object'
       and oi->'nonReturnable' = 'true'::jsonb
       and (oi->>'productId' = r->>'product_id'
            or oi->>'batchId' = r->>'batch_id')
  ) then
    raise exception 'item_non_returnable';
  end if;
  return new;
end;
$$;
revoke all on function public.guard_return_non_returnable() from public, anon, authenticated;

drop trigger if exists trg_guard_return_non_returnable on public.returns;
create trigger trg_guard_return_non_returnable
  before insert or update of items, order_id on public.returns
  for each row execute function public.guard_return_non_returnable();

-- ── 8. Жеке сұрақ-жауап ──────────────────────────────────────────────────────
insert into public.app_settings (key, value)
values ('qa_public', 'false')
on conflict (key) do nothing;

-- ӘДЕЙІ ПУБЛИЧТІ (anon + authenticated): тек бір баптаудың true/false мәні,
-- құпия дерек жоқ. Қонақ app_settings кестесін оқи алмайды (0022 RLS).
create or replace function public.qa_is_public()
returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select lower(btrim(value)) from public.app_settings where key = 'qa_public'),
    'false') = 'true';
$$;
revoke execute on function public.qa_is_public() from public;
grant execute on function public.qa_is_public() to anon, authenticated;

-- 0046-дағы using (true) орнына. Тірі БД-дағы ескі нұсқа: qual = true.
drop policy if exists product_questions_select on public.product_questions;
create policy product_questions_select on public.product_questions
  for select using (
    client_uid = auth.uid()
    or admin_uid = public.app_owner_uid()
    or public.is_superadmin()
    or public.qa_is_public()
  );
