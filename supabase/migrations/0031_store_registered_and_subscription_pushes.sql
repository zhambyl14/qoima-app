-- ════════════════════════════════════════════════════════════════════════════
--  0031 · Модератор пуштары: жаңа тіркелген дүкен + жазылым мерзімі жақындағанда
-- ════════════════════════════════════════════════════════════════════════════

-- ── 1) Жаңа дүкен жолы жасалғанда → барлық модераторларға (superadmin) ───────
-- Ескерту: тек INSERT-те іске қосылады (saveStore upsert-тың UPDATE тармағында
-- қайталанбайды) — «жаңа бизнес пайда болды» сәтін дәл ұстайды, дүкен ашу
-- өтінімі (shop_requests) пушынан тәуелсіз.
create or replace function public.notify_store_registered() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform public.notify_push(
    (select array_agg(id) from public.users where role = 'superadmin'),
    'Новый магазин зарегистрирован',
    coalesce(nullif(new.store_name, ''), 'Магазин') || ' — проверьте карточку',
    jsonb_build_object('type', 'store_registered', 'storeAdminUid', new.admin_uid)
  );
  return new;
end;
$$;

drop trigger if exists trg_notify_store_registered on public.stores;
create trigger trg_notify_store_registered
  after insert on public.stores
  for each row execute function public.notify_store_registered();

-- ── 2) Жазылым мерзімі 3 күннен аз қалғанда → модераторларға (бір рет) ──────
alter table public.users add column if not exists sub_reminder_sent boolean not null default false;

create or replace function public.sweep_subscription_expiry_reminders() returns void
language plpgsql security definer set search_path = public as $$
declare
  r record;
begin
  for r in
    select id, name, subscription_until from public.users
    where role = 'admin'
      and sub_reminder_sent = false
      and subscription_until is not null
      and subscription_until between now() and now() + interval '3 days'
  loop
    perform public.notify_push(
      (select array_agg(id) from public.users where role = 'superadmin'),
      'Подписка скоро истекает',
      coalesce(nullif(r.name, ''), 'Магазин') || ' — доступ истекает ' ||
        to_char(r.subscription_until, 'DD.MM'),
      jsonb_build_object('type', 'subscription_expiring', 'ownerUid', r.id)
    );
    update public.users set sub_reminder_sent = true where id = r.id;
  end loop;
end;
$$;

select cron.schedule(
  'subscription-expiry-reminders',
  '0 9 * * *',
  $$select public.sweep_subscription_expiry_reminders()$$
);

-- Ескерту: мерзім ұзартылғанда `sub_reminder_sent` қайта false болуы керек —
-- бұл lib/data/repositories/store_moderation_repository.dart ішіндегі
-- grantSubscription/setSubscriptionUntil жазуларына тікелей қосылған (жаңа
-- RPC қажет емес — сол екеуі де users.update-ті тікелей RLS арқылы жасайды).
