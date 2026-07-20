-- 0024: Төлем режимі (платформа/дүкен) + модератор барлық тапсырысты оқиды
--
-- Бұл миграция идемпотентті әрі ҚАУІПСІЗ — бар схемаға зиян тигізбейді.
-- Іс жүзінде жаңа баған/кесте керек емес: төмендегілердің бәрі бұрыннан бар
-- схемамен істейді. Бұл файл тек:
--   1) payment_mode кілтін app_settings-ке себеді (әдепкі 'platform');
--   2) orders_select policy-ін superadmin барлық тапсырысты оқитындай кепілдейді
--      (live DB дрейфіне қарсы — 0001-де солай болған, бірақ растап қоямыз).

-- ── 1) Төлем режимі кілті ───────────────────────────────────────────────────
-- 'platform' — барлық аударым модератор картасына (әдепкі, қазіргідей).
-- 'store'    — әр тапсырыс сол дүкеннің картасына; дүкенде карта болмаса —
--              модератор картасына (fallback). Superadmin «Реквизиты» экранынан
--              ауыстырады (app_settings_write = is_superadmin).
insert into public.app_settings(key, value) values
  ('payment_mode', 'platform')
on conflict (key) do nothing;

-- ── 2) Модератор (superadmin) БАРЛЫҚ онлайн-тапсырыстарды оқи алады ──────────
-- «Онлайн-продажи» панелі осыған сүйенеді (watchAllOnlineOrders). 0001-дегі
-- шарттың дәл өзін қайта жасаймыз — клиент өз тапсырысын, дүкен иесі өз
-- дүкенінің тапсырысын, superadmin бәрін көреді.
drop policy if exists orders_select on public.orders;
create policy orders_select on public.orders for select using (
  client_uid = auth.uid()
  or admin_uid = public.app_owner_uid()
  or public.is_superadmin()
);

-- Ескерту: дүкеннің төлем реквизиті (stores.payment_card_number/holder/bank)
-- 'store' режимінде клиентке көрінеді. Ол stores_select policy арқылы бұрыннан
-- қолжетімді (is_published = true) — жаңа рұқсат керек емес.
