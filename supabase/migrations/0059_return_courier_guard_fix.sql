-- ════════════════════════════════════════════════════════════════════════════
--  0059 · Курьермен қайтарылатын тауарды дүкен ЕРТЕ қабылдап қоятын
-- ────────────────────────────────────────────────────────────────────────────
--  0057-де қорған былай жазылған еді:
--
--      if pickup = 'courier' and courier_uid is not null
--         and courier_status <> 'delivered' then raise ...
--                        ^^^^^^^^^^^^^^^^^^^^
--  `courier_uid is not null` — ҚАТЕ шарт. Курьер ӘЛІ ТАҒАЙЫНДАЛМАҒАН кезде
--  (`courier_uid is null`) шарт орындалмай, қорған МҮЛДЕ ІСКЕ ҚОСЫЛМАЙТЫН.
--  Нәтижесінде: клиент курьермен қайтаруды ашады → дүкен «мақұлдау» басады →
--  курьер оны әлі алған да жоқ → дүкен «тауарды қабылдадым» деп басып,
--  қоймаға ЖОҚ тауар қосылады, клиентке ақша қайтарылады.
--
--  Базада дәлел бар: RET-2026-0014 мен RET-2026-0015 — `pickup='courier'`,
--  `courier_uid is null`, бірақ `refunded`.
--
--  Дұрыс ереже ҚАРАПАЙЫМ: курьермен қайтарылатын тауар дүкенге ЖЕТКІЗІЛГЕН
--  болуы керек. Курьер тағайындалды ма, жоқ па — маңызды емес: тағайындалмаса
--  тауар тіпті жолға да шықпаған.
-- ════════════════════════════════════════════════════════════════════════════

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
  v_wh_add jsonb := '{}'::jsonb;
  v_key    text;
begin
  select * into v_ret from public.returns where id = p_return for update;
  if not found then raise exception 'return_not_found'; end if;

  if v_ret.status = 'refunded' then return 'already_refunded'; end if;
  if v_ret.status = 'rejected' then raise exception 'return_rejected'; end if;

  if v_ret.admin_uid <> public.app_owner_uid() and not public.is_superadmin() then
    raise exception 'not_your_return';
  end if;

  -- ⚠️ ТҮЗЕТУ (0059): `courier_uid` тексерілмейді.
  if v_ret.pickup = 'courier'
     and coalesce(v_ret.courier_status, '') <> 'delivered' then
    raise exception 'courier_not_delivered';
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

  -- ⚠️ ТҮЗЕТУ (0059): `courier_uid` тексерілмейді.
  if v_ret.pickup = 'courier'
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
