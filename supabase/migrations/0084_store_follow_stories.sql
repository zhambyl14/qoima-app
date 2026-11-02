-- ════════════════════════════════════════════════════════════════════════════
--  0084 · Дүкенге жазылу (follow) + жеңілдік/эфир push-тары + сторис
-- ────────────────────────────────────────────────────────────────────────────
--  НЕ ҮШІН (иесінің сөзі): клиент ұнаған дүкенге жазылып, жеңілдік не live
--  басталғанда хабар алсын; жазылған дүкендердің эфирі басты бетте бірінші
--  тұрсын; дүкен иелері эфирден бөлек 24 сағаттық сторис сала алсын.
--
--  ҚАУІПСІЗДІК (CLAUDE.md / 0065 ережелері):
--   • store_follows / store_stories кестелеріне клиенттің ТІКЕЛЕЙ жазуы жоқ
--     (insert/update/delete саясаты жоқ + грант алынды) — бәрі SECURITY DEFINER
--     RPC арқылы, әрқайсысы auth.uid() / app_owner_uid() тексереді.
--   • Әр функцияның соңында `revoke … from public` (create or replace PUBLIC
--     грантын қайта тудырады — сондықтан әр функциядан кейін бірден).
--   • Жалаушалар: feature_store_follow, feature_stories — әдепкіде 'false',
--     иесі телефонда сынаған соң суперадмин бетінен қосады.
--   • Push спамынан қорғау: store_push_throttle (дүкен × түр бойынша соңғы
--     уақыт), атомды upsert — жеңілдікке 12 сағат, эфирге 2 сағат.
--   • Сторис суреті тек Cloudinary-дің qoima_stories қалтасынан: өшкенде
--     сурет cloudinary_delete_queue-ге түседі, сондықтан тауар суретін
--     сторис ретінде көрсетіп, кейін оны өшіртіп жіберу мүмкін болмасын.
-- ════════════════════════════════════════════════════════════════════════════

-- ── 0. Жалаушалар ───────────────────────────────────────────────────────────
insert into public.app_settings (key, value) values
  ('feature_store_follow', 'false'),
  ('feature_stories',      'false')
on conflict (key) do nothing;

-- ── 1. Дүкен жұртқа көрінетін бе ────────────────────────────────────────────
--  Жарияланған, блокталмаған, иесі глобал блокта емес. Әдейі публиктік
--  (anon да): store_stories RLS саясаты ішінде шақырылады, тек true/false
--  қайтарады — бұл каталогтың өзі сияқты ашық ақпарат.
create or replace function public.store_publicly_visible(p_store uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(exists (
    select 1 from public.stores s
    where s.admin_uid = p_store
      and s.is_published = true
      and coalesce(s.status, 'active') <> 'blocked'
      and not exists (select 1 from public.users u
                      where u.id = p_store and coalesce(u.blocked, false))
  ), false);
$$;
revoke execute on function public.store_publicly_visible(uuid) from public;
grant execute on function public.store_publicly_visible(uuid) to anon, authenticated;

-- ── 2. Жазылулар ────────────────────────────────────────────────────────────
create table if not exists public.store_follows (
  client_uid uuid not null references auth.users(id) on delete cascade,
  -- Дүкен кілті = stores.admin_uid (иесінің uid-і).
  store_uid  uuid not null references public.stores(admin_uid) on delete cascade,
  -- false = жазылған, бірақ push алмайды («қоңырауды өшіру»).
  notify     boolean not null default true,
  created_at timestamptz not null default now(),
  primary key (client_uid, store_uid)
);
-- Push таратуда және санағышта дүкен бойынша іздейміз.
create index if not exists store_follows_store_idx
  on public.store_follows(store_uid, created_at);

alter table public.store_follows enable row level security;
revoke insert, update, delete, truncate on public.store_follows from anon, authenticated;
revoke select on public.store_follows from anon;

-- Әркім тек ӨЗ жазылуларын көреді (кім кімге жазылғаны — жеке дерек).
drop policy if exists store_follows_own on public.store_follows;
create policy store_follows_own on public.store_follows
  for select to authenticated using (client_uid = auth.uid());

-- RPC: жазылу. Қайталап шақыру қауіпсіз (идемпотент). Қайтарады: true.
create or replace function public.follow_store(p_store uuid)
returns boolean
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_cnt integer;
begin
  if v_uid is null then raise exception 'not_authorized'; end if;
  if not public.feature_enabled('store_follow') then raise exception 'feature_disabled'; end if;
  if exists (select 1 from public.users u where u.id = v_uid and coalesce(u.blocked, false)) then
    raise exception 'user_blocked';
  end if;
  if p_store is null or not public.store_publicly_visible(p_store) then
    raise exception 'store_unavailable';
  end if;
  -- Өз дүкеніне (иесі не сатушысы) жазылу мағынасыз әрі санағышты бұрмалайды.
  if coalesce(p_store = public.app_owner_uid(), false) then
    raise exception 'cannot_follow_own_store';
  end if;
  if exists (select 1 from public.store_follows
             where client_uid = v_uid and store_uid = p_store) then
    return true;
  end if;
  -- Шек тексерісі мен insert бір қолданушы үшін сериялансын (екі құрылғыдан
  -- қатар басса да 200-ден аспасын).
  perform pg_advisory_xact_lock(hashtextextended('store_follow:' || v_uid::text, 0));
  select count(*) into v_cnt from public.store_follows where client_uid = v_uid;
  if v_cnt >= 200 then raise exception 'follow_limit'; end if;
  insert into public.store_follows(client_uid, store_uid)
    values (v_uid, p_store)
    on conflict (client_uid, store_uid) do nothing;
  return true;
end;
$$;
revoke execute on function public.follow_store(uuid) from public, anon;
grant execute on function public.follow_store(uuid) to authenticated;

-- RPC: жазылудан шығу. Жалауша өшік болса да рұқсат (қолданушы өз дерегін
-- әрқашан тазалай алсын). Қайтарады: false (енді жазылмаған).
create or replace function public.unfollow_store(p_store uuid)
returns boolean
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not_authorized'; end if;
  delete from public.store_follows
    where client_uid = auth.uid() and store_uid = p_store;
  return false;
end;
$$;
revoke execute on function public.unfollow_store(uuid) from public, anon;
grant execute on function public.unfollow_store(uuid) to authenticated;

-- RPC: хабарламаны қосу/өшіру. Өшіру әрқашан рұқсат, қосу — жалауша қосулыда.
-- Қайтарады: жаңа notify мәні.
create or replace function public.set_follow_notify(p_store uuid, p_notify boolean)
returns boolean
language plpgsql security definer set search_path = public as $$
declare
  v_val boolean := coalesce(p_notify, false);
begin
  if auth.uid() is null then raise exception 'not_authorized'; end if;
  if v_val and not public.feature_enabled('store_follow') then
    raise exception 'feature_disabled';
  end if;
  update public.store_follows set notify = v_val
    where client_uid = auth.uid() and store_uid = p_store;
  if not found then raise exception 'not_following'; end if;
  return v_val;
end;
$$;
revoke execute on function public.set_follow_notify(uuid, boolean) from public, anon;
grant execute on function public.set_follow_notify(uuid, boolean) to authenticated;

-- RPC: менің жазылуларым (дүкен аты/логотипімен). available = false болса
-- дүкен қазір жабық/блокта — UI оны сұр көрсетіп, «шығу» батырмасын қалдырады.
create or replace function public.my_follows()
returns table (
  store_uid  uuid,
  notify     boolean,
  created_at timestamptz,
  store_name text,
  logo_url   text,
  city       text,
  available  boolean
)
language sql stable security definer set search_path = public as $$
  select f.store_uid, f.notify, f.created_at,
         coalesce(s.store_name, ''), coalesce(s.logo_url, ''), coalesce(s.city, ''),
         public.store_publicly_visible(f.store_uid)
  from public.store_follows f
  left join public.stores s on s.admin_uid = f.store_uid
  where auth.uid() is not null and f.client_uid = auth.uid()
  order by f.created_at desc;
$$;
revoke execute on function public.my_follows() from public, anon;
grant execute on function public.my_follows() to authenticated;

-- RPC: дүкеннің жазылушылар САНЫ (тек сан — кім екені емес). Әдейі публиктік
-- (гость те дүкен бетінде көреді). Жабық дүкенге 0, иесі/суперадмин — әрқашан.
create or replace function public.store_follower_count(p_store uuid)
returns integer
language sql stable security definer set search_path = public as $$
  select case
    when public.store_publicly_visible(p_store)
      or coalesce(p_store = public.app_owner_uid(), false)
      or public.is_superadmin()
    then (select count(*)::integer from public.store_follows f where f.store_uid = p_store)
    else 0
  end;
$$;
revoke execute on function public.store_follower_count(uuid) from public;
grant execute on function public.store_follower_count(uuid) to anon, authenticated;

-- ── 3. Push шектегіші + жазылушыларға тарату ────────────────────────────────
--  RLS қосулы, саясат ЖОҚ, грант алынды → клиентке мүлде жабық.
create table if not exists public.store_push_throttle (
  store_uid uuid not null,
  kind      text not null,
  last_at   timestamptz not null,
  primary key (store_uid, kind)
);
alter table public.store_push_throttle enable row level security;
revoke all on public.store_push_throttle from anon, authenticated;

--  Ішкі функция: тек definer триггерлер мен cron (postgres атынан) шақырады.
--  Сондықтан SECURITY INVOKER әрі ешкімге грант жоқ (0071 live_rate_hit
--  үлгісі) — авторизация = EXECUTE құқығының өзі; клиент шақыра алмайды.
--  p_exclude — басқа жолмен push алатындар (қос хабар жібермеу үшін).
--  Қайтарады: push жіберілген адам саны (шектеуге түссе — 0).
create or replace function public.notify_followers(
  p_store   uuid,
  p_kind    text,
  p_min_gap interval,
  p_title   text,
  p_body    text,
  p_data    jsonb,
  p_exclude uuid[] default null)
returns integer
language plpgsql set search_path = public as $$
declare
  v_uids uuid[];
  v_ok   integer;
  v_n    integer;
  i      integer;
begin
  if p_store is null or not public.feature_enabled('store_follow') then return 0; end if;

  -- Арзан алдын ала тексеріс: шектегіш әлі жабық болса — 5000 жолдық алушы
  -- сұранысын мүлде жасамаймыз. Әйтпесе жаппай жеңілдік (setDiscountBulk,
  -- N партия) әр жол үшін бүкіл жазылушылар тізімін қайта жинап, иесінің
  -- сұранысын statement_timeout-қа жеткізетін. Шешімді бәрібір төмендегі
  -- атомды upsert қабылдайды — бұл тек оңтайландыру.
  if exists (select 1 from public.store_push_throttle t
             where t.store_uid = p_store and t.kind = p_kind
               and t.last_at > now() - p_min_gap) then
    return 0;
  end if;

  -- Алушылар: хабарламасы қосулы, дүкенді жасырмаған, блокта емес.
  -- Шек 5000 — push синхронды жазылады, дүкен иесінің сұранысы ұзармасын.
  select array_agg(t.client_uid order by t.created_at) into v_uids from (
    select f.client_uid, f.created_at
    from public.store_follows f
    where f.store_uid = p_store and f.notify
      and not exists (select 1 from public.hidden_stores h
                      where h.admin_uid = p_store and h.client_uid = f.client_uid)
      and not exists (select 1 from public.users bu
                      where bu.id = f.client_uid and coalesce(bu.blocked, false))
      and (p_exclude is null or not (f.client_uid = any(p_exclude)))
    order by f.created_at
    limit 5000
  ) t;
  v_n := coalesce(cardinality(v_uids), 0);
  -- Алушы жоқ болса шектегішті «жұмсамаймыз» — алғашқы жазылушы келесі
  -- оқиғаны бірден алсын.
  if v_n = 0 then return 0; end if;

  -- Атомды шектегіш: соңғы push p_min_gap-тен ескі болса ғана жаңартылады.
  -- Қатар келген екі транзакцияның екіншісі жол құлпын күтіп, шартты қайта
  -- тексереді → тек біреуі өтеді.
  insert into public.store_push_throttle as t (store_uid, kind, last_at)
    values (p_store, p_kind, now())
    on conflict (store_uid, kind) do update set last_at = excluded.last_at
      where t.last_at <= now() - p_min_gap
    returning 1 into v_ok;
  if v_ok is null then return 0; end if;

  i := 1;
  while i <= v_n loop
    perform public.notify_push(v_uids[i:i + 499], p_title, p_body, p_data);
    i := i + 500;
  end loop;
  return v_n;
end;
$$;
revoke execute on function public.notify_followers(uuid, text, interval, text, text, jsonb, uuid[])
  from public, anon, authenticated;

-- ── 4. Жеңілдік push-ы ──────────────────────────────────────────────────────
--  Партия жеңілдігінің ҚАЗІРГІ пайызы (белсенді емес → 0). Dart-тағы
--  effectivePrice + discountBadgePercent-тің дәл көшірмесі: мерзімдер
--  _discount_ts арқылы (зонасыз жол = Алматы уақыты, Dart сияқты), баға
--  бүтінге дөңгелектенеді, пайыз сол дөңгелек бағадан есептеледі.
--  _batch_effective_price — сатып алушы ҚАЗІР төлейтін баға (белсенді жеңілдік
--  болмаса — selling_price өзі). Триггер «бағаны көтеріп, жеңілдік қосу»
--  (тиімді баға өзгермейді) жалған жеңілдігін осымен ажыратады.
create or replace function public._batch_effective_price(
  p_price double precision, p_discount jsonb, p_at timestamptz default now())
returns double precision
language plpgsql stable set search_path = public as $$
declare
  v_start timestamptz;
  v_end   timestamptz;
  v_val   double precision;
  v_eff   double precision;
begin
  if p_price is null then return null; end if;
  if p_price <= 0 or p_discount is null
     or jsonb_typeof(p_discount) <> 'object'
     or coalesce(p_discount ->> 'active', 'false') <> 'true' then
    return p_price;
  end if;
  v_start := public._discount_ts(p_discount ->> 'starts_at');
  v_end   := public._discount_ts(p_discount ->> 'ends_at');
  if v_start is not null and p_at < v_start then return p_price; end if;
  if v_end is not null and p_at > v_end then return p_price; end if;
  begin v_val := coalesce((p_discount ->> 'value')::double precision, 0);
  exception when others then v_val := 0; end;
  v_eff := case when coalesce(p_discount ->> 'type', 'percent') = 'percent'
                then p_price * (1 - v_val / 100)
                else p_price - v_val end;
  begin
    v_eff := greatest(0, round(v_eff::numeric)::double precision);
  exception when others then
    return p_price; -- NaN/Infinity сияқты бүлінген мән — жеңілдік жоқ деп
  end;
  return least(v_eff, p_price);
end;
$$;
revoke execute on function public._batch_effective_price(double precision, jsonb, timestamptz)
  from public, anon, authenticated;

create or replace function public._batch_discount_pct(
  p_price double precision, p_discount jsonb, p_at timestamptz default now())
returns integer
language plpgsql stable set search_path = public as $$
declare
  v_eff double precision;
begin
  if p_price is null or p_price <= 0 then return 0; end if;
  v_eff := public._batch_effective_price(p_price, p_discount, p_at);
  if v_eff is null or v_eff >= p_price then return 0; end if;
  return round(((1 - v_eff / p_price) * 100)::numeric)::integer;
end;
$$;
revoke execute on function public._batch_discount_pct(double precision, jsonb, timestamptz)
  from public, anon, authenticated;

-- Қай партияның қай басталу уақытына push кеткені (cron қайталамауы үшін).
create table if not exists public.discount_push_log (
  batch_id    uuid primary key references public.batches(id) on delete cascade,
  starts_at   timestamptz,
  notified_at timestamptz not null default now()
);
alter table public.discount_push_log enable row level security;
revoke all on public.discount_push_log from anon, authenticated;

-- Ішкі: бір партия үшін жазылушыларға жеңілдік хабары (тауар сөреде болса).
create or replace function public._discount_follow_push(
  p_batch uuid, p_owner uuid, p_product uuid, p_pct integer, p_starts timestamptz)
returns integer
language plpgsql set search_path = public as $$
declare
  v_name text;
begin
  insert into public.discount_push_log(batch_id, starts_at, notified_at)
    values (p_batch, p_starts, now())
    on conflict (batch_id) do update
      set starts_at = excluded.starts_at, notified_at = excluded.notified_at;
  if p_pct <= 0 or p_owner is null or not public.store_publicly_visible(p_owner) then
    return 0;
  end if;
  -- Жасырылған не сатылып біткен тауардың жеңілдігі туралы хабар — бос үміт.
  if not exists (select 1 from public.products p
                 where p.id = p_product and p.owner_uid = p_owner
                   and not coalesce(p.storefront_hidden, false)
                   and p.status = 'В наличии') then
    return 0;
  end if;
  select coalesce(nullif(btrim(store_name), ''), 'Qoima') into v_name
    from public.stores where admin_uid = p_owner;
  return public.notify_followers(
    p_owner, 'discount', interval '12 hours',
    '🏷 ' || v_name || ': скидка до −' || p_pct || '% / жеңілдік −' || p_pct || '%',
    'Загляните в магазин / Дүкенге кіріп көріңіз',
    jsonb_build_object('type', 'store_discount', 'storeUid', p_owner,
                       'adminUid', p_owner, 'percent', p_pct));
end;
$$;
revoke execute on function public._discount_follow_push(uuid, uuid, uuid, integer, timestamptz)
  from public, anon, authenticated;

--  Триггер: жеңілдік ҚАЗІР белсенді әрі (бұрын болмаған не пайызы өскен)
--  әрі тиімді баға шын төмендеген кезде ғана (бағаны көтеріп «−50%» қою —
--  хабар жоқ). INSERT (повторный завоз ескі жеңілдікті көшірсе) — сол тауардың
--  басқа партиясында одан үлкен/тең жеңілдік бұрыннан бар болса үнсіз.
--  Push қатесі иесінің жеңілдікті сақтауын ЕШҚАШАН бұзбайды.
create or replace function public.on_batch_discount_follow_push()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_new   integer;
  v_old   integer := 0;
  v_new_eff double precision;
  v_old_eff double precision;
  v_owner uuid;
begin
  if not public.feature_enabled('store_follow') then return null; end if;
  begin
    v_new := public._batch_discount_pct(new.selling_price, new.discount);
    if v_new <= 0 then return null; end if;
    v_new_eff := public._batch_effective_price(new.selling_price, new.discount);
    if tg_op = 'UPDATE' then
      v_old := public._batch_discount_pct(old.selling_price, old.discount);
      v_old_eff := public._batch_effective_price(old.selling_price, old.discount);
    else
      select coalesce(max(public._batch_discount_pct(b.selling_price, b.discount)), 0),
             min(public._batch_effective_price(b.selling_price, b.discount))
        into v_old, v_old_eff
        from public.batches b
        where b.product_id = new.product_id and b.id <> new.id;
    end if;
    -- Жалған жеңілдік: бағаны көтеріп, бір мезетте жеңілдік қосу — пайыз өсті,
    -- бірақ сатып алушы бұрынғыдан арзан алмайды. Тиімді баға ТӨМЕНДЕМЕСЕ
    -- (INSERT: сол тауардың ең арзан басқа партиясынан) — хабар жоқ.
    if v_new <= v_old
       or (v_old_eff is not null and v_new_eff is not null and v_new_eff >= v_old_eff) then
      -- Сақтау сәтінде бұрыннан белсенді жеңілдік «өңделді» деп белгіленеді:
      -- әйтпесе starts_at өткен уақытта тұрса (повторный завоз көшірмесі,
      -- пайызды төмендету) cron оны «басталды» деп қайта push жіберер еді.
      insert into public.discount_push_log(batch_id, starts_at, notified_at)
        values (new.id, public._discount_ts(new.discount ->> 'starts_at'), now())
        on conflict (batch_id) do update
          set starts_at = excluded.starts_at, notified_at = excluded.notified_at;
      return null;
    end if;
    v_owner := coalesce(new.owner_uid,
                        (select owner_uid from public.products where id = new.product_id));
    perform public._discount_follow_push(
      new.id, v_owner, new.product_id, v_new,
      public._discount_ts(new.discount ->> 'starts_at'));
  exception when others then
    null;
  end;
  return null;
end;
$$;
revoke execute on function public.on_batch_discount_follow_push() from public, anon, authenticated;

drop trigger if exists trg_batch_discount_follow_push on public.batches;
create trigger trg_batch_discount_follow_push
  after insert or update of discount on public.batches
  for each row execute function public.on_batch_discount_follow_push();

--  Cron (10 мин сайын): starts_at-ы алдағы уақытқа қойылған жеңілдік
--  басталғанда триггер іске қосылмайды (жол өзгермейді) — оны осы sweep
--  ұстайды. Соңғы 1 тәулікте басталған, әлі белсенді, push-ы жіберілмеген
--  (discount_push_log-та сол starts_at жоқ) партиялар. Cron кешіксе де
--  жоғалмайды, қайталанбайды; 12 сағаттық шектегіш триггермен ортақ.
create or replace function public.sweep_scheduled_discount_pushes()
returns integer
language plpgsql security definer set search_path = public as $$
declare
  r     record;
  v_cnt integer := 0;
begin
  if not public.feature_enabled('store_follow') then return 0; end if;
  for r in
    select b.id, b.product_id, b.selling_price, b.discount,
           coalesce(b.owner_uid, p.owner_uid) as owner_uid,
           public._discount_ts(b.discount ->> 'starts_at') as st
    from public.batches b
    left join public.products p on p.id = b.product_id
    where b.discount is not null
      and jsonb_typeof(b.discount) = 'object'
      and coalesce(b.discount ->> 'active', 'false') = 'true'
      and coalesce(b.discount ->> 'starts_at', '') <> ''
      and public._discount_ts(b.discount ->> 'starts_at') <= now()
      and public._discount_ts(b.discount ->> 'starts_at') > now() - interval '1 day'
      and not exists (
        select 1 from public.discount_push_log l
        where l.batch_id = b.id
          and l.starts_at is not distinct from public._discount_ts(b.discount ->> 'starts_at'))
    order by b.id
  loop
    begin
      v_cnt := v_cnt + coalesce(public._discount_follow_push(
        r.id, r.owner_uid, r.product_id,
        public._batch_discount_pct(r.selling_price, r.discount), r.st), 0);
    exception when others then
      null; -- бір бүлінген жол қалғандарын тоқтатпасын
    end;
  end loop;
  -- Ескі журнал жолдары керек емес (1 тәуліктік терезеден әлдеқайда ескі).
  delete from public.discount_push_log where notified_at < now() - interval '7 days';
  return v_cnt;
end;
$$;
revoke execute on function public.sweep_scheduled_discount_pushes() from public, anon, authenticated;

select cron.unschedule('follow-discount-sweep')
  where exists (select 1 from cron.job where jobname = 'follow-discount-sweep');
select cron.schedule(
  'follow-discount-sweep',
  '*/10 * * * *',
  $$select public.sweep_scheduled_discount_pushes()$$
);

-- ── 5. Эфир push-ы ──────────────────────────────────────────────────────────
--  Эфир басталғанда (live_start INSERT, status='live') жазылушыларға 2 сағатта
--  1 рет. data.type = 'live_started' — қосымшаның қазіргі нұсқасы бұл түрді
--  бұрыннан ашады (push_navigation.dart), жаңа UI керек емес.
--  Қос хабар болмасын: live_start өзі favorites ∪ completed orders аудиториясына
--  push жібереді (6 сағатта 1 рет). Сол push осы эфирде кететін болса — сол
--  адамдарды (live_start-тағыдай дәл есептеп) бұл таратудан шығарамыз.
create or replace function public.on_live_session_follow_push()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_name text;
  v_excl uuid[];
begin
  if new.status <> 'live' then return null; end if;
  if tg_op = 'UPDATE' and old.status = 'live' then return null; end if;
  if not public.feature_enabled('store_follow') then return null; end if;
  begin
    select coalesce(nullif(btrim(store_name), ''), 'Qoima') into v_name
      from public.stores where admin_uid = new.admin_uid;
    if not exists (
      select 1 from public.live_sessions
      where admin_uid = new.admin_uid and pushed and started_at > now() - interval '6 hours'
    ) then
      select array_agg(distinct uid) into v_excl from (
        select client_uid as uid from public.favorites where admin_uid = new.admin_uid
        union
        select client_uid as uid from public.orders
          where admin_uid = new.admin_uid and status = 'completed'
      ) t
      where uid is not null
        and not exists (select 1 from public.hidden_stores h
                        where h.admin_uid = new.admin_uid and h.client_uid = t.uid)
        and not exists (select 1 from public.users bu
                        where bu.id = t.uid and coalesce(bu.blocked, false));
      if v_excl is not null and cardinality(v_excl) > 2000 then
        v_excl := v_excl[1:2000];
      end if;
    end if;
    perform public.notify_followers(
      new.admin_uid, 'live', interval '2 hours',
      '🔴 ' || coalesce(v_name, 'Qoima') || ' — в эфире / эфирде',
      new.title,
      jsonb_build_object('type', 'live_started', 'sessionId', new.id,
                         'adminUid', new.admin_uid, 'storeUid', new.admin_uid,
                         'source', 'follow'),
      v_excl);
  exception when others then
    null; -- push қатесі эфирдің басталуын бұзбайды
  end;
  return null;
end;
$$;
revoke execute on function public.on_live_session_follow_push() from public, anon, authenticated;

drop trigger if exists trg_live_session_follow_push on public.live_sessions;
create trigger trg_live_session_follow_push
  after insert or update of status on public.live_sessions
  for each row execute function public.on_live_session_follow_push();

--  Басты бет үшін тірі эфирлер: жазылған дүкендер БІРІНШІ, сосын көрермені
--  көп / жаңасы. Авторизация бар live_sessions_read саясатымен бірдей
--  (live_store_visible): гостьқа бос тізім (грант бар — клиент коды
--  қарапайым болсын, бірақ қатар қайтпайды). Жасырылған дүкендер шықпайды.
--  Бар getLiveSessions (тікелей select) өзгеріссіз қалды.
create or replace function public.live_sessions_for_home(p_limit integer default 30)
returns table (
  id                 uuid,
  admin_uid          uuid,
  host_uid           uuid,
  title              text,
  cover_url          text,
  status             text,
  room_name          text,
  current_product_id uuid,
  viewer_count       integer,
  peak_viewers       integer,
  like_count         integer,
  heartbeat_at       timestamptz,
  started_at         timestamptz,
  ended_at           timestamptz,
  store_name         text,
  store_logo_url     text,
  followed           boolean
)
language sql stable security definer set search_path = public as $$
  select ls.id, ls.admin_uid, ls.host_uid, ls.title, ls.cover_url, ls.status,
         ls.room_name, ls.current_product_id, ls.viewer_count, ls.peak_viewers,
         ls.like_count, ls.heartbeat_at, ls.started_at, ls.ended_at,
         coalesce(s.store_name, ''), coalesce(s.logo_url, ''),
         (fl.client_uid is not null and public.feature_enabled('store_follow'))
  from public.live_sessions ls
  join public.stores s on s.admin_uid = ls.admin_uid
  left join public.store_follows fl
    on fl.store_uid = ls.admin_uid and fl.client_uid = auth.uid()
  where auth.uid() is not null
    and ls.status = 'live'
    and public.feature_enabled('live_shopping')
    and public.live_store_visible(ls.admin_uid)
    and not exists (select 1 from public.hidden_stores h
                    where h.client_uid = auth.uid() and h.admin_uid = ls.admin_uid)
  order by (fl.client_uid is not null and public.feature_enabled('store_follow')) desc,
           ls.viewer_count desc, ls.started_at desc
  limit greatest(1, least(coalesce(p_limit, 30), 100));
$$;
revoke execute on function public.live_sessions_for_home(integer) from public;
grant execute on function public.live_sessions_for_home(integer) to anon, authenticated;

-- ── 6. Сторис ───────────────────────────────────────────────────────────────
create table if not exists public.store_stories (
  id         uuid primary key default gen_random_uuid(),
  store_uid  uuid not null references public.stores(admin_uid) on delete cascade,
  image_url  text not null,
  caption    text not null default '',
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '24 hours',
  constraint store_stories_caption_len check (char_length(caption) <= 200),
  constraint store_stories_url_len     check (char_length(image_url) <= 500)
);
create index if not exists store_stories_store_idx
  on public.store_stories(store_uid, created_at);
create index if not exists store_stories_expires_idx
  on public.store_stories(expires_at);
-- Бір сурет — бір сторис: біреуі өшкенде сурет Cloudinary-ден жойылады,
-- екіншісі «бос» қалмасын.
create unique index if not exists store_stories_image_uniq
  on public.store_stories(image_url);
-- URL бойынша бірегейлік ЖЕТКІЛІКСІЗ: Cloudinary бір суретті версиясыз
-- (…/upload/qoima_stories/x.jpg), басқа версиямен (v1/…) не басқа кеңейтіммен
-- (.png) де береді, ал cloudinary-cleanup өшіргенде тек public_id-ді алады
-- (publicIdFromUrl: v123/ және кеңейтім алынады). Сондықтан бөтен дүкен сол
-- суреттің «синонимін» сторис етіп, өшіріп, біреудің сторисін жойып жібере
-- алатын. Бірегейлік public_id бойынша — publicIdFromUrl-дың дәл көшірмесі.
alter table public.store_stories
  add column if not exists public_id text generated always as (
    regexp_replace(
      regexp_replace(image_url,
        '^https://res\.cloudinary\.com/divynstru/image/upload/(v[0-9]+/)?', ''),
      '\.[^./]*$', '')
  ) stored;
create unique index if not exists store_stories_public_id_uniq
  on public.store_stories(public_id);

alter table public.store_stories enable row level security;
revoke insert, update, delete, truncate on public.store_stories from anon, authenticated;

-- Әдейі публиктік оқу (гость те): сторис — дүкен витринасының ашық контенті,
-- каталог сияқты кірмей де қаралады. Шарт: мерзімі өтпеген, дүкен жарияланған
-- әрі блокта емес, функция суперадминмен қосулы.
drop policy if exists store_stories_read on public.store_stories;
create policy store_stories_read on public.store_stories
  for select to anon, authenticated
  using (expires_at > now()
         and public.feature_enabled('stories')
         and public.store_publicly_visible(store_uid));

-- Сторис қай жолмен өшсе де (RPC, cron, дүкен каскады) суреті Cloudinary
-- өшіру кезегіне түседі — бір ғана жерде, ұмытылмайды.
create or replace function public.on_store_story_deleted()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if coalesce(old.image_url, '') <> '' then
    insert into public.cloudinary_delete_queue(url) values (old.image_url);
  end if;
  return null;
end;
$$;
revoke execute on function public.on_store_story_deleted() from public, anon, authenticated;

drop trigger if exists trg_store_story_deleted on public.store_stories;
create trigger trg_store_story_deleted
  after delete on public.store_stories
  for each row execute function public.on_store_story_deleted();

-- RPC: сторис қосу (иесі не белсенді сатушы). Сурет алдымен Cloudinary-ге
-- qoima_stories қалтасына жүктеледі, мұнда тек URL тексеріледі.
create or replace function public.story_create(p_image_url text, p_caption text default '')
returns public.store_stories
language plpgsql security definer set search_path = public as $$
declare
  v_uid     uuid := auth.uid();
  v_owner   uuid;
  v_ownr    record;
  v_store   record;
  v_url     text := btrim(coalesce(p_image_url, ''));
  v_caption text := btrim(coalesce(p_caption, ''));
  v_cnt     integer;
  v_row     public.store_stories;
begin
  if v_uid is null then raise exception 'not_authorized'; end if;
  if not public.feature_enabled('stories') then raise exception 'feature_disabled'; end if;
  v_owner := public.app_owner_uid();
  if v_owner is null or not public.live_is_staff(v_owner) then
    raise exception 'not_authorized';
  end if;

  -- Иесінің глобал блогы / жазылым «заморозкасы» — live_start-пен бірдей ереже.
  select blocked, subscription_until into v_ownr from public.users where id = v_owner;
  if coalesce(v_ownr.blocked, false) then raise exception 'user_blocked'; end if;
  if v_ownr.subscription_until is not null
     and (now() at time zone 'Asia/Almaty')::date
         - (v_ownr.subscription_until at time zone 'Asia/Almaty')::date > 3 then
    raise exception 'subscription_frozen';
  end if;

  -- Дүкен жолын құлыптаймыз: 10-шек екі құрылғыдан қатар қосқанда да сақталсын.
  select admin_uid, is_published, status into v_store
    from public.stores where admin_uid = v_owner for update;
  if not found or not coalesce(v_store.is_published, false)
     or coalesce(v_store.status, 'active') = 'blocked' then
    raise exception 'store_unavailable';
  end if;

  -- Тек біздің Cloudinary-дің qoima_stories қалтасы: өшкенде сурет жойылатын
  -- болғандықтан тауар/баннер суретін сторис етіп, оны өшіртуге болмайды;
  -- сыртқы URL көрермендердің IP-ін бөтен хостқа ағызбайды.
  if char_length(v_url) > 500
     or v_url !~ '^https://res\.cloudinary\.com/divynstru/image/upload/(v[0-9]+/)?qoima_stories/[A-Za-z0-9_./-]+$'
     or v_url like '%..%' then
    raise exception 'invalid_image_url';
  end if;
  if char_length(v_caption) > 200 then raise exception 'invalid_caption'; end if;

  select count(*) into v_cnt from public.store_stories
    where store_uid = v_owner and expires_at > now();
  if v_cnt >= 10 then raise exception 'stories_limit'; end if;
  -- Сол Cloudinary суреті (public_id — версия/кеңейтімсіз) бұрыннан стористе
  -- тұрса — бас тарту (бағандағы бірегей индекс те ұстайды; мұнда — түсінікті қате).
  if exists (select 1 from public.store_stories
             where image_url = v_url
                or public_id = regexp_replace(
                     regexp_replace(v_url,
                       '^https://res\.cloudinary\.com/divynstru/image/upload/(v[0-9]+/)?', ''),
                     '\.[^./]*$', '')) then
    raise exception 'invalid_image_url';
  end if;

  insert into public.store_stories(store_uid, image_url, caption, created_by)
    values (v_owner, v_url, v_caption, v_uid)
    returning * into v_row;
  return v_row;
end;
$$;
revoke execute on function public.story_create(text, text) from public, anon;
grant execute on function public.story_create(text, text) to authenticated;

-- RPC: сторисді өшіру (сол дүкеннің белсенді қызметкері не суперадмин).
-- Жалауша өшік болса да рұқсат — тазалау әрқашан мүмкін болсын.
-- Жоқ сторис → үнсіз (екі рет басу қауіпсіз).
create or replace function public.story_delete(p_id uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_store uuid;
begin
  if auth.uid() is null then raise exception 'not_authorized'; end if;
  select store_uid into v_store from public.store_stories where id = p_id for update;
  if not found then return; end if;
  if not (public.live_is_staff(v_store) or public.is_superadmin()) then
    raise exception 'not_authorized';
  end if;
  delete from public.store_stories where id = p_id; -- сурет триггермен кезекке
end;
$$;
revoke execute on function public.story_delete(uuid) from public, anon;
grant execute on function public.story_delete(uuid) to authenticated;

-- RPC: бір дүкеннің белсенді стористері, ЕСКІСІ алдымен (көру реті).
-- Жұртқа — RLS-пен бірдей шарт; дүкен қызметкері мен суперадминге — дүкен
-- жабық не жалауша өшік болса да (өз сторисін басқарып, өшіре алсын).
create or replace function public.stories_for_store(p_store uuid)
returns setof public.store_stories
language sql stable security definer set search_path = public as $$
  select st.* from public.store_stories st
  where st.store_uid = p_store
    and st.expires_at > now()
    and (
      (public.feature_enabled('stories') and public.store_publicly_visible(p_store))
      or (auth.uid() is not null
          and (public.live_is_staff(p_store) or public.is_superadmin()))
    )
  order by st.created_at asc;
$$;
revoke execute on function public.stories_for_store(uuid) from public;
grant execute on function public.stories_for_store(uuid) to anon, authenticated;

-- RPC: басты беттегі сторис жолағы — дүкен бойынша топталған.
-- p_stores = null → шақырушының жазылған дүкендері (гостьқа бос).
-- Ең көбі 200 дүкен; жасырылған дүкендер шықпайды. Жаңасы алдымен.
create or replace function public.stories_for_stores(p_stores uuid[] default null)
returns table (
  store_uid   uuid,
  store_name  text,
  logo_url    text,
  story_count integer,
  latest_at   timestamptz,
  oldest_at   timestamptz
)
language sql stable security definer set search_path = public as $$
  with wanted as (
    select w.uid from (
      select distinct u as uid from unnest(p_stores) as u
      where p_stores is not null and u is not null
      union
      select f.store_uid from public.store_follows f
      where p_stores is null and auth.uid() is not null and f.client_uid = auth.uid()
    ) w
    limit 200
  )
  select st.store_uid,
         coalesce(max(s.store_name), ''), coalesce(max(s.logo_url), ''),
         count(*)::integer, max(st.created_at), min(st.created_at)
  from public.store_stories st
  join wanted w on w.uid = st.store_uid
  join public.stores s on s.admin_uid = st.store_uid
  where st.expires_at > now()
    and public.feature_enabled('stories')
    and public.store_publicly_visible(st.store_uid)
    and not exists (select 1 from public.hidden_stores h
                    where h.client_uid = auth.uid() and h.admin_uid = st.store_uid)
  group by st.store_uid
  order by max(st.created_at) desc;
$$;
revoke execute on function public.stories_for_stores(uuid[]) from public;
grant execute on function public.stories_for_stores(uuid[]) to anon, authenticated;

-- Cron (сағат сайын): мерзімі өткен стористерді өшіреді — суреттері
-- on_store_story_deleted триггерімен бір транзакцияда кезекке түседі.
create or replace function public.sweep_expired_stories()
returns integer
language plpgsql security definer set search_path = public as $$
declare
  v_cnt integer;
begin
  delete from public.store_stories where expires_at <= now();
  get diagnostics v_cnt = row_count;
  return v_cnt;
end;
$$;
revoke execute on function public.sweep_expired_stories() from public, anon, authenticated;

select cron.unschedule('stories-expired-sweep')
  where exists (select 1 from cron.job where jobname = 'stories-expired-sweep');
select cron.schedule(
  'stories-expired-sweep',
  '7 * * * *',
  $$select public.sweep_expired_stories()$$
);
