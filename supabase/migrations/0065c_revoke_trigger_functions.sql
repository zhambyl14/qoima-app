-- ═══════════════════════════════════════════════════════════════════════════
--  0065c — триггер функцияларынан клиент EXECUTE құқығын алу (гигиена)
-- ═══════════════════════════════════════════════════════════════════════════
--  0065b-дан кейін тірі БД-да `anon`-ға ашық, авторизация тексерісі жоқ
--  SECURITY DEFINER функциялардың ішінде ~25 ТРИГГЕР функциясы қалды:
--  on_*_push (18), refresh_product_rating, refresh_store_rating,
--  fill_return_source_ref, notify_store_registered, check_broadcast_rate_limit.
--
--  Нақты тәуекел төмен: plpgsql триггер функциясын тікелей шақырғанда
--  Postgres «trigger functions can only be called as triggers» деп қабылдамайды.
--  Бірақ: (а) advisor тізімін шуылдан тазалайды, сондықтан ШЫН тесік көрінеді;
--         (б) «клиент рөлі триггер функциясын шақыра алмайды» деген нақты
--             инвариант орнатады.
--
--  Триггер орындалуында EXECUTE құқығы ТЕКСЕРІЛМЕЙДІ, сондықтан алу қауіпсіз.
--
--  ЕСКЕРТПЕ: жеке-жеке жазудың орнына `prorettype = 'trigger'` бойынша
--  циклмен жүрдік — келешекте жаңа триггер функциясы қосылса, осы миграцияны
--  қайта орындау жеткілікті (идемпотентті).
do $$
declare
  r record;
  n int := 0;
begin
  for r in
    select p.oid::regprocedure::text as sig
      from pg_proc p
      join pg_namespace ns on ns.oid = p.pronamespace
     where ns.nspname = 'public'
       and p.prorettype = 'pg_catalog.trigger'::regtype
  loop
    execute format('revoke execute on function %s from public, anon, authenticated', r.sig);
    n := n + 1;
  end loop;
  raise notice 'trigger functions locked down: %', n;
end;
$$;
