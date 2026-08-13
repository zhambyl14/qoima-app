-- ═══════════════════════════════════════════════════════════════════════════
--  0065b — `revoke … from anon` ЖЕТКІЛІКСІЗ: PUBLIC грантын алу
-- ═══════════════════════════════════════════════════════════════════════════
--  0065-те `revoke execute on function … from anon` жазылды, бірақ қолданған
--  соң тексергенде `has_function_privilege('anon', …, 'EXECUTE')` ӘЛІ де true
--  болып шықты. Себебі: Postgres жаңа функцияға әдепкіде `EXECUTE TO PUBLIC`
--  береді, ал PUBLIC — anon-ды да қамтиды. ACL-де ол `=X/postgres` болып
--  көрінеді (рөл аты жоқ «=» = PUBLIC).
--
--  Демек нақты рөлден алу ЕШНӘРСЕ бермейді, PUBLIC гранты орнында қалса.
--  Дұрысы — PUBLIC-тен алу, керек рөлдерге нақты grant қалдыру.
--
--  ⚠️ ЕРЕЖЕ (guardrail): `create or replace function` ӘРҚАШАН PUBLIC грантын
--     қайта тудырады. Сондықтан функцияны қайта жазған соң `revoke … from
--     public` -ты ҚАЙТА орындау керек, әйтпесе тесік үнсіз ашылып қалады.
--     Тексеру: `select proacl from pg_proc where proname='…'` — `=X/` жоқ болуы тиіс.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── A топ: Dart тікелей шақырады → `authenticated` МІНДЕТТІ қалады ──────────
--  Бұл функциялардың ACL-інде `authenticated=X` және `service_role=X` нақты
--  жазылған, сондықтан PUBLIC-ті алу оларға тимейді — тек anon шығып қалады.
revoke execute on function public.adjust_batch_sizes(uuid, jsonb, text, boolean) from public;
revoke execute on function public.claim_order_transition(uuid, text[], text, text, text, text) from public;
revoke execute on function public.next_counter(uuid, text) from public;
revoke execute on function public.increment_warehouse_totals(uuid, integer, integer) from public;
revoke execute on function public.adjust_promo_usage(uuid, uuid, integer) from public;
revoke execute on function public.recompute_product_status(uuid) from public;
revoke execute on function public.release_fitting_holds(uuid, integer[]) from public;
revoke execute on function public.store_handover_fitting(uuid, integer[]) from public;
revoke execute on function public.store_confirm_return_leg(uuid) from public;
revoke execute on function public.get_or_create_referral_code(uuid) from public;
revoke execute on function public.my_referral_stores() from public;
revoke execute on function public.superadmin_set_courier(uuid, text, text) from public;

-- ── B топ: тек триггер/service_role → клиенттің ЕШҚАЙСЫСЫ шақырмайды ────────
--  `service_role=X` нақты жазылған, сондықтан edge function-дар (admin client)
--  жұмысын жалғастырады. Триггер орындалуында EXECUTE тексерілмейді.
revoke execute on function public.notify_push(uuid[], text, text, jsonb) from public;
revoke execute on function public.handle_new_user() from public;
revoke execute on function public.rls_auto_enable() from public;
revoke execute on function public.auto_confirm_email() from public;
revoke execute on function public.guard_courier_order_lock() from public;
revoke execute on function public.sweep_expired_receipts(integer) from public;
revoke execute on function public.sweep_daily_digest() from public;
revoke execute on function public.sweep_review_reminders() from public;
revoke execute on function public.sweep_reservation_reminders() from public;
revoke execute on function public.sweep_subscription_expiry_reminders() from public;

-- ── C топ: sweep_returned_photos — PUBLIC жоқ, бірақ anon НАҚТЫ берілген ────
--  Dart-тан шақырылады (return_service.dart:50), бірақ ол әрқашан кірген
--  пайдаланушының контексті — anon керек емес.
revoke execute on function public.sweep_returned_photos(integer) from anon;
