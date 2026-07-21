-- 0026: Қонақ (anon) промокодты тексере алады
--
-- Мәселе: promos_read policy тек `authenticated`-ке рұқсат берген. Гест
-- (кірмеген) себетте промокод жазғанда SELECT бос қайтып, «табылмады» деп
-- шыққан. Гест те тауар таңдап, промокодты тексере алуы керек (checkout кезінде
-- логин сұралады; промокодтың per-user лимиті сол жерде — тапсырыс жасауда —
-- тексеріледі).
--
-- Қауіпсіздік: promos_read бұрыннан `using (true)` — кез келген authenticated
-- клиент кез келген дүкеннің промосын оқи алатын. Anon-ды қосу сол ұстанымды
-- сақтайды (промокод — маркетинг, құпия емес). Идемпотентті.

drop policy if exists promos_read on public.promos;
create policy promos_read on public.promos
  for select to anon, authenticated using (true);
