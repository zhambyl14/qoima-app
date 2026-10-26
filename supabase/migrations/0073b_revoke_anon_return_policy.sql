-- ════════════════════════════════════════════════════════════════════════
-- 0073b: қайтару ережесі RPC-лерінен anon грантын алу
--
-- Неге: тірі БД-ның default privileges жаңа функцияларға anon-ға EXECUTE
-- береді — 0073-тегі `revoke … from public` оны жаппады. Ішінде
-- is_superadmin()/app_owner_uid() тексерісі бар (anon бәрібір қате алады),
-- бірақ ереже бойынша бұлар тек authenticated-ке ашық болуы керек.
-- ════════════════════════════════════════════════════════════════════════
revoke execute on function public.set_store_non_returnable_permission(uuid, boolean) from public, anon;
revoke execute on function public.set_store_return_note(text) from public, anon;
grant execute on function public.set_store_non_returnable_permission(uuid, boolean) to authenticated;
grant execute on function public.set_store_return_note(text) to authenticated;
