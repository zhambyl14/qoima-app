-- ════════════════════════════════════════════════════════════════════════════
--  0043 · Дүкеннің өз жарнама push-ы (сатушының маркетинг хабарламасы)
-- ────────────────────────────────────────────────────────────────────────────
--  Аудитория: осы дүкеннен таңдаулыға қосқан НЕМЕСЕ сатып алған (completed
--  тапсырыс) клиенттердің бірігуі (favorites + orders, дубль жоқ).
--  Спамнан қорғау: аптасына 1 рет (admin_uid бойынша, BEFORE INSERT триггер
--  — API арқылы тікелей шақырса да айналып өте алмайды).
-- ════════════════════════════════════════════════════════════════════════════

create table if not exists public.store_broadcasts (
  id               uuid primary key default gen_random_uuid(),
  admin_uid        uuid not null,
  title            text not null,
  body             text not null,
  recipient_count  integer not null default 0,
  sent_by          uuid,
  created_at       timestamptz not null default now(),
  constraint broadcast_title_len check (char_length(title) between 1 and 60),
  constraint broadcast_body_len  check (char_length(body)  between 1 and 200)
);
create index if not exists store_broadcasts_admin_idx
  on public.store_broadcasts(admin_uid, created_at desc);

alter table public.store_broadcasts enable row level security;

drop policy if exists broadcasts_select on public.store_broadcasts;
create policy broadcasts_select on public.store_broadcasts for select using (
  admin_uid = public.app_owner_uid() or public.is_superadmin()
);

drop policy if exists broadcasts_insert on public.store_broadcasts;
create policy broadcasts_insert on public.store_broadcasts for insert with check (
  admin_uid = public.app_owner_uid()
);

-- ── Аптасына 1 рет шектеу (BEFORE INSERT — тікелей API шақырса да өтпейді) ──
create or replace function public.check_broadcast_rate_limit() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if exists (
    select 1 from public.store_broadcasts
    where admin_uid = new.admin_uid
      and created_at > now() - interval '7 days'
  ) then
    raise exception 'broadcast_rate_limited';
  end if;
  return new;
end;
$$;
drop trigger if exists trg_broadcast_rate_limit on public.store_broadcasts;
create trigger trg_broadcast_rate_limit before insert on public.store_broadcasts
  for each row execute function public.check_broadcast_rate_limit();

-- ── Жіберу: favorites ∪ completed orders клиенттеріне notify_push ───────────
create or replace function public.on_store_broadcast_push() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_uids uuid[];
begin
  select array_agg(distinct uid) into v_uids from (
    select client_uid as uid from public.favorites where admin_uid = new.admin_uid
    union
    select client_uid as uid from public.orders
      where admin_uid = new.admin_uid and status = 'completed'
  ) t;
  if v_uids is null then return new; end if;

  update public.store_broadcasts
    set recipient_count = array_length(v_uids, 1)
    where id = new.id;

  perform public.notify_push(
    v_uids,
    new.title,
    new.body,
    jsonb_build_object('type', 'store_broadcast', 'adminUid', new.admin_uid)
  );
  return new;
end;
$$;
drop trigger if exists trg_store_broadcast_push on public.store_broadcasts;
create trigger trg_store_broadcast_push after insert on public.store_broadcasts
  for each row execute function public.on_store_broadcast_push();
