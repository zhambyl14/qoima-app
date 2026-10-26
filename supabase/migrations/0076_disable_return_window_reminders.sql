-- ════════════════════════════════════════════════════════════════════════
-- 0076: «Қайтару мерзімі бітуге жақын» push еске салғышын өшіру
--
-- Неге: иесінің шешімі — клиентке «тауарды қайтаруға болады» деп еске
-- салу қайтарымды көбейтеді. 0062-дегі return-window-reminders cron-жобасы
-- алынады. Функция өзі қалады (зиянсыз, ешкім шақырмайды); 0062 қайта
-- қолданылса, cron қайта қосылмауы үшін функция енді ештеңе жібермейді.
-- ════════════════════════════════════════════════════════════════════════

select cron.unschedule('return-window-reminders')
  where exists (select 1 from cron.job where jobname = 'return-window-reminders');

create or replace function public.sweep_return_window_reminders() returns void
language plpgsql security definer set search_path = public as $$
begin
  -- 0076: әдейі бос — қайтару туралы push жіберілмейді.
  return;
end;
$$;
revoke all on function public.sweep_return_window_reminders() from public, anon, authenticated;
