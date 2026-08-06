-- ════════════════════════════════════════════════════════════════════════════
--  0036 · Қойма координаттары (lat/lng) — «Магазины» картасы (Yandex MapKit)
-- ────────────────────────────────────────────────────────────────────────────
--  Клиент өз қаласындағы дүкендерді картадан көре алуы үшін — тек ВИТРИНАДА
--  көрінетін (stores.visible_warehouse_ids) қоймалардың координаттары ғана
--  клиентке ашылады (жасырын қоймалардың орны/бар-жоғы жарияланбайды).
--
--  Бұл сонымен қатар ЕСКІ wh_read = using(true) саясатын тарылтады — бұрын
--  warehouses кестесі толық публичті оқылатын (0032 миграциясы products/
--  batches-ті тарылтқанда warehouses ұмытылып қалған еді).
-- ════════════════════════════════════════════════════════════════════════════

alter table public.warehouses
  add column if not exists lat double precision,
  add column if not exists lng double precision;

drop policy if exists wh_read on public.warehouses;
create policy wh_read on public.warehouses for select using (
  owner_uid = public.app_owner_uid()
  or public.is_superadmin()
  or exists (
    select 1 from public.stores s
    where s.admin_uid = warehouses.owner_uid
      and s.is_published = true
      and s.status <> 'blocked'
      and warehouses.id::text = any(s.visible_warehouse_ids)
  )
);
