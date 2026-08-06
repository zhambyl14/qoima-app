-- ════════════════════════════════════════════════════════════════════════════
--  0037 · sweep_returned_photos грантын түзету (0035-те қате REVOKE қойылған)
-- ────────────────────────────────────────────────────────────────────────────
--  ✅ 2026-08-06 базаға MCP арқылы қолданылды.
--
--  0035_articul_seq_and_product_views.sql sweep_sold_out_images (0007)
--  үлгісін көшірген — сол функция ТЕК cron/service_role арқылы шақырылады,
--  сол себепті одан REVOKE дұрыс. Бірақ sweep_returned_photos керісінше —
--  ReturnService.sweepReturnedPhotos() арқылы админ қосымшасынан ТІКЕЛЕЙ,
--  authenticated ретінде шақырылады (admin_shell.dart initState). REVOKE
--  осыны бұғаттап, RPC 403 Forbidden қайтаратын.
-- ════════════════════════════════════════════════════════════════════════════

grant execute on function public.sweep_returned_photos(int) to authenticated;
