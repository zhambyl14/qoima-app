-- ════════════════════════════════════════════════════════════════════════════
--  0022 · Онлайн-төлем жаңарту: модератор картасы (app_settings) + чек 14 күн
--  sweep + пуш-триггерлерді толықтыру (ешкім хабарсыз қалмайды).
-- ────────────────────────────────────────────────────────────────────────────
--  1) app_settings — платформа реквизиттері (клиент төлейтін карта). Оқу —
--     кез келген авторизацияланған қолданушы (checkout-та көрсету үшін),
--     жазу — тек superadmin (модератор).
--  2) sweep_expired_receipts — 14+ күн бұрын тіркелген чектерді
--     cloudinary_delete_queue кезегіне қосып, orders.receipt_url-ды тазалайды.
--     Шақырушы — cloudinary-cleanup edge function (drain режимі).
--  3) Пуш-триггерлер:
--       · on_order_status_push: 'reserved' (бронь расталды) қосылды
--       · чек тіркелді → дүкен иесіне
--       · сатушы қосылу өтінімі → иесіне; шешім → сатушыға
--       · дүкен ашу өтінімі → модераторларға; шешім → иесіне
--       · дүкен деректерін өзгерту өтінімі → модераторларға; шешім → иесіне
--       · жаңа шағым → модераторларға
-- ════════════════════════════════════════════════════════════════════════════

-- ── 1) app_settings ──────────────────────────────────────────────────────────
create table if not exists public.app_settings (
  key        text primary key,
  value      text not null default '',
  updated_at timestamptz not null default now()
);
alter table public.app_settings enable row level security;

drop policy if exists app_settings_read on public.app_settings;
create policy app_settings_read on public.app_settings
  for select to authenticated using (true);

drop policy if exists app_settings_write on public.app_settings;
create policy app_settings_write on public.app_settings
  for all using (public.is_superadmin()) with check (public.is_superadmin());

insert into public.app_settings(key, value) values
  ('payment_card_number', ''),
  ('payment_card_holder', ''),
  ('payment_card_bank', '')
on conflict (key) do nothing;

-- ── 2) Чек 14 күн sweep ──────────────────────────────────────────────────────
create or replace function public.sweep_expired_receipts(p_days int default 14)
returns int
language plpgsql security definer set search_path = public as $$
declare
  v_count int := 0;
begin
  with expired as (
    select id, receipt_url
    from public.orders
    where coalesce(receipt_url, '') <> ''
      and receipt_submitted_at is not null
      and receipt_submitted_at < now() - make_interval(days => p_days)
  ),
  queued as (
    insert into public.cloudinary_delete_queue(url)
    select receipt_url from expired
    returning 1
  )
  update public.orders o
     set receipt_url = ''
    from expired e
   where o.id = e.id;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- ── 3а) Тапсырыс статусы → клиентке ('reserved' қосылды) ─────────────────────
create or replace function public.on_order_status_push() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_title text;
begin
  if new.status is not distinct from old.status or new.client_uid is null then
    return new;
  end if;
  v_title := case new.status
    when 'reserved'  then 'Бронь подтверждена'
    when 'confirmed' then 'Оплата подтверждена'
    when 'ready'     then 'Заказ готов к выдаче'
    when 'completed' then 'Заказ выполнен'
    when 'rejected'  then 'Чек отклонён — прикрепите новый'
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

-- ── 3б) Чек тіркелді → дүкен иесіне (төлемді тек иесі растайды) ──────────────
create or replace function public.on_receipt_push() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if coalesce(new.receipt_url, '') <> ''
     and new.receipt_url is distinct from old.receipt_url then
    perform public.notify_push(
      array[new.admin_uid],
      'Новый чек об оплате',
      'Заказ №' || new.order_number || ' — проверьте и подтвердите оплату',
      jsonb_build_object('type', 'receipt', 'orderId', new.id)
    );
  end if;
  return new;
end;
$$;
drop trigger if exists trg_receipt_push on public.orders;
create trigger trg_receipt_push after update on public.orders
  for each row execute function public.on_receipt_push();

-- ── 3в) Сатушы қосылу өтінімі ────────────────────────────────────────────────
-- Жаңа/қайта жіберілген өтінім → дүкен иесіне.
create or replace function public.on_join_request_push() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'pending'
     and (tg_op = 'INSERT' or new.status is distinct from old.status) then
    perform public.notify_push(
      array[new.admin_uid],
      'Новая заявка продавца',
      coalesce(nullif(new.seller_name, ''), 'Продавец') || ' хочет присоединиться',
      jsonb_build_object('type', 'join_request', 'requestId', new.id)
    );
  end if;
  return new;
end;
$$;
drop trigger if exists trg_join_request_push on public.join_requests;
create trigger trg_join_request_push after insert or update on public.join_requests
  for each row execute function public.on_join_request_push();

-- Шешім (approved/rejected) → сатушыға.
create or replace function public.on_join_decision_push() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_title text;
begin
  if new.status is not distinct from old.status then return new; end if;
  v_title := case new.status
    when 'approved' then 'Заявка одобрена 🎉'
    when 'rejected' then 'Заявка отклонена'
    else null
  end;
  if v_title is null then return new; end if;
  perform public.notify_push(
    array[new.seller_uid],
    v_title,
    case new.status
      when 'approved' then 'Добро пожаловать в команду магазина!'
      else 'Владелец магазина отклонил вашу заявку'
    end,
    jsonb_build_object('type', 'join_decision', 'requestId', new.id, 'status', new.status)
  );
  return new;
end;
$$;
drop trigger if exists trg_join_decision_push on public.join_requests;
create trigger trg_join_decision_push after update on public.join_requests
  for each row execute function public.on_join_decision_push();

-- ── 3г) Дүкен ашу өтінімі → модераторларға; шешім → иесіне ───────────────────
create or replace function public.on_shop_request_push() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_uids uuid[];
begin
  select array_agg(id) into v_uids
    from public.users where role = 'superadmin';
  if v_uids is null then return new; end if;
  perform public.notify_push(
    v_uids,
    'Новая заявка на магазин',
    coalesce(nullif(new.shop_name, ''), 'Без названия') ||
      ' · ' || coalesce(new.city, ''),
    jsonb_build_object('type', 'shop_request', 'requestId', new.id)
  );
  return new;
end;
$$;
drop trigger if exists trg_shop_request_push on public.shop_requests;
create trigger trg_shop_request_push after insert on public.shop_requests
  for each row execute function public.on_shop_request_push();

create or replace function public.on_shop_decision_push() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_title text;
begin
  if new.status is not distinct from old.status then return new; end if;
  v_title := case new.status
    when 'approved' then 'Магазин одобрен 🎉'
    when 'rejected' then 'Заявка на магазин отклонена'
    else null
  end;
  if v_title is null then return new; end if;
  perform public.notify_push(
    array[new.owner_uid],
    v_title,
    case new.status
      when 'approved' then 'Можно начинать работу — добро пожаловать!'
      else coalesce(nullif(new.review_note, ''), 'Подробности в приложении')
    end,
    jsonb_build_object('type', 'shop_decision', 'requestId', new.id, 'status', new.status)
  );
  return new;
end;
$$;
drop trigger if exists trg_shop_decision_push on public.shop_requests;
create trigger trg_shop_decision_push after update on public.shop_requests
  for each row execute function public.on_shop_decision_push();

-- ── 3д) Дүкен деректерін өзгерту өтінімі → модераторларға; шешім → иесіне ────
create or replace function public.on_store_edit_push() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_uids uuid[];
begin
  select array_agg(id) into v_uids
    from public.users where role = 'superadmin';
  if v_uids is null then return new; end if;
  perform public.notify_push(
    v_uids,
    'Запрос на изменение магазина',
    coalesce(nullif(new.shop_name, ''), 'Магазин'),
    jsonb_build_object('type', 'store_edit_request', 'requestId', new.id)
  );
  return new;
end;
$$;
drop trigger if exists trg_store_edit_push on public.store_edit_requests;
create trigger trg_store_edit_push after insert on public.store_edit_requests
  for each row execute function public.on_store_edit_push();

create or replace function public.on_store_edit_decision_push() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_title text;
begin
  if new.status is not distinct from old.status then return new; end if;
  v_title := case new.status
    when 'approved' then 'Изменения магазина одобрены'
    when 'rejected' then 'Изменения магазина отклонены'
    else null
  end;
  if v_title is null then return new; end if;
  perform public.notify_push(
    array[new.owner_uid],
    v_title,
    coalesce(nullif(new.review_note, ''), 'Подробности в приложении'),
    jsonb_build_object('type', 'store_edit_decision', 'requestId', new.id, 'status', new.status)
  );
  return new;
end;
$$;
drop trigger if exists trg_store_edit_decision_push on public.store_edit_requests;
create trigger trg_store_edit_decision_push after update on public.store_edit_requests
  for each row execute function public.on_store_edit_decision_push();

-- ── 3е) Жаңа шағым → модераторларға ──────────────────────────────────────────
create or replace function public.on_report_push() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_uids uuid[];
begin
  select array_agg(id) into v_uids
    from public.users where role = 'superadmin';
  if v_uids is null then return new; end if;
  perform public.notify_push(
    v_uids,
    'Новая жалоба',
    coalesce(nullif(new.target_name, ''), new.target_type) ||
      ' · ' || new.reason,
    jsonb_build_object('type', 'report', 'reportId', new.id)
  );
  return new;
end;
$$;
drop trigger if exists trg_report_push on public.content_reports;
create trigger trg_report_push after insert on public.content_reports
  for each row execute function public.on_report_push();
