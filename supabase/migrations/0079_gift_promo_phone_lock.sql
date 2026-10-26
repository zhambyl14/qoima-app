-- ════════════════════════════════════════════════════════════════════════════
--  0079 · Сыйлық: промокод, алушыны телефон бойынша табу, өлшем құлпы, қойма
-- ────────────────────────────────────────────────────────────────────────────
--   • Промокод СЕРВЕРДЕ тексеріледі (gift_promo_check — клиенттік validatePromo
--     ережелерінің көшірмесі, бір ғана көзде). Жеңілдік сыйлаушының төлемінен
--     шегеріледі; сыйлық құны (gift_paid_amount) толық баға — алушының ауыстыру
--     кредиті өзгермейді. Бас тартқанда есептегішті клиент қолданыстағы жолмен
--     (adjust_promo_usage −1) қайтарады — orders.promo_* бағандары арқылы.
--   • p_recipient_phone: алушы Qoima-да тіркелген болса сыйлық оған қосымша
--     ішінде ғана жіберіледі (gift_recipient_uid), claim_gift басқаларды өткізбейді.
--   • Сыйлаушы өлшемді таңдаса, алушы өлшем/тауарды өзгерте алмайды
--     (gift_size_locked); берілген соң дүкенде ауыстыру сақталады.
--   • Төлем расталғанда алушыға push (тауар атауынсыз — тосынсый).
--   • Мерзімі өткен, алынбаған сыйлықтың брондалған өлшемі қоймаға қайтады.
-- ════════════════════════════════════════════════════════════════════════════

-- ── Промокод тексерісі (жалғыз көз) ────────────────────────────────────────
create or replace function public.gift_promo_check(
  p_store uuid, p_client uuid, p_product uuid, p_base double precision,
  p_code text, p_lock boolean
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_code text := upper(trim(coalesce(p_code, '')));
  v_p    public.promos;
  v_used integer;
  v_disc double precision;
begin
  if v_code = '' then
    return jsonb_build_object('promo_id', null, 'discount', 0, 'reason', null);
  end if;
  if p_lock then
    select * into v_p from public.promos where admin_uid = p_store and code = v_code for update;
  else
    select * into v_p from public.promos where admin_uid = p_store and code = v_code;
  end if;
  if not found then return jsonb_build_object('reason', 'promo_not_found'); end if;
  if not v_p.active then return jsonb_build_object('reason', 'promo_inactive'); end if;
  if v_p.starts_at is not null and now() < v_p.starts_at then
    return jsonb_build_object('reason', 'promo_not_started');
  end if;
  if v_p.ends_at is not null and now() > v_p.ends_at then
    return jsonb_build_object('reason', 'promo_expired');
  end if;
  if v_p.max_uses is not null and v_p.used_count >= v_p.max_uses then
    return jsonb_build_object('reason', 'promo_exhausted');
  end if;
  if v_p.referral_owner_uid is not null then
    if v_p.referral_owner_uid = p_client then
      return jsonb_build_object('reason', 'promo_referral_self');
    end if;
    if exists (select 1 from public.orders o
                where o.admin_uid = p_store and o.client_uid = p_client and o.status = 'completed') then
      return jsonb_build_object('reason', 'promo_referral_first_only');
    end if;
  end if;
  if v_p.only_for_uid is not null and v_p.only_for_uid <> p_client then
    return jsonb_build_object('reason', 'promo_not_yours');
  end if;
  if v_p.per_user_limit is not null then
    select coalesce(r.count, 0) into v_used from public.promo_redemptions r
     where r.promo_id = v_p.id and r.client_uid = p_client;
    if coalesce(v_used, 0) >= v_p.per_user_limit then
      return jsonb_build_object('reason', 'promo_limit_user');
    end if;
  end if;
  if v_p.scope = 'products' and not (p_product::text = any (coalesce(v_p.product_ids, '{}'::text[]))) then
    return jsonb_build_object('reason', 'promo_not_applicable');
  end if;
  if p_base < coalesce(v_p.min_order, 0) then
    return jsonb_build_object('reason', 'promo_min_order', 'min_order', v_p.min_order);
  end if;
  v_disc := case when v_p.type = 'percent' then p_base * v_p.value / 100 else v_p.value end;
  v_disc := greatest(least(v_disc, p_base), 0);
  return jsonb_build_object('promo_id', v_p.id, 'discount', round(v_disc), 'reason', null);
end;
$$;
revoke all on function public.gift_promo_check(uuid, uuid, uuid, double precision, text, boolean) from public, anon, authenticated;

-- Сыйлау парақшасындағы «Қолдану» — жеңілдікті алдын ала көрсету (сақтамайды).
create or replace function public.gift_promo_preview(p_product uuid, p_size text, p_code text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid   uuid := auth.uid();
  v_prod  public.products;
  v_store public.stores;
  v_size  text := left(trim(coalesce(p_size, '')), 20);
  v_price double precision;
  v_chk   jsonb;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;
  if not exists (select 1 from public.clients where id = v_uid) then raise exception 'not_a_client'; end if;
  select * into v_prod from public.products where id = p_product;
  if not found then raise exception 'product_unavailable'; end if;
  select * into v_store from public.stores where admin_uid = v_prod.owner_uid;
  if not found then raise exception 'store_unavailable'; end if;
  -- create_gift_order-дегі баға логикасымен бірдей
  if v_size <> '' then
    select min(public.batch_effective_price(b.selling_price, b.discount)) into v_price
      from public.batches b
     where b.product_id = v_prod.id
       and b.warehouse_id::text = any (coalesce(v_store.visible_warehouse_ids, '{}'::text[]))
       and coalesce((b.sizes_quantity ->> v_size)::int, 0)
           - coalesce((b.reserved_sizes ->> v_size)::int, 0) >= 1;
  else
    select max(public.batch_effective_price(b.selling_price, b.discount)) into v_price
      from public.batches b
     where b.product_id = v_prod.id
       and b.warehouse_id::text = any (coalesce(v_store.visible_warehouse_ids, '{}'::text[]))
       and public.batch_available_qty(b.sizes_quantity, b.reserved_sizes) > 0;
  end if;
  if v_price is null then raise exception 'gift_out_of_stock'; end if;
  v_chk := public.gift_promo_check(v_store.admin_uid, v_uid, v_prod.id, v_price, p_code, false);
  return jsonb_build_object(
    'ok', v_chk ->> 'reason' is null,
    'reason', v_chk ->> 'reason',
    'min_order', v_chk -> 'min_order',
    'discount', coalesce((v_chk ->> 'discount')::double precision, 0),
    'price', v_price);
end;
$$;
revoke all on function public.gift_promo_preview(uuid, text, text) from public, anon;
grant execute on function public.gift_promo_preview(uuid, text, text) to authenticated;

-- Алушыны телефон бойынша іздеу: тек аты (бірінші сөз) қайтады.
create or replace function public.find_gift_recipient(p_phone text)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_uid    uuid := auth.uid();
  v_digits text := regexp_replace(coalesce(p_phone, ''), '\D', '', 'g');
  v_name   text;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;
  if not exists (select 1 from public.clients where id = v_uid) then raise exception 'not_a_client'; end if;
  if length(v_digits) < 10 then return jsonb_build_object('found', false); end if;
  select split_part(trim(coalesce(c.name, '')), ' ', 1) into v_name
    from public.clients c
   where right(regexp_replace(coalesce(c.phone, ''), '\D', '', 'g'), 10) = right(v_digits, 10)
     and c.id <> v_uid
   limit 1;
  if not found then return jsonb_build_object('found', false); end if;
  return jsonb_build_object('found', true, 'first_name', coalesce(v_name, ''));
end;
$$;
revoke all on function public.find_gift_recipient(text) from public, anon;
grant execute on function public.find_gift_recipient(text) to authenticated;

-- ── Ескі қолтаңбалар (overload қалмасын) ───────────────────────────────────
drop function if exists public.create_gift_order(uuid, text, text, text, boolean, text);
drop function if exists public.create_registry_gift_order(uuid, text, boolean, boolean);
drop function if exists public.claim_gift(uuid, text, text, text, text, uuid, text, text);

-- ── create_gift_order (промо + телефон) ───────────────────────────────────
create or replace function public.create_gift_order(
  p_product        uuid,
  p_delivery_mode  text,
  p_recipient_name text,
  p_message        text,
  p_hide_price     boolean,
  p_size           text default null,
  p_promo          text default null,
  p_recipient_phone text default null
) returns public.orders
language plpgsql security definer set search_path = public as $$
declare
  v_uid     uuid := auth.uid();
  v_client  public.clients;
  v_prod    public.products;
  v_store   public.stores;
  v_b       public.batches;
  v_price   double precision;
  v_orig    double precision := 0;
  v_fee     double precision := 0;
  v_fit     double precision := 0;
  v_base    double precision;
  v_reduced double precision;
  v_from    double precision;
  v_courier boolean := (p_delivery_mode = 'courier');
  v_size    text := left(trim(coalesce(p_size, '')), 20);
  v_nr      boolean;
  v_wh_id   uuid;
  v_wh_addr text := '';
  v_num     bigint;
  v_item    jsonb;
  v_order   public.orders;
  v_chk     jsonb;
  v_promo_id uuid;
  v_promo_code text := '';
  v_disc    double precision := 0;
  v_recip   uuid;
  v_digits  text := regexp_replace(coalesce(p_recipient_phone, ''), '\D', '', 'g');
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;
  select * into v_client from public.clients where id = v_uid;
  if not found then raise exception 'not_a_client'; end if;
  if not public.feature_enabled('gift_links') then
    raise exception 'feature_disabled';
  end if;
  if p_delivery_mode is null or p_delivery_mode not in ('store', 'courier', 'open') then
    raise exception 'invalid_delivery_mode';
  end if;

  select * into v_prod from public.products where id = p_product;
  if not found or coalesce(v_prod.storefront_hidden, false) then
    raise exception 'product_unavailable';
  end if;
  select * into v_store from public.stores where admin_uid = v_prod.owner_uid;
  if not found or not coalesce(v_store.is_published, false)
     or v_store.status = 'blocked'
     or exists (select 1 from public.users u
                 where u.id = v_store.admin_uid and coalesce(u.blocked, false)) then
    raise exception 'store_unavailable';
  end if;
  if v_uid = v_store.admin_uid then raise exception 'not_a_client'; end if;

  -- Қайтарылмайтын тауарды алушы ауыстыра алмайды → өлшемін біліп сыйлау керек.
  -- (to_jsonb — 0073 бағаны жоқ ортада да функция құламасын.)
  v_nr := public.feature_enabled('non_returnable')
          and coalesce((to_jsonb(v_prod) ->> 'non_returnable')::boolean, false);
  if v_nr and v_size = '' then raise exception 'gift_size_required'; end if;

  if v_size <> '' then
    -- Өлшем белгілі: осы тауардың партияларын id ретімен құлыптап, сол өлшемі
    -- бар ЕҢ АРЗАН партиядан бір данасын ДӘЛ ҚАЗІР қоймадан шығарамыз.
    perform 1 from public.batches b
     where b.product_id = v_prod.id
       and b.warehouse_id::text = any (coalesce(v_store.visible_warehouse_ids, '{}'::text[]))
     order by b.id
     for update;
    select b.* into v_b
      from public.batches b
     where b.product_id = v_prod.id
       and b.warehouse_id::text = any (coalesce(v_store.visible_warehouse_ids, '{}'::text[]))
       and coalesce((b.sizes_quantity ->> v_size)::int, 0)
           - coalesce((b.reserved_sizes ->> v_size)::int, 0) >= 1
     order by public.batch_effective_price(b.selling_price, b.discount), b.date_arrived
     limit 1
     for update of b;
    if not found then raise exception 'gift_size_unavailable'; end if;

    v_price := public.batch_effective_price(v_b.selling_price, v_b.discount);
    if v_price <= 0 then raise exception 'price_invalid'; end if;
    if v_b.selling_price > v_price then v_orig := v_b.selling_price; end if;

    update public.batches
       set sizes_quantity = jsonb_set(coalesce(sizes_quantity, '{}'::jsonb), array[v_size],
             to_jsonb(coalesce((sizes_quantity ->> v_size)::int, 0) - 1))
     where id = v_b.id;
    v_wh_id := v_b.warehouse_id;
    select coalesce(w.address, '') into v_wh_addr
      from public.warehouses w where w.id = v_b.warehouse_id;
    v_wh_addr := coalesce(v_wh_addr, '');
  else
    -- Баға = қолда бары бар партиялардағы ЕҢ ЖОҒАРЫ тиімді баға: өлшем белгісіз,
    -- сондықтан кез келген өлшемге жетуі керек. Клиент бағасына сенбейміз.
    select max(public.batch_effective_price(b.selling_price, b.discount))
      into v_price
      from public.batches b
     where b.product_id = v_prod.id
       and b.warehouse_id::text = any (coalesce(v_store.visible_warehouse_ids, '{}'::text[]))
       and public.batch_available_qty(b.sizes_quantity, b.reserved_sizes) > 0;
    if v_price is null then raise exception 'gift_out_of_stock'; end if;
    if v_price <= 0 then raise exception 'price_invalid'; end if;

    -- «Бастапқы баға» (сызылған): осы бағаны берген партияның жеңілдіксіз бағасы.
    select b.selling_price into v_orig
      from public.batches b
     where b.product_id = v_prod.id
       and b.warehouse_id::text = any (coalesce(v_store.visible_warehouse_ids, '{}'::text[]))
       and public.batch_available_qty(b.sizes_quantity, b.reserved_sizes) > 0
       and public.batch_effective_price(b.selling_price, b.discount) = v_price
     order by b.selling_price desc limit 1;
    if v_orig is null or v_orig <= v_price then v_orig := 0; end if;
  end if;

  -- Промокод (сервер өзі есептейді; бағаны/жеңілдікті клиенттен алмаймыз).
  -- Жеңілдік тек сыйлаушының төлемінен шегеріледі; сыйлықтың құны (gift_paid_amount)
  -- өзгермейді — алушының ауыстыру кредиті толық баға.
  v_promo_code := upper(trim(coalesce(p_promo, '')));
  if v_promo_code <> '' then
    v_chk := public.gift_promo_check(v_store.admin_uid, v_uid, v_prod.id, v_price, v_promo_code, true);
    if v_chk ->> 'reason' is not null then
      raise exception '%', v_chk ->> 'reason';
    end if;
    v_promo_id := (v_chk ->> 'promo_id')::uuid;
    v_disc := coalesce((v_chk ->> 'discount')::double precision, 0);
    update public.promos set used_count = used_count + 1 where id = v_promo_id;
    insert into public.promo_redemptions (promo_id, client_uid, count)
      values (v_promo_id, v_uid, 1)
    on conflict (promo_id, client_uid) do update
      set count = public.promo_redemptions.count + 1, updated_at = now();
  end if;

  -- Алушы Qoima-да тіркелген болса (телефон бойынша) — сыйлық оған қосымша
  -- ішінде ғана жіберіледі, басқа ешкім сілтеме арқылы ала алмайды.
  if length(v_digits) >= 10 then
    select c.id into v_recip from public.clients c
     where right(regexp_replace(coalesce(c.phone, ''), '\D', '', 'g'), 10) = right(v_digits, 10)
       and c.id <> v_uid
     limit 1;
  end if;

  if v_courier then
    if not public.courier_city_enabled(v_store.city) then
      raise exception 'courier_unavailable';
    end if;
    -- DeliveryTariff.feeForSubOrder(index 0) көшірмесі
    select coalesce(nullif((select value from public.app_settings where key = 'delivery_base_fee'), '')::double precision, 690),
           coalesce(nullif((select value from public.app_settings where key = 'delivery_reduced_fee'), '')::double precision, 390),
           coalesce(nullif((select value from public.app_settings where key = 'delivery_reduced_from'), '')::double precision, 15000)
      into v_base, v_reduced, v_from;
    v_fee := case when v_from > 0 and (v_price - v_disc) >= v_from then v_reduced else v_base end;
    -- «Өлшеп көру» ақысын СЫЙЛАУШЫ төлейді (DeliveryTariff.fittingFee, кілт
    -- delivery_fitting_fee). Ақшасы дүкенге — кәдімгі примерка сияқты
    -- (storeAmount = тауар + fitting). Қайтарылмайтын тауарда примерка жоқ.
    if not v_nr then
      v_fit := greatest(coalesce(nullif((select value from public.app_settings
                                          where key = 'delivery_fitting_fee'), '')::double precision, 300), 0);
    end if;
  end if;

  v_item := jsonb_build_object(
    'productId', v_prod.id, 'productName', v_prod.name,
    'batchId', coalesce(v_b.id::text, ''), 'size', v_size, 'qty', 1,
    'price', v_price, 'originalPrice', v_orig,
    'adminUid', v_store.admin_uid, 'storeName', coalesce(v_store.store_name, ''),
    'imageUrl', coalesce(v_prod.images[1], ''),
    'warehouseId', coalesce(v_wh_id::text, ''), 'warehouseAddress', v_wh_addr,
    'selected', true);
  if coalesce(v_prod.brand, '') <> '' then v_item := v_item || jsonb_build_object('brand', v_prod.brand); end if;
  if coalesce(v_prod.type, '') <> '' then v_item := v_item || jsonb_build_object('type', v_prod.type); end if;
  if coalesce(v_prod.color, '') <> '' then v_item := v_item || jsonb_build_object('color', v_prod.color); end if;
  if coalesce(v_prod.variant_note, '') <> '' then v_item := v_item || jsonb_build_object('variantNote', v_prod.variant_note); end if;
  if coalesce(v_prod.articul, '') <> '' then v_item := v_item || jsonb_build_object('articul', v_prod.articul); end if;

  -- Тілек тізімінен (create_registry_gift_order) шақырылса: тауар жолына бронь
  -- id-сі жазылады, алушы = тізім иесі. GUC-ті тек сол definer-функция қояды.
  if coalesce(current_setting('qoima.gift_registry_claim', true), '') <> '' then
    v_item := v_item || jsonb_build_object('registryClaimId', current_setting('qoima.gift_registry_claim', true));
  end if;

  v_num := public.next_counter(v_store.admin_uid, 'orders');

  perform set_config('qoima.gift_rpc', 'on', true);
  insert into public.orders (
    admin_uid, client_uid, client_phone, client_name, store_name, store_phone,
    warehouse_id, warehouse_address,
    items, status, order_type, delivery_mode, deposit_amount, delivery_fee, fitting_fee,
    pickup_code, order_number, seller_id, seller_name, deadline_at,
    stock_restored, payment_card_number, payment_card_holder, payment_bank,
    is_gift, gift_token, gift_recipient_uid, gift_recipient_name, gift_message, gift_hide_price,
    gift_expires_at, gift_giver_name, gift_paid_amount, gift_extra_due,
    gift_delivery_open, promo_id, promo_code, promo_discount, promo_counts_usage
  ) values (
    v_store.admin_uid, v_uid, coalesce(v_client.phone, ''), coalesce(v_client.name, ''),
    coalesce(v_store.store_name, ''), coalesce(v_store.phone, ''),
    v_wh_id, v_wh_addr,
    jsonb_build_array(v_item), 'pending',
    case when v_courier then 'delivery' else 'click_collect' end,
    case when v_courier then 'courier' else 'store' end,
    (v_price - v_disc) + v_fit, v_fee, v_fit,
    lpad((('x' || substr(md5(gen_random_uuid()::text), 1, 7))::bit(28)::int % 1000000)::text, 6, '0'),
    v_num::int, 'онлайн', 'Онлайн', now() + interval '30 minutes',
    -- өлшем брондалса — қойма ұсталды (бас тартқанда қайтарылуы керек)
    (v_size = ''),
    coalesce(v_store.payment_card_number, ''), coalesce(v_store.payment_card_holder, ''),
    coalesce(v_store.payment_bank, ''),
    true, gen_random_uuid(),
    coalesce(nullif(current_setting('qoima.gift_registry_owner', true), '')::uuid, v_recip),
    left(trim(coalesce(p_recipient_name, '')), 60),
    left(trim(coalesce(p_message, '')), 300),
    coalesce(p_hide_price, false),
    now() + interval '30 days',
    left(trim(coalesce(v_client.name, '')), 60),
    v_price, 0,
    (p_delivery_mode = 'open'),
    coalesce(v_promo_id::text, ''), v_promo_code, v_disc, (v_promo_id is not null)
  ) returning * into v_order;
  perform set_config('qoima.gift_rpc', 'off', true);

  if v_size <> '' then
    perform public.recompute_product_status(v_prod.id);
  end if;

  return v_order;
end;
$$;
revoke all on function public.create_gift_order(uuid, text, text, text, boolean, text, text, text) from public, anon;
grant execute on function public.create_gift_order(uuid, text, text, text, boolean, text, text, text) to authenticated;

-- ── get_gift_public (size_locked / recipient_bound / not_for_you) ─────────
create or replace function public.get_gift_public(p_token uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_uid     uuid := auth.uid();
  o         public.orders;
  v_store   public.stores;
  v_prod    public.products;
  v_item    jsonb;
  v_status  text;
  v_sizes   jsonb := '[]'::jsonb;
  v_opts    jsonb := '[]'::jsonb;
  v_giver   boolean;
  v_recip   boolean;
  v_paid    boolean;
  v_credit  double precision;
  v_courier boolean;
  v_nr      boolean := false;
  v_fit     boolean;
  v_chosen  text;
begin
  select * into o from public.orders where gift_token = p_token and is_gift;
  if not found then return null; end if;

  v_item := coalesce(o.items -> 0, '{}'::jsonb);
  v_giver := v_uid is not null and o.client_uid = v_uid;
  v_recip := v_uid is not null and o.gift_recipient_uid = v_uid;
  -- Басқа адамға арналған сыйлықты (кірген бөгде адам) ашпаймыз.
  if o.gift_recipient_uid is not null and v_uid is not null
     and not v_giver and not v_recip then
    return jsonb_build_object('status', 'not_for_you');
  end if;
  select * into v_store from public.stores where admin_uid = o.admin_uid;
  select * into v_prod from public.products
   where id = nullif(v_item ->> 'productId', '')::uuid;

  -- «Төленді» = иесі растады (payment_confirmed_by-ді клиент жаза алмайды, 0065).
  -- Тек status = 'confirmed'-ке сенуге болмайды: сыйлаушы оны өзі қоя алатын еді.
  v_paid := o.status = 'confirmed' and coalesce(o.payment_confirmed_by, '') <> '';

  v_status := case
    when o.status in ('cancelled', 'returned') then 'cancelled'
    when o.gift_claimed_at is not null then 'claimed'
    when v_paid and o.gift_expires_at is not null
         and o.gift_expires_at < now() then 'expired'
    when v_paid then 'ready_to_claim'
    else 'awaiting_payment'
  end;

  v_courier := o.order_type = 'delivery' and coalesce(o.delivery_mode, 'courier') = 'courier';
  v_nr := v_prod.id is not null
          and public.feature_enabled('non_returnable')
          and coalesce((to_jsonb(v_prod) ->> 'non_returnable')::boolean, false);
  v_fit := v_courier and not v_nr;
  -- Сыйлаушы таңдаған (брондалған) өлшем — алушы әлі растамаған кезде
  v_chosen := case when o.gift_claimed_at is null then nullif(v_item ->> 'size', '') end;

  if v_status = 'ready_to_claim' and v_prod.id is not null then
    v_credit := coalesce(o.gift_paid_amount::double precision,
                         (v_item ->> 'price')::double precision, 0);
    v_opts := public.gift_size_options(
      v_prod.id, v_store.visible_warehouse_ids, v_credit, v_courier,
      nullif(v_item ->> 'batchId', '')::uuid, coalesce(v_item ->> 'size', ''),
      v_fit, o.gift_hide_price and not v_giver);
    -- Қайтарылмайтын тауар: тек сыйлаушы таңдаған өлшем (ауыстыруға болмайды)
    if v_chosen is not null then
      select coalesce(jsonb_agg(e), '[]'::jsonb) into v_opts
        from jsonb_array_elements(v_opts) e where e ->> 'size' = v_chosen;
    end if;
    select coalesce(jsonb_agg(e ->> 'size'), '[]'::jsonb) into v_sizes
      from jsonb_array_elements(v_opts) e where (e ->> 'allowed')::boolean;
  end if;

  return jsonb_build_object(
    'status', v_status,
    'giver_first_name', split_part(trim(o.gift_giver_name), ' ', 1),
    'recipient_name', o.gift_recipient_name,
    'message', o.gift_message,
    'product', jsonb_build_object(
      'id', v_prod.id, 'name', coalesce(v_prod.name, v_item ->> 'productName'),
      'brand', coalesce(v_prod.brand, ''), 'color', coalesce(v_prod.color, ''),
      'category_key', coalesce(v_prod.category_key, ''),
      'image_url', coalesce(v_prod.images[1], v_item ->> 'imageUrl', ''),
      'images', to_jsonb(coalesce(v_prod.images, '{}'::text[]))),
    'store', jsonb_build_object(
      'admin_uid', v_store.admin_uid,
      'name', coalesce(v_store.store_name, ''),
      'city', coalesce(v_store.city, ''),
      'address', coalesce(v_store.address, '')),
    'price', case when o.gift_hide_price and not v_giver then null
                  else (v_item ->> 'price')::double precision end,
    'hide_price', o.gift_hide_price,
    'delivery_mode', o.delivery_mode,
    'delivery_open', o.gift_delivery_open and o.gift_claimed_at is null,
    'courier_available', coalesce(public.courier_city_enabled(v_store.city), false),
    'courier_fee_estimate', public.gift_courier_fee(greatest(coalesce((v_item ->> 'price')::double precision, 0) - coalesce(o.promo_discount, 0), 0)),
    'delivery_fee', case when o.delivery_mode = 'courier' then o.delivery_fee else 0 end,
    'available_sizes', v_sizes,
    'size_options', v_opts,
    'chosen_size', v_chosen,
    'size_locked', v_chosen is not null,
    'recipient_bound', o.gift_recipient_uid is not null,
    'non_returnable', v_nr,
    'fitting_available', v_fit,
    'fitting_fee', case when v_courier then coalesce(o.fitting_fee, 0) else 0 end,
    'extra_due', case when v_giver or v_recip then coalesce(o.gift_extra_due, 0) else 0 end,
    'exchange_until', case when (v_giver or v_recip) and o.status = 'completed'
                           then coalesce(o.completed_at, o.created_at) + interval '14 days' end,
    'exchanged', jsonb_array_length(coalesce(o.gift_exchange_log, '[]'::jsonb)) > 0,
    'claimed_size', case when o.gift_claimed_at is not null then v_item ->> 'size' else null end,
    'expires_at', o.gift_expires_at,
    'is_giver', v_giver,
    'is_recipient', v_recip,
    'order_id', case when v_giver or v_recip then to_jsonb(o.id) else null end,
    'order_status', case when v_giver or v_recip then to_jsonb(o.status) else null end
  );
end;
$$;
revoke all on function public.get_gift_public(uuid) from public;
grant execute on function public.get_gift_public(uuid) to anon, authenticated;

-- ── claim_gift (өлшем құлпы + нақты алушы) ───────────────────────────────
create or replace function public.claim_gift(
  p_token    uuid,
  p_size     text,
  p_address  text,
  p_city     text,
  p_phone    text,
  p_product  uuid default null,
  p_alt_size text default null,
  p_delivery text default null
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid      uuid := auth.uid();
  o          public.orders;
  v_client   public.clients;
  v_store    public.stores;
  v_item     jsonb;
  v_old_pid  uuid;
  v_old_size text;
  v_pid      uuid;
  v_size     text := trim(coalesce(p_size, ''));
  v_courier  boolean;
  v_rname    text;
  v_phone    text := left(trim(coalesce(p_phone, '')), 30);
  v_staff    uuid[];
  v_pname    text;
  v_alt_now  text;
  v_title    text;
  v_body     text;
  v_open_courier boolean := false;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;
  select * into v_client from public.clients where id = v_uid;
  if not found then raise exception 'not_a_client'; end if;

  select * into o from public.orders where gift_token = p_token and is_gift for update;
  if not found then raise exception 'gift_not_found'; end if;
  if o.client_uid = v_uid then raise exception 'gift_self_claim'; end if;
  -- Нақты алушыға (телефон/тілек тізімі) жіберілген сыйлықты басқа ешкім алмайды.
  if o.gift_recipient_uid is not null and o.gift_recipient_uid <> v_uid then
    raise exception 'gift_not_for_you';
  end if;
  if o.gift_claimed_at is not null then raise exception 'gift_already_claimed'; end if;
  if o.status in ('cancelled', 'returned') then raise exception 'gift_cancelled'; end if;
  -- иесі растаған төлем ғана (payment_confirmed_by-ді клиент жаза алмайды)
  if o.status <> 'confirmed' or coalesce(o.payment_confirmed_by, '') = '' then
    raise exception 'gift_not_paid';
  end if;
  if o.gift_expires_at is not null and o.gift_expires_at < now() then
    raise exception 'gift_expired';
  end if;
  if v_size = '' then raise exception 'gift_size_required'; end if;
  if length(regexp_replace(v_phone, '\D', '', 'g')) < 7 then
    raise exception 'gift_phone_required';
  end if;

  select * into v_store from public.stores where admin_uid = o.admin_uid;
  if not found or not coalesce(v_store.is_published, false) or v_store.status = 'blocked' then
    raise exception 'store_unavailable';
  end if;

  -- Жеткізуді алушы таңдайды (gift_delivery_open): 'store' — дүкеннен алу,
  -- 'courier' — курьер. Курьер таңдалса тапсырыс gift_apply_item-ге дейін
  -- курьерлікке ауыстырылады (сонда «сомадан артық емес» шегі де қолданылады).
  if o.gift_delivery_open then
    if p_delivery is null or p_delivery not in ('store', 'courier') then
      raise exception 'gift_delivery_required';
    end if;
    if p_delivery = 'courier' then
      if not public.courier_city_enabled(v_store.city) then
        raise exception 'courier_unavailable';
      end if;
      v_open_courier := true;
      perform set_config('qoima.gift_rpc', 'on', true);
      update public.orders set order_type = 'delivery', delivery_mode = 'courier'
       where id = o.id returning * into o;
      perform set_config('qoima.gift_rpc', 'off', true);
    end if;
  end if;

  v_courier := (o.order_type = 'delivery' and coalesce(o.delivery_mode, 'courier') = 'courier');
  if v_courier then
    if length(trim(coalesce(p_address, ''))) < 4 then raise exception 'gift_address_required'; end if;
    if lower(trim(coalesce(p_city, ''))) <> lower(trim(coalesce(v_store.city, '')))
       or not public.courier_city_enabled(v_store.city) then
      raise exception 'gift_city_unsupported';
    end if;
  elsif trim(coalesce(p_alt_size, '')) <> '' then
    raise exception 'gift_fitting_unavailable';
  end if;

  v_item     := coalesce(o.items -> 0, '{}'::jsonb);
  v_old_pid  := nullif(v_item ->> 'productId', '')::uuid;
  v_old_size := coalesce(v_item ->> 'size', '');
  v_pid      := coalesce(p_product, v_old_pid);
  if v_pid is null then raise exception 'gift_not_found'; end if;
  -- Сыйлаушы өлшемді өзі таңдаса — алушы өлшемді де, тауарды да өзгерте алмайды
  -- (курьер примеркасына екінші өлшем — тек қосымша). Сыйлық берілген соң дүкенде
  -- ауыстыру gift_store_exchange арқылы жалғаса береді.
  if v_old_size <> '' and (v_pid is distinct from v_old_pid or v_size <> v_old_size) then
    raise exception 'gift_size_locked';
  end if;

  -- Қойма/баға/позиция — бір ғана көзде (бір транзакция, for update)
  o := public.gift_apply_item(o.id, v_pid, v_size, p_alt_size, 'recipient');

  v_item    := coalesce(o.items -> 0, '{}'::jsonb);
  v_pname   := coalesce(v_item ->> 'productName', '');
  v_alt_now := coalesce(v_item ->> 'altSize', '');
  v_rname   := coalesce(nullif(trim(o.gift_recipient_name), ''), nullif(trim(v_client.name), ''), '');

  perform set_config('qoima.gift_rpc', 'on', true);
  update public.orders set
    address = case when v_courier then trim(p_address) else '' end,
    client_city = left(trim(coalesce(p_city, '')), 80),
    -- дүкенге/курьерге ТАПСЫРАТЫН адамның байланысы (сыйлаушы gift_giver_name-де)
    client_name = case when v_rname <> '' then v_rname else client_name end,
    client_phone = v_phone,
    delivery_fee = case when v_open_courier
      then public.gift_courier_fee(greatest(coalesce((v_item ->> 'price')::double precision, 0) - coalesce(o.promo_discount, 0), 0))
      else delivery_fee end,
    gift_recipient_uid = v_uid,
    gift_recipient_name = v_rname,
    gift_recipient_phone = v_phone,
    gift_claimed_at = now(),
    stock_restored = false
  where id = o.id
  returning * into o;
  perform set_config('qoima.gift_rpc', 'off', true);

  -- Дүкен иесі + сатушылар (on_order_push-пен бірдей алушылар). Алушы өлшемді
  -- немесе тауарды ауыстырса — тақырыпта айтылады, қосымша төлем де көрсетіледі.
  v_title := case
    when v_pid is distinct from v_old_pid
      then '🎁 Подарок: выбран другой товар / Сыйлық: басқа тауар таңдалды'
    when v_old_size <> '' and v_old_size <> v_size
      then '🎁 Подарок: размер изменён / Сыйлық: өлшем ауыстырылды'
    else '🎁 Подарок: размер выбран / Сыйлық: өлшем таңдалды' end;
  v_body := '№' || o.order_number || ' · ' || v_pname || ' · ' || v_size
    || case when v_alt_now <> '' then ' (+' || v_alt_now || ' примерка/өлшеп көру)' else '' end
    || case when coalesce(o.gift_extra_due, 0) > 0
            then ' · доплата/қосымша ' || round(o.gift_extra_due)::bigint || ' ₸' else '' end;
  select array_agg(id) into v_staff
    from public.users
   where id = o.admin_uid or (owner_id = o.admin_uid and role = 'seller');
  perform public.notify_push(
    coalesce(v_staff, array[o.admin_uid]), v_title, v_body,
    jsonb_build_object('type', 'order', 'orderId', o.id));
  -- Сыйлаушыға
  perform public.notify_push(
    array[o.client_uid],
    '🎁 Подарок принят / Сыйлығыңыз қабылданды',
    coalesce(nullif(v_rname, ''), 'Получатель') || ' — ' || v_size,
    jsonb_build_object('type', 'gift_claimed', 'orderId', o.id));

  -- Курьерлерге: on_courier_job_push статус өзгермегендіктен жанбайды, сондықтан осында.
  if v_courier then
    declare v_couriers uuid[];
    begin
      select array_agg(u.id) into v_couriers from public.users u
       where u.role = 'courier' and u.courier_status = 'active'
         and coalesce(u.blocked, false) = false and u.city = v_store.city;
      if v_couriers is not null then
        perform public.notify_push(
          v_couriers,
          '🚚 Новый заказ / Жаңа тапсырыс',
          coalesce(nullif(v_store.city, ''), '') || ' · '
            || coalesce(o.delivery_fee, 0)::int || ' ₸ · '
            || coalesce(nullif(o.store_name, ''), 'магазин'),
          jsonb_build_object('type', 'courier_work', 'orderId', o.id));
      end if;
    end;
  end if;

  -- Алушыға шикі жол емес, тазартылған көрініс (жасырын баға, чек, карта жоқ)
  return public.gift_recipient_view(o);
end;
$$;
revoke all on function public.claim_gift(uuid, text, text, text, text, uuid, text, text) from public, anon;
grant execute on function public.claim_gift(uuid, text, text, text, text, uuid, text, text) to authenticated;

-- ── create_registry_gift_order (промо) ───────────────────────────────────
create or replace function public.create_registry_gift_order(
  p_claim      uuid,
  p_message    text,
  p_hide_price boolean default false,
  p_fitting    boolean default false,
  p_promo      text default null
) returns public.orders
language plpgsql security definer set search_path = public as $$
declare
  v_uid    uuid := auth.uid();
  v_claim  public.gift_registry_claims;
  v_item   public.gift_registry_items;
  v_reg    public.gift_registries;
  v_rname  text;
  v_order  public.orders;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;
  if not public.feature_enabled('gift_registry') then raise exception 'feature_disabled'; end if;

  -- Құлып реті: позиция → бронь (reserve_registry_item / триггермен бірдей)
  select i.* into v_item from public.gift_registry_items i
   where i.id = (select item_id from public.gift_registry_claims
                  where id = p_claim and guest_uid = v_uid)
   for update;
  if not found then raise exception 'registry_claim_not_active'; end if;
  select * into v_claim from public.gift_registry_claims
   where id = p_claim and guest_uid = v_uid for update;
  if not found or v_claim.status <> 'reserved' or v_claim.order_id is not null
     or (v_claim.reserved_until is not null and v_claim.reserved_until < now()) then
    raise exception 'registry_claim_not_active';
  end if;
  select * into v_reg from public.gift_registries where id = v_claim.registry_id;
  if not found or v_reg.owner_uid = v_uid then raise exception 'registry_claim_not_active'; end if;

  select split_part(trim(coalesce(c.name, '')), ' ', 1) into v_rname
    from public.clients c where c.id = v_reg.owner_uid;

  -- create_gift_order бұларды тапсырыс INSERT-інде қолданады (клиент UPDATE-пен
  -- items-ті өзгерте алмайды — guard_orders_client_money).
  perform set_config('qoima.gift_registry_claim', v_claim.id::text, true);
  perform set_config('qoima.gift_registry_owner', v_reg.owner_uid::text, true);
  v_order := public.create_gift_order(
    v_item.product_id,
    case when coalesce(p_fitting, false) then 'courier' else 'open' end,
    coalesce(v_rname, ''), p_message, coalesce(p_hide_price, false),
    nullif(v_item.size, ''), p_promo, null);
  perform set_config('qoima.gift_registry_claim', '', true);
  perform set_config('qoima.gift_registry_owner', '', true);

  update public.gift_registry_claims
     set order_id = v_order.id, qty = 1,
         reserved_until = greatest(coalesce(reserved_until, now()), now() + interval '48 hours'),
         updated_at = now()
   where id = v_claim.id;

  return v_order;
end;
$$;
revoke all on function public.create_registry_gift_order(uuid, text, boolean, boolean, text) from public, anon;
grant execute on function public.create_registry_gift_order(uuid, text, boolean, boolean, text) to authenticated;

-- ── «Маған келген»: тек ТӨЛЕНГЕН сыйлықтар ──────────────────────────────────
--  Алушы нақты адам (телефон / тілек тізімі) болған кезде тапсырыс төлемге дейін-ақ
--  gift_recipient_uid-ке ие болады — төленбеген сыйлық алушыға көрінбеуі керек.
create or replace function public.get_my_received_gifts()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  r     jsonb;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;
  select coalesce(jsonb_agg(public.gift_recipient_view(o) order by o.created_at desc), '[]'::jsonb)
    into r
    from public.orders o
   where o.is_gift
     and o.gift_recipient_uid = v_uid
     and o.client_uid is distinct from v_uid
     and coalesce(o.payment_confirmed_by, '') <> '';
  return r;
end;
$$;
revoke all on function public.get_my_received_gifts() from public, anon;
grant execute on function public.get_my_received_gifts() to authenticated;
-- ── Алушыға push: төлем расталды (тауар атауынсыз) ─────────────────────────
create or replace function public.on_gift_recipient_push()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_title text;
  v_body  text;
  v_data  jsonb;
begin
  if not new.is_gift or new.gift_recipient_uid is null then return new; end if;
  if new.status is not distinct from old.status then return new; end if;

  -- Төлем расталды, алушы әлі ашпаған: «Сізге сыйлық бар». Тілек тізімінің
  -- сыйлығында иесіне on_order_registry_claims өзі push жібереді.
  if new.status = 'confirmed' and new.gift_claimed_at is null
     and coalesce(new.payment_confirmed_by, '') <> ''
     and not coalesce((new.items -> 0) ? 'registryClaimId', false) then
    perform public.notify_push(
      array[new.gift_recipient_uid],
      '🎁 Вам подарок! / Сізге сыйлық бар!',
      coalesce(nullif(split_part(trim(new.gift_giver_name), ' ', 1), ''), 'Qoima')
        || ' · Откройте в Qoima / Qoima-да ашыңыз',
      jsonb_build_object('type', 'gift_received', 'orderId', new.id));
    return new;
  end if;

  v_title := case new.status
    when 'ready'     then '📦 Подарок готов к выдаче / Сыйлық беруге дайын'
    when 'completed' then '🎉 Подарок получен / Сыйлық тапсырылды'
    when 'cancelled' then '❌ Заказ отменён / Тапсырыс бас тартылды'
    else null end;
  if v_title is null then return new; end if;
  perform public.notify_push(
    array[new.gift_recipient_uid], v_title,
    coalesce(nullif(new.store_name, ''), 'Магазин') || ' · №' || new.order_number,
    jsonb_build_object('type', 'order_status', 'orderId', new.id, 'status', new.status,
                       'gift', 'recipient'));
  return new;
end;
$$;
revoke all on function public.on_gift_recipient_push() from public, anon, authenticated;

-- ── Мерзімі өткен, алынбаған сыйлық: брондалған өлшем қоймаға қайтады ──────
--  Ақша төленген, сыйлық 30 күнде алынбады → өлшем мәңгі бұғатталып қалмасын.
--  stock_restored = true болады, сондықтан кейін дүкен тапсырысты бас тартса да
--  екінші рет қосылмайды. Сыйлаушы «қайтаруды сұрау» арқылы ақшасын дүкеннен алады.
create or replace function public.sweep_gift_expired_holds() returns void
language plpgsql security definer set search_path = public as $$
declare
  r      record;
  v_item jsonb;
  v_b    uuid;
  v_sz   text;
begin
  for r in
    select id, items, client_uid, order_number
      from public.orders
     where is_gift
       and gift_claimed_at is null
       and status = 'confirmed'
       and gift_expires_at is not null
       and gift_expires_at < now()
       and coalesce(stock_restored, false) = false
     for update skip locked
  loop
    v_item := coalesce(r.items -> 0, '{}'::jsonb);
    v_b    := nullif(v_item ->> 'batchId', '')::uuid;
    v_sz   := coalesce(v_item ->> 'size', '');
    if v_b is not null and v_sz <> '' then
      update public.batches
         set sizes_quantity = jsonb_set(coalesce(sizes_quantity, '{}'::jsonb), array[v_sz],
               to_jsonb(coalesce((sizes_quantity ->> v_sz)::int, 0) + 1))
       where id = v_b;
    end if;
    perform set_config('qoima.gift_rpc', 'on', true);
    update public.orders set stock_restored = true where id = r.id;
    perform set_config('qoima.gift_rpc', 'off', true);
    if nullif(v_item ->> 'productId', '') is not null then
      perform public.recompute_product_status((v_item ->> 'productId')::uuid);
    end if;
    if r.client_uid is not null then
      perform public.notify_push(
        array[r.client_uid],
        '⌛ Срок подарка истёк / Сыйлық мерзімі өтті',
        'Заказ №' || r.order_number || ' — запросите возврат у магазина / дүкеннен қайтаруды сұраңыз',
        jsonb_build_object('type', 'gift_reminder', 'orderId', r.id));
    end if;
  end loop;
end;
$$;
revoke all on function public.sweep_gift_expired_holds() from public, anon, authenticated;

select cron.unschedule('gift-expired-holds')
  where exists (select 1 from cron.job where jobname = 'gift-expired-holds');
select cron.schedule('gift-expired-holds', '30 5 * * *', $$select public.sweep_gift_expired_holds()$$);
