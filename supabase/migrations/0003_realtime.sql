-- ════════════════════════════════════════════════════════════════════════════
--  Qoima · Realtime қосу (Flutter `.stream()` тірі жаңаруы үшін)
-- ────────────────────────────────────────────────────────────────────────────
--  Supabase-те жаңа кестелер ӘДЕПКІ realtime бермейді. `.stream()` қолданатын
--  әр кестені `supabase_realtime` публикациясына қосамыз (RLS сақталады).
-- ════════════════════════════════════════════════════════════════════════════

alter publication supabase_realtime add table public.products;
alter publication supabase_realtime add table public.batches;
alter publication supabase_realtime add table public.sales_history;
alter publication supabase_realtime add table public.warehouses;
alter publication supabase_realtime add table public.promos;
alter publication supabase_realtime add table public.orders;
alter publication supabase_realtime add table public.reservations;
alter publication supabase_realtime add table public.users;
alter publication supabase_realtime add table public.join_requests;
alter publication supabase_realtime add table public.transfers;
alter publication supabase_realtime add table public.stores;
alter publication supabase_realtime add table public.returns;
alter publication supabase_realtime add table public.courier_deliveries;
alter publication supabase_realtime add table public.banners;
alter publication supabase_realtime add table public.store_discounts;
alter publication supabase_realtime add table public.favorites;
alter publication supabase_realtime add table public.addresses;
alter publication supabase_realtime add table public.shop_requests;
alter publication supabase_realtime add table public.store_edit_requests;
