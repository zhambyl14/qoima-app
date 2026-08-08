-- ════════════════════════════════════════════════════════════════════════════
--  ТЕКСЕРУ: 0037–0051 миграцияларының қайсысы live DB-ға ҚОЛДАНЫЛҒАН?
-- ────────────────────────────────────────────────────────────────────────────
--  SQL Editor-дағы «Private queries» тізімі — тек САҚТАЛҒАН сұраныстар,
--  қолданылған миграциялардың тізімі ЕМЕС. Сұранысты сақтамай «Run» бассаң,
--  схема өзгереді де, тізімде із қалмайды. Сондықтан жалғыз шындық көзі —
--  базаның каталогтары (төмендегі сұраныс соларды оқиды).
--
--  ЕШТЕҢЕ ӨЗГЕРТПЕЙДІ — тек оқиды. Бүтіндей көшіріп, Run басу қауіпсіз.
-- ════════════════════════════════════════════════════════════════════════════

with checks(mig, obj, ok) as (values

  -- 0037 · sweep_returned_photos-қа grant
  ('0037', 'grant sweep_returned_photos', (select coalesce((
      select has_function_privilege('authenticated',
             'public.sweep_returned_photos(int)', 'execute')
      where exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                     where n.nspname = 'public' and p.proname = 'sweep_returned_photos')
    ), false))),

  -- 0038 · дүкен рейтингі
  ('0038', 'stores.rating_avg', (select exists(select 1 from information_schema.columns
     where table_schema='public' and table_name='stores' and column_name='rating_avg'))),
  ('0038', 'trigger product_reviews_store_rating', (select exists(select 1 from pg_trigger
     where tgname='product_reviews_store_rating' and not tgisinternal))),

  -- 0039 · қойма гео шектеуі
  ('0039', 'constraint warehouses_geo_within_kz', (select exists(select 1 from pg_constraint
     where conname='warehouses_geo_within_kz'))),

  -- 0040 · мекенжай координаттары
  ('0040', 'addresses.lat', (select exists(select 1 from information_schema.columns
     where table_schema='public' and table_name='addresses' and column_name='lat'))),

  -- 0041 · «қайта түсті» пушы
  ('0041', 'fn on_batch_restock_push', (select exists(select 1 from pg_proc p
     join pg_namespace n on n.oid=p.pronamespace
     where n.nspname='public' and p.proname='on_batch_restock_push'))),
  ('0041', 'trigger trg_batch_restock_push', (select exists(select 1 from pg_trigger
     where tgname='trg_batch_restock_push' and not tgisinternal))),

  -- 0042 · таңдаулыларды дүкен иесі оқиды
  ('0042', 'policy fav_admin_read', (select exists(select 1 from pg_policies
     where schemaname='public' and tablename='favorites' and policyname='fav_admin_read'))),

  -- 0043 · дүкен таратылымы
  ('0043', 'table store_broadcasts', (select to_regclass('public.store_broadcasts') is not null)),

  -- 0044 · «Досыңды шақыр» ⚠️ 0049 ОСЫҒАН ТӘУЕЛДІ
  ('0044', 'stores.referral_percent', (select exists(select 1 from information_schema.columns
     where table_schema='public' and table_name='stores' and column_name='referral_percent'))),
  ('0044', 'promos.referral_owner_uid', (select exists(select 1 from information_schema.columns
     where table_schema='public' and table_name='promos' and column_name='referral_owner_uid'))),
  ('0044', 'fn get_or_create_referral_code', (select exists(select 1 from pg_proc p
     join pg_namespace n on n.oid=p.pronamespace
     where n.nspname='public' and p.proname='get_or_create_referral_code'))),

  -- 0045 · пікір еске салу + күнделікті қорытынды
  ('0045', 'orders.completed_at', (select exists(select 1 from information_schema.columns
     where table_schema='public' and table_name='orders' and column_name='completed_at'))),
  ('0045', 'fn sweep_daily_digest', (select exists(select 1 from pg_proc p
     join pg_namespace n on n.oid=p.pronamespace
     where n.nspname='public' and p.proname='sweep_daily_digest'))),

  -- 0046 · тауар сұрақтары
  ('0046', 'table product_questions', (select to_regclass('public.product_questions') is not null)),
  ('0046', 'fn answer_product_question', (select exists(select 1 from pg_proc p
     join pg_namespace n on n.oid=p.pronamespace
     where n.nspname='public' and p.proname='answer_product_question'))),

  -- 0047 · сұрақ антиспам
  ('0047', 'index product_questions_client_admin_pending_uidx', (select exists(
     select 1 from pg_indexes where schemaname='public'
      and indexname='product_questions_client_admin_pending_uidx'))),

  -- 0048 · клиент өз сұрағын өзгертеді
  ('0048', 'policy product_questions_update', (select exists(select 1 from pg_policies
     where schemaname='public' and tablename='product_questions'
       and policyname='product_questions_update'))),

  -- ── ЖАҢАЛАРЫ (әлі қолданылмаған болуы тиіс) ──────────────────────────────
  ('0049', 'fn my_referral_stores', (select exists(select 1 from pg_proc p
     join pg_namespace n on n.oid=p.pronamespace
     where n.nspname='public' and p.proname='my_referral_stores'))),

  ('0050', 'fn delivery_tariff', (select exists(select 1 from pg_proc p
     join pg_namespace n on n.oid=p.pronamespace
     where n.nspname='public' and p.proname='delivery_tariff'))),
  ('0050', 'orders.fitting_fee', (select exists(select 1 from information_schema.columns
     where table_schema='public' and table_name='orders' and column_name='fitting_fee'))),
  ('0050', 'setting delivery_base_fee', (select exists(
     select 1 from public.app_settings where key='delivery_base_fee'))),

  ('0051', 'users.courier_status', (select exists(select 1 from information_schema.columns
     where table_schema='public' and table_name='users' and column_name='courier_status'))),
  ('0051', 'orders.courier_uid', (select exists(select 1 from information_schema.columns
     where table_schema='public' and table_name='orders' and column_name='courier_uid'))),
  ('0051', 'fn courier_take_order', (select exists(select 1 from pg_proc p
     join pg_namespace n on n.oid=p.pronamespace
     where n.nspname='public' and p.proname='courier_take_order')))
)
select
  mig                                        as "Миграция",
  obj                                        as "Объект",
  case when ok then '✅ БАР' else '❌ ЖОҚ' end as "Күйі"
from checks
order by mig, obj;
