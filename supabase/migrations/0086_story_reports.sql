-- ════════════════════════════════════════════════════════════════════════════
--  0086 — Сторисқа шағым (UGC: App Store 1.2 / Google Play UGC саясаты)
-- ════════════════════════════════════════════════════════════════════════════
--  0084 стористі ашты, бірақ оған шағымдану мүмкін емес еді. Бар шағым ағыны
--  (0015 content_reports + 0047 'question') сол күйі қолданылады:
--    • клиент кестеге тікелей insert жасайды (reports_insert саясаты:
--      тек authenticated, reporter_uid = auth.uid()) — гость жаза алмайды;
--    • superadmin ReportsScreen-де realtime көреді (reports_select);
--    • жаңа шағым → модераторларға push (0022 trg_report_push, AFTER INSERT).
--
--  Бұл миграция:
--    1) target_type тізіміне 'story' қосады (бар мәндердің бәрі сақталады);
--    2) content_reports.target_image — нысан суретінің снапшоты (сторис
--       24 сағатта жойылады, модератор не көргенін білсін);
--    3) BEFORE INSERT триггер (тексерістер тек target_type='story'): сторис бар әрі ҚАЗІР
--       көрінетін болуы керек (store_stories_read RLS-пен бірдей шарт), өз
--       дүкенінің сторисіне шағым жоқ, атауы/дүкені/суреті СЕРВЕРДЕН
--       толтырылады (клиент жалған target_name/admin_uid жібере алмайды);
--       басқа түрлерде target_image әрқашан '' (клиент URL қоя алмайды);
--    4) бір қолданушы бір сторисқа бір рет қана шағымдана алады — бұрынғы
--       түрлерде серверлік қайталау ережесі ЖОҚ еді (тек UI), сондықтан
--       ереже тек 'story' үшін жаңадан: триггер түсінікті 'already_reported'
--       қатесін береді, жартылай бірегей индекс қатар келген екі insert-ті де
--       ұстайды.
--  Авто-жасыру ережесі қосылмады: басқа түрлерде де жоқ, модератор шешеді
--  (story_delete RPC 0084-те superadmin-ге бұрыннан рұқсат).
--
--  Идемпотентті: 0084-тің екі нұсқасының (түзетусіз / түзетулі) үстінде де
--  қайта-қайта орындауға болады.
-- ════════════════════════════════════════════════════════════════════════════

-- ── 1) target_type: 'story' ─────────────────────────────────────────────────
alter table public.content_reports
  drop constraint if exists content_reports_target_type_check;
alter table public.content_reports
  add constraint content_reports_target_type_check
    check (target_type in ('product', 'store', 'review', 'question', 'story'));

-- ── 2) Нысан суретінің снапшоты (модератор экраны үшін) ─────────────────────
alter table public.content_reports
  add column if not exists target_image text not null default '';

-- ── 3) Қайталау ережесі: бір қолданушы — бір сторис — бір шағым ─────────────
--  Ескерту: content_reports-та 'story' жолы бұрын болмаған (CHECK рұқсат
--  етпеген), сондықтан индекс бар деректерге соқтығыспайды.
create unique index if not exists content_reports_story_once
  on public.content_reports(reporter_uid, target_id)
  where target_type = 'story';

-- ── 4) Сторис шағымының күзеті ──────────────────────────────────────────────
--  SECURITY DEFINER: store_stories/stores-ты RLS-сіз оқиды (көріну шартын
--  өзі тексереді). Авторизация: шақырушы кірген әрі reporter_uid = өзі.
create or replace function public.content_reports_story_guard()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_id  uuid;
  v_st  record;
begin
  -- Басқа түрлер: сурет снапшоты тек сервер толтыратын өріс. Клиент жіберген
  -- URL модератор экранында Image.network болып ашылар еді (суперадмин IP-і
  -- бөтен хостқа ағады / кез келген сурет көрсетіледі) — сондықтан тазаланады.
  if new.target_type is distinct from 'story' then
    new.target_image := '';
    return new;
  end if;
  if v_uid is null or new.reporter_uid is distinct from v_uid then
    raise exception 'not_authorized';
  end if;

  begin
    v_id := btrim(coalesce(new.target_id, ''))::uuid;
  exception when others then
    raise exception 'story_unavailable';
  end;

  -- «Қазір көрінетін» = store_stories_read саясатымен бірдей шарт.
  select st.id, st.store_uid, st.image_url, st.caption,
         coalesce(s.store_name, '') as store_name
    into v_st
    from public.store_stories st
    join public.stores s on s.admin_uid = st.store_uid
    where st.id = v_id
      and st.expires_at > now()
      and public.feature_enabled('stories')
      and public.store_publicly_visible(st.store_uid);
  if not found then raise exception 'story_unavailable'; end if;

  -- Дүкеннің өз қызметкері (иесі/белсенді сатушысы) өз сторисіне шағымданбайды.
  if public.live_is_staff(v_st.store_uid) then
    raise exception 'cannot_report_own';
  end if;

  -- Канондық id (кіші әріппен) — бірегей индекс регистр айырмасымен айналып
  -- өтілмесін.
  new.target_id := v_id::text;
  if exists (select 1 from public.content_reports r
             where r.reporter_uid = v_uid
               and r.target_type = 'story'
               and r.target_id = new.target_id) then
    raise exception 'already_reported';
  end if;

  -- Модератор көретін мәліметтер — тек серверден.
  new.admin_uid     := v_st.store_uid;
  new.store_name    := v_st.store_name;
  new.target_name   := left(coalesce(nullif(btrim(v_st.caption), ''), v_st.store_name), 120);
  new.target_image  := v_st.image_url;
  new.comment       := left(coalesce(new.comment, ''), 500);
  new.reason        := left(coalesce(nullif(btrim(new.reason), ''), 'other'), 40);
  -- Жаңа шағым әрқашан «жаңа» — reporter өзі «шешілді» деп жаза алмайды.
  new.status          := 'new';
  new.resolved_by     := '';
  new.resolution_note := '';
  new.resolved_at     := null;
  return new;
end;
$$;
revoke execute on function public.content_reports_story_guard() from public, anon, authenticated;

--  WHEN шарты ЖОҚ: 'story' емес жолдарда да target_image тазалансын (жоғарыда).
drop trigger if exists trg_content_reports_story_guard on public.content_reports;
create trigger trg_content_reports_story_guard
  before insert on public.content_reports
  for each row
  execute function public.content_reports_story_guard();

--  Ертерек нұсқа (WHEN шартымен) қолданылып үлгерсе — клиент қойған сурет
--  сілтемелері тазаланады (идемпотентті; жаңа БД-да 0 жол).
update public.content_reports
   set target_image = ''
 where target_type <> 'story' and target_image <> '';
