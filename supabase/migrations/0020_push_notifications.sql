-- ════════════════════════════════════════════════════════════════════════════
--  0020 · Push-хабарламалар: notify_push диспетчері + оқиға триггерлері
-- ────────────────────────────────────────────────────────────────────────────
--  pg_net арқылы send-push edge function-ды асинхронды шақырады (транзакцияны
--  бөгемейді, сәтсіз болса негізгі операция бұзылмайды — exception жұтылады).
--  Секрет vault-та ('push_trigger_secret', 0018-де жасалды осы файлда емес —
--  Bash арқылы бөлек орнатылды: см. push_service memory).
-- ════════════════════════════════════════════════════════════════════════════

-- ── notify_push: барлық триггерлер осы арқылы шақырады ───────────────────────
create or replace function public.notify_push(
  p_uids uuid[],
  p_title text,
  p_body text,
  p_data jsonb default '{}'::jsonb
) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_secret text;
begin
  if p_uids is null or array_length(p_uids, 1) is null then return; end if;
  select decrypted_secret into v_secret
    from vault.decrypted_secrets where name = 'push_trigger_secret';
  if v_secret is null then return; end if; -- секрет орнатылмаса — үнсіз өтеміз

  perform net.http_post(
    url := 'https://ujpcdfgwxdholsepioji.supabase.co/functions/v1/send-push',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'apikey', 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVqcGNkZmd3eGRob2xzZXBpb2ppIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODI4MDYxMzcsImV4cCI6MjA5ODM4MjEzN30.E2AIz2quumSuU0K3lzONM8alw26NLzje3zvWWFUMk7o',
      'x-push-secret', v_secret
    ),
    body := jsonb_build_object(
      'uids', to_jsonb(p_uids),
      'title', p_title,
      'body', p_body,
      'data', p_data
    )
  );
exception when others then
  -- Push сәтсіз болса да НЕГІЗГІ операция (сатылым/тапсырыс/пікір) бұзылмайды.
  null;
end;
$$;

-- ── 1) Дүкен иесіне: складынан товар сатылды (sales_history, type='sale') ────
create or replace function public.on_sale_push() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.type = 'sale' then
    perform public.notify_push(
      array[new.owner_uid],
      'Новая продажа',
      coalesce(new.product_name, '') || ' — ' || new.total_price::int || ' ₸',
      jsonb_build_object('type', 'sale', 'saleId', new.id)
    );
  end if;
  return new;
end;
$$;
drop trigger if exists trg_sale_push on public.sales_history;
create trigger trg_sale_push after insert on public.sales_history
  for each row execute function public.on_sale_push();

-- ── 2) Возврат: иесіне барлығы, сатушыларға тек ОНЛАЙН возврат ───────────────
create or replace function public.on_return_push() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_title text;
  v_uids  uuid[];
begin
  if new.type = 'online' then
    v_title := 'Новый онлайн-возврат';
    select array_agg(id) into v_uids
      from public.users
      where id = new.admin_uid or (owner_id = new.admin_uid and role = 'seller');
  else
    v_title := 'Новый возврат';
    v_uids := array[new.admin_uid];
  end if;
  perform public.notify_push(
    coalesce(v_uids, array[new.admin_uid]),
    v_title,
    coalesce(new.client_name, '') || ' — ' || new.total_amount::int || ' ₸',
    jsonb_build_object('type', 'return', 'returnId', new.id)
  );
  return new;
end;
$$;
drop trigger if exists trg_return_push on public.returns;
create trigger trg_return_push after insert on public.returns
  for each row execute function public.on_return_push();

-- ── 3) Онлайн тапсырыс түсті: иесіне + сол дүкеннің барлық сатушыларына ──────
create or replace function public.on_order_push() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_uids uuid[];
begin
  select array_agg(id) into v_uids
    from public.users
    where id = new.admin_uid or (owner_id = new.admin_uid and role = 'seller');
  perform public.notify_push(
    coalesce(v_uids, array[new.admin_uid]),
    'Новый заказ №' || new.order_number,
    coalesce(new.client_name, '') || ' — ' || new.deposit_amount::int || ' ₸',
    jsonb_build_object('type', 'order', 'orderId', new.id)
  );
  return new;
end;
$$;
drop trigger if exists trg_order_push on public.orders;
create trigger trg_order_push after insert on public.orders
  for each row execute function public.on_order_push();

-- ── 4) Тапсырыс статусы өзгерді → клиентке ────────────────────────────────────
create or replace function public.on_order_status_push() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_title text;
begin
  if new.status is not distinct from old.status or new.client_uid is null then
    return new;
  end if;
  v_title := case new.status
    when 'confirmed' then 'Заказ подтверждён'
    when 'ready'     then 'Заказ готов к выдаче'
    when 'completed' then 'Заказ выполнен'
    when 'rejected'  then 'Заказ отклонён'
    when 'cancelled' then 'Заказ отменён'
    else null
  end;
  if v_title is null then return new; end if;
  perform public.notify_push(
    array[new.client_uid],
    v_title,
    'Заказ №' || new.order_number,
    jsonb_build_object('type', 'order_status', 'orderId', new.id, 'status', new.status)
  );
  return new;
end;
$$;
drop trigger if exists trg_order_status_push on public.orders;
create trigger trg_order_status_push after update on public.orders
  for each row execute function public.on_order_status_push();

-- ── 5) Жаңа пікір → дүкен иесіне ──────────────────────────────────────────────
create or replace function public.on_review_push() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform public.notify_push(
    array[new.admin_uid],
    'Новый отзыв ★' || new.rating,
    coalesce(nullif(new.client_name, ''), 'Покупатель') || ': ' ||
      left(coalesce(new.comment, ''), 80),
    jsonb_build_object('type', 'review', 'productId', new.product_id)
  );
  return new;
end;
$$;
drop trigger if exists trg_review_push on public.product_reviews;
create trigger trg_review_push after insert on public.product_reviews
  for each row execute function public.on_review_push();

-- ── 6) Пікірге дүкен жауап берді → клиентке ───────────────────────────────────
create or replace function public.on_review_reply_push() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if coalesce(old.seller_reply, '') = '' and coalesce(new.seller_reply, '') <> '' then
    perform public.notify_push(
      array[new.client_uid],
      'Ответ на ваш отзыв',
      left(new.seller_reply, 100),
      jsonb_build_object('type', 'review_reply', 'productId', new.product_id)
    );
  end if;
  return new;
end;
$$;
drop trigger if exists trg_review_reply_push on public.product_reviews;
create trigger trg_review_reply_push after update on public.product_reviews
  for each row execute function public.on_review_reply_push();

-- ── 7) Модератор жаңа баннер қосты (active) → БАРЛЫҚ клиенттерге ────────────
create or replace function public.on_banner_push() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_uids uuid[];
begin
  if new.active is distinct from true then return new; end if;
  select array_agg(id) into v_uids from public.clients;
  if v_uids is null then return new; end if;
  perform public.notify_push(
    v_uids,
    coalesce(nullif(new.title, ''), 'Новое предложение'),
    new.subtitle,
    jsonb_build_object('type', 'banner', 'bannerId', new.id)
  );
  return new;
end;
$$;
drop trigger if exists trg_banner_push on public.banners;
create trigger trg_banner_push after insert on public.banners
  for each row execute function public.on_banner_push();
