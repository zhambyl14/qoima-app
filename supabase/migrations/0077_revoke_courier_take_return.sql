-- ════════════════════════════════════════════════════════════════════════
-- 0077: courier_take_return — PUBLIC/anon грантын жабу
--
-- Неге: 0065 аудитінен тыс қалған — тірі БД-да `=X/` (PUBLIC) және anon
-- EXECUTE бар. Ішінде active_courier_city() тексерісі бар (anon бәрібір
-- not_active_courier алады), бірақ ереже бойынша тек authenticated.
-- ════════════════════════════════════════════════════════════════════════
revoke execute on function public.courier_take_return(text) from public, anon;
grant execute on function public.courier_take_return(text) to authenticated;
