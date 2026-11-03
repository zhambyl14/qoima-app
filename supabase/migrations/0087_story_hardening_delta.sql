-- ════════════════════════════════════════════════════════════════════════════
--  0087 — Сторис/жазылу қатайтуы: 0084 шолу түзетулерінің ДЕЛЬТАСЫ
-- ════════════════════════════════════════════════════════════════════════════
--  0084 тірі БД-ға қолданылды, бірақ қай нұсқасы (шолу түзетулерімен бе,
--  жоқ па) — белгісіз. Сондықтан 0084-ті орнында өзгертпейміз; мұнда барлық
--  кейінгі түзетулер ИДЕМПОТЕНТТІ түрде қайта қолданылады — 0084-тің екі
--  нұсқасының үстінде де нәтиже бірдей:
--    1) store_stories.public_id (генерацияланған) + store_stories_public_id_uniq
--       — Cloudinary суретінің «синонимі» (басқа версия/кеңейтім) арқылы бөтен
--       дүкеннің сторисін өшіртуге болмайды;
--    2) _batch_effective_price + _batch_discount_pct (соның үстінде);
--    3) on_batch_discount_follow_push — «бағаны көтеріп жеңілдік қою» жалған
--       жеңілдігіне push жоқ, өңделген жеңілдік cron-да қайталанбайды;
--    4) notify_followers — шектегіш жабық болса алушы тізімін жинамайтын арзан
--       алдын ала тексеріс;
--    5) story_create — public_id қайталану тексерісі + ЖАҢА: бір мезеттегі
--       жарыста бірегей индекс қатесі (unique_violation) шикі қате емес,
--       'invalid_image_url' болып қайтады.
--  Функция денелері репо 0084-тен сөзбе-сөз көшірілді (5-тармақтан басқа).
--  Әр create or replace-тен кейін revoke ... from public ҚАЙТА орындалады.
-- ════════════════════════════════════════════════════════════════════════════

-- ── 1) store_stories.public_id ──────────────────────────────────────────────
--  publicIdFromUrl-дың (cloudinary-cleanup) дәл көшірмесі: v123/ мен кеңейтім
--  алынады.
alter table public.store_stories
  add column if not exists public_id text generated always as (
    regexp_replace(
      regexp_replace(image_url,
        '^https://res\.cloudinary\.com/divynstru/image/upload/(v[0-9]+/)?', ''),
      '\.[^./]*$', '')
  ) stored;

--  Түзетусіз 0084 кезінде «синоним» сторис кіріп үлгерсе, бірегей индекс
--  құрылмай миграция құлар еді. Ондай жолдар тек шабуыл/қате нәтижесі:
--  әр public_id үшін ЕҢ ЕСКІСІ (түпнұсқа) қалады, кейінгілері өшіріледі.
--  Өшіру триггері (on_store_story_deleted) бұл сәтте өшіріледі — әйтпесе
--  ортақ public_id Cloudinary-ден жойылып, түпнұсқа сторис суретсіз қалар еді.
do $$
begin
  if exists (select 1 from public.store_stories
             group by public_id having count(*) > 1) then
    alter table public.store_stories disable trigger trg_store_story_deleted;
    delete from public.store_stories st
      using (
        select id, row_number() over (partition by public_id
                                      order by created_at, id) as rn
        from public.store_stories
      ) d
      where d.id = st.id and d.rn > 1;
    alter table public.store_stories enable trigger trg_store_story_deleted;
  end if;
end;
$$;

create unique index if not exists store_stories_public_id_uniq
  on public.store_stories(public_id);

-- ── 2) Жеңілдіктің тиімді бағасы мен пайызы ─────────────────────────────────
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

-- ── 3) Жеңілдік push триггерінің функциясы ──────────────────────────────────

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

-- ── 4) notify_followers: арзан шектегіш тексерісі ───────────────────────────
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

-- ── 5) story_create: public_id тексерісі + жарыс қатесін түсінікті ету ──────
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

  -- Жарыс: екі құрылғы бір мезетте сол суретті жіберсе, екеуі де жоғарыдағы
  -- тексерістен өтуі мүмкін — біреуін бірегей индекс (image_url не public_id)
  -- тоқтатады. Шикі «duplicate key» қатесінің орнына — сол түсінікті қате.
  begin
    insert into public.store_stories(store_uid, image_url, caption, created_by)
      values (v_owner, v_url, v_caption, v_uid)
      returning * into v_row;
  exception when unique_violation then
    raise exception 'invalid_image_url';
  end;
  return v_row;
end;
$$;
revoke execute on function public.story_create(text, text) from public, anon;
grant execute on function public.story_create(text, text) to authenticated;
