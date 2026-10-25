-- ════════════════════════════════════════════════════════════════════════════
--  0075: Тауар қосуға AI көмегі — дүкен иесінің күндік квотасы
-- ════════════════════════════════════════════════════════════════════════════
--  Не үшін:
--    Дүкен иесі/сатушы тауар қосқанда «Суреттен толтыру» және «Сипаттаманы AI
--    жазсын» батырмалары `ai-product-assist` edge функциясын шақырады. Әр
--    шақыру — ақылы AI сұрауы, сондықтан ДҮКЕН бойынша (иесі + оның барлық
--    сатушылары ортақ) күндік шек керек.
--
--    Wave-1-дің клиенттік AI кестелерінен (try-on/stylist/assistant) БӨЛЕК:
--    олар клиент бойынша санайды, бұл — дүкен иесі (app_owner_uid()) бойынша.
--
--  Ережелер (CLAUDE.md / 0065 аудиті):
--    • Санағыш тек серверде, `for update` құлпымен, бір транзакцияда өседі.
--      Клиентте оқып-есептеп-жазу ЖОҚ — кестеге клиенттік write саясаты жоқ.
--    • SECURITY DEFINER-де авторизация МІНДЕТТІ; `revoke … from public`
--      + `grant … to authenticated`. Бұл жобада default privileges жаңа
--      функцияға anon-ға ЖЕКЕ грант береді (pg_default_acl: anon=X), сондықтан
--      `from anon` та қосымша жазылады.
--    • Күн шекарасы — Алматы уақыты бойынша (UTC+5).
--    • Шек app_settings 'ai_describe_daily_limit' кілтінен (суперадмин
--      өзгертеді), әдепкі '30'.
-- ════════════════════════════════════════════════════════════════════════════

create table if not exists public.ai_owner_usage (
  owner_uid  uuid    not null references auth.users(id) on delete cascade,
  day        date    not null,
  count      integer not null default 0,
  updated_at timestamptz not null default now(),
  primary key (owner_uid, day)
);

alter table public.ai_owner_usage enable row level security;

-- Тек ӨЗ дүкенінің санағышын оқу (сатушы — иесінікін). Жазу саясаты ӘДЕЙІ
-- ЖОҚ: санағыш тек consume/refund функциялары арқылы өзгереді.
drop policy if exists ai_owner_usage_select on public.ai_owner_usage;
create policy ai_owner_usage_select on public.ai_owner_usage
  for select to authenticated
  using (owner_uid = public.app_owner_uid() or public.is_superadmin());

-- Supabase-тің default privileges жаңа кестеге anon/authenticated-ке толық
-- грант береді. RLS бәрібір қорғайды, бірақ қосымша қабат: клиент тек оқиды.
revoke all on table public.ai_owner_usage from anon;
revoke insert, update, delete, truncate on table public.ai_owner_usage from authenticated;

-- Әдепкі шек (суперадмин app_settings арқылы өзгертеді).
insert into public.app_settings (key, value)
values ('ai_describe_daily_limit', '30')
on conflict (key) do nothing;


-- ── Шекті оқу (ішкі көмекші) ───────────────────────────────────────────────
--  Мән бос/қате болса — 30. Теріс сан → 0 (AI өшірулі).
create or replace function public.ai_describe_daily_limit()
returns integer
language plpgsql
stable
security definer
set search_path = public
as $function$
declare
  v text;
  n integer;
begin
  if auth.uid() is null then
    raise exception 'not_authorized';
  end if;
  select s.value into v from public.app_settings s
   where s.key = 'ai_describe_daily_limit';
  begin
    n := coalesce(nullif(trim(v), '')::integer, 30);
  exception when others then
    n := 30;
  end;
  return greatest(n, 0);
end;
$function$;

revoke execute on function public.ai_describe_daily_limit() from public;
revoke execute on function public.ai_describe_daily_limit() from anon;
grant execute on function public.ai_describe_daily_limit() to authenticated;


-- ── Квотаны тұтыну ─────────────────────────────────────────────────────────
--  Шақырушы — дүкен қызметкері (admin/seller) болуы МІНДЕТТІ. Санақ дүкен
--  иесі бойынша (app_owner_uid()). Шектен асса — 'ai_quota_exceeded'.
--  Қайтарады: БҮГІН қалған шақыру саны (осы шақырудан кейін).
create or replace function public.consume_owner_ai_quota()
returns integer
language plpgsql
volatile
security definer
set search_path = public
as $function$
declare
  v_owner uuid := public.app_owner_uid();
  v_role  text := public.app_role();
  v_day   date := (now() at time zone 'Asia/Almaty')::date;
  v_limit integer;
  v_count integer;
begin
  if auth.uid() is null or v_owner is null
     or v_role not in ('admin', 'seller') then
    raise exception 'not_authorized';
  end if;

  -- Суперадмин жалауы (0067b): өшік болса квота тұтынылмайды.
  if not public.feature_enabled('ai_product_assist') then
    raise exception 'feature_disabled';
  end if;

  v_limit := public.ai_describe_daily_limit();

  insert into public.ai_owner_usage (owner_uid, day, count)
  values (v_owner, v_day, 0)
  on conflict (owner_uid, day) do nothing;

  select u.count into v_count
    from public.ai_owner_usage u
   where u.owner_uid = v_owner and u.day = v_day
   for update;

  if v_count >= v_limit then
    raise exception 'ai_quota_exceeded';
  end if;

  update public.ai_owner_usage
     set count = v_count + 1, updated_at = now()
   where owner_uid = v_owner and day = v_day;

  return v_limit - (v_count + 1);
end;
$function$;

revoke execute on function public.consume_owner_ai_quota() from public;
revoke execute on function public.consume_owner_ai_quota() from anon;
grant execute on function public.consume_owner_ai_quota() to authenticated;


-- ── Қалған санды көрсету (UI үшін) ─────────────────────────────────────────
--  Дүкен қызметкері емес шақырушыға null.
create or replace function public.owner_ai_quota_remaining()
returns integer
language plpgsql
stable
security definer
set search_path = public
as $function$
declare
  v_owner uuid := public.app_owner_uid();
  v_day   date := (now() at time zone 'Asia/Almaty')::date;
  v_used  integer;
begin
  if auth.uid() is null or v_owner is null
     or public.app_role() not in ('admin', 'seller') then
    return null;
  end if;
  select u.count into v_used from public.ai_owner_usage u
   where u.owner_uid = v_owner and u.day = v_day;
  return greatest(public.ai_describe_daily_limit() - coalesce(v_used, 0), 0);
end;
$function$;

revoke execute on function public.owner_ai_quota_remaining() from public;
revoke execute on function public.owner_ai_quota_remaining() from anon;
grant execute on function public.owner_ai_quota_remaining() to authenticated;


-- ── Қайтару (AI сұрауы сәтсіз болғанда) ────────────────────────────────────
--  ТЕК edge функция (service_role) шақырады: клиентке ашық болса, қайта-қайта
--  шақырып санағышты нөлдеп, шексіз AI алуға болар еді.
create or replace function public.refund_owner_ai_quota(p_owner uuid)
returns void
language plpgsql
volatile
security definer
set search_path = public
as $function$
begin
  -- Тек service_role (edge функция). auth.uid() бұл жерде null болады.
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'not_authorized';
  end if;
  update public.ai_owner_usage
     set count = greatest(count - 1, 0), updated_at = now()
   where owner_uid = p_owner
     and day = (now() at time zone 'Asia/Almaty')::date;
end;
$function$;

revoke execute on function public.refund_owner_ai_quota(uuid) from public;
revoke execute on function public.refund_owner_ai_quota(uuid) from anon, authenticated;
grant execute on function public.refund_owner_ai_quota(uuid) to service_role;

-- Тексеру (қолданғаннан кейін):
--   select proname, proacl from pg_proc
--    where proname in ('consume_owner_ai_quota','owner_ai_quota_remaining',
--                      'refund_owner_ai_quota','ai_describe_daily_limit');
--   → ешқайсысында `=X/` болмауы тиіс.
