-- ════════════════════════════════════════════════════════════════════════════
--  0058 · Жеткізу қаласы + 0057 әкелген жаңа оқиғаларға хабарламалар
-- ────────────────────────────────────────────────────────────────────────────
--  A) `orders.client_city` — клиент себетте таңдайтын ЖЕТКІЗУ ҚАЛАСЫ.
--     Бұрын қала тек `address` жолының ішінде еркін мәтін болатын. Дүкен өзі
--     жеткізетін жағдайда сатушы қай қалаға жіберетінін білмейтін («Бараева
--     28» деген көше бірнеше қалада бар), әрі курьер қызметінің бар-жоғы
--     клиенттің профиліндегі — іс жүзінде БОС — қаладан анықталатын.
--
--  B) ЖАҢА ХАБАРЛАМА ТҮРЛЕРІ. 0057-де пайда болған оқиғалар үнсіз өтетін:
--       · возратты дүкен қабылдады / ақшасы қайтарылды  → КЛИЕНТ білмейтін;
--       · қалада жаңа жұмыс шықты                       → КУРЬЕР 25 секундтық
--         поллингпен ғана табатын (қосымша жабық болса — мүлде білмейтін);
--       · модератор қаланы қосты                        → ол қаладағы дүкен де,
--         курьер де ЕШҚАШАН білмейтін.
-- ════════════════════════════════════════════════════════════════════════════

-- ══════════════════════════════════════════════════════════════════════════
--  A · Жеткізу қаласы
-- ══════════════════════════════════════════════════════════════════════════

alter table public.orders
  add column if not exists client_city text not null default '';

-- ══════════════════════════════════════════════════════════════════════════
--  B1 · Возврат күйі — КЛИЕНТКЕ
-- ══════════════════════════════════════════════════════════════════════════
--  Клиент возврат ашқан соң «не болып жатыр?» деген сұрақпен қалатын.
--  Ең маңыздысы — «ақшаңыз қайтарылды»: оны білмесе, клиент дүкенге
--  қоңырау шала бастайды.
create or replace function public.on_return_status_push()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_title text;
  v_body  text;
  v_first text := coalesce(new.items->0->>'product_title',
                           new.items->0->>'productName', '');
  v_uids  uuid[];
  v_city  text;
begin
  if new.status is not distinct from old.status then return new; end if;

  -- ── Клиентке ────────────────────────────────────────────────────────────
  if new.client_uid is not null then
    if new.status = 'approved' then
      v_title := '✅ Возврат одобрен / Қайтарым мақұлданды';
      v_body  := case when new.pickup = 'courier'
                   then 'Курьер заберёт товар / Курьер тауарды алады'
                   else 'Принесите товар в магазин / Тауарды дүкенге әкеліңіз'
                 end;
    elsif new.status = 'rejected' then
      v_title := '❌ Возврат отклонён / Қайтарым қабылданбады';
      v_body  := coalesce(nullif(new.rejection_reason, ''), v_first);
    elsif new.status = 'received' then
      v_title := '📦 Магазин принял товар / Дүкен тауарды қабылдады';
      v_body  := 'Возврат денег готовится / Ақша қайтару дайындалуда';
    elsif new.status = 'refunded' then
      v_title := '💸 Деньги возвращены / Ақша қайтарылды';
      v_body  := new.total_amount::int || ' ₸'
                 || case when coalesce(new.refund_method, '') = 'cash'
                      then ' — наличными / қолма-қол'
                      else ' — на карту / картаға' end;
    end if;

    if v_title is not null then
      perform public.notify_push(
        array[new.client_uid], v_title, v_body,
        jsonb_build_object('type', 'return_status', 'returnId', new.id));
    end if;
  end if;

  -- ── Курьерлерге: қалада жаңа возврат тасымалы шықты ─────────────────────
  --  Дүкен растаған, курьермен алынатын, әлі ешкім алмаған возврат.
  if new.status = 'approved'
     and new.pickup = 'courier'
     and new.courier_uid is null then
    select s.city into v_city from public.stores s
     where s.admin_uid = new.admin_uid;
    if public.courier_city_enabled(v_city) then
      select array_agg(u.id) into v_uids from public.users u
       where u.role = 'courier' and u.courier_status = 'active'
         and coalesce(u.blocked, false) = false and u.city = v_city;
      perform public.notify_push(
        coalesce(v_uids, '{}'::uuid[]),
        '↩️ Новый возврат / Жаңа қайтарым',
        coalesce(nullif(v_city, ''), '') || ' — забрать у клиента / клиенттен алу',
        jsonb_build_object('type', 'courier_work', 'returnId', new.id));
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_return_status_push on public.returns;
create trigger trg_return_status_push after update on public.returns
  for each row execute function public.on_return_status_push();

-- ══════════════════════════════════════════════════════════════════════════
--  B2 · Қалада жаңа жеткізу шықты — КУРЬЕРЛЕРГЕ
-- ══════════════════════════════════════════════════════════════════════════
--  Бұған дейін курьер жаңа жұмысты тек 25 секундтық поллингпен көретін, ал
--  қосымша жабық тұрса — мүлде білмейтін. Тапсырыс расталған сәтте (дүкен
--  чекті растады) сол қаладағы белсенді курьерлерге push барады.
create or replace function public.on_courier_job_push()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_city text;
  v_uids uuid[];
begin
  if new.status is not distinct from old.status then return new; end if;
  if new.status <> 'confirmed' then return new; end if;
  if new.order_type <> 'delivery' then return new; end if;
  if coalesce(new.delivery_mode, 'courier') <> 'courier' then return new; end if;
  if new.courier_uid is not null then return new; end if;

  select s.city into v_city from public.stores s where s.admin_uid = new.admin_uid;
  if not public.courier_city_enabled(v_city) then return new; end if;

  select array_agg(u.id) into v_uids from public.users u
   where u.role = 'courier' and u.courier_status = 'active'
     and coalesce(u.blocked, false) = false and u.city = v_city;
  if v_uids is null then return new; end if;

  perform public.notify_push(
    v_uids,
    '🚚 Новый заказ / Жаңа тапсырыс',
    coalesce(nullif(v_city, ''), '') || ' · '
      || coalesce(new.delivery_fee, 0)::int || ' ₸ · '
      || coalesce(nullif(new.store_name, ''), 'магазин'),
    jsonb_build_object('type', 'courier_work', 'orderId', new.id));
  return new;
end;
$$;

drop trigger if exists trg_courier_job_push on public.orders;
create trigger trg_courier_job_push after update on public.orders
  for each row execute function public.on_courier_job_push();

-- ══════════════════════════════════════════════════════════════════════════
--  B3 · Модератор қаланы ҚОСТЫ/ӨШІРДІ — сол қаладағыларға
-- ══════════════════════════════════════════════════════════════════════════
--  Модератор «Астананы қостым» деп сақтайды да, ол қаладағы дүкендер мен
--  курьерлер бұл туралы ЕШҚАШАН білмейтін. Курьер қосымшаны ашпаса — жұмыс
--  бос жатады; дүкен әлі күнге «өзім жеткіземін» деп отырады.
--
--  Superadmin экраны сақтаған соң шақырады. Тек ӨЗГЕРГЕН қалалар туралы
--  хабарлайды — әр сақтауда бәріне спам жіберілмеуі үшін.
create or replace function public.notify_courier_cities_changed(
  p_enabled text[],
  p_disabled text[] default '{}'
) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_city text;
  v_uids uuid[];
begin
  if not public.is_superadmin() then raise exception 'not_superadmin'; end if;

  foreach v_city in array coalesce(p_enabled, '{}'::text[]) loop
    -- Дүкендер: енді жеткізуді курьер орындайды.
    select array_agg(u.id) into v_uids
      from public.users u
      join public.stores s on s.admin_uid = coalesce(u.owner_id, u.id)
     where s.city = v_city and coalesce(u.blocked, false) = false;
    perform public.notify_push(
      coalesce(v_uids, '{}'::uuid[]),
      '🚚 Курьеры теперь работают / Курьерлер енді жұмыс істейді',
      v_city || ' — новые заказы на доставку поедут курьером / '
             || 'жаңа жеткізу тапсырыстарын курьер апарады',
      jsonb_build_object('type', 'courier_city', 'city', v_city, 'on', true));

    -- Курьерлер: қаланы аштық.
    select array_agg(u.id) into v_uids from public.users u
     where u.role = 'courier' and u.courier_status = 'active'
       and coalesce(u.blocked, false) = false and u.city = v_city;
    perform public.notify_push(
      coalesce(v_uids, '{}'::uuid[]),
      '✅ Ваш город подключён / Қалаңыз қосылды',
      v_city || ' — заказы начнут появляться во вкладке «Новые» / '
             || 'тапсырыстар «Жаңа» табында шыға бастайды',
      jsonb_build_object('type', 'courier_city', 'city', v_city, 'on', true));
  end loop;

  foreach v_city in array coalesce(p_disabled, '{}'::text[]) loop
    select array_agg(u.id) into v_uids
      from public.users u
      join public.stores s on s.admin_uid = coalesce(u.owner_id, u.id)
     where s.city = v_city and coalesce(u.blocked, false) = false;
    perform public.notify_push(
      coalesce(v_uids, '{}'::uuid[]),
      '📦 Доставка снова на вас / Жеткізу қайта сізде',
      v_city || ' — курьерская служба отключена, договаривайтесь с клиентом / '
             || 'курьерлік қызмет өшірілді, клиентпен өзіңіз келісесіз',
      jsonb_build_object('type', 'courier_city', 'city', v_city, 'on', false));

    select array_agg(u.id) into v_uids from public.users u
     where u.role = 'courier' and u.courier_status = 'active'
       and coalesce(u.blocked, false) = false and u.city = v_city;
    perform public.notify_push(
      coalesce(v_uids, '{}'::uuid[]),
      '⏸️ Город отключён / Қала өшірілді',
      v_city || ' — новых заказов не будет, начатые доведите до конца / '
             || 'жаңа тапсырыс болмайды, басталғанын аяқтаңыз',
      jsonb_build_object('type', 'courier_city', 'city', v_city, 'on', false));
  end loop;
end;
$$;
grant execute on function public.notify_courier_cities_changed(text[], text[])
  to authenticated;
