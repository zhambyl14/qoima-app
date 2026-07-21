-- 0025: Товар «айырмашылық белгісі» (variant_note) + дүкен Kaspi сілтемесі
--
-- Идемпотентті әрі ҚАУІПСІЗ — тек екі жаңа мәтін баған қосады (әдепкі '').
-- Ескі жолдарға әсер жоқ, RLS өзгермейді.
--
--   1) products.variant_note — бір модельдің ұсақ айырмашылығы (мыс. «қара
--      табан», «гүлі бар»). findMatchingProduct кимлікке қосады → әр түрлі
--      белгі = БӨЛЕК товар (повторный завоз емес). Клиент detail-де нұсқа
--      ауыстырғышта көрінеді.
--   2) stores.kaspi_link — дүкеннің Kaspi QR сілтемесі. Клиент төлемде негізгі
--      «Kaspi арқылы төлеу» батырмасы; карта нөмірі — қосымша (астында).
--      stores_select policy (is_published) арқылы клиентке бұрыннан қолжетімді
--      бағандармен бірге көрінеді — жаңа рұқсат керек емес.

alter table public.products      add column if not exists variant_note text not null default '';
alter table public.stores        add column if not exists kaspi_link   text not null default '';
-- Дүкен иесі өтінімде/өңдеуде енгізетін Kaspi сілтемесі → бекітілгенде stores-ке көшеді.
alter table public.shop_requests add column if not exists kaspi_link   text not null default '';
R