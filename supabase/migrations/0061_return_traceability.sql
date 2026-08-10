-- ════════════════════════════════════════════════════════════════════════════
--  0061 · Возврат ҚАЙ ЧЕКТЕН екені көрінеді
-- ────────────────────────────────────────────────────────────────────────────
--  МӘСЕЛЕ. Сатылым жолы «#00046 · Р: 42 · 17:06» деп толық жазылатын, ал сол
--  сатылымның возраты «Возврат · 14:39» болып қана шығатын: қай чек, қай
--  өлшем, қай тапсырыс — ешқайсысы жоқ. Бір тауар күніне бірнеше рет
--  сатылса (тесте — «New Balance 530» күніне 5 рет), сатушы қай сатылым
--  қайтарылғанын АНЫҚТАЙ АЛМАЙТЫН.
--
--  Себебі: теріс `sales_history` жазбасы `receipt_number` мен `sizes_sold`-ты
--  МҮЛДЕ толтырмайтын, ал возврат карточкасы солардан оқиды.
--
--  ШЕШІМ (үш қабат):
--    1) теріс жазба бастапқы чектің нөмірін ЖӘНЕ өлшемін көшіріп алады;
--    2) `returns` кестесінің өзінде де чек/тапсырыс нөмірі снапшот болып
--       жатады — возраттар тізімінде қосымша сұраныссыз көрінуі үшін;
--    3) бұрынғы жазбалар да толтырылады (backfill).
-- ════════════════════════════════════════════════════════════════════════════

-- ══════════════════════════════════════════════════════════════════════════
--  1 · returns кестесіндегі снапшот
-- ══════════════════════════════════════════════════════════════════════════

alter table public.returns
  add column if not exists order_number   int,
  add column if not exists receipt_number text not null default '';

-- Возврат жасалғанда бастапқы чек/тапсырыс нөмірін өзі тауып алады.
-- Клиент кодына тәуелді емес: онлайн да, офлайн да бір жерден толады.
create or replace function public.fill_return_source_ref()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if coalesce(new.receipt_number, '') <> '' or new.order_number is not null then
    return new;
  end if;

  if coalesce(new.order_id, '') <> '' then
    select o.order_number, coalesce(o.receipt_number, '')
      into new.order_number, new.receipt_number
      from public.orders o where o.id::text = new.order_id;
  elsif coalesce(new.sale_id, '') <> '' then
    select coalesce(s.receipt_number, '')
      into new.receipt_number
      from public.sales_history s where s.id::text = new.sale_id;
  end if;

  new.receipt_number := coalesce(new.receipt_number, '');
  return new;
end;
$$;

drop trigger if exists trg_fill_return_source_ref on public.returns;
create trigger trg_fill_return_source_ref before insert on public.returns
  for each row execute function public.fill_return_source_ref();

-- Бұрынғы возраттар.
update public.returns r
   set order_number   = o.order_number,
       receipt_number = coalesce(o.receipt_number, '')
  from public.orders o
 where o.id::text = r.order_id
   and r.order_number is null;

update public.returns r
   set receipt_number = coalesce(s.receipt_number, '')
  from public.sales_history s
 where s.id::text = r.sale_id
   and coalesce(r.receipt_number, '') = ''
   and coalesce(r.sale_id, '') <> '';

-- ══════════════════════════════════════════════════════════════════════════
--  2 · Теріс sales_history жазбасы чек нөмірі мен өлшемді алып жүреді
-- ══════════════════════════════════════════════════════════════════════════

create or replace function public.return_complete_refund(
  p_return text,
  p_method text default 'cash'
) returns text
language plpgsql security definer set search_path = public as $$
declare
  v_ret     public.returns;
  v_item    jsonb;
  v_batch   uuid;
  v_qty     int;
  v_size    text;
  v_wh      uuid;
  v_cost    double precision;
  v_receipt text;
  v_wh_add  jsonb := '{}'::jsonb;
  v_key     text;
begin
  select * into v_ret from public.returns where id = p_return for update;
  if not found then raise exception 'return_not_found'; end if;

  if v_ret.status = 'refunded' then return 'already_refunded'; end if;
  if v_ret.status = 'rejected' then raise exception 'return_rejected'; end if;

  if v_ret.admin_uid <> public.app_owner_uid() and not public.is_superadmin() then
    raise exception 'not_your_return';
  end if;

  -- 0059: курьермен қайтарылатын тауар ЖЕТКІЗІЛГЕН болуы шарт.
  if v_ret.pickup = 'courier'
     and coalesce(v_ret.courier_status, '') <> 'delivered' then
    raise exception 'courier_not_delivered';
  end if;

  -- Бастапқы чектің нөмірі: возраттың өзінде (0061 снапшоты) → тапсырыстан.
  v_receipt := coalesce(nullif(v_ret.receipt_number, ''), '');
  if v_receipt = '' and coalesce(v_ret.order_id, '') <> '' then
    select coalesce(o.receipt_number, '') into v_receipt
      from public.orders o where o.id::text = v_ret.order_id;
  end if;

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

    insert into public.sales_history(
      owner_uid, type, return_id, product_id, product_name, batch_id,
      selected_size, sizes_sold, receipt_number,
      sale_date, quantity, total_price, base_price,
      discount_percent, discount_amount, seller_id, seller_name,
      warehouse_id, is_online, order_id, payment_method, purchase_price)
    values (
      v_ret.admin_uid, 'return', v_ret.id,
      nullif(v_item ->> 'product_id', '')::uuid,
      coalesce(v_item ->> 'product_title', ''), v_batch,
      v_size,
      -- ⚠️ Карточка өлшемді `sizes_sold`-тан оқиды — сатылыммен бірдей пішім.
      jsonb_build_object(v_size, v_qty),
      v_receipt,
      now(), v_qty,
      -coalesce((v_item ->> 'price_per_unit')::double precision, 0) * v_qty,
      -coalesce((v_item ->> 'price_per_unit')::double precision, 0) * v_qty,
      0, 0, 'онлайн', 'Онлайн',
      v_ret.warehouse_id, v_ret.type = 'online',
      coalesce(v_ret.order_id, ''), coalesce(p_method, 'cash'),
      coalesce(v_cost, 0));
  end loop;

  for v_key, v_qty in select key, value::int from jsonb_each_text(v_wh_add) loop
    perform public.increment_warehouse_totals(v_key::uuid, v_qty, 0);
  end loop;

  if coalesce(v_ret.order_id, '') <> '' then
    update public.orders set status = 'returned' where id::text = v_ret.order_id;
  end if;

  update public.returns set
    status        = 'refunded',
    refund_method = coalesce(p_method, 'cash'),
    refunded_at   = now(),
    received_at   = coalesce(received_at, now())
  where id = p_return;

  perform public.recompute_product_status(pid)
     from (select distinct nullif(i ->> 'product_id', '')::uuid as pid
             from jsonb_array_elements(v_ret.items) i) q
    where pid is not null;

  return 'refunded';
end;
$$;
grant execute on function public.return_complete_refund(text, text)
  to authenticated;

-- ══════════════════════════════════════════════════════════════════════════
--  3 · Бұрынғы теріс жазбалар да чек нөмірі мен өлшемді алсын
-- ══════════════════════════════════════════════════════════════════════════

update public.sales_history s
   set receipt_number = coalesce(o.receipt_number, '')
  from public.orders o
 where o.id::text = s.order_id
   and s.type = 'return'
   and coalesce(s.receipt_number, '') = '';

update public.sales_history s
   set sizes_sold = jsonb_build_object(s.selected_size, greatest(s.quantity, 1))
 where s.type = 'return'
   and coalesce(s.selected_size, '') <> ''
   and coalesce(s.sizes_sold, '{}'::jsonb) = '{}'::jsonb;
