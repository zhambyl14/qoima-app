-- ════════════════════════════════════════════════════════════════════════════
--  0067 · Чек тіркеу еске салғышы (pg_cron, 5 минут сайын)
-- ────────────────────────────────────────────────────────────────────────────
--  Тірі базадан расталды (аудит, 2026-08-14): барлық тапсырыстың 63%-ы
--  (165/264) чек тіркелместен «cancelled» болады — 198 бас тартудың 83%-ы
--  дәл осыдан. Себебі: 0021-де ТЕК smart_reservation түріне арналған
--  reminder бар (sweep_reservation_reminders); click_collect/delivery
--  (толық алдын ала төлем) осы санақтан тыс қалып, клиентке 30 минуттық
--  терезе ішінде ЕШБІР еске салу жіберілмейді.
--
--  Бұл функция sweep_reservation_reminders-ті ЕШТЕҢЕ өзгертпейді — WHERE
--  шарты ортогональ (order_type <> 'smart_reservation', ал бұрынғысы
--  = 'smart_reservation' талап етеді), сондықтан әр тапсырыс түрінің
--  reminder_sent жалаушасын дәл БІР ғана sweep функциясы иеленеді —
--  қайшылық жоқ, бұрынғы бронь-еске-салғыш дәл бұрынғыдай жұмыс істей береді.
-- ════════════════════════════════════════════════════════════════════════════

create or replace function public.sweep_receipt_reminders() returns void
language plpgsql security definer set search_path = public as $$
declare
  r record;
begin
  for r in
    select id, client_uid, order_number
    from public.orders
    where order_type <> 'smart_reservation'
      and status in ('pending','reserved')
      and reminder_sent = false
      and client_uid is not null
      and deadline_at is not null
      and coalesce(receipt_url, '') = ''
      and deadline_at between now() and now() + interval '15 minutes'
  loop
    perform public.notify_push(
      array[r.client_uid],
      'Заказ ждёт оплаты / Тапсырыс төлемді күтуде',
      'Заказ №' || r.order_number ||
        ' — прикрепите чек, иначе бронь снимется / чекті тіркеңіз, әйтпесе бронь алынып тасталады',
      jsonb_build_object('type', 'receipt_reminder', 'orderId', r.id)
    );
    update public.orders set reminder_sent = true where id = r.id;
  end loop;
end;
$$;

revoke all on function public.sweep_receipt_reminders() from public, anon, authenticated;

select cron.unschedule('receipt-reminders')
  where exists (select 1 from cron.job where jobname = 'receipt-reminders');
select cron.schedule(
  'receipt-reminders',
  '*/5 * * * *',
  $$select public.sweep_receipt_reminders()$$
);
