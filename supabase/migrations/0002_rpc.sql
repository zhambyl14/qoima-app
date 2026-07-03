-- ════════════════════════════════════════════════════════════════════════════
--  Qoima · Атомдық операциялар (Firestore транзакциялары орнына RPC)
-- ────────────────────────────────────────────────────────────────────────────
--  Қойма (sizes_quantity / reserved_sizes JSONB) — қатарды LOCK жасап өзгертеді,
--  сондықтан қатар жүрген сатылым/бронь кезінде «lost update» болмайды.
-- ════════════════════════════════════════════════════════════════════════════

-- Batch-тың sizes_quantity немесе reserved_sizes JSONB өрісіне дельталарды
-- атомдық қосады. p_guard=true болса, нәтижеде ешбір өлшемнің қолжетімдісі
-- (sizes_quantity − reserved_sizes) теріс болмауын тексереді (oversell қорғауы).
-- p_deltas: {"42": -1, "43": 2} түрінде (теріс = азайту, оң = қосу).
create or replace function public.adjust_batch_sizes(
  p_batch uuid, p_deltas jsonb, p_field text, p_guard boolean default false
) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_q jsonb; v_r jsonb; v_sizes jsonb; k text; d int;
begin
  select sizes_quantity, reserved_sizes into v_q, v_r
    from public.batches where id = p_batch for update;
  if not found then raise exception 'batch_not_found'; end if;

  v_sizes := case when p_field = 'reserved_sizes' then v_r else v_q end;
  for k, d in select key, value::int from jsonb_each_text(p_deltas) loop
    v_sizes := jsonb_set(v_sizes, array[k],
      to_jsonb(coalesce((v_sizes->>k)::int, 0) + d));
  end loop;

  if p_field = 'reserved_sizes' then
    update public.batches set reserved_sizes = v_sizes where id = p_batch;
    v_r := v_sizes;
  else
    update public.batches set sizes_quantity = v_sizes where id = p_batch;
    v_q := v_sizes;
  end if;

  if p_guard then
    for k in select key from jsonb_each_text(p_deltas) loop
      if coalesce((v_q->>k)::int, 0) - coalesce((v_r->>k)::int, 0) < 0 then
        raise exception 'insufficient_stock:%', k;
      end if;
    end loop;
  end if;
end;
$$;
grant execute on function public.adjust_batch_sizes(uuid, jsonb, text, boolean) to authenticated;

-- Тауардың статусын барлық партияларының нақты қолжетімді қалдығына қарай түзейді.
create or replace function public.recompute_product_status(p_product uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare v_in boolean;
begin
  select exists(
    select 1 from public.batches b, jsonb_each_text(b.sizes_quantity) s
    where b.product_id = p_product
      and (s.value)::int - coalesce((b.reserved_sizes->>s.key)::int, 0) > 0
  ) into v_in;
  update public.products
    set status = case when v_in then 'В наличии' else 'Продано' end
    where id = p_product;
end;
$$;
grant execute on function public.recompute_product_status(uuid) to authenticated;

-- Қойма есептегіштерін (display) атомдық арттыру/азайту.
create or replace function public.increment_warehouse_totals(
  p_wh uuid, p_pairs int, p_products int
) returns void
language sql security definer set search_path = public as $$
  update public.warehouses
    set total_pairs = total_pairs + p_pairs,
        total_products = total_products + p_products
    where id = p_wh;
$$;
grant execute on function public.increment_warehouse_totals(uuid, int, int) to authenticated;

-- Промокод қолдану есептегішін атомдық түзейді (бас тартқанда −1, т.б.).
create or replace function public.adjust_promo_usage(
  p_promo uuid, p_client uuid, p_delta int
) returns void
language plpgsql security definer set search_path = public as $$
begin
  update public.promos
    set used_count = greatest(0, used_count + p_delta) where id = p_promo;
  if p_client is not null then
    insert into public.promo_redemptions(promo_id, client_uid, count)
      values (p_promo, p_client, greatest(0, p_delta))
    on conflict (promo_id, client_uid) do update
      set count = greatest(0, public.promo_redemptions.count + p_delta),
          updated_at = now();
  end if;
end;
$$;
grant execute on function public.adjust_promo_usage(uuid, uuid, int) to authenticated;
