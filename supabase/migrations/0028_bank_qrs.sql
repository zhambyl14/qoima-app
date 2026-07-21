-- 0028: Дүкен/өтінім/платформа банк QR сілтемелері (bank_qrs)
--
-- Идемпотентті, ҚАУІПСІЗ — тек бір JSONB баған қосады (әдепкі '{}').
-- Карта нөмірі орнына — банк QR сілтемелерінің картасы {bank_id: qr_link}.
-- Клиент төлемде осы QR-ды кәдімгі QR-код ретінде көреді (единый QR — кез
-- келген банк қосымшасы сканерлейді). Ескі kaspi_link — bank_qrs.kaspi ретінде
-- оқылады (кодта fallback), сол себепті ескі деректер бұзылмайды.
--
-- stores_select (is_published) арқылы клиентке бұрыннан қолжетімді бағандармен
-- бірге көрінеді — жаңа рұқсат керек емес.

alter table public.stores        add column if not exists bank_qrs jsonb not null default '{}'::jsonb;
alter table public.shop_requests add column if not exists bank_qrs jsonb not null default '{}'::jsonb;
