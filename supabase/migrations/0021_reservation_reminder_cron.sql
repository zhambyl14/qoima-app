-- ════════════════════════════════════════════════════════════════════════════
--  0021 · Бронь мерзімін еске салу (pg_cron, 5 минут сайын)
-- ────────────────────────────────────────────────────────────────────────────
--  smart_reservation тапсырыстың deadline_at-на 15 мин қалғанда клиентке
--  БІР РЕТ push жіберіледі (reminder_sent жалаушасы қайталауды болдырмайды).
-- ════════════════════════════════════════════════════════════════════════════

alter table public.orders add column if not exists reminder_sent boolean not null default false;

create or replace function public.sweep_reservation_reminders() returns void
language plpgsql security definer set search_path = public as $$
declare
  r record;
begin
  for r in
    select id, client_uid, order_number
    from public.orders
    where order_type = 'smart_reservation'
      and status in ('reserved','pending')
      and reminder_sent = false
      and client_uid is not null
      and deadline_at is not null
      and deadline_at between now() and now() + interval '15 minutes'
  loop
    perform public.notify_push(
      array[r.client_uid],
      'Бронь скоро истекает',
      'Заказ №' || r.order_number || ' — успейте оплатить',
      jsonb_build_object('type', 'reservation_reminder', 'orderId', r.id)
    );
    update public.orders set reminder_sent = true where id = r.id;
  end loop;
end;
$$;

select cron.schedule(
  'reservation-reminders',
  '*/5 * * * *',
  $$select public.sweep_reservation_reminders()$$
);
