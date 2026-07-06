-- ════════════════════════════════════════════════════════════════════════════
--  Qoima · Ревизия (недостача) + списание
-- ────────────────────────────────────────────────────────────────────────────
--  «Ревизия» бөлімі: дүкен иесі тауардан нешеу жетіспейтінін жазады
--  (revisions, status='open'), кейін «Списать» басқанда қойма азайып,
--  sales_history-ге type='writeoff' жазба түседі (status='written_off').
--  sales_history.type енді: sale | return | writeoff.
-- ════════════════════════════════════════════════════════════════════════════

create table public.revisions (
  id              uuid primary key default gen_random_uuid(),
  owner_uid       uuid not null references auth.users(id) on delete cascade,
  product_id      uuid,
  product_name    text default '',
  warehouse_id    uuid,
  sizes_missing   jsonb not null default '{}',
  quantity        integer not null default 0,
  note            text default '',
  status          text not null default 'open',   -- open | written_off
  created_by      uuid,
  created_by_name text default '',
  created_at      timestamptz not null default now(),
  written_off_at  timestamptz
);
create index revisions_owner_idx on public.revisions(owner_uid, created_at);

alter table public.revisions enable row level security;

-- Тек бизнес мүшелері (иесі + сатушылары) — sales_history үлгісімен.
create policy revisions_rw on public.revisions for all
  using (owner_uid = public.app_owner_uid())
  with check (owner_uid = public.app_owner_uid());

-- Flutter `.stream()` тірі жаңаруы үшін.
alter publication supabase_realtime add table public.revisions;
