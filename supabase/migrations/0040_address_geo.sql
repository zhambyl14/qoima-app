-- ════════════════════════════════════════════════════════════════════════════
--  0040 · Клиент мекенжайының координаттары (lat/lng) — «Магазины» тізімінде
--  «Сізге ең жақын дүкен» ұсынысы үшін (warehouses.lat/lng — 0036/0039 үлгісі
--  бойынша, дәл сол ҚР шекарасымен шектеледі).
-- ════════════════════════════════════════════════════════════════════════════

alter table public.addresses
  add column if not exists lat double precision,
  add column if not exists lng double precision;

alter table public.addresses
  drop constraint if exists addresses_geo_within_kz;

alter table public.addresses
  add constraint addresses_geo_within_kz check (
    (lat is null and lng is null)
    or (lat between 40.5 and 55.6 and lng between 46.2 and 87.5)
  );
