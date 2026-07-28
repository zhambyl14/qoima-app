-- ════════════════════════════════════════════════════════════════════════════
--  0030 · Тапсырыс статусын атомдық ауыстыру (race condition түзету)
-- ────────────────────────────────────────────────────────────────────────────
--  Бұрын: админ/сатушы/клиент әрекеттері (выдать/отменить/чек тіркеу/растау)
--  Dart жағында «оқы → тексер → жаз» деген бірнеше бөлек Supabase шақыруымен
--  жасалатын — қатардың DB деңгейінде LOCK-ы жоқ. Сондықтан екі әрекет бір
--  тапсырысқа ДӘЛ СОЛ СӘТТЕ түссе (мыс. админ «выдать» басты, сол сәтте
--  сатушы «отменить» басты), екеуі де өз нұсқасын жазып, қойма/статус
--  бүлінетін (lost update).
--
--  Түзету: статус ауыстырудың алдында осы функция қатарды `for update`
--  LOCK-тайды әрі АҒЫМДАҒЫ статусты тексереді. Екі жақтан бір мезетте
--  шақырылса — біреуі бірінші lock алып, статусты сәтті ауыстырады;
--  екіншісі lock босағанда ЖАҢА статусты көреді, күткен статусқа сай
--  келмегендіктен `order_state_changed:<нақты статус>` қатесін алады және
--  ЕШҚАНДАЙ қойма/жазба өзгертпейді (Dart жағында бұл кезек тексерістен
--  КЕЙІН орындалады — claim сәтті болмаса, ешбір side-effect жүрмейді).
-- ════════════════════════════════════════════════════════════════════════════

alter table public.orders
  add column if not exists cancelled_by_role text not null default '', -- client|admin|seller|system
  add column if not exists cancelled_by_uid  text not null default '',
  add column if not exists cancelled_by_name text not null default '',
  add column if not exists cancelled_at      timestamptz;

-- p_expected — рұқсат етілген АҒЫМДАҒЫ статустар тізімі; сәйкес келмесе
-- 'order_state_changed:<статус>' деп raise етеді (Dart жағы бұл кезекті
-- «тапсырыс өңделіп қойды» деген түсінікті хабарламаға айналдырады).
-- p_new_status = 'cancelled' болса — cancelled_by_* бағандарын да толтырады.
create or replace function public.claim_order_transition(
  p_order uuid,
  p_expected text[],
  p_new_status text,
  p_actor_role text default '',
  p_actor_uid text default '',
  p_actor_name text default ''
) returns public.orders
language plpgsql security definer set search_path = public as $$
declare
  v_order public.orders;
begin
  select * into v_order from public.orders where id = p_order for update;
  if not found then
    raise exception 'order_not_found';
  end if;
  if not (v_order.status = any(p_expected)) then
    raise exception 'order_state_changed:%', v_order.status;
  end if;

  update public.orders set
    status = p_new_status,
    cancelled_by_role = case when p_new_status = 'cancelled' then p_actor_role else cancelled_by_role end,
    cancelled_by_uid  = case when p_new_status = 'cancelled' then p_actor_uid  else cancelled_by_uid  end,
    cancelled_by_name = case when p_new_status = 'cancelled' then p_actor_name else cancelled_by_name end,
    cancelled_at      = case when p_new_status = 'cancelled' then now() else cancelled_at end
  where id = p_order
  returning * into v_order;

  return v_order;
end;
$$;
grant execute on function public.claim_order_transition(uuid, text[], text, text, text, text) to authenticated;
