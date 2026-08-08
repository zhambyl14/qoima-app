-- ════════════════════════════════════════════════════════════════════════════
--  0054 · Курьермен возврат: мекенжай мен дүкен мәліметі курьерге көрінеді
-- ────────────────────────────────────────────────────────────────────────────
--  МӘСЕЛЕ: 0052-де курьермен қайтару RPC-лері жасалды, бірақ `returns` кестесінде
--  клиенттің МЕКЕНЖАЙЫ жоқ әрі дүкеннің аты/қойма мекенжайы басқа кестеде.
--  Курьер «қайдан алып, қайда апарамын?» дегенді біле алмайтын — сондықтан
--  бұл ағын іс жүзінде жұмыс істемейтін.
--
--  ШЕШІМ:
--   1) returns.pickup_address — клиент қайтару сұрағанда енгізетін мекенжай
--      (курьер сол жерден алады). Өзі апаратын болса — бос қалады.
--   2) courier_available_returns / courier_my_returns енді jsonb қайтарады:
--      жолға дүкен аты, қойма мекенжайы мен телефоны ҚОСЫЛАДЫ.
-- ════════════════════════════════════════════════════════════════════════════

alter table public.returns
  add column if not exists pickup_address text not null default '';

-- ── Курьерге арналған байытылған жол ────────────────────────────────────────
--  returns.* + дүкен аты/телефоны + қойма мекенжайы. Курьер екі нүктені де
--  көреді: клиенттен алу (pickup_address) → дүкенге апару (warehouse_address).
create or replace function public.courier_return_row(r public.returns)
returns jsonb
language sql stable security definer set search_path = public as $$
  select to_jsonb(r)
    || jsonb_build_object(
         'store_name', coalesce((select s.store_name from public.stores s
                                  where s.admin_uid = r.admin_uid), ''),
         'store_phone', coalesce((select s.phone from public.stores s
                                   where s.admin_uid = r.admin_uid), ''),
         -- Қойма мекенжайы; қойма көрсетілмесе — дүкеннің мекенжайы.
         'warehouse_address', coalesce(
             nullif((select w.address from public.warehouses w
                      where w.id = r.warehouse_id), ''),
             (select s.address from public.stores s
               where s.admin_uid = r.admin_uid),
             ''));
$$;

drop function if exists public.courier_available_returns();
create or replace function public.courier_available_returns()
returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(public.courier_return_row(r) order by r.created_at),
                  '[]'::jsonb)
    from public.returns r
    join public.stores s on s.admin_uid = r.admin_uid
   where r.pickup = 'courier'
     and r.status = 'approved'
     and r.courier_uid is null
     and public.active_courier_city() is not null
     and s.city = public.active_courier_city();
$$;
grant execute on function public.courier_available_returns() to authenticated;

drop function if exists public.courier_my_returns();
create or replace function public.courier_my_returns()
returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(public.courier_return_row(r)
                    order by (r.courier_status <> 'delivered') desc,
                             r.created_at desc),
                  '[]'::jsonb)
    from public.returns r
   where r.courier_uid = auth.uid()
     and (r.courier_status <> 'delivered'
          or r.created_at > now() - interval '30 days');
$$;
grant execute on function public.courier_my_returns() to authenticated;
