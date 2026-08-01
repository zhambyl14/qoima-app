-- ════════════════════════════════════════════════════════════════════════════
--  0032 · Дүкен иесі онлайн-витринаны өшірсе — тауарлары/партиялары/тапсырыс
--  жасау мүлде қолжетімсіз болу керек (тек «В наличии» тізімдерден жасырылу
--  емес).
-- ────────────────────────────────────────────────────────────────────────────
--  Бұрын: products_read/batches_read RLS — `using (true)` (толық публичті,
--  stores.is_published-ге сілтеме жоқ). Flutter қабаты (stores_list_screen,
--  client_home_screen, store_public_screen) is_published бойынша сүзеді, БІРАҚ
--  бұл тек әдепкі тізім экрандарын қорғайды — Supabase API-ге тікелей сұраныс
--  (product id/owner_uid бойынша) жасырын дүкеннің тауарын/қалдығын әлі де
--  қайтара береді, ал orders_insert де мақсатты дүкен жарияланған ба — тексер-
--  мейді. Сол себепті клиент жасырын дүкеннің тауарын себетке қоса алады да,
--  тек checkout-та «бітіп қалған» деп естиді — ал шын мәнінде дерек деңгейінде
--  ешқашан жасырылмаған.
--
--  Түзету: products_read/batches_read/orders_insert енді ИЕСІНІҢ дүкені
--  (stores.is_published=true, status<>'blocked') болғанда ғана публичті оқуға
--  рұқсат етеді. Иесінің/сатушысының өз оқуы (owner_uid=app_owner_uid()) және
--  superadmin бұрынғыдай толық қол жеткізеді — ішкі экрандар өзгеріссіз.
--  Бұл сонымен қатар «дүкен деңгейі өшірулі болса — қойма/тауар деңгейіндегі
--  көрінбейтін-емес toggle-дар маңызды емес» талабын автоматты орындайды:
--  is_published=false болса — БАРЛЫҚ клиенттік жол (browse/іздеу/сілтеме/
--  себет/checkout) дерек деңгейінде жабылады.
-- ════════════════════════════════════════════════════════════════════════════

drop policy if exists products_read on public.products;
create policy products_read on public.products for select using (
  owner_uid = public.app_owner_uid()
  or public.is_superadmin()
  or (
    storefront_hidden = false
    and exists (
      select 1 from public.stores s
      where s.admin_uid = products.owner_uid
        and s.is_published = true
        and s.status <> 'blocked'
    )
  )
);

drop policy if exists batches_read on public.batches;
create policy batches_read on public.batches for select using (
  owner_uid = public.app_owner_uid()
  or public.is_superadmin()
  or exists (
    select 1 from public.stores s
    where s.admin_uid = batches.owner_uid
      and s.is_published = true
      and s.status <> 'blocked'
  )
);

drop policy if exists orders_insert on public.orders;
create policy orders_insert on public.orders for insert with check (
  client_uid = auth.uid()
  and exists (
    select 1 from public.stores s
    where s.admin_uid = orders.admin_uid
      and s.is_published = true
      and s.status <> 'blocked'
  )
);
