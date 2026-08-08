-- ════════════════════════════════════════════════════════════════════════════
--  0050 · Жеткізу тарифі (ақылы, бірақ арзан) + «Өлшеп көру» (қосымша өлшем)
-- ────────────────────────────────────────────────────────────────────────────
--  1) ТАРИФ. Бұрын жеткізу аппта ТЕГІН еді (client_cart_screen: deliveryFee =
--     0.0 хардкод) — жол шығыны ешқашан жабылмайтын. Енді тариф app_settings-те
--     тұрады, superadmin «Реквизиты» экранынан өзгертеді:
--       delivery_base_fee            — қала ішіндегі базалық ақы
--       delivery_reduced_fee         — үлкен чекке арналған төмендетілген ақы
--       delivery_reduced_from        — осы сомадан асқанда reduced_fee қолданылады
--       delivery_extra_store_percent — 2-ші, 3-ші дүкеннен алу (%-бен, базадан)
--       delivery_fitting_fee         — «өлшеп көру» қосымша ақысы
--       delivery_fitting_max_items   — бір тапсырыста қанша позицияға рұқсат
--     ЕШҚАШАН 0 болмайды: «тегін жеткізу» негізсіз бас тартуларды көбейтеді.
--
--  2) ӨЛШЕП КӨРУ. Клиент 38-ді тапсырыс береді, курьер 39-ды ДА алып барады.
--     Ақшасы тек 38 үшін төленеді; 39 қоймада БРОНЬДАЛАДЫ (reserved_sizes),
--     әйтпесе курьер жолда келе жатқанда оны басқа біреу сатып алар еді.
--     Клиент 39-ды алса — курьер своп жасайды (0051: courier_complete_order):
--     38 қоймаға қайтады, 39 сатылады. Бағасы бірдей (сол тауар, сол партия) —
--     ақша қозғалмайды.
--
--     Қосымша өлшем orders.items JSONB ішінде `altSize` кілтімен сақталады —
--     жаңа кесте/баған керек емес, бүкіл қолданыстағы логика бұзылмайды.
-- ════════════════════════════════════════════════════════════════════════════

-- ── 1) Тариф кілттері (әдепкі мәндер — Dart жағындағы DeliveryTariff-пен бірдей)
insert into public.app_settings(key, value) values
  ('delivery_base_fee',            '690'),
  ('delivery_reduced_fee',         '390'),
  ('delivery_reduced_from',        '15000'),
  ('delivery_extra_store_percent', '50'),
  ('delivery_fitting_fee',         '300'),
  ('delivery_fitting_max_items',   '2')
on conflict (key) do nothing;

-- app_settings оқуы `to authenticated` (0022) — ал себетті ҚОНАҚ та ашады.
-- Тарифті бөлек, публичті RPC арқылы береміз (реквизиттер ашылмайды).
create or replace function public.delivery_tariff()
returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_object_agg(key, value)
    from public.app_settings
   where key like 'delivery\_%';
$$;
grant execute on function public.delivery_tariff() to anon, authenticated;

-- ── 2) Тапсырыстағы «өлшеп көру» ақысы (delivery_fee-ден бөлек есептеледі —
--       аналитикада «жеткізу» мен «примерка» табысы шатаспауы үшін).
alter table public.orders
  add column if not exists fitting_fee numeric not null default 0;

-- ── 3) Бронь босату: тапсырыс аяқталғанда/болдырылғанда қалған «өлшеп көру»
--       бронін қайтарады. Курьер де (0051), дүкен де (Dart) шақырады —
--       бір ғана ақиқат көзі болуы үшін осында.
--       p_except_index — своп жасалған позициялар (олардың броні сатылымға
--       айналған, қайта босатылмайды).
create or replace function public.release_fitting_holds(
  p_order uuid,
  p_except_index integer[] default '{}'
) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_order public.orders;
  v_items jsonb;
  v_item  jsonb;
  v_alt   text;
  i       integer;
begin
  select * into v_order from public.orders where id = p_order;
  if not found then return; end if;

  -- SECURITY DEFINER — сондықтан шақырушының осы тапсырысқа қатысы бар-жоғын
  -- ӨЗІМІЗ тексереміз (әйтпесе кез келген клиент бөтен тапсырыстың бронін
  -- босата алар еді).
  -- (0051 бұл функцияны курьерді де қосып қайта жасайды.)
  if not (
    v_order.client_uid = auth.uid()
    or v_order.admin_uid = auth.uid()
    or v_order.admin_uid = public.app_owner_uid()
    or public.is_superadmin()
  ) then
    raise exception 'not_your_order';
  end if;

  v_items := v_order.items;
  if v_items is null then return; end if;

  for i in 0 .. jsonb_array_length(v_items) - 1 loop
    if i = any(p_except_index) then continue; end if;
    v_item := v_items -> i;
    v_alt  := coalesce(v_item ->> 'altSize', '');
    if v_alt = '' then continue; end if;
    begin
      perform public.adjust_batch_sizes(
        (v_item ->> 'batchId')::uuid,
        jsonb_build_object(v_alt, -coalesce((v_item ->> 'qty')::int, 1)),
        'reserved_sizes',
        false);
    exception when others then
      null; -- партия өшірілген болуы мүмкін — тапсырысты жабу бөгелмейді
    end;
  end loop;
end;
$$;
grant execute on function public.release_fitting_holds(uuid, integer[]) to authenticated;
