-- ════════════════════════════════════════════════════════════════════════════
--  0033 · Іштегі хабарламалар (notifications): push оқиғаларының тарихы
-- ────────────────────────────────────────────────────────────────────────────
--  Бұрын: notify_push() (0020) тек FCM push жібереді — ештеңе сақталмайды.
--  Қоңырау зілі (bell) басылғанда көрсетуге ешбір тарих жоқ еді (client/admin
--  беттерінде «Хабарламалар — жақында» деген snackbar ғана болды, ал админ
--  зілі қате SellersScreen-ге секіретін).
--
--  Түзету: notify_push() әр уид-ке notifications жолын да жазады — барлық
--  бұрыннан бар триггерлер (order/order_status/review/review_reply/return/
--  sale/banner/join_request/store_edit/subscription, т.б.) осы бір функция
--  арқылы өтетіндіктен, әр оқиға түрі автоматты түрде іштегі тарихқа ілінеді
--  — триггерлерді бөлек өзгертудің қажеті жоқ. Навигация push_navigation.dart-
--  тағы handlePushOpen(data)-ты қайта пайдаланады (data payload пішіні дәл
--  сол — {type, ...}).
-- ════════════════════════════════════════════════════════════════════════════

create table if not exists public.notifications (
  id         uuid primary key default gen_random_uuid(),
  uid        uuid not null references auth.users(id) on delete cascade,
  title      text not null default '',
  body       text not null default '',
  data       jsonb not null default '{}'::jsonb,
  read_at    timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists notifications_uid_idx
  on public.notifications(uid, created_at desc);

alter table public.notifications enable row level security;

drop policy if exists notifications_select on public.notifications;
create policy notifications_select on public.notifications for select using (
  uid = auth.uid()
);

drop policy if exists notifications_update on public.notifications;
create policy notifications_update on public.notifications for update using (
  uid = auth.uid()
) with check (
  uid = auth.uid()
);
-- Insert policy ӘДЕЙІ жоқ — жазу тек notify_push() (SECURITY DEFINER,
-- RLS-ты айналып өтеді) арқылы, қалғандарымен бірдей конвенция.

create or replace function public.notify_push(
  p_uids uuid[],
  p_title text,
  p_body text,
  p_data jsonb default '{}'::jsonb
) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_secret text;
  v_uid uuid;
begin
  if p_uids is null or array_length(p_uids, 1) is null then return; end if;

  foreach v_uid in array p_uids loop
    if v_uid is not null then
      insert into public.notifications(uid, title, body, data)
      values (v_uid, p_title, p_body, coalesce(p_data, '{}'::jsonb));
    end if;
  end loop;

  select decrypted_secret into v_secret
    from vault.decrypted_secrets where name = 'push_trigger_secret';
  if v_secret is null then return; end if; -- секрет орнатылмаса — үнсіз өтеміз

  perform net.http_post(
    url := 'https://ujpcdfgwxdholsepioji.supabase.co/functions/v1/send-push',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'apikey', 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVqcGNkZmd3eGRob2xzZXBpb2ppIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODI4MDYxMzcsImV4cCI6MjA5ODM4MjEzN30.E2AIz2quumSuU0K3lzONM8alw26NLzje3zvWWFUMk7o',
      'x-push-secret', v_secret
    ),
    body := jsonb_build_object(
      'uids', to_jsonb(p_uids),
      'title', p_title,
      'body', p_body,
      'data', p_data
    )
  );
exception when others then
  -- Push сәтсіз болса да НЕГІЗГІ операция (сатылым/тапсырыс/пікір) бұзылмайды.
  null;
end;
$$;
