-- ════════════════════════════════════════════════════════════════════════════
--  0035 · Артикул реттік санауышы + тауар карточкасының қаралым саны
-- ────────────────────────────────────────────────────────────────────────────
--  1) Артикул: бұрын Flutter жағында продукт id-нің алғашқы 6 hex-символынан
--     ('QM-XXXXXX') жасалатын, GLOBAL UNIQUE емес еді (16^6 ≈ 16.7 млн нұсқа,
--     ~4-5 мың тауарда қақтығыс ықтималдығы жоғарылайды). Енді БД-де жалғыз
--     реттік санауыш арқылы жасалады — ешқашан таусылмайды, әрқашан қайталан-
--     байды. INSERT кезінде articul бос болса ғана орнатылады (Flutter енді
--     articul: '' жібереді, өзі тағайындамайды — lib/data/services/
--     firestore_service.dart addNewProduct).
--
--  2) product_views: тауар карточкасын клиент/қонақ ашқанда қаралым санын
--     ұлғайту үшін SECURITY DEFINER RPC (клиенттердің products-қа тікелей
--     UPDATE құқығы жоқ, products_write RLS admin_uid бойынша ғана рұқсат
--     береді — 0001_initial_schema.sql:634).
--
--  3) sweep_returned_photos: клиент қайтару (возврат) кезінде қосқан фото-
--     лар (returns.photo_urls/condition_photos) толық аяқталғаннан
--     (status='refunded') 1-2 күн өткен соң Cloudinary-ден өшіріледі —
--     0007_cloudinary_image_gc.sql-дегі cloudinary_delete_queue/drain
--     тетігін қайта пайдаланады.
-- ════════════════════════════════════════════════════════════════════════════

-- ── 1) Артикул реттік санауышы ────────────────────────────────────────────────
create sequence if not exists public.articul_seq;

create or replace function public.set_product_articul()
returns trigger
language plpgsql as $$
begin
  if new.articul is null or new.articul = '' then
    new.articul := 'QM-' || lpad(nextval('public.articul_seq')::text, 7, '0');
  end if;
  return new;
end;
$$;

drop trigger if exists products_set_articul_trg on public.products;
create trigger products_set_articul_trg
  before insert on public.products
  for each row execute function public.set_product_articul();

-- ── 2) Тауар қаралым саны ─────────────────────────────────────────────────────
alter table public.products
  add column if not exists view_count integer not null default 0;

create or replace function public.increment_product_view(p_product uuid)
returns void
language plpgsql security definer set search_path = public as $$
begin
  update public.products set view_count = view_count + 1 where id = p_product;
end;
$$;
grant execute on function public.increment_product_view(uuid) to authenticated, anon;

-- ── 3) Аяқталған қайтару фотоларын тазалау ────────────────────────────────────
create or replace function public.sweep_returned_photos(p_days int default 1)
returns int
language plpgsql security definer set search_path = public as $$
declare v_count int := 0;
begin
  insert into public.cloudinary_delete_queue(url)
  select unnest(r.photo_urls || r.condition_photos)
    from public.returns r
   where r.status = 'refunded'
     and r.refunded_at is not null
     and r.refunded_at < now() - make_interval(days => p_days)
     and (coalesce(array_length(r.photo_urls, 1), 0) > 0
          or coalesce(array_length(r.condition_photos, 1), 0) > 0);
  get diagnostics v_count = row_count;

  update public.returns r
     set photo_urls = '{}', condition_photos = '{}'
   where r.status = 'refunded'
     and r.refunded_at is not null
     and r.refunded_at < now() - make_interval(days => p_days)
     and (coalesce(array_length(r.photo_urls, 1), 0) > 0
          or coalesce(array_length(r.condition_photos, 1), 0) > 0);

  return v_count;
end;
$$;
revoke all on function public.sweep_returned_photos(int) from public, authenticated;
