-- ════════════════════════════════════════════════════════════════════════════
--  0019 · FCM push токендері
-- ────────────────────────────────────────────────────────────────────────────
--  Әр құрылғының FCM токені (логинде upsert, шығуда өшіріледі).
--  Push жіберуші (send-push edge function) uid/role бойынша токендерді
--  осы жерден алады. Бір токен — бір құрылғы; аккаунт ауысса uid жаңарады.
-- ════════════════════════════════════════════════════════════════════════════

create table if not exists public.fcm_tokens (
  token      text primary key,
  uid        uuid not null references auth.users(id) on delete cascade,
  role       text not null default '',      -- admin|seller|client|superadmin
  platform   text not null default '',      -- android|ios|web
  updated_at timestamptz not null default now()
);
create index if not exists fcm_tokens_uid_idx on public.fcm_tokens(uid);

alter table public.fcm_tokens enable row level security;

-- Әркім тек өз токендерін жазады/көреді/өшіреді.
drop policy if exists fcm_rw on public.fcm_tokens;
create policy fcm_rw on public.fcm_tokens for all
  using (uid = auth.uid()) with check (uid = auth.uid());
