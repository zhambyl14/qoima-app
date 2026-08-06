-- ════════════════════════════════════════════════════════════════════════════
--  0042 · БАГ ТҮЗЕТУ: favorites-тың бұрынғы RLS саясаты (fav_rw, ALL, using
--  client_uid=auth.uid()) тек клиенттің ӨЗІНЕ рұқсат беретін — сол себепті
--  0038-де (getDemandSignals) admin/seller favorites-ты ешқашан оқи алмаған
--  (бос тізім, RLS үнсіз сүзіп тастайды). Дүкен иесіне/сатушыға ТЕК ОҚУ
--  рұқсатын қосамыз (client_uid жазу/өшіру құқығы дәл бұрынғыдай клиентте
--  қалады — бұл жаңа саясат тек SELECT).
-- ════════════════════════════════════════════════════════════════════════════

drop policy if exists fav_admin_read on public.favorites;
create policy fav_admin_read on public.favorites for select using (
  admin_uid = public.app_owner_uid() or public.is_superadmin()
);
