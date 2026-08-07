-- ════════════════════════════════════════════════════════════════════════════
--  0045 · Екі жоспарлы push (pg_cron, 0021 үлгісі бойынша):
--    A) Клиентке — тапсырыс орындалғаннан 2 күн өткенде пікір қалдыруды
--       еске салу (пікір саны өссе, рейтинг те, «Спрос клиентов» те дәлірек).
--    B) Дүкен иесіне — күнделікті қорытынды («бүгін N сатылым, X ₸»).
-- ════════════════════════════════════════════════════════════════════════════

-- ── A) Пікір қалдыруды еске салу ────────────────────────────────────────────
alter table public.orders
  add column if not exists completed_at timestamptz,
  add column if not exists review_reminder_sent boolean not null default false;

-- Тапсырыс аяқталған сәтті белгілейміз (бұрын мұндай баған болмаған —
-- created_at пайдалану қате болар еді: тапсырыс апталар бойы тұруы мүмкін).
create or replace function public.set_order_completed_at() returns trigger
language plpgsql set search_path = public as $$
begin
  if new.status = 'completed' and coalesce(old.status, '') <> 'completed' then
    new.completed_at := now();
  end if;
  return new;
end;
$$;
drop trigger if exists trg_order_completed_at on public.orders;
create trigger trg_order_completed_at before update on public.orders
  for each row execute function public.set_order_completed_at();

-- МАҢЫЗДЫ: бар (ескі) аяқталған тапсырыстарды «еске салынған» деп белгілейміз
-- — әйтпесе cron-ның АЛҒАШҚЫ жүрісі бүкіл тарихқа push жіберіп, спам болар еді.
update public.orders
   set review_reminder_sent = true
 where status = 'completed' and review_reminder_sent = false;

create or replace function public.sweep_review_reminders() returns void
language plpgsql security definer set search_path = public as $$
declare
  r record;
  v_pids uuid[];
  v_has  boolean;
begin
  for r in
    select id, client_uid, admin_uid, store_name, items
    from public.orders
    where status = 'completed'
      and review_reminder_sent = false
      and client_uid is not null
      and completed_at is not null
      and completed_at < now() - interval '2 days'
      -- Тым ескі тапсырысқа еске салудың мәні жоқ.
      and completed_at > now() - interval '30 days'
    limit 200
  loop
    -- items — JSONB массиві, элементтері camelCase: [{"productId": "..."}].
    select array_agg(distinct (e ->> 'productId')::uuid) into v_pids
      from jsonb_array_elements(coalesce(r.items, '[]'::jsonb)) as e
     where (e ->> 'productId') ~*
           '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';

    if v_pids is null or array_length(v_pids, 1) is null then
      update public.orders set review_reminder_sent = true where id = r.id;
      continue;
    end if;

    select exists (
      select 1 from public.product_reviews
      where client_uid = r.client_uid and product_id = any(v_pids)
    ) into v_has;

    if not v_has then
      perform public.notify_push(
        array[r.client_uid],
        'Как вам покупка? / Сатып алғаныңыз ұнады ма?',
        coalesce(nullif(r.store_name, ''), 'Магазин') ||
          ' — оставьте отзыв, это поможет другим покупателям',
        jsonb_build_object('type', 'review_reminder',
                           'productId', v_pids[1], 'adminUid', r.admin_uid)
      );
    end if;
    update public.orders set review_reminder_sent = true where id = r.id;
  end loop;
end;
$$;

select cron.unschedule('review-reminders')
  where exists (select 1 from cron.job where jobname = 'review-reminders');
select cron.schedule(
  'review-reminders',
  '0 * * * *',                       -- сағат сайын (2 күндік терезе кең)
  $$select public.sweep_review_reminders()$$
);

-- ── B) Дүкен иесіне күнделікті қорытынды ────────────────────────────────────
-- Тек БЕЛСЕНДІЛІК БОЛҒАНДА жіберіледі (нөлдік «бүгін 0 сатылым» спам емес).
create or replace function public.sweep_daily_digest() returns void
language plpgsql security definer set search_path = public as $$
declare
  r record;
begin
  for r in
    select s.owner_uid                as uid,
           count(*)                   as sales,
           coalesce(sum(s.total_price), 0)::bigint as revenue,
           count(*) filter (where s.is_online)     as online
    from public.sales_history s
    where s.type = 'sale'
      and s.sale_date >= date_trunc('day', now() at time zone 'Asia/Almaty')
                          at time zone 'Asia/Almaty'
    group by s.owner_uid
    having count(*) > 0
  loop
    perform public.notify_push(
      array[r.uid],
      'Итоги дня / Күн қорытындысы',
      r.sales || ' продаж · ' || r.revenue || ' ₸' ||
        case when r.online > 0 then ' (онлайн: ' || r.online || ')' else '' end,
      jsonb_build_object('type', 'daily_digest')
    );
  end loop;
end;
$$;

select cron.unschedule('daily-digest')
  where exists (select 1 from cron.job where jobname = 'daily-digest');
select cron.schedule(
  'daily-digest',
  '0 15 * * *',                      -- 15:00 UTC = 20:00 Алматы
  $$select public.sweep_daily_digest()$$
);
