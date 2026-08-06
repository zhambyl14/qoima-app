-- ════════════════════════════════════════════════════════════════════════════
--  0041 · «Тауар қайта келді» push — таңдаулыға (favorites) қосылған тауар
--  қоймаға қайта келгенде (0 → бар болды өтуі), сол клиенттерге автоматты
--  хабарлама. Дайын инфрақұрылым (favorites + notify_push, 0020) біріктіріледі
--  — жаңа кесте/edge function қажет емес.
--
--  «Бар болды» тек СТОРФРОНТТА КӨРІНЕТІН қорды есептейді: дүкен жарияланған
--  әрі бұғатталмаған, ал batch-тың warehouse_id-і stores.visible_warehouse_ids
--  ішінде болуы керек (жасырын қоймаға тек офлайн тауар қосу клиентке
--  жалған "қайта келді" хабарлама жібермеуі үшін).
-- ════════════════════════════════════════════════════════════════════════════

-- ── Бір batch жолындағы қолжетімді сан (өлшем бойынша: қор − брондалған) ────
create or replace function public.batch_available_qty(p_sizes jsonb, p_reserved jsonb)
returns integer
language sql immutable set search_path = public as $$
  select coalesce(sum(
    greatest((kv.value)::int - coalesce((p_reserved ->> kv.key)::int, 0), 0)
  ), 0)::integer
  from jsonb_each_text(coalesce(p_sizes, '{}'::jsonb)) as kv;
$$;

create or replace function public.on_batch_restock_push() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_store         record;
  v_new_avail     integer;
  v_old_avail     integer;
  v_total_after   integer;
  v_total_before  integer;
  v_product       record;
  v_uids          uuid[];
begin
  select admin_uid, is_published, status, visible_warehouse_ids
    into v_store
    from public.stores where admin_uid = new.owner_uid;
  if v_store is null or v_store.is_published is not true or v_store.status = 'blocked' then
    return new;
  end if;
  if not (new.warehouse_id::text = any(v_store.visible_warehouse_ids)) then
    return new; -- жасырын қойма — клиентке бәрібір көрінбейді
  end if;

  v_new_avail := public.batch_available_qty(new.sizes_quantity, new.reserved_sizes);
  v_old_avail := case when TG_OP = 'INSERT' then 0
                       else public.batch_available_qty(old.sizes_quantity, old.reserved_sizes) end;

  select coalesce(sum(public.batch_available_qty(b.sizes_quantity, b.reserved_sizes)), 0)
    into v_total_after
    from public.batches b
    where b.product_id = new.product_id
      and b.warehouse_id::text = any(v_store.visible_warehouse_ids);

  v_total_before := v_total_after - v_new_avail + v_old_avail;

  -- Тек «0 → бар болды» ауысуында ғана хабарлаймыз (қайталанбас үшін).
  if v_total_before > 0 or v_total_after <= 0 then
    return new;
  end if;

  select name, storefront_hidden into v_product
    from public.products where id = new.product_id;
  if v_product is null or v_product.storefront_hidden is true then
    return new;
  end if;

  select array_agg(client_uid) into v_uids
    from public.favorites where product_id = new.product_id;
  if v_uids is null then return new; end if;

  perform public.notify_push(
    v_uids,
    'Товар снова в наличии! / Тауар қайта келді!',
    coalesce(v_product.name, ''),
    jsonb_build_object('type', 'back_in_stock', 'productId', new.product_id)
  );
  return new;
end;
$$;

drop trigger if exists trg_batch_restock_push on public.batches;
create trigger trg_batch_restock_push after insert or update on public.batches
  for each row execute function public.on_batch_restock_push();
