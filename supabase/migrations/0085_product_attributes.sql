-- 0085 · Тауардың категорияға тән сипаттамалары (products.attributes)
--
-- Не өзгереді:
--  products.attributes jsonb — {кілт: мән} объектісі. Кілттер мен опциялар
--  қосымшадағы category_attributes.dart схемасында (телефонда жады/жағдайы,
--  кітапта автор/тілі, тағамда салмағы/жарамдылығы т.б.). DB мазмұнды
--  тексермейді (схема қосымшамен бірге өседі), тек пішін мен көлемді:
--   * тек JSON объект (массив/жол/сан емес);
--   * pg_column_size ≤ 4096 байт — бір тауардың сипаттамасы бірнеше жүз байт,
--     шек әдейі жаман клиенттің мегабайттық JSON жазуын тоқтатады.
--
-- Қауіпсіздік: жаңа функция ЖОҚ. Бағанды тек products-тың бар RLS саясаттары
-- қорғайды (иесі/сатушысы ғана жазады) — бұл артықшылықты баған емес (ақша,
-- рөл, статус емес), сондықтан бөлек BEFORE-триггер керек емес.
--
-- Тексерілген: products-тағы BEFORE триггерлер (set_product_articul,
-- clear_sold_out_on_stock, guard_products_non_returnable) жаңа бағанға тимейді;
-- search_catalog қайтаратын бағандар өзгермейді.
--
-- ⚠️ ҚОЛДАНУ ТӘРТІБІ: жаңа апп нұсқасынан БҰРЫН. Апп attributes-ті тек бос
--    болмаса жібереді, сондықтан миграциясыз БД-да сипаттамасыз тауарлар
--    сақтала береді, ал сипаттамасы бар тауар «белгісіз баған» қатесін береді.

alter table public.products
  add column if not exists attributes jsonb not null default '{}'::jsonb;

do $$
begin
  if not exists (
    select 1 from pg_constraint
     where conrelid = 'public.products'::regclass
       and conname = 'products_attributes_object'
  ) then
    alter table public.products
      add constraint products_attributes_object
      check (jsonb_typeof(attributes) = 'object');
  end if;

  if not exists (
    select 1 from pg_constraint
     where conrelid = 'public.products'::regclass
       and conname = 'products_attributes_size'
  ) then
    alter table public.products
      add constraint products_attributes_size
      check (pg_column_size(attributes) <= 4096);
  end if;
end $$;

comment on column public.products.attributes is
  'Категорияға тән сипаттамалар {key: value}; схема — lib/data/models/category_attributes.dart (0085)';
