-- ════════════════════════════════════════════════════════════════════════════
--  0057 · Төрт нақты қате түзетіледі
-- ────────────────────────────────────────────────────────────────────────────
--  A) ҚОС ВОЗВРАТ. Админ мен сатушы бір возратты бір мезгілде «қабылдадым»
--     деп басса, қойма ЕКІ РЕТ артатын (1 дана → 3 дана). Себебі: Dart
--     жағындағы `completeRefund` алдымен status-ты ОҚИТЫН, сосын жазатын —
--     екеуі де «refunded емес» дегенді көріп, екеуі де толық қайтаруды
--     орындайтын. Read-then-write жарысын код деңгейінде жеңу мүмкін емес.
--     Енді бүкіл операция БІР транзакцияда, жол құлпымен (`for update`)
--     жүреді: екіншісі құлыпты күтіп, статусты 'refunded' деп көреді де,
--     ЕШТЕҢЕ істемей қайтады.
--
--  B) ҚАЛА БОЙЫНША КУРЬЕР. Бұрын БОС тізім = «барлық қалада қосулы» еді.
--     Дұрысы керісінше: модератор қаланы өзі белгілемейінше курьер ЕШҚАЙДА
--     жұмыс істемейді (тізім бос → жеткізуді дүкен өзі ұйымдастырады).
--
--  C) БІР КЛИЕНТ · ЕКІ ДҮКЕН. Себет дүкен/қойма бойынша бөлінеді де, курьерге
--     екі БӨЛЕК тапсырыс болып көрінетін — біреуін алып, екіншісін басқа
--     курьер алып кетуі мүмкін еді, ал мекенжай біреу. Енді бір төлемнен
--     шыққан суб-тапсырыстар `cart_group_id`-мен байланысады да, курьер
--     оларды БІРГЕ алады (әр дүкеннің коды бөлек қалады).
--
--  D) ПОВТОРНЫЙ ЗАВОЗ. «Прошлый завоз» деп партияның ҚАЗІРГІ қалдығы
--     көрсетілетін (сатылғаны шегерілген). Енді партияның КЕЛГЕН САНЫ
--     (`sizes_initial`) бөлек сақталады — «алдыңғы жолы қанша әкелдім»
--     деген сұрақтың жауабы сол.
-- ════════════════════════════════════════════════════════════════════════════

-- ══════════════════════════════════════════════════════════════════════════
--  A · Атомды возврат (қос есептеуді түбегейлі жояды)
-- ══════════════════════════════════════════════════════════════════════════

create or replace function public.return_complete_refund(
  p_return text,
  p_method text default 'cash'
) returns text
language plpgsql security definer set search_path = public as $$
declare
  v_ret    public.returns;
  v_item   jsonb;
  v_batch  uuid;
  v_qty    int;
  v_size   text;
  v_wh     uuid;
  v_cost   double precision;
  v_wh_add jsonb := '{}'::jsonb;   -- {warehouse_id: +pairs}
  v_key    text;
begin
  -- ⚠️ Құлып ЕҢ АЛДЫМЕН: екінші шақыру осы жолда тұрып қалады да, құлып
  --    босағанда статусты 'refunded' деп көреді. Бүкіл түзетудің түйіні.
  select * into v_ret from public.returns where id = p_return for update;
  if not found then raise exception 'return_not_found'; end if;

  -- Идемпотенттік: біреу үлгеріп қойған — үнсіз шығамыз (қате емес).
  if v_ret.status = 'refunded' then return 'already_refunded'; end if;
  if v_ret.status = 'rejected' then raise exception 'return_rejected'; end if;

  -- Тек осы дүкеннің адамы (иесі/сатушысы) немесе модератор.
  if v_ret.admin_uid <> public.app_owner_uid() and not public.is_superadmin() then
    raise exception 'not_your_return';
  end if;

  -- Курьер әкелмей тұрып қоймаға қосуға болмайды — тауар әлі жолда.
  if v_ret.pickup = 'courier'
     and v_ret.courier_uid is not null
     and coalesce(v_ret.courier_status, '') <> 'delivered' then
    raise exception 'courier_not_delivered';
  end if;

  -- ── Қойманы қалпына келтіру ──────────────────────────────────────────────
  for v_item in select * from jsonb_array_elements(v_ret.items) loop
    v_batch := nullif(v_item ->> 'batch_id', '')::uuid;
    v_size  := coalesce(v_item ->> 'size', '');
    v_qty   := coalesce((v_item ->> 'quantity')::int, 0);
    if v_batch is null or v_size = '' or v_qty <= 0 then continue; end if;

    perform public.adjust_batch_sizes(
      v_batch, jsonb_build_object(v_size, v_qty), 'sizes_quantity', false);

    select warehouse_id into v_wh from public.batches where id = v_batch;
    if v_wh is not null then
      v_key := v_wh::text;
      v_wh_add := jsonb_set(v_wh_add, array[v_key],
        to_jsonb(coalesce((v_wh_add ->> v_key)::int, 0) + v_qty));
    end if;

    -- Өзіндік құн: осы тапсырыстың сатылымынан → батчтың құнынан.
    v_cost := null;
    if coalesce(v_ret.order_id, '') <> '' then
      select s.purchase_price into v_cost
        from public.sales_history s
       where s.owner_uid = v_ret.admin_uid
         and s.order_id = v_ret.order_id
         and s.batch_id = v_batch
         and coalesce(s.selected_size, '') = v_size
         and s.type <> 'return'
       limit 1;
    end if;
    if v_cost is null then
      select purchase_price into v_cost
        from public.batch_costs where batch_id = v_batch;
    end if;

    -- Теріс сатылым жазбасы (себестоимость пен кассаны балансылайды).
    insert into public.sales_history(
      owner_uid, type, return_id, product_id, product_name, batch_id,
      selected_size, sale_date, quantity, total_price, base_price,
      discount_percent, discount_amount, seller_id, seller_name,
      warehouse_id, is_online, order_id, payment_method, purchase_price)
    values (
      v_ret.admin_uid, 'return', v_ret.id,
      nullif(v_item ->> 'product_id', '')::uuid,
      coalesce(v_item ->> 'product_title', ''), v_batch,
      v_size, now(), v_qty,
      -coalesce((v_item ->> 'price_per_unit')::double precision, 0) * v_qty,
      -coalesce((v_item ->> 'price_per_unit')::double precision, 0) * v_qty,
      0, 0, 'онлайн', 'Онлайн',
      v_ret.warehouse_id, v_ret.type = 'online',
      coalesce(v_ret.order_id, ''), coalesce(p_method, 'cash'),
      coalesce(v_cost, 0));
  end loop;

  -- Қойма есептегіштері.
  for v_key, v_qty in select key, value::int from jsonb_each_text(v_wh_add) loop
    perform public.increment_warehouse_totals(v_key::uuid, v_qty, 0);
  end loop;

  -- Тапсырыс «Қайтарылды».
  if coalesce(v_ret.order_id, '') <> '' then
    update public.orders set status = 'returned' where id::text = v_ret.order_id;
  end if;

  update public.returns set
    status        = 'refunded',
    refund_method = coalesce(p_method, 'cash'),
    refunded_at   = now(),
    -- Курьерсіз тікелей әкелген жағдайда «қабылданды» кезеңі өткізіліп
    -- кетуі мүмкін — уақытты жоғалтпаймыз.
    received_at   = coalesce(received_at, now())
  where id = p_return;

  -- Тауар статусын қайта есептеу.
  perform public.recompute_product_status(pid)
     from (select distinct nullif(i ->> 'product_id', '')::uuid as pid
             from jsonb_array_elements(v_ret.items) i) q
    where pid is not null;

  return 'refunded';
end;
$$;

grant execute on function public.return_complete_refund(text, text)
  to authenticated;

-- ── «Қабылдадым» да атомды болсын ─────────────────────────────────────────
--  Екі адам бірдей басса — біріншісі ғана күйді ауыстырады, екіншісіне
--  'already' қайтады (қате емес: тауар шынымен қабылданған).
create or replace function public.return_mark_received(
  p_return text,
  p_condition_ok boolean default true,
  p_photos text[] default '{}'
) returns text
language plpgsql security definer set search_path = public as $$
declare v_ret public.returns;
begin
  select * into v_ret from public.returns where id = p_return for update;
  if not found then raise exception 'return_not_found'; end if;
  if v_ret.admin_uid <> public.app_owner_uid() and not public.is_superadmin() then
    raise exception 'not_your_return';
  end if;
  if v_ret.status in ('received', 'refunded') then return 'already'; end if;
  if v_ret.status = 'rejected' then raise exception 'return_rejected'; end if;

  if v_ret.pickup = 'courier'
     and v_ret.courier_uid is not null
     and coalesce(v_ret.courier_status, '') <> 'delivered' then
    raise exception 'courier_not_delivered';
  end if;

  update public.returns set
    status            = 'received',
    item_condition_ok = coalesce(p_condition_ok, true),
    condition_photos  = coalesce(p_photos, '{}'),
    received_at       = now(),
    seller_id         = coalesce(nullif(seller_id, ''), auth.uid()::text)
  where id = p_return;
  return 'received';
end;
$$;
grant execute on function public.return_mark_received(text, boolean, text[])
  to authenticated;

-- ── Офлайн возратта да қос жазба болмасын ─────────────────────────────────
--  Бір сатылым — бір возврат. Dart-тағы «алдымен іздеп көру» тексерісі де
--  дәл сол жарысқа ұшырайды, сондықтан ережені БАЗА ұстайды.
do $$
begin
  if not exists (select 1 from pg_indexes
                  where schemaname = 'public' and indexname = 'returns_sale_once_idx')
     and not exists (
       select 1 from public.returns
        where coalesce(sale_id, '') <> '' and status <> 'rejected'
        group by admin_uid, sale_id having count(*) > 1) then
    create unique index returns_sale_once_idx
      on public.returns(admin_uid, sale_id)
      where coalesce(sale_id, '') <> '' and status <> 'rejected';
  end if;
end $$;

-- ══════════════════════════════════════════════════════════════════════════
--  B · Қалалар: БОС ТІЗІМ = КУРЬЕР ЖОҚ (0055-тегі ереже керісінше болатын)
-- ══════════════════════════════════════════════════════════════════════════
--  ⚠️ Баған C бөлімінде емес, ДӘЛ ОСЫ ЖЕРДЕ қосылады: төмендегі
--  `courier_available_orders` оны `order by`-да қолданады, ал функция
--  құрылған сәтте баған болуы шарт (әйтпесе 42703).

alter table public.orders
  add column if not exists cart_group_id uuid;

--  Модератор қайсы қалада курьер бар екенін ӨЗІ белгілейді. Белгіленбеген
--  қалада клиент курьер ақысын мүлде көрмейді: жеткізуді дүкен өзі
--  ұйымдастырады, возратты клиент өзі әкеледі.

create or replace function public.courier_city_enabled(p_city text)
returns boolean
language sql stable security definer set search_path = public as $$
  select case
    when coalesce(p_city, '') = '' then false
    else coalesce(
      (select exists (select 1
                        from jsonb_array_elements_text(v.value) c
                       where lower(trim(c)) = lower(trim(p_city)))
         from (select coalesce(nullif(value, ''), '[]')::jsonb as value
                 from public.app_settings
                where key = 'delivery_courier_cities') v),
      false)
  end;
$$;
grant execute on function public.courier_city_enabled(text) to anon, authenticated;

-- ── Қала өшірілсе — ЖАҢА тапсырыстар курьерсіз болады, ал БҰРЫН расталған
--    тапсырыс курьерде қалуы керек ────────────────────────────────────────
--  0055-те тізім «тірі» болып тексерілетін: модератор қаланы өшірсе, сол
--  сәтте төленіп, курьер күтіп тұрған тапсырыстар курьерлердің тізімінен
--  ЖОҒАЛЫП КЕТЕТІН — дүкен «курьер келеді» деп отырады, ал ешкім көрмейді.
--  Шешім: шешім тапсырыс жасалғанда қабылданады да, `delivery_mode`-та
--  (возратта `pickup`-та) қатып қалады. Тізім тек ЖАҢА тапсырысқа әсер етеді
--  (себет экраны мен возврат формасы `courier_city_enabled`-ті сол үшін
--  оқиды).
create or replace function public.courier_available_orders()
returns setof public.orders
language sql stable security definer set search_path = public as $$
  select o.* from public.orders o
    join public.stores s on s.admin_uid = o.admin_uid
   where o.order_type = 'delivery'
     and o.status = 'confirmed'
     and o.courier_uid is null
     and coalesce(o.delivery_mode, 'courier') = 'courier'
     and public.active_courier_city() is not null
     and s.city = public.active_courier_city()
   order by o.cart_group_id nulls last, o.created_at;
$$;
grant execute on function public.courier_available_orders() to authenticated;

create or replace function public.courier_available_returns()
returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(public.courier_return_row(r) order by r.created_at),
                  '[]'::jsonb)
    from public.returns r
    join public.stores s on s.admin_uid = r.admin_uid
   where r.pickup = 'courier'
     and r.status = 'approved'
     and r.courier_uid is null
     and public.active_courier_city() is not null
     and s.city = public.active_courier_city();
$$;
grant execute on function public.courier_available_returns() to authenticated;

-- «Алам» батырмалары да сол ережемен: расталған тапсырысты қала өшкені үшін
-- ұстап қалу — оны ЕШКІМ жеткізбейді дегенмен бірдей.
create or replace function public.courier_take_order(p_order uuid)
returns public.orders
language plpgsql security definer set search_path = public as $$
declare
  v_order public.orders;
  v_city  text := public.active_courier_city();
  v_name  text;
begin
  if v_city is null then raise exception 'not_active_courier'; end if;
  select name into v_name from public.users where id = auth.uid();

  select * into v_order from public.orders where id = p_order for update;
  if not found then raise exception 'order_not_found'; end if;
  if v_order.order_type <> 'delivery' or v_order.status <> 'confirmed' then
    raise exception 'order_state_changed:%', v_order.status;
  end if;
  if coalesce(v_order.delivery_mode, 'courier') <> 'courier' then
    raise exception 'store_delivers_itself';
  end if;
  if v_order.courier_uid is not null then raise exception 'order_already_taken'; end if;
  if not exists (select 1 from public.stores
                  where admin_uid = v_order.admin_uid and city = v_city) then
    raise exception 'other_city';
  end if;

  update public.orders set
    courier_uid = auth.uid(),
    courier_name = coalesce(v_name, ''),
    courier_status = 'assigned',
    courier_taken_at = now()
  where id = p_order returning * into v_order;

  perform public.notify_push(
    array[v_order.admin_uid],
    'Курьер назначен / Курьер тағайындалды',
    coalesce(v_name, '') || ' — №' || v_order.order_number,
    jsonb_build_object('type', 'courier_assigned', 'orderId', v_order.id));
  return v_order;
end;
$$;
grant execute on function public.courier_take_order(uuid) to authenticated;

create or replace function public.courier_take_return(p_return text)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_ret  public.returns;
  v_city text := public.active_courier_city();
  v_name text;
  v_fee  numeric;
begin
  if v_city is null then raise exception 'not_active_courier'; end if;
  select name into v_name from public.users where id = auth.uid();
  select coalesce(nullif(value, '')::numeric, 1500) into v_fee
    from public.app_settings where key = 'delivery_return_fee';

  select * into v_ret from public.returns where id = p_return for update;
  if not found then raise exception 'return_not_found'; end if;
  if v_ret.pickup <> 'courier' then raise exception 'not_courier_return'; end if;
  if v_ret.status <> 'approved' then raise exception 'return_not_approved'; end if;
  if v_ret.courier_uid is not null then raise exception 'return_already_taken'; end if;
  if not exists (select 1 from public.stores
                  where admin_uid = v_ret.admin_uid and city = v_city) then
    raise exception 'other_city';
  end if;

  update public.returns set
    courier_uid = auth.uid(),
    courier_name = coalesce(v_name, ''),
    courier_status = 'assigned',
    courier_taken_at = now(),
    delivery_fee = coalesce(v_fee, 1500)
  where id = p_return;

  if v_ret.client_uid is not null then
    perform public.notify_push(array[v_ret.client_uid],
      'Курьер заберёт возврат / Курьер қайтарымды алады',
      coalesce(v_name, ''),
      jsonb_build_object('type', 'return_status', 'returnId', v_ret.id));
  end if;
end;
$$;
grant execute on function public.courier_take_return(text) to authenticated;

-- ══════════════════════════════════════════════════════════════════════════
--  C · Бір клиенттің тапсырысы — бір курьерге (екі дүкен болса да)
-- ══════════════════════════════════════════════════════════════════════════

-- (баған B бөлімінде қосылған — ол жерде `courier_available_orders` оны
--  пайдаланады, сондықтан ретін бұзуға болмайды.)

create index if not exists orders_cart_group_idx
  on public.orders(cart_group_id) where cart_group_id is not null;

-- Топтағы БАРЛЫҚ бос тапсырысты бір мезгілде алу. Жарты топты алу мағынасыз:
-- клиент біреу, мекенжай біреу, бару да біреу.
create or replace function public.courier_take_group(p_group uuid)
returns int
language plpgsql security definer set search_path = public as $$
declare
  v_city  text := public.active_courier_city();
  v_name  text;
  v_row   public.orders;
  v_taken int := 0;
begin
  if v_city is null then raise exception 'not_active_courier'; end if;
  select name into v_name from public.users where id = auth.uid();

  for v_row in
    select o.* from public.orders o
      join public.stores s on s.admin_uid = o.admin_uid
     where o.cart_group_id = p_group
       and o.order_type = 'delivery'
       and o.status = 'confirmed'
       and o.courier_uid is null
       and coalesce(o.delivery_mode, 'courier') = 'courier'
       and s.city = v_city
     order by o.created_at
     for update of o
  loop
    update public.orders set
      courier_uid      = auth.uid(),
      courier_name     = coalesce(v_name, ''),
      courier_status   = 'assigned',
      courier_taken_at = now()
    where id = v_row.id;
    v_taken := v_taken + 1;

    perform public.notify_push(
      array[v_row.admin_uid],
      'Курьер назначен / Курьер тағайындалды',
      coalesce(v_name, '') || ' — №' || v_row.order_number,
      jsonb_build_object('type', 'courier_assigned', 'orderId', v_row.id));
  end loop;

  if v_taken = 0 then raise exception 'group_already_taken'; end if;
  return v_taken;
end;
$$;
grant execute on function public.courier_take_group(uuid) to authenticated;

-- ══════════════════════════════════════════════════════════════════════════
--  D · Партияның КЕЛГЕН саны (қазіргі қалдықпен шатастырмау үшін)
-- ══════════════════════════════════════════════════════════════════════════
--  `sizes_quantity` — сатылған сайын азаяды. «Прошлый завоз» соны көрсетсе,
--  админ алдыңғы жолы 10 әкеліп 9-ы сатылса «1 дана әкелген екенмін» деп
--  оқиды. Келген сан бөлек, өзгермейтін болып сақталады.

alter table public.batches
  add column if not exists sizes_initial jsonb not null default '{}';

-- Ескі партиялар: не бар — сол. Дәлірегі белгісіз, бірақ бос қалдырғаннан
-- гөрі қазіргі қалдық жақынырақ (жаңа партиялар дұрыс толады).
update public.batches
   set sizes_initial = sizes_quantity
 where sizes_initial = '{}'::jsonb and sizes_quantity <> '{}'::jsonb;

-- Жаңа партия қосылғанда автоматты толады — клиент кодына тәуелді емес.
create or replace function public.fill_batch_sizes_initial()
returns trigger
language plpgsql set search_path = public as $$
begin
  if new.sizes_initial is null or new.sizes_initial = '{}'::jsonb then
    new.sizes_initial := coalesce(new.sizes_quantity, '{}'::jsonb);
  end if;
  return new;
end;
$$;

drop trigger if exists trg_fill_batch_sizes_initial on public.batches;
create trigger trg_fill_batch_sizes_initial before insert on public.batches
  for each row execute function public.fill_batch_sizes_initial();
