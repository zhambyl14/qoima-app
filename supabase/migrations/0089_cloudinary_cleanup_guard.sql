-- ════════════════════════════════════════════════════════════════════════════
--  0089 · cloudinary-cleanup edge функциясының серверлік күзеті
-- ────────────────────────────────────────────────────────────────────────────
--  Мәселе: cloudinary-cleanup ешкімді тексермейтін — публиктік anon кілті бар
--  кез келген адам { urls:[...] } арқылы КЕЗ КЕЛГЕН Cloudinary суретін (тауар
--  фотосы, төлем чегі, сторис) біржола өшіре алатын, drain/reconcile де ашық.
--  Функция енді JWT-ті тексереді (supabase/functions/cloudinary-cleanup), ал
--  «бұл суретті біреу қолданып тұр ма» шешімі осы жерде, БД ішінде жасалады.
--
--  1) cloudinary_pids_in(text) — мәтіндегі (URL не жолдың jsonb мәтіні) біздің
--     public_id-лерді шығарады. Версия (v123/) мен кеңейтімге (.jpg/
--     .png) тәуелсіз: Cloudinary destroy тек public_id-ді алады, сондықтан
--     «синоним» URL арқылы айналып өтуге болмайды. Артық сәйкестік (басқа хост,
--     т.б.) тек ӨШІРМЕУГЕ әкеледі — қауіпсіз бағыт.
--  2) cloudinary_blocked_ids(ids, caller, mode) — өшіруге БОЛМАЙТЫН public_id-
--     дер тізімі. Екі түрлі сілтеме:
--       «Тірі» жол — сурет қазір көрсетіліп/сақталып тұрған жер: тауар, сторис,
--         эфир мұқабасы, дүкен жолы (логотип), төлем чегі, қайтару фотолары,
--         қолдау хаты, баннер, дүкен ашу/өзгерту өтінімдері, шағым айғағы
--         (content_reports.target_image, 0086). Мұнда сілтелген
--         сурет ЕКІ режимде де, ИЕСІНЕ ҚАРАМАЙ бұғатталады (тіпті өз тауарың
--         болса да — алдымен жолдан алып таста; қосымшаның барлық ағыны солай
--         жасайды: _persist → deleteByUrl, deleteBatch → deleteMany).
--       Снапшот — тауар суретінің көшірмесі: orders (receipt_url-дан басқасы),
--         returns (фотолардан басқасы), favorites, gift_registry_items.
--         mode='user' — шақырушының дүкеніне (иесі/белсенді сатушы) тиесілі
--         снапшот бұғаттамайды, бөтен дүкендікі бұғаттайды.
--         mode='queue' (drain/reconcile) — снапшоттар есепке алынбайды
--         (sweep_sold_out_images бұрынғыдай жұмыс істесін).
--     Ешқайда сілтелмеген сурет рұқсат: ешкімге зияны жоқ (тек біздің
--     қалталар — edge функция тексереді; public_id кездейсоқ).
--  3) cloudinary_gc_state + cloudinary_gc_try_claim(key, sec) — drain/reconcile
--     «балғамен ұруға» қарсы атомды дроссель (Cloudinary Admin API лимиті),
--     сондай-ақ {urls} режимінің пайдаланушы бойынша дросселі ('u:<uuid>').
--  4) cdq_insert саясаты (0008) енді тек біздің Cloudinary URL-ін қабылдайды
--     (бұрын `with check (true)` еді) — кезек қоқыспен толмасын. drain бәрібір
--     әр жолды қайта тексереді.
--
--  Барлық жаңа функция SECURITY INVOKER және ТЕК service_role-ға ашық (edge
--  функция service_role кілтімен шақырады); public/anon/authenticated-тен алынған.
--  Идемпотентті: 0084-тің кез келген нұсқасының үстінен қайта жүргізуге болады
--  (store_stories.public_id бағанына тәуелді емес — to_jsonb(...) қолданылады;
--  plpgsql денесі баған атауларын тек орындалғанда тексереді).
-- ════════════════════════════════════════════════════════════════════════════

-- ── 1) Мәтіндегі біздің public_id-лер ──────────────────────────────────────
-- Мәтіннен (URL не жолдың jsonb мәтіні) «qoima_<қалта>/<сегмент>[/…]»
-- үзінділерін алады: нұсқа (v123/), трансформация сегменттері, кеңейтім
-- (.jpg/.png), ?query, тырнақша — бәрі шекара. Сондықтан бір суреттің кез
-- келген «синоним» URL-і бір public_id береді (Cloudinary destroy тек
-- public_id-ді алады). Артық сәйкестік тек ӨШІРМЕУГЕ әкеледі — қауіпсіз бағыт.
-- Әр жол бір рет қана оқылады (id санына тәуелсіз), сәйкестік — теңдік.
create or replace function public.cloudinary_pids_in(p_text text)
returns setof text
language sql immutable set search_path = public as $$
  select distinct m[1]
    from regexp_matches(coalesce(p_text, ''),
                        '(qoima_[a-z]+(?:/[A-Za-z0-9_-]+)+)', 'g') as m;
$$;
revoke execute on function public.cloudinary_pids_in(text) from public, anon, authenticated;
grant execute on function public.cloudinary_pids_in(text) to service_role;

-- ── 2) Өшіруге болмайтын public_id-лер ─────────────────────────────────────
create or replace function public.cloudinary_blocked_ids(
  p_public_ids text[],
  p_caller     uuid default null,
  p_mode       text default 'user'
)
returns setof text
language plpgsql stable security invoker set search_path = public as $$
declare
  v_ids   text[];
  v_user  boolean;
  v_store uuid;               -- шақырушының дүкен кілті (иесі/белсенді сатушы)
begin
  if p_mode is null or p_mode not in ('user', 'queue') then
    raise exception 'bad_mode';
  end if;
  v_user := (p_mode = 'user');

  select coalesce(array_agg(distinct x), '{}') into v_ids
    from unnest(coalesce(p_public_ids, '{}'::text[])) x
   where x is not null and x <> '' and char_length(x) <= 300;
  if cardinality(v_ids) = 0 then return; end if;
  if cardinality(v_ids) > 500 then raise exception 'too_many'; end if;

  -- Дүкен кілті: иесі (admin) не белсенді сатушы, блоксыз. Басқаларда null —
  -- ешбір снапшотқа иелік етпейді.
  if v_user and p_caller is not null then
    select case
             when u.role in ('admin', 'seller')
              and not coalesce(u.blocked, false)
              and (u.role = 'admin' or coalesce(u.join_status, '') = 'active')
             then coalesce(u.owner_id, u.id)
           end
      into v_store
      from public.users u
     where u.id = p_caller;
  end if;

  return query
  with refs(pid) as (
    -- ═══ «Тірі» жолдар: иесіне қарамай, екі режимде де бұғаттайды ═══
    select x.pid from public.products p
      cross join lateral public.cloudinary_pids_in(to_jsonb(p)::text) as x(pid)
     where x.pid = any(v_ids)
    union
    select x.pid from public.store_stories s
      cross join lateral public.cloudinary_pids_in(to_jsonb(s)::text) as x(pid)
     where x.pid = any(v_ids)
    union
    select x.pid from public.live_sessions l
      cross join lateral public.cloudinary_pids_in(to_jsonb(l)::text) as x(pid)
     where x.pid = any(v_ids)
    union
    select x.pid from public.stores st
      cross join lateral public.cloudinary_pids_in(to_jsonb(st)::text) as x(pid)
     where x.pid = any(v_ids)
    union
    -- Төлем чегі — төлем айғағы.
    select x.pid from public.orders o
      cross join lateral public.cloudinary_pids_in(to_jsonb(o)->>'receipt_url') as x(pid)
     where x.pid = any(v_ids)
    union
    -- Қайтару: клиент фотолары мен дүкеннің күй фотолары — айғақ.
    select x.pid from public.returns rt
      cross join lateral public.cloudinary_pids_in(
        coalesce((to_jsonb(rt)->'photo_urls')::text, '')
        || ' ' || coalesce((to_jsonb(rt)->'condition_photos')::text, '')) as x(pid)
     where x.pid = any(v_ids)
    union
    select x.pid from public.support_messages m
      cross join lateral public.cloudinary_pids_in(to_jsonb(m)::text) as x(pid)
     where x.pid = any(v_ids)
    union
    select x.pid from public.banners b
      cross join lateral public.cloudinary_pids_in(to_jsonb(b)::text) as x(pid)
     where x.pid = any(v_ids)
    union
    select x.pid from public.shop_requests q
      cross join lateral public.cloudinary_pids_in(to_jsonb(q)::text) as x(pid)
     where x.pid = any(v_ids)
    union
    select x.pid from public.store_edit_requests q
      cross join lateral public.cloudinary_pids_in(to_jsonb(q)::text) as x(pid)
     where x.pid = any(v_ids)
    union
    -- Шағым айғағы (0086 target_image — сторис суретінің снапшоты): сторис
    -- 24 сағатта өшіп, суреті кезекке түседі, бірақ модератор шағымда не
    -- болғанын көруі керек. to_jsonb(...)->> — 0086 әлі қолданылмаса да
    -- (баған жоқ → null) құламайды.
    select x.pid from public.content_reports cr
      cross join lateral public.cloudinary_pids_in(to_jsonb(cr)->>'target_image') as x(pid)
     where x.pid = any(v_ids)
    -- ═══ Снапшоттар: тек user режимінде, бөтен дүкендікі ғана бұғаттайды ═══
    union
    select x.pid from public.orders o
      cross join lateral public.cloudinary_pids_in((to_jsonb(o) - 'receipt_url')::text) as x(pid)
     where v_user and x.pid = any(v_ids) and not coalesce(o.admin_uid = v_store, false)
    union
    select x.pid from public.returns rt
      cross join lateral public.cloudinary_pids_in(
        (to_jsonb(rt) - 'photo_urls' - 'condition_photos')::text) as x(pid)
     where v_user and x.pid = any(v_ids) and not coalesce(rt.admin_uid = v_store, false)
    union
    select x.pid from public.favorites f
      cross join lateral public.cloudinary_pids_in(to_jsonb(f)::text) as x(pid)
     where v_user and x.pid = any(v_ids) and not coalesce(f.admin_uid = v_store, false)
    union
    select x.pid from public.gift_registry_items g
      cross join lateral public.cloudinary_pids_in(to_jsonb(g)::text) as x(pid)
     where v_user and x.pid = any(v_ids) and not coalesce(g.admin_uid = v_store, false)
  )
  select distinct refs.pid from refs;
end;
$$;
revoke execute on function public.cloudinary_blocked_ids(text[], uuid, text) from public, anon, authenticated;
grant execute on function public.cloudinary_blocked_ids(text[], uuid, text) to service_role;

-- ── 3) drain/reconcile дроссельі ───────────────────────────────────────────
create table if not exists public.cloudinary_gc_state (
  key     text primary key,
  last_at timestamptz not null default '-infinity'
);
alter table public.cloudinary_gc_state enable row level security;
-- Саясат жоқ → клиенттер мүлдем көрмейді; тек service_role (RLS-ті айналып өтеді).
revoke all on public.cloudinary_gc_state from public, anon, authenticated;
grant select, insert, update on public.cloudinary_gc_state to service_role;

-- true → шақырушы «слотты» алды (соңғы іске қосудан p_min_seconds өтті);
-- false → тым жиі, өткізіп жіберу. INSERT … ON CONFLICT … WHERE — атомды,
-- қатар келген екі drain-нің тек біреуі ғана true алады.
create or replace function public.cloudinary_gc_try_claim(p_key text, p_min_seconds integer)
returns boolean
language plpgsql security invoker set search_path = public as $$
declare
  v_ok boolean;
begin
  -- 'u:<uuid>' — {urls} режимінің пайдаланушы бойынша дросселі (әр шақыру
  -- бірнеше кестені толық сканерлейді — бір аккаунт БД-ны «балғамен ұрмасын»).
  if p_key is null
     or not (p_key in ('drain', 'reconcile_auto', 'reconcile_manual')
             or p_key ~ '^u:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') then
    raise exception 'bad_key';
  end if;
  insert into public.cloudinary_gc_state as s (key, last_at)
  values (p_key, now())
  on conflict (key) do update
     set last_at = now()
   where s.last_at < now() - make_interval(secs => greatest(coalesce(p_min_seconds, 0), 0))
  returning true into v_ok;
  return coalesce(v_ok, false);
end;
$$;
revoke execute on function public.cloudinary_gc_try_claim(text, integer) from public, anon, authenticated;
grant execute on function public.cloudinary_gc_try_claim(text, integer) to service_role;

-- drain service_role-мен шақырады. Supabase әдепкі гранттарына сүйенбей,
-- нақты береміз; клиенттерге жабық күйін қайта бекітеміз (0007/0065/0065b).
revoke execute on function public.sweep_sold_out_images(integer) from public, anon, authenticated;
grant execute on function public.sweep_sold_out_images(integer) to service_role;

-- ── 4) Кезекке клиент тек біздің Cloudinary URL-ін сала алады ──────────────
-- (CloudinaryService.deleteMany edge функция сәтсіз болғанда осында жазады.)
drop policy if exists cdq_insert on public.cloudinary_delete_queue;
create policy cdq_insert on public.cloudinary_delete_queue
  for insert to authenticated
  with check (
    char_length(url) <= 500
    and url ~ '^https://res\.cloudinary\.com/divynstru/image/upload/'
  );

-- ── 5) Өзін-өзі тексеру (тірі БД схемасының дрифті) ────────────────────────
-- plpgsql денесі кесте/баған атауын тек ОРЫНДАЛҒАНДА тексереді. Тірі БД-да
-- бір кесте жоқ не admin_uid типі өзгеше (text) болса, функция әр шақыруда
-- құлап, edge функция үнсіз «guard_unavailable» күйінде қалар еді (ештеңе
-- өшірілмейді, ешкім байқамайды). Сондықтан екі режимді осында бір рет
-- шақырамыз: қате болса — бүкіл миграция кері қайтады және қате мәтіні
-- қай кесте/баған екенін көрсетеді. Ешнәрсе жазбайды (stable функция).
do $$
begin
  perform count(*) from public.cloudinary_blocked_ids(
    array['qoima_products/__0089_selftest__'], gen_random_uuid(), 'user');
  perform count(*) from public.cloudinary_blocked_ids(
    array['qoima_products/__0089_selftest__'], null, 'queue');
  perform public.cloudinary_pids_in('x');
end $$;
