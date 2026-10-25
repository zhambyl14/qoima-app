-- ════════════════════════════════════════════════════════════════════════════
--  0072 · Қолдау чаты (пайдаланушы ↔ платформа модераторы / superadmin)
-- ────────────────────────────────────────────────────────────────────────────
--  НЕГЕ КЕРЕК: клиент, дүкен иесі, сатушы, курьер — бәрі көмек сұрайтын бір
--  арна керек. Бұрын тек профильдегі WhatsApp/Telegram сілтемесі болатын —
--  тарих сақталмайды, кім жазғаны белгісіз, модератор телефонға байланады.
--
--  Модель:
--    · support_threads — әр пайдаланушыға БІР ғана тред (user_uid unique).
--      Рөл/аты/телефоны СЕРВЕРДЕ анықталады (users/clients кестесінен) —
--      клиент жіберген мәнге сенбейміз (CLAUDE.md: метадерек сенімсіз).
--    · support_messages — хабарламалар (is_staff = модератор жазды ма).
--
--  Қауіпсіздік (0065 ережелері):
--    · RLS select: тред иесі немесе is_superadmin(). using(true) ЖОҚ.
--    · Тікелей INSERT/UPDATE/DELETE саясаты ЖОҚ (әрі грант алынады) — бар
--      жазу тек SECURITY DEFINER RPC арқылы: support_send / support_reply /
--      support_mark_read / support_set_status. Санауыштар (unread_*),
--      статус, рөл — клиенттен ӨЗГЕРТІЛМЕЙДІ.
--    · Әр функцияда авторизация + `revoke … from public` +
--      `grant … to authenticated`.
--    · support_send: секундына 1 хабарлама шегі (тред жолы `for update`
--      құлпымен — қатар келген екі сұрау шекті айналып өте алмайды).
--
--  Push түрлері (Dart push_navigation.dart-та өңделеді):
--    · support_message {threadId} → барлық superadmin-ге
--    · support_reply   {threadId} → тред иесіне
--
--  Қосымша: app_settings.qa_public ('false' әдепкі — тауар туралы сұрақ
--  клиент пен дүкен арасында ғана; 'true' — жария). Superadmin
--  «Платформа баптаулары» экранында ауыстырады.
--
--  Идемпотентті: қайта іске қосуға болады.
-- ════════════════════════════════════════════════════════════════════════════

-- ── 1. Кестелер ──────────────────────────────────────────────────────────────

create table if not exists public.support_threads (
  id                   uuid primary key default gen_random_uuid(),
  -- Бір пайдаланушыға бір тред (аккаунт өшсе — тред те өшеді).
  user_uid             uuid not null unique references auth.users(id) on delete cascade,
  user_role            text not null,              -- client|admin|seller|courier
  user_name            text not null default '',
  user_phone           text not null default '',
  store_name           text not null default '',   -- admin/seller үшін (модераторға ыңғайлы)
  status               text not null default 'open'
                         check (status in ('open', 'closed')),
  last_message_at      timestamptz,
  last_message_preview text not null default '',
  unread_for_staff     int not null default 0,
  unread_for_user      int not null default 0,
  created_at           timestamptz not null default now()
);

create index if not exists support_threads_last_idx
  on public.support_threads (last_message_at desc nulls last);

create table if not exists public.support_messages (
  id          bigint generated always as identity primary key,
  thread_id   uuid not null references public.support_threads(id) on delete cascade,
  sender_uid  uuid,
  is_staff    boolean not null,
  body        text not null default '',
  image_url   text,
  created_at  timestamptz not null default now(),
  -- Мәтін ≤2000; бос мәтінге тек сурет болса ғана рұқсат.
  constraint support_messages_body_chk check (
    char_length(body) <= 2000
    and (char_length(btrim(body)) >= 1 or image_url is not null)
  )
);

create index if not exists support_messages_thread_idx
  on public.support_messages (thread_id, id desc);

-- ── 2. RLS: тек оқу (иесі немесе superadmin) ─────────────────────────────────

alter table public.support_threads  enable row level security;
alter table public.support_messages enable row level security;

drop policy if exists support_threads_select on public.support_threads;
create policy support_threads_select on public.support_threads
  for select to authenticated
  using (user_uid = auth.uid() or public.is_superadmin());

drop policy if exists support_messages_select on public.support_messages;
create policy support_messages_select on public.support_messages
  for select to authenticated
  using (
    public.is_superadmin()
    or exists (
      select 1 from public.support_threads t
       where t.id = support_messages.thread_id and t.user_uid = auth.uid()
    )
  );

-- Тікелей жазу саясаты ЖОҚ; оған қоса әдепкі гранттарды да аламыз
-- (саясат кездейсоқ қосылып кетсе де, клиент санауышты өзгерте алмасын).
revoke insert, update, delete, truncate on public.support_threads  from anon, authenticated;
revoke insert, update, delete, truncate on public.support_messages from anon, authenticated;
revoke all on public.support_threads  from anon;
revoke all on public.support_messages from anon;
grant select on public.support_threads  to authenticated;
grant select on public.support_messages to authenticated;

-- ── 3. RPC: пайдаланушы жазады ───────────────────────────────────────────────

create or replace function public.support_send(p_body text, p_image_url text default null)
returns public.support_messages
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_uid    uuid := auth.uid();
  v_role   text;
  v_name   text := '';
  v_phone  text := '';
  v_store  text := '';
  v_body   text := coalesce(btrim(p_body), '');
  v_img    text := nullif(btrim(coalesce(p_image_url, '')), '');
  v_thread public.support_threads;
  v_last   timestamptz;
  v_msg    public.support_messages;
  v_staff  uuid[];
begin
  if v_uid is null then
    raise exception 'not_authorized';
  end if;

  v_role := public.app_role();
  if v_role = 'superadmin' then
    -- Модератор өзіне жазбайды — ол support_reply қолданады.
    raise exception 'not_allowed';
  end if;
  if v_role not in ('client', 'admin', 'seller', 'courier') then
    raise exception 'not_authorized';
  end if;

  -- Superadmin функцияны өшірсе — жаңа хабарлама жіберілмейді
  -- (жауап беру/оқу тоқтамайды: мұндағы тексеру тек пайдаланушы жағына).
  if not public.feature_enabled('support_chat') then
    raise exception 'feature_disabled';
  end if;

  if char_length(v_body) > 2000 then
    raise exception 'too_long';
  end if;
  if v_body = '' and v_img is null then
    raise exception 'empty_message';
  end if;
  -- Сурет тек өз Cloudinary аккаунтымыздан (cloud name = divynstru, cloudinary_service.dart-пен бірдей) —
  -- бөтен аккаунт/сілтеме модератордың IP-ін ашып алмасын.
  if v_img is not null and v_img !~ '^https://res\.cloudinary\.com/divynstru/' then
    raise exception 'bad_image_url';
  end if;

  -- Аты/телефоны — сервердегі профильден.
  if v_role = 'client' then
    select coalesce(c.name, ''), coalesce(c.phone, '')
      into v_name, v_phone
      from public.clients c where c.id = v_uid;
  else
    select coalesce(u.name, ''), coalesce(u.phone, '')
      into v_name, v_phone
      from public.users u where u.id = v_uid;
    if v_role in ('admin', 'seller') then
      select coalesce(s.store_name, '') into v_store
        from public.stores s where s.admin_uid = public.app_owner_uid();
      v_store := coalesce(v_store, '');
    end if;
  end if;

  -- Тред жоқ болса — құрамыз; бар болса — жолды құлыптаймыз (rate limit
  -- пен санауыштар бір транзакцияда, жарыссыз).
  insert into public.support_threads (user_uid, user_role, user_name, user_phone, store_name)
  values (v_uid, v_role, coalesce(v_name, ''), coalesce(v_phone, ''), v_store)
  on conflict (user_uid) do nothing;

  select * into v_thread
    from public.support_threads
   where user_uid = v_uid
   for update;

  select max(m.created_at) into v_last
    from public.support_messages m
   where m.thread_id = v_thread.id and m.sender_uid = v_uid;
  if v_last is not null and v_last > now() - interval '1 second' then
    raise exception 'rate_limited';
  end if;
  -- Жылжымалы шек: 10 минутта ≤30 хабарлама (әр хабарлама барлық
  -- superadmin-ге push + notifications жолын тудырады — спам жолын жабамыз).
  if (select count(*) from public.support_messages m
       where m.thread_id = v_thread.id and m.sender_uid = v_uid
         and m.created_at > now() - interval '10 minutes') >= 30 then
    raise exception 'rate_limited';
  end if;

  insert into public.support_messages (thread_id, sender_uid, is_staff, body, image_url)
  values (v_thread.id, v_uid, false, v_body, v_img)
  returning * into v_msg;

  update public.support_threads
     set user_role            = v_role,
         user_name            = coalesce(v_name, ''),
         user_phone           = coalesce(v_phone, ''),
         store_name           = v_store,
         status               = 'open',
         last_message_at      = v_msg.created_at,
         last_message_preview = left(case when v_body = '' then '📷' else v_body end, 140),
         unread_for_staff     = unread_for_staff + 1
   where id = v_thread.id;

  select array_agg(id) into v_staff from public.users where role = 'superadmin';
  if v_staff is not null then
    perform public.notify_push(
      v_staff,
      'Қолдау чаты: ' || coalesce(nullif(v_name, ''), 'пайдаланушы'),
      left(case when v_body = '' then '📷 Сурет' else v_body end, 100),
      jsonb_build_object('type', 'support_message', 'threadId', v_thread.id)
    );
  end if;

  return v_msg;
end;
$function$;

revoke execute on function public.support_send(text, text) from public, anon;
grant execute on function public.support_send(text, text) to authenticated;

-- ── 4. RPC: модератор жауап береді ───────────────────────────────────────────

create or replace function public.support_reply(p_thread uuid, p_body text, p_image_url text default null)
returns public.support_messages
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_body   text := coalesce(btrim(p_body), '');
  v_img    text := nullif(btrim(coalesce(p_image_url, '')), '');
  v_thread public.support_threads;
  v_msg    public.support_messages;
begin
  if not public.is_superadmin() then
    raise exception 'not_authorized';
  end if;
  if char_length(v_body) > 2000 then
    raise exception 'too_long';
  end if;
  if v_body = '' and v_img is null then
    raise exception 'empty_message';
  end if;
  if v_img is not null and v_img !~ '^https://res\.cloudinary\.com/divynstru/' then
    raise exception 'bad_image_url';
  end if;

  select * into v_thread from public.support_threads where id = p_thread for update;
  if not found then
    raise exception 'not_found';
  end if;

  insert into public.support_messages (thread_id, sender_uid, is_staff, body, image_url)
  values (v_thread.id, auth.uid(), true, v_body, v_img)
  returning * into v_msg;

  update public.support_threads
     set last_message_at      = v_msg.created_at,
         last_message_preview = left(case when v_body = '' then '📷' else v_body end, 140),
         unread_for_user      = unread_for_user + 1,
         -- Модератор жауап берсе — тред оқылды деп есептеледі.
         unread_for_staff     = 0
   where id = v_thread.id;

  perform public.notify_push(
    array[v_thread.user_uid],
    'Qoima қолдау қызметі',
    left(case when v_body = '' then '📷 Сурет' else v_body end, 100),
    jsonb_build_object('type', 'support_reply', 'threadId', v_thread.id)
  );

  return v_msg;
end;
$function$;

revoke execute on function public.support_reply(uuid, text, text) from public, anon;
grant execute on function public.support_reply(uuid, text, text) to authenticated;

-- ── 5. RPC: оқылды деп белгілеу ──────────────────────────────────────────────

create or replace function public.support_mark_read(p_thread uuid)
returns void
language plpgsql
security definer
set search_path = public
as $function$
begin
  if auth.uid() is null then
    raise exception 'not_authorized';
  end if;
  if public.is_superadmin() then
    update public.support_threads set unread_for_staff = 0
     where id = p_thread and unread_for_staff <> 0;
    return;
  end if;
  update public.support_threads set unread_for_user = 0
   where id = p_thread and user_uid = auth.uid() and unread_for_user <> 0;
end;
$function$;

revoke execute on function public.support_mark_read(uuid) from public, anon;
grant execute on function public.support_mark_read(uuid) to authenticated;

-- ── 6. RPC: тредті жабу / қайта ашу (тек модератор) ──────────────────────────

create or replace function public.support_set_status(p_thread uuid, p_status text)
returns void
language plpgsql
security definer
set search_path = public
as $function$
begin
  if not public.is_superadmin() then
    raise exception 'not_authorized';
  end if;
  if p_status not in ('open', 'closed') then
    raise exception 'bad_status';
  end if;
  update public.support_threads set status = p_status where id = p_thread;
  if not found then
    raise exception 'not_found';
  end if;
end;
$function$;

revoke execute on function public.support_set_status(uuid, text) from public, anon;
grant execute on function public.support_set_status(uuid, text) to authenticated;

-- ── 7. Realtime ──────────────────────────────────────────────────────────────

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime' and schemaname = 'public'
       and tablename = 'support_threads'
  ) then
    alter publication supabase_realtime add table public.support_threads;
  end if;
  if not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime' and schemaname = 'public'
       and tablename = 'support_messages'
  ) then
    alter publication supabase_realtime add table public.support_messages;
  end if;
end $$;

-- ── 8. Платформа баптауы: сұрақ-жауаптың жариялығы ──────────────────────────
-- 'false' (әдепкі) — тауар туралы сұрақ пен жауап тек клиент пен дүкен
-- арасында; 'true' — барлық сатып алушыға көрінеді.
insert into public.app_settings (key, value)
values ('qa_public', 'false')
on conflict (key) do nothing;

-- ── Тексеру (қолданғаннан кейін қолмен) ──────────────────────────────────────
-- select proname, proacl from pg_proc
--  where proname in ('support_send','support_reply','support_mark_read','support_set_status');
--   → proacl ішінде `=X/` та, `anon=X/` та болмауы тиіс (pg_default_acl anon-ға
--     жеке грант береді), `authenticated=X/` болуы тиіс.
-- select tablename from pg_publication_tables
--  where pubname='supabase_realtime' and tablename like 'support_%';
