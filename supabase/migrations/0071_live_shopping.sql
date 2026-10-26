-- ════════════════════════════════════════════════════════════════════════════
--  0071 · Live shopping (тікелей эфирден сауда)
-- ────────────────────────────────────────────────────────────────────────────
--  НЕ ҮШІН: дүкен иесі (не оның сатушысы) телефон камерасынан эфирге шығады,
--  сатып алушылар нақты уақытта көреді, чатта жазады, «бекітілген» тауарды
--  екі басумен себетке салады. Видео — LiveKit (edge fn `livekit-token`
--  тек JWT береді), ал мына кестелер — эфирдің «күйі»: кім эфирде, қай тауар
--  бекітілген, чат, лайк/себет санағыштары.
--
--  ҚАУІПСІЗДІК (CLAUDE.md / 0065 ережелері):
--   • Клиенттің кестелерге ТІКЕЛЕЙ жазуы мүлде ЖОҚ (insert/update/delete
--     саясаты жоқ + грант алынды) — бәрі SECURITY DEFINER RPC арқылы, әрқайсысы
--     auth.uid()/app_owner_uid() тексереді, соңында `revoke … from public`.
--   • Оқу: тек кірген қолданушыға, дүкен жарияланған әрі блокталмаған болса;
--     немесе дүкеннің өз қызметкерлеріне / superadmin-ге. `using (true)` жоқ.
--   • Спамнан қорғау: чат 1 хабар / 2 сек, лайк 10 / 10 сек, себет 5 / мин —
--     live_rate_limits кестесінде, `for update` құлпымен.
--   • Follower push: favorites ∪ completed orders (0043 үлгісі), дүкенге
--     6 сағатта 1 рет қана (эфир бәрібір басталады, тек push өткізіледі).
--   • СУПЕРАДМИН ӨШІРГІШІ (0067b): live_start / live_send_message / live_like /
--     live_track_cart `feature_enabled('live_shopping')` тексереді, өшік болса
--     'feature_disabled'. live_end / live_heartbeat / live_pin_product ашық
--     қалады (қызметкер ашық тұрған эфирін таза жаба алсын), ал cron өшік
--     кезде тірі эфирлердің бәрін жабады.
--   • Модерация: live_delete_message / live_mute_user (тек қызметкер),
--     live_mutes кестесі; мұқаба тек дүкен тауарларының суреті; тауар тек
--     сөредегі (жасырылмаған, «В наличии»); like клиентте жиналып жіберіледі.
--   • Хост желіден түсіп қалса: pg_cron минут сайын heartbeat-і 2 минуттан
--     ескі эфирлерді жабады.
-- ════════════════════════════════════════════════════════════════════════════

-- ── 1. Кестелер ─────────────────────────────────────────────────────────────
create table if not exists public.live_sessions (
  id                 uuid primary key default gen_random_uuid(),
  -- Дүкен кілті = stores.admin_uid (сатушы эфирге шықса да — иесінің uid-і).
  admin_uid          uuid not null references public.stores(admin_uid) on delete cascade,
  -- Нақты кім эфирде (иесі не сатушы).
  host_uid           uuid not null references auth.users(id) on delete cascade,
  title              text not null,
  cover_url          text,
  status             text not null default 'live',
  room_name          text not null unique,
  current_product_id uuid references public.products(id) on delete set null,
  viewer_count       integer not null default 0,
  peak_viewers       integer not null default 0,
  like_count         integer not null default 0,
  -- Осы эфир кезінде follower-ларға push кетті ме (6 сағаттық шектеу үшін).
  pushed             boolean not null default false,
  heartbeat_at       timestamptz not null default now(),
  started_at         timestamptz not null default now(),
  ended_at           timestamptz,
  constraint live_sessions_status_chk check (status in ('live','ended')),
  constraint live_sessions_title_len  check (char_length(title) between 1 and 80)
);
create index if not exists live_sessions_live_idx
  on public.live_sessions(started_at desc) where status = 'live';
create index if not exists live_sessions_admin_idx
  on public.live_sessions(admin_uid, started_at desc);
-- Бір дүкенде бір мезетте тек БІР тірі эфир (екі құрылғыдан қатар бастаса да).
create unique index if not exists live_sessions_one_live_per_store
  on public.live_sessions(admin_uid) where status = 'live';

create table if not exists public.live_session_products (
  session_id        uuid not null references public.live_sessions(id) on delete cascade,
  product_id        uuid not null references public.products(id) on delete cascade,
  position          integer not null default 0,
  add_to_cart_count integer not null default 0,
  created_at        timestamptz not null default now(),
  primary key (session_id, product_id)
);

create table if not exists public.live_messages (
  id          bigint generated always as identity primary key,
  session_id  uuid not null references public.live_sessions(id) on delete cascade,
  user_uid    uuid references auth.users(id) on delete set null,
  -- Тек АТЫ (тегі/телефоны емес) — чат ашық, жеке дерек жарияланбасын.
  user_name   text not null default '',
  body        text not null,
  kind        text not null default 'chat',
  -- Дүкен қызметкерінің хабары (UI-де бөлек белгіленеді).
  is_host     boolean not null default false,
  created_at  timestamptz not null default now(),
  constraint live_messages_body_len check (char_length(body) between 1 and 300),
  constraint live_messages_kind_chk check (kind in ('chat','system','cart','like'))
);
create index if not exists live_messages_session_idx
  on public.live_messages(session_id, id desc);

-- Rate limit есептегіші. RLS қосулы, саясат ЖОҚ → клиентке мүлде жабық,
-- тек төмендегі definer RPC-лер жазады.
create table if not exists public.live_rate_limits (
  session_id   uuid not null references public.live_sessions(id) on delete cascade,
  user_uid     uuid not null,
  kind         text not null,
  window_start timestamptz not null default now(),
  hits         integer not null default 0,
  primary key (session_id, user_uid, kind)
);

-- Чаттан бұғатталғандар (хост модерациясы). RLS қосулы, саясат ЖОҚ →
-- клиентке жабық; жазу тек live_mute_user арқылы, оқу live_send_message ішінде.
create table if not exists public.live_mutes (
  session_id uuid not null references public.live_sessions(id) on delete cascade,
  user_uid   uuid not null,
  created_at timestamptz not null default now(),
  primary key (session_id, user_uid)
);

-- ── 2. RLS ──────────────────────────────────────────────────────────────────
alter table public.live_sessions         enable row level security;
alter table public.live_session_products enable row level security;
alter table public.live_messages         enable row level security;
alter table public.live_rate_limits      enable row level security;
alter table public.live_mutes            enable row level security;

-- Тікелей жазу гранты да алынады (саясат жоқ болса да — қосымша қабат).
revoke insert, update, delete, truncate on public.live_sessions         from anon, authenticated;
revoke insert, update, delete, truncate on public.live_session_products from anon, authenticated;
revoke insert, update, delete, truncate on public.live_messages         from anon, authenticated;
revoke all on public.live_rate_limits from anon, authenticated;
revoke all on public.live_mutes       from anon, authenticated;

-- Дүкеннің эфирі көрінетін бе: өз қызметкері / superadmin — әрқашан;
-- басқа кірген қолданушы — дүкен жарияланған, блокталмаған, иесі глобал
-- блокта емес болса. Гостьқа (auth.uid() null) — ешқашан.
create or replace function public.live_store_visible(p_admin uuid)
returns boolean language sql stable security definer set search_path = public as $$
  -- coalesce: app_owner_uid() сатып алушы үшін NULL — NULL үштік логикасы
  -- «not live_store_visible()» тексерісін өткізіп жібермесін.
  select coalesce(auth.uid() is not null and (
    coalesce(p_admin = public.app_owner_uid(), false)
    or public.is_superadmin()
    or exists (
      select 1 from public.stores s
      where s.admin_uid = p_admin
        and s.is_published = true
        and coalesce(s.status, 'active') <> 'blocked'
        and not exists (select 1 from public.users u
                        where u.id = p_admin and coalesce(u.blocked, false))
    )
  ), false);
$$;
revoke execute on function public.live_store_visible(uuid) from public, anon;
grant execute on function public.live_store_visible(uuid) to authenticated;

create or replace function public.live_session_visible(p_session uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select auth.uid() is not null and exists (
    select 1 from public.live_sessions ls
    where ls.id = p_session and public.live_store_visible(ls.admin_uid)
  );
$$;
revoke execute on function public.live_session_visible(uuid) from public, anon;
grant execute on function public.live_session_visible(uuid) to authenticated;

drop policy if exists live_sessions_read on public.live_sessions;
create policy live_sessions_read on public.live_sessions
  for select to authenticated using (public.live_store_visible(admin_uid));

drop policy if exists live_session_products_read on public.live_session_products;
create policy live_session_products_read on public.live_session_products
  for select to authenticated using (public.live_session_visible(session_id));

drop policy if exists live_messages_read on public.live_messages;
create policy live_messages_read on public.live_messages
  for select to authenticated using (public.live_session_visible(session_id));

-- ── 3. Ішкі көмекшілер (клиентке жабық) ─────────────────────────────────────

-- Rate limit: терезе ішінде p_limit-тен асса false. Тек definer RPC-лерден
-- шақырылады (олар postgres атынан орындалады) — сондықтан invoker, грант жоқ.
create or replace function public.live_rate_hit(
  p_session uuid, p_kind text, p_limit integer, p_window interval)
returns boolean language plpgsql set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_row public.live_rate_limits;
begin
  if v_uid is null then return false; end if;
  insert into public.live_rate_limits(session_id, user_uid, kind, window_start, hits)
    values (p_session, v_uid, p_kind, now(), 0)
    on conflict (session_id, user_uid, kind) do nothing;
  select * into v_row from public.live_rate_limits
    where session_id = p_session and user_uid = v_uid and kind = p_kind
    for update;
  if v_row.window_start < now() - p_window then
    update public.live_rate_limits set window_start = now(), hits = 1
      where session_id = p_session and user_uid = v_uid and kind = p_kind;
    return true;
  end if;
  if v_row.hits >= p_limit then return false; end if;
  update public.live_rate_limits set hits = hits + 1
    where session_id = p_session and user_uid = v_uid and kind = p_kind;
  return true;
end;
$$;
revoke execute on function public.live_rate_hit(uuid, text, integer, interval) from public, anon, authenticated;

-- Қолданушының чатта көрінетін АТЫ (тек бірінші сөз).
create or replace function public.live_first_name(p_uid uuid)
returns text language sql stable set search_path = public as $$
  select coalesce(split_part(btrim(coalesce(
    (select nullif(btrim(c.name), '') from public.clients c where c.id = p_uid),
    (select nullif(btrim(u.name), '') from public.users u where u.id = p_uid),
    '')), ' ', 1), '');
$$;
revoke execute on function public.live_first_name(uuid) from public, anon, authenticated;

-- Шақырушы осы дүкеннің белсенді қызметкері ме (admin/seller, блоксыз).
create or replace function public.live_is_staff(p_admin uuid)
returns boolean language sql stable set search_path = public as $$
  select exists (
    select 1 from public.users u
    where u.id = auth.uid()
      and u.role in ('admin','seller')
      and not coalesce(u.blocked, false)
      and coalesce(u.owner_id, u.id) = p_admin
      and (u.role = 'admin' or coalesce(u.join_status, '') = 'active')
  );
$$;
revoke execute on function public.live_is_staff(uuid) from public, anon, authenticated;

-- Дәл сол тексеріс, бірақ ӘРБІР қолданушы үшін (мақсатты қолданушы қызметкер ме).
create or replace function public.live_is_staff_uid(p_uid uuid, p_admin uuid)
returns boolean language sql stable set search_path = public as $$
  select exists (
    select 1 from public.users u
    where u.id = p_uid
      and u.role in ('admin','seller')
      and coalesce(u.owner_id, u.id) = p_admin
  );
$$;
revoke execute on function public.live_is_staff_uid(uuid, uuid) from public, anon, authenticated;

-- ── 4. RPC: эфирді бастау ───────────────────────────────────────────────────
create or replace function public.live_start(
  p_title text, p_product_ids uuid[], p_cover_url text default null)
returns public.live_sessions
language plpgsql security definer set search_path = public as $$
declare
  v_uid    uuid := auth.uid();
  v_owner  uuid;
  v_ownr   record;
  v_store  record;
  v_ids    uuid[] := coalesce(p_product_ids, '{}'::uuid[]);
  v_valid  integer;
  v_title  text := left(btrim(coalesce(p_title, '')), 80);
  v_cover  text := nullif(btrim(coalesce(p_cover_url, '')), '');
  v_id     uuid := gen_random_uuid();
  v_sess   public.live_sessions;
  v_uids   uuid[];
begin
  if v_uid is null then raise exception 'not_authorized'; end if;
  if not public.feature_enabled('live_shopping') then raise exception 'feature_disabled'; end if;
  v_owner := public.app_owner_uid();
  if v_owner is null or not public.live_is_staff(v_owner) then
    raise exception 'not_authorized';
  end if;

  -- Иесінің глобал блогы / жазылым «заморозкасы» (мерзімі 3 күннен асса —
  -- Dart AppUser.subFrozen-мен бірдей ереже, Алматы күнімен).
  select blocked, subscription_until into v_ownr from public.users where id = v_owner;
  if coalesce(v_ownr.blocked, false) then raise exception 'user_blocked'; end if;
  if v_ownr.subscription_until is not null
     and (now() at time zone 'Asia/Almaty')::date
         - (v_ownr.subscription_until at time zone 'Asia/Almaty')::date > 3 then
    raise exception 'subscription_frozen';
  end if;

  -- Дүкен жолын құлыптаймыз: екі құрылғыдан қатар «бастау» сериялансын.
  select admin_uid, store_name, is_published, status into v_store
    from public.stores where admin_uid = v_owner for update;
  if not found then raise exception 'store_not_found'; end if;
  if not coalesce(v_store.is_published, false) then raise exception 'store_not_published'; end if;
  if coalesce(v_store.status, 'active') = 'blocked' then raise exception 'store_blocked'; end if;

  -- Тауарлар: дубльсіз, ≤50, бәрі ОСЫ дүкендікі болуы шарт.
  select coalesce(array_agg(id order by ord), '{}'::uuid[]) into v_ids from (
    select distinct on (t.id) t.id, t.ord
    from unnest(v_ids) with ordinality t(id, ord)
    where t.id is not null
    order by t.id, t.ord
  ) d;
  if cardinality(v_ids) > 50 then raise exception 'too_many_products'; end if;
  -- Тек сөредегі (жасырылмаған, қоймада бар) тауарлар: RPC тікелей
  -- шақырылса да, Dart-тағы getHostProducts сүзгісін айналып өтпейді.
  select count(*) into v_valid from public.products p
    where p.id = any(v_ids) and p.owner_uid = v_owner
      and not coalesce(p.storefront_hidden, false)
      and p.status = 'В наличии';
  if v_valid <> cardinality(v_ids) then raise exception 'product_not_in_store'; end if;

  if v_title = '' then v_title := left(coalesce(nullif(btrim(v_store.store_name), ''), 'Live'), 80); end if;
  -- Мұқаба — тек осы дүкен тауарларының өз суреті болуы мүмкін: еркін URL
  -- көрермендердің IP-ін сырттағы хостқа ағызып жібермесін (tracking).
  if v_cover is not null and (
       char_length(v_cover) > 500
       or not exists (select 1 from public.products p
                      where p.owner_uid = v_owner and v_cover = any(p.images))
     ) then
    v_cover := null;
  end if;

  -- Дүкеннің басқа (ілініп қалған) эфирлерін жабамыз.
  update public.live_sessions set status = 'ended', ended_at = now()
    where admin_uid = v_owner and status = 'live';

  insert into public.live_sessions(id, admin_uid, host_uid, title, cover_url, room_name)
    values (v_id, v_owner, v_uid, v_title, v_cover, 'live_' || v_id::text)
    returning * into v_sess;

  insert into public.live_session_products(session_id, product_id, position)
    select v_id, t.id, t.ord::integer
    from unnest(v_ids) with ordinality t(id, ord);

  -- Жүйелік хабар: body — КОД, Dart оны tr() арқылы аударады.
  insert into public.live_messages(session_id, user_uid, user_name, body, kind, is_host)
    values (v_id, null, '', 'live_started', 'system', true);

  -- Follower push: 6 сағатта 1 рет (эфир бәрібір басталады).
  if not exists (
    select 1 from public.live_sessions
    where admin_uid = v_owner and pushed and started_at > now() - interval '6 hours'
  ) then
    select array_agg(distinct uid) into v_uids from (
      select client_uid as uid from public.favorites where admin_uid = v_owner
      union
      select client_uid as uid from public.orders
        where admin_uid = v_owner and status = 'completed'
    ) t
    where uid is not null
      -- дүкенді жасырғандар мен блокталғандарға push жіберілмейді
      and not exists (select 1 from public.hidden_stores h
                      where h.admin_uid = v_owner and h.client_uid = t.uid)
      and not exists (select 1 from public.users bu
                      where bu.id = t.uid and coalesce(bu.blocked, false));
    -- Жауап жылдамдығы үшін аудитория шегі (push синхронды орындалады).
    if v_uids is not null and cardinality(v_uids) > 2000 then
      v_uids := v_uids[1:2000];
    end if;
    if v_uids is not null then
      perform public.notify_push(
        v_uids,
        '🔴 ' || coalesce(v_store.store_name, 'Qoima') || ' — в эфире / эфирде',
        v_title,
        jsonb_build_object('type', 'live_started', 'sessionId', v_id, 'adminUid', v_owner)
      );
      update public.live_sessions set pushed = true where id = v_id returning * into v_sess;
    end if;
  end if;

  return v_sess;
end;
$$;
revoke execute on function public.live_start(text, uuid[], text) from public, anon;
grant execute on function public.live_start(text, uuid[], text) to authenticated;

-- ── 5. RPC: эфирді аяқтау ───────────────────────────────────────────────────
create or replace function public.live_end(p_session uuid)
returns public.live_sessions
language plpgsql security definer set search_path = public as $$
declare
  v_sess public.live_sessions;
begin
  if auth.uid() is null then raise exception 'not_authorized'; end if;
  select * into v_sess from public.live_sessions where id = p_session for update;
  if not found then raise exception 'live_not_found'; end if;
  -- Аяқтау — блокталған қызметкерге де рұқсат (эфирді ілулі қалдырмау үшін).
  -- coalesce: сатып алушыда app_owner_uid() NULL → `not NULL` тексерісті өткізіп жібереді.
  if not (coalesce(v_sess.admin_uid = public.app_owner_uid(), false) or public.is_superadmin()) then
    raise exception 'not_authorized';
  end if;
  if v_sess.status = 'live' then
    update public.live_sessions set status = 'ended', ended_at = now()
      where id = p_session returning * into v_sess;
    insert into public.live_messages(session_id, user_uid, user_name, body, kind, is_host)
      values (p_session, null, '', 'live_ended', 'system', true);
  end if;
  return v_sess;
end;
$$;
revoke execute on function public.live_end(uuid) from public, anon;
grant execute on function public.live_end(uuid) to authenticated;

-- ── 6. RPC: тауарды бекіту / алып тастау (null) ─────────────────────────────
create or replace function public.live_pin_product(p_session uuid, p_product uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_sess public.live_sessions;
  v_pos  integer;
  v_cnt  integer;
begin
  if auth.uid() is null then raise exception 'not_authorized'; end if;
  select * into v_sess from public.live_sessions where id = p_session for update;
  if not found then raise exception 'live_not_found'; end if;
  if not public.live_is_staff(v_sess.admin_uid) then raise exception 'not_authorized'; end if;
  if v_sess.status <> 'live' then raise exception 'live_ended'; end if;

  if p_product is not null then
    if not exists (select 1 from public.products
                   where id = p_product and owner_uid = v_sess.admin_uid
                     and not coalesce(storefront_hidden, false)
                     and status = 'В наличии') then
      raise exception 'product_not_in_store';
    end if;
    -- Тізімде жоқ болса — эфир барысында қосамыз (≤50).
    if not exists (select 1 from public.live_session_products
                   where session_id = p_session and product_id = p_product) then
      select count(*), coalesce(max(position), 0) + 1 into v_cnt, v_pos
        from public.live_session_products where session_id = p_session;
      if v_cnt >= 50 then raise exception 'too_many_products'; end if;
      insert into public.live_session_products(session_id, product_id, position)
        values (p_session, p_product, v_pos)
        on conflict (session_id, product_id) do nothing;
    end if;
  end if;

  update public.live_sessions set current_product_id = p_product where id = p_session;
end;
$$;
revoke execute on function public.live_pin_product(uuid, uuid) from public, anon;
grant execute on function public.live_pin_product(uuid, uuid) to authenticated;

-- ── 7. RPC: хост heartbeat (20 сек сайын) ───────────────────────────────────
--  Қайтарады: эфирдің статусы ('live' | 'ended') — cron жауып қойса, хост біледі.
create or replace function public.live_heartbeat(p_session uuid, p_viewers integer)
returns text
language plpgsql security definer set search_path = public as $$
declare
  v_sess public.live_sessions;
  v_n    integer := greatest(0, least(coalesce(p_viewers, 0), 1000000));
begin
  if auth.uid() is null then raise exception 'not_authorized'; end if;
  select * into v_sess from public.live_sessions where id = p_session for update;
  if not found then raise exception 'live_not_found'; end if;
  if not public.live_is_staff(v_sess.admin_uid) then raise exception 'not_authorized'; end if;
  if v_sess.status <> 'live' then return v_sess.status; end if;
  update public.live_sessions
    set heartbeat_at = now(),
        viewer_count = v_n,
        peak_viewers = greatest(peak_viewers, v_n)
    where id = p_session;
  return 'live';
end;
$$;
revoke execute on function public.live_heartbeat(uuid, integer) from public, anon;
grant execute on function public.live_heartbeat(uuid, integer) to authenticated;

-- ── 8. RPC: чат хабары ──────────────────────────────────────────────────────
create or replace function public.live_send_message(p_session uuid, p_body text)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_uid   uuid := auth.uid();
  v_body  text := btrim(coalesce(p_body, ''));
  v_admin uuid;
  v_stat  text;
begin
  if v_uid is null then raise exception 'not_authorized'; end if;
  if not public.feature_enabled('live_shopping') then raise exception 'feature_disabled'; end if;
  if char_length(v_body) < 1 or char_length(v_body) > 300 then
    raise exception 'invalid_message';
  end if;
  select admin_uid, status into v_admin, v_stat from public.live_sessions where id = p_session;
  if v_admin is null or not coalesce(public.live_store_visible(v_admin), false) then
    raise exception 'live_not_found';
  end if;
  if v_stat <> 'live' then raise exception 'live_ended'; end if;
  if exists (select 1 from public.live_mutes
             where session_id = p_session and user_uid = v_uid) then
    raise exception 'live_muted';
  end if;
  if not public.live_rate_hit(p_session, 'chat', 1, interval '2 seconds') then
    raise exception 'live_rate_limited';
  end if;
  insert into public.live_messages(session_id, user_uid, user_name, body, kind, is_host)
    values (p_session, v_uid, left(public.live_first_name(v_uid), 40), v_body, 'chat',
            public.live_is_staff(v_admin));
end;
$$;
revoke execute on function public.live_send_message(uuid, text) from public, anon;
grant execute on function public.live_send_message(uuid, text) to authenticated;

-- ── 9. RPC: лайк (арзан — тек санағыш; шектеуден асса үнсіз false) ──────────
create or replace function public.live_like(p_session uuid, p_count integer default 1)
returns boolean
language plpgsql security definer set search_path = public as $$
declare
  v_admin uuid;
  v_stat  text;
begin
  if auth.uid() is null then raise exception 'not_authorized'; end if;
  if not public.feature_enabled('live_shopping') then raise exception 'feature_disabled'; end if;
  select admin_uid, status into v_admin, v_stat from public.live_sessions where id = p_session;
  if v_admin is null or not coalesce(public.live_store_visible(v_admin), false) then
    raise exception 'live_not_found';
  end if;
  if v_stat <> 'live' then return false; end if;
  if not public.live_rate_hit(p_session, 'like', 10, interval '10 seconds') then
    return false;
  end if;
  -- Клиент лайктарды 2-3 с сайын бір шақыруға жинайды (p_count) — бір жолға
  -- түсетін UPDATE және realtime оқиғалар саны азаяды.
  update public.live_sessions
    set like_count = like_count + least(greatest(coalesce(p_count, 1), 1), 20)
    where id = p_session;
  return true;
end;
$$;
revoke execute on function public.live_like(uuid, integer) from public, anon;
grant execute on function public.live_like(uuid, integer) to authenticated;

-- ── 10. RPC: «себетке қосты» сигналы (санағыш + чаттағы жүйелік жол) ────────
--  Себет клиенттің жергілікті күйі (CartProvider) — қойма/ақшаға ТИМЕЙДІ,
--  бұл тек статистика әрі әлеуметтік дәлел. Шектеуден асса үнсіз false.
create or replace function public.live_track_cart(p_session uuid, p_product uuid)
returns boolean
language plpgsql security definer set search_path = public as $$
declare
  v_uid   uuid := auth.uid();
  v_admin uuid;
  v_stat  text;
  v_name  text;
begin
  if v_uid is null then raise exception 'not_authorized'; end if;
  if not public.feature_enabled('live_shopping') then raise exception 'feature_disabled'; end if;
  select admin_uid, status into v_admin, v_stat from public.live_sessions where id = p_session;
  if v_admin is null or not coalesce(public.live_store_visible(v_admin), false) then
    raise exception 'live_not_found';
  end if;
  if v_stat <> 'live' then return false; end if;
  if not exists (select 1 from public.live_session_products
                 where session_id = p_session and product_id = p_product) then
    raise exception 'product_not_in_live';
  end if;
  if not public.live_rate_hit(p_session, 'cart', 5, interval '1 minute') then
    return false;
  end if;
  -- Бір қолданушы бір тауарды сағатына 1 рет санайды — қайталап жіберіп
  -- санауышты/чатты бұрмалай алмайды (себет жергілікті, сервер тексермейді,
  -- сондықтан сан шамамен ғана).
  if not public.live_rate_hit(p_session, 'cart:' || p_product::text, 1, interval '1 hour') then
    return false;
  end if;
  update public.live_session_products set add_to_cart_count = add_to_cart_count + 1
    where session_id = p_session and product_id = p_product;
  select left(coalesce(nullif(btrim(name), ''), '—'), 120) into v_name
    from public.products where id = p_product;
  -- body = тауар аты, user_name = сатып алушының аты; мәтінді Dart құрастырады.
  insert into public.live_messages(session_id, user_uid, user_name, body, kind, is_host)
    values (p_session, v_uid, left(public.live_first_name(v_uid), 40),
            coalesce(v_name, '—'), 'cart', false);
  return true;
end;
$$;
revoke execute on function public.live_track_cart(uuid, uuid) from public, anon;
grant execute on function public.live_track_cart(uuid, uuid) to authenticated;

-- ── 10b. Чат модерациясы (UGC: App Store 1.2 / Play) ────────────────────────
--  Хабарға шағым — клиенттегі бар content_reports ағыны (showReportSheet);
--  бұл жерде хосттың өз құралдары: хабарды жою және қолданушыны бұғаттау.
create or replace function public.live_delete_message(p_session uuid, p_message bigint)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_admin uuid;
begin
  if auth.uid() is null then raise exception 'not_authorized'; end if;
  select admin_uid into v_admin from public.live_sessions where id = p_session;
  if v_admin is null then raise exception 'live_not_found'; end if;
  if not public.live_is_staff(v_admin) then raise exception 'not_authorized'; end if;
  delete from public.live_messages
    where id = p_message and session_id = p_session and kind in ('chat', 'cart');
end;
$$;
revoke execute on function public.live_delete_message(uuid, bigint) from public, anon;
grant execute on function public.live_delete_message(uuid, bigint) to authenticated;

create or replace function public.live_mute_user(p_session uuid, p_user uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_admin uuid;
begin
  if auth.uid() is null then raise exception 'not_authorized'; end if;
  select admin_uid into v_admin from public.live_sessions where id = p_session;
  if v_admin is null then raise exception 'live_not_found'; end if;
  if not public.live_is_staff(v_admin) then raise exception 'not_authorized'; end if;
  -- Қызметкерді (өзін де) бұғаттауға болмайды.
  if p_user is null or p_user = auth.uid() or public.live_is_staff_uid(p_user, v_admin) then
    raise exception 'not_authorized';
  end if;
  insert into public.live_mutes(session_id, user_uid) values (p_session, p_user)
    on conflict (session_id, user_uid) do nothing;
  delete from public.live_messages
    where session_id = p_session and user_uid = p_user and kind in ('chat', 'cart');
end;
$$;
revoke execute on function public.live_mute_user(uuid, uuid) from public, anon;
grant execute on function public.live_mute_user(uuid, uuid) to authenticated;

-- ── 11. pg_cron: ілініп қалған эфирлерді жабу (минут сайын) ─────────────────
create or replace function public.sweep_stale_live_sessions() returns void
language plpgsql security definer set search_path = public as $$
begin
  with ended as (
    update public.live_sessions
      set status = 'ended', ended_at = now()
      where status = 'live'
        and (heartbeat_at < now() - interval '2 minutes'
             -- суперадмин функцияны өшірсе — тірі эфирлер де жабылады
             or not public.feature_enabled('live_shopping'))
      returning id
  )
  insert into public.live_messages(session_id, user_uid, user_name, body, kind, is_host)
    select id, null, '', 'live_ended', 'system', true from ended;
  -- Ескі rate-limit жолдары керек емес.
  delete from public.live_rate_limits where window_start < now() - interval '1 day';
end;
$$;
revoke all on function public.sweep_stale_live_sessions() from public, anon, authenticated;

select cron.unschedule('live-stale-sweep')
  where exists (select 1 from cron.job where jobname = 'live-stale-sweep');
select cron.schedule(
  'live-stale-sweep',
  '* * * * *',
  $$select public.sweep_stale_live_sessions()$$
);

-- ── 12. Realtime ────────────────────────────────────────────────────────────
do $$
declare t text;
begin
  foreach t in array array['live_sessions','live_messages','live_session_products'] loop
    if not exists (select 1 from pg_publication_tables
                   where pubname = 'supabase_realtime' and schemaname = 'public'
                     and tablename = t) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;
-- Тауар жолы өшкенде (DELETE) session_id сүзгісі жұмыс істеуі үшін.
alter table public.live_session_products replica identity full;
-- Хабар жойылғанда (DELETE) session_id сүзгісі клиентке жетуі үшін.
alter table public.live_messages replica identity full;
