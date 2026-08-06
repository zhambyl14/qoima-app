-- ════════════════════════════════════════════════════════════════════════════
--  0038 · Дүкен деңгейіндегі денормализацияланған рейтинг (stores.rating_avg/
--  rating_count) — «Магазины» картасындағы қалқымалы карточкада көрсету үшін.
--  product_reviews.admin_uid дүкен иесіне ТІКЕЛЕЙ сілтейді (0015), сол
--  себепті products арқылы join керек емес — 0015-тегі
--  refresh_product_rating() үлгісі бойынша.
-- ════════════════════════════════════════════════════════════════════════════

alter table public.stores
  add column if not exists rating_avg   double precision not null default 0,
  add column if not exists rating_count integer          not null default 0;

create or replace function public.refresh_store_rating()
returns trigger
language plpgsql security definer set search_path = public as $$
declare uid uuid;
begin
  uid := coalesce(new.admin_uid, old.admin_uid);
  update public.stores s set
    rating_avg = coalesce(
      (select round(avg(r.rating)::numeric, 2)::double precision
         from public.product_reviews r where r.admin_uid = uid), 0),
    rating_count = coalesce(
      (select count(*) from public.product_reviews r
         where r.admin_uid = uid), 0)
  where s.admin_uid = uid;
  return null;
end;
$$;

drop trigger if exists product_reviews_store_rating on public.product_reviews;
create trigger product_reviews_store_rating
  after insert or update or delete on public.product_reviews
  for each row execute function public.refresh_store_rating();

-- Бар пікірлер бойынша бір реттік backfill (жаңа баған әдепкі 0-мен келеді).
update public.stores s set
  rating_avg = coalesce(
    (select round(avg(r.rating)::numeric, 2)::double precision
       from public.product_reviews r where r.admin_uid = s.admin_uid), 0),
  rating_count = coalesce(
    (select count(*) from public.product_reviews r
       where r.admin_uid = s.admin_uid), 0);
