-- ════════════════════════════════════════════════════════════════════════════
--  0062 · Жылдам код + іздеу сөздері + «қайтару мерзімі бітеді» push
-- ────────────────────────────────────────────────────────────────────────────
--  1) products.quick_code — АДМИН/САТУШЫ ғана қолданатын қысқа сан («103»).
--     Офлайн сату мен қоймадан іздеу кезінде тауарды атауымен емес, сол
--     санмен бір-екі басуда табу үшін. Артикул (QM-0000123) бұл рөлге
--     жарамайды: ол ГЛОБАЛЬ реттік санауыш, ұзын әрі есте қалмайды.
--     Код ДҮКЕНГЕ тиесілі: әр иеде өз нөмірлеу жүйесі бар, сондықтан
--     бірегейлік owner_uid бойынша (бос мән — шектеусіз, көп тауарда коды
--     мүлдем болмайды). Клиентке КӨРСЕТІЛМЕЙДІ (UI-де де, іздеуде де).
--
--  2) products.keywords — «ұқсас сөздер»: клиент тауарды не деп іздесе де
--     табылу үшін (мыс. «кроссовка, сникерс, беговые»). Іздеу буферіне
--     қосылады, карточкада көрсетілмейді.
--
--  3) «Қайтару мерзімі бітеді» push (0045 үлгісі бойынша, pg_cron).
--     Клиентте қайтару терезесі — тапсырыс АЛЫНҒАННАН кейін 14 күн.
--     12-күні әлі қайтару рәсімделмеген болса — бір рет еске саламыз.
-- ════════════════════════════════════════════════════════════════════════════

-- ══════════════════════════════════════════════════════════════════════════
--  1 · Жылдам код пен іздеу сөздері
-- ══════════════════════════════════════════════════════════════════════════

alter table public.products
  add column if not exists quick_code text not null default '',
  add column if not exists keywords   text not null default '';

-- Бір дүкен ішінде код қайталанбауы керек — әйтпесе «103» деп іздегенде екі
-- тауар шығады да, бүкіл мәні жоғалады. Бос код шектелмейді (partial index).
create unique index if not exists products_owner_quick_code_uidx
  on public.products (owner_uid, quick_code)
  where quick_code <> '';

-- ══════════════════════════════════════════════════════════════════════════
--  2 · «Қайтару мерзімі бітеді» еске салуы
-- ══════════════════════════════════════════════════════════════════════════

alter table public.orders
  add column if not exists return_window_push_sent boolean not null default false;

-- Бар тарихқа push жібермейміз: терезесі әлдеқашан жабылған (немесе әлі
-- ашылмаған) тапсырыстарды «жіберілді» деп белгілейміз. Соңғы 12 күнде
-- аяқталғандар — нағыз терезеде тұр, оларға еске салу ДҰРЫС, сондықтан
-- оларға тимейміз.
update public.orders
   set return_window_push_sent = true
 where return_window_push_sent = false
   and (status <> 'completed'
        or completed_at is null
        or completed_at < now() - interval '12 days');

create or replace function public.sweep_return_window_reminders() returns void
language plpgsql security definer set search_path = public as $$
declare
  r record;
  v_has_return boolean;
begin
  for r in
    select id, client_uid, order_number, store_name
      from public.orders
     where status = 'completed'
       and return_window_push_sent = false
       and client_uid is not null
       and completed_at is not null
       -- 12-күн: клиентке шешім қабылдауға әлі 2 күн бар.
       and completed_at < now() - interval '12 days'
       and completed_at > now() - interval '14 days'
     limit 200
  loop
    -- Қайтару әлдеқашан рәсімделсе (қабылданбағаннан басқасы) — еске салу артық.
    select exists (
      select 1 from public.returns rt
       where rt.order_id = r.id::text
         and rt.status <> 'rejected'
    ) into v_has_return;

    if not v_has_return then
      perform public.notify_push(
        array[r.client_uid],
        'Возврат ещё возможен / Қайтаруға әлі болады',
        'Заказ №' || lpad(coalesce(r.order_number, 0)::text, 5, '0') ||
          ' · срок возврата истекает через 2 дня / қайтару мерзімі 2 күнде бітеді',
        jsonb_build_object('type', 'return_window', 'orderId', r.id)
      );
    end if;

    update public.orders set return_window_push_sent = true where id = r.id;
  end loop;
end;
$$;

revoke all on function public.sweep_return_window_reminders() from public, anon, authenticated;

select cron.unschedule('return-window-reminders')
  where exists (select 1 from cron.job where jobname = 'return-window-reminders');
select cron.schedule(
  'return-window-reminders',
  '30 6 * * *',                        -- 06:30 UTC = 11:30 Алматы (күніне бір рет)
  $$select public.sweep_return_window_reminders()$$
);
