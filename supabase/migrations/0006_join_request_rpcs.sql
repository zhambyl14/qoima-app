-- ════════════════════════════════════════════════════════════════════════════
--  0006 · Seller ↔ admin қосылу ағымын түзеу (RLS айналып өтетін RPC + dedup)
-- ────────────────────────────────────────────────────────────────────────────
--  ✅ 2026-07-02 базаға қолданылды (MCP: join_request_rpcs_and_dedup +
--     reassign_seller_warehouse_rpc).
--
--  Мәселе: users_update саясаты тек id=auth.uid()-ке рұқсат береді, сондықтан
--  дүкен иесі сатушының users жолын жаңарта алмайды — approve/reject/remove/
--  reassign үнсіз 0 жол жаңартады. Сатушы «active» болмайды, экраны өзгермейді.
--  Оған қоса join_requests-те unique жоқ болғандықтан upsert дубликат жол қосып,
--  кейін .maybeSingle() 2 жолда 406 («multiple rows returned») қатесін берген.
-- ════════════════════════════════════════════════════════════════════════════

-- ── 1) Дубликаттарды жинау + (seller,admin) бойынша unique ───────────────────
delete from public.join_requests a
  using public.join_requests b
  where a.seller_uid = b.seller_uid
    and a.admin_uid = b.admin_uid
    and a.ctid < b.ctid;

alter table public.join_requests
  drop constraint if exists join_requests_seller_admin_key;
alter table public.join_requests
  add constraint join_requests_seller_admin_key unique (seller_uid, admin_uid);

-- ── 2) Approve: тек сол заявканың admin_uid-і шақыра алады ────────────────────
create or replace function public.approve_join_request(
  p_request_id uuid, p_warehouse_id uuid
) returns void
language plpgsql security definer set search_path = public as $$
declare v_seller uuid; v_admin uuid;
begin
  select seller_uid, admin_uid into v_seller, v_admin
    from public.join_requests where id = p_request_id for update;
  if not found then raise exception 'request_not_found'; end if;
  if v_admin is null or v_admin <> auth.uid() then
    raise exception 'not_authorized';
  end if;

  update public.users set
    owner_id = v_admin,
    assigned_warehouse_id = p_warehouse_id,
    join_status = 'active'
  where id = v_seller;

  update public.join_requests set
    status = 'approved',
    assigned_warehouse_id = p_warehouse_id
  where id = p_request_id;
end;
$$;
grant execute on function public.approve_join_request(uuid, uuid) to authenticated;

-- ── 3) Reject: заявка иесі (admin) бас тартады ───────────────────────────────
create or replace function public.reject_join_request(p_request_id uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare v_seller uuid; v_admin uuid;
begin
  select seller_uid, admin_uid into v_seller, v_admin
    from public.join_requests where id = p_request_id;
  if not found then raise exception 'request_not_found'; end if;
  if v_admin is null or v_admin <> auth.uid() then
    raise exception 'not_authorized';
  end if;

  update public.join_requests set status = 'rejected' where id = p_request_id;
  update public.users set join_status = 'none'
    where id = v_seller and join_status = 'pending'
      and (owner_id is null or owner_id = v_admin);
end;
$$;
grant execute on function public.reject_join_request(uuid) to authenticated;

-- ── 4) Remove seller: ағымдағы иесі шығарады ─────────────────────────────────
create or replace function public.remove_seller(p_seller_id uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare v_owner uuid;
begin
  select owner_id into v_owner from public.users where id = p_seller_id;
  if v_owner is null or v_owner <> auth.uid() then
    raise exception 'not_authorized';
  end if;

  update public.users set
    owner_id = null, assigned_warehouse_id = null, join_status = 'none'
  where id = p_seller_id;

  update public.join_requests set status = 'removed'
    where seller_uid = p_seller_id and admin_uid = auth.uid();
end;
$$;
grant execute on function public.remove_seller(uuid) to authenticated;

-- ── 5) Reassign seller warehouse: иесі сатушысының қоймасын ауыстырады ────────
create or replace function public.reassign_seller_warehouse(
  p_seller_id uuid, p_warehouse_id uuid
) returns void
language plpgsql security definer set search_path = public as $$
declare v_owner uuid;
begin
  select owner_id into v_owner from public.users where id = p_seller_id;
  if v_owner is null or v_owner <> auth.uid() then
    raise exception 'not_authorized';
  end if;
  update public.users set assigned_warehouse_id = p_warehouse_id
    where id = p_seller_id;
end;
$$;
grant execute on function public.reassign_seller_warehouse(uuid, uuid) to authenticated;

-- ── 6) Ескі дрейф: сатушы жолы «approved» заявкамен сәйкессіз (owner_id null) ─
update public.join_requests jr
  set status = 'pending'
  where jr.status = 'approved'
    and not exists (
      select 1 from public.users u
      where u.id = jr.seller_uid and u.owner_id = jr.admin_uid
        and u.join_status = 'active'
    );
