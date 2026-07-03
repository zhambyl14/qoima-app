-- ════════════════════════════════════════════════════════════════════════════
--  0005 · Схема дрейфін түзеу + дүкен иесін жалпы блоктау
-- ────────────────────────────────────────────────────────────────────────────
--  ✅ 2026-07-02 базаға қолданылды (MCP apply_migration: repair_drift_and_global_block).
--  Дрейф себебі: базадағы схема 0001-дің ескі нұсқасынан жасалған еді
--  (returns.id uuid, addresses.title, favorites/transfers-те бағандар жетіспеді).
-- ════════════════════════════════════════════════════════════════════════════

-- ── 1) returns.id: uuid → text (қосымша RET-YYYY-NNNN жазады) ────────────────
alter table public.returns_index drop constraint if exists returns_index_return_id_fkey;
alter table public.returns alter column id drop default;
alter table public.returns alter column id type text using id::text;
alter table public.returns_index alter column return_id type text using return_id::text;
alter table public.returns_index
  add constraint returns_index_return_id_fkey
  foreign key (return_id) references public.returns(id) on delete cascade;

-- ── 2) sales_history: возврат сілтемесі ──────────────────────────────────────
alter table public.sales_history add column if not exists return_id text default '';

-- ── 3) addresses: title → label (қосымша label жазады) ───────────────────────
do $$
begin
  if exists (select 1 from information_schema.columns
             where table_schema='public' and table_name='addresses' and column_name='title')
     and not exists (select 1 from information_schema.columns
             where table_schema='public' and table_name='addresses' and column_name='label')
  then
    alter table public.addresses rename column title to label;
  end if;
end $$;

-- ── 4) favorites: жетіспейтін бағандар + артық FK ────────────────────────────
alter table public.favorites
  add column if not exists product_name text default '',
  add column if not exists image_url text default '',
  add column if not exists admin_uid uuid,
  add column if not exists store_name text default '',
  add column if not exists price double precision default 0;
alter table public.favorites drop constraint if exists favorites_product_id_fkey;

-- ── 5) transfers: жаңа схема (sizes JSONB, бір жазба = бір трансфер) ─────────
alter table public.transfers
  add column if not exists product_name text default '',
  add column if not exists sizes jsonb not null default '{}',
  add column if not exists total_quantity integer not null default 0,
  add column if not exists performed_by uuid;
alter table public.transfers drop column if exists batch_id;
alter table public.transfers drop column if exists size;
alter table public.transfers drop column if exists quantity;

-- ── 6) users: жалпы блоктау (офлайн + онлайн) ────────────────────────────────
alter table public.users
  add column if not exists blocked boolean not null default false,
  add column if not exists block_reason text default '',
  add column if not exists blocked_at timestamptz,
  add column if not exists blocked_by text default '';

-- ── 7) RPC: ағымдағы қолданушының блок күйі ──────────────────────────────────
-- Seller иесінің users жолын RLS бойынша оқи алмайды — сондықтан SECURITY DEFINER.
-- source: 'self' = өзі блокталған; 'owner' = дүкен иесі блокталған (каскад).
create or replace function public.my_block_status()
returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce((
    select case
      when u.blocked then jsonb_build_object(
        'blocked', true, 'reason', coalesce(u.block_reason, ''), 'source', 'self')
      when o.blocked then jsonb_build_object(
        'blocked', true, 'reason', coalesce(o.block_reason, ''), 'source', 'owner')
      else jsonb_build_object('blocked', false)
    end
    from public.users u
    left join public.users o on o.id = u.owner_id and o.id <> u.id
    where u.id = auth.uid()
  ), jsonb_build_object('blocked', false));
$$;
grant execute on function public.my_block_status() to authenticated;
