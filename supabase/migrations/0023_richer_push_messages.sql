-- ════════════════════════════════════════════════════════════════════════════
--  0023 · Пуш-хабарламаларды түсінікті ету: кім сатты, қай қоймадан, қандай
--  тауар, клиент кім — детальдармен байыту (триггерлер сол күйінде қалады,
--  тек функция денесі жаңарады).
-- ────────────────────────────────────────────────────────────────────────────
--  Ескерту: пуш мәтіні тек орысша — DB триггері клиенттің тілін білмейді
--  (қолданыстағы конвенция, notify_push статикалық мәтін жібереді).
-- ════════════════════════════════════════════════════════════════════════════

-- ── 1) Сатылым → дүкен иесіне (кім сатты · тауар · қойма · сома) ─────────────
create or replace function public.on_sale_push() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_wh    text;
  v_item  text;
begin
  if new.type <> 'sale' then return new; end if;

  select name into v_wh from public.warehouses where id = new.warehouse_id;

  v_item := coalesce(nullif(new.product_name, ''), 'товар')
    || case when coalesce(new.quantity, 1) > 1 then ' ×' || new.quantity else '' end;

  if coalesce(new.is_online, false) then
    -- Онлайн-заказ берілді (тауарды кім берген — delivered_by_name)
    perform public.notify_push(
      array[new.owner_uid],
      '🛒 Онлайн-продажа · ' || new.total_price::int || ' ₸',
      'Выдал(а): ' || coalesce(nullif(new.delivered_by_name, ''), 'сотрудник')
        || E'\n' || v_item
        || coalesce(E'\n📍 ' || v_wh, ''),
      jsonb_build_object('type', 'sale', 'saleId', new.id, 'online', true)
    );
  else
    -- Офлайн-сатылым (кім сатты — seller_name)
    perform public.notify_push(
      array[new.owner_uid],
      '🛒 Новая продажа · ' || new.total_price::int || ' ₸',
      coalesce(nullif(new.seller_name, ''), 'Продавец') || ' продал(а):'
        || E'\n' || v_item
        || coalesce(E'\n📍 ' || v_wh, ''),
      jsonb_build_object('type', 'sale', 'saleId', new.id)
    );
  end if;
  return new;
end;
$$;

-- ── 2) Жаңа онлайн-тапсырыс → иесіне + сатушыларға (клиент · тәсіл · сома) ───
create or replace function public.on_order_push() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_uids   uuid[];
  v_type   text;
  v_first  text;
  v_count  int;
  v_more   text := '';
begin
  select array_agg(id) into v_uids
    from public.users
    where id = new.admin_uid or (owner_id = new.admin_uid and role = 'seller');

  v_type := case new.order_type
    when 'smart_reservation' then 'Бронь'
    when 'click_collect'     then 'Самовывоз'
    when 'delivery'          then 'Доставка'
    else new.order_type
  end;

  v_first := coalesce(new.items->0->>'productName', 'товар');
  v_count := coalesce(jsonb_array_length(new.items), 0);
  if v_count > 1 then v_more := ' +' || (v_count - 1); end if;

  perform public.notify_push(
    coalesce(v_uids, array[new.admin_uid]),
    '🛍 Новый заказ №' || new.order_number || ' · ' || v_type,
    coalesce(nullif(new.client_name, ''), 'Клиент') || ' · ' ||
      new.deposit_amount::int || ' ₸' ||
      E'\n' || v_first || v_more,
    jsonb_build_object('type', 'order', 'orderId', new.id)
  );
  return new;
end;
$$;

-- ── 3) Чек тіркелді → дүкен иесіне (клиент · заказ № · сома) ─────────────────
create or replace function public.on_receipt_push() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if coalesce(new.receipt_url, '') <> ''
     and new.receipt_url is distinct from old.receipt_url then
    perform public.notify_push(
      array[new.admin_uid],
      '💳 Новый чек · Заказ №' || new.order_number,
      coalesce(nullif(new.client_name, ''), 'Клиент') || ' — ' ||
        new.deposit_amount::int || ' ₸' ||
        E'\nНажмите, чтобы проверить и подтвердить оплату',
      jsonb_build_object('type', 'receipt', 'orderId', new.id)
    );
  end if;
  return new;
end;
$$;

-- ── 4) Тапсырыс статусы → клиентке (дүкен аты · заказ № · тауар) ─────────────
create or replace function public.on_order_status_push() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_title text;
  v_first text;
begin
  if new.status is not distinct from old.status or new.client_uid is null then
    return new;
  end if;
  v_title := case new.status
    when 'reserved'  then '✅ Бронь подтверждена'
    when 'confirmed' then '✅ Оплата подтверждена'
    when 'ready'     then '📦 Заказ готов к выдаче'
    when 'completed' then '🎉 Заказ выполнен'
    when 'rejected'  then '⚠️ Чек отклонён — прикрепите новый'
    when 'cancelled' then '❌ Заказ отменён'
    else null
  end;
  if v_title is null then return new; end if;

  v_first := coalesce(new.items->0->>'productName', '');
  perform public.notify_push(
    array[new.client_uid],
    v_title,
    coalesce(nullif(new.store_name, ''), 'Магазин') || ' · Заказ №' || new.order_number
      || coalesce(E'\n' || nullif(v_first, ''), ''),
    jsonb_build_object('type', 'order_status', 'orderId', new.id, 'status', new.status)
  );
  return new;
end;
$$;

-- ── 5) Возврат → иесіне (онлайн болса сатушыларға да) — клиент · тауар · сома ─
create or replace function public.on_return_push() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_title text;
  v_uids  uuid[];
  v_first text;
begin
  v_first := coalesce(new.items->0->>'productName', 'товар');
  if new.type = 'online' then
    v_title := '↩️ Онлайн-возврат';
    select array_agg(id) into v_uids
      from public.users
      where id = new.admin_uid or (owner_id = new.admin_uid and role = 'seller');
  else
    v_title := '↩️ Новый возврат';
    v_uids := array[new.admin_uid];
  end if;
  perform public.notify_push(
    coalesce(v_uids, array[new.admin_uid]),
    v_title || ' · ' || new.total_amount::int || ' ₸',
    coalesce(nullif(new.client_name, ''), 'Клиент') || E'\n' || v_first,
    jsonb_build_object('type', 'return', 'returnId', new.id)
  );
  return new;
end;
$$;

-- ── 6) Жаңа пікір → дүкен иесіне (тауар аты · жұлдыз · пікір) ────────────────
create or replace function public.on_review_push() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_product text;
begin
  select name into v_product from public.products where id = new.product_id;
  perform public.notify_push(
    array[new.admin_uid],
    '⭐ Новый отзыв · ' || new.rating || '★',
    coalesce(nullif(v_product, ''), 'Товар') || E'\n' ||
      coalesce(nullif(new.client_name, ''), 'Покупатель') || ': ' ||
      left(coalesce(new.comment, ''), 80),
    jsonb_build_object('type', 'review', 'productId', new.product_id)
  );
  return new;
end;
$$;

-- ── 7) Сатушы қосылу өтінімі → иесіне (эмодзи) ──────────────────────────────
create or replace function public.on_join_request_push() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'pending'
     and (tg_op = 'INSERT' or new.status is distinct from old.status) then
    perform public.notify_push(
      array[new.admin_uid],
      '👤 Новая заявка продавца',
      coalesce(nullif(new.seller_name, ''), 'Продавец') || ' хочет присоединиться к магазину',
      jsonb_build_object('type', 'join_request', 'requestId', new.id)
    );
  end if;
  return new;
end;
$$;
