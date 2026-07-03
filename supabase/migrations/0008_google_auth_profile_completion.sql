-- ════════════════════════════════════════════════════════════════════════════
--  0008 · Google-мен кіру: профильді кейін толтыру + Cloudinary кезек fallback
-- ────────────────────────────────────────────────────────────────────────────
--  ✅ 2026-07-02 базаға қолданылды (MCP: google_auth_profile_completion).
-- ════════════════════════════════════════════════════════════════════════════

-- ── 1) handle_new_user: метадеректе 'role' ЖОҚ болса (Google/OAuth алғашқы
--   кіру) — профиль ЖАСАМАЙМЫЗ. Қосымша CompleteProfileScreen арқылы рөл мен
--   жетіспейтін деректерді (телефон/қала) сұрап, профильді өзі жасайды.
--   Бұрынғы мінез: рөлсіз қолданушы 'client' болып phone=''-мен жазылып,
--   екінші Google қолданушыда clients.phone unique бұзылып, кіру құлайтын еді.
create or replace function public.handle_new_user()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_role text := new.raw_user_meta_data->>'role';
  v_name text := coalesce(new.raw_user_meta_data->>'name', '');
  v_code text;
begin
  if v_role is null then
    return new; -- OAuth (Google) — профиль қосымшада толтырылады
  end if;

  if v_role = 'client' then
    insert into public.clients (id, phone, email, name, city, email_verified)
    values (
      new.id,
      coalesce(new.raw_user_meta_data->>'phone', ''),
      coalesce(new.email, ''),
      v_name,
      coalesce(new.raw_user_meta_data->>'city', ''),
      true
    );
  elsif v_role = 'admin' then
    v_code := lpad((floor(random() * 1000000))::int::text, 6, '0');
    insert into public.users (id, name, email, role, owner_id, business_code, join_status)
    values (new.id, v_name, coalesce(new.email, ''), 'admin', new.id, v_code, 'active');
    insert into public.business_codes (code, admin_uid) values (v_code, new.id);
  elsif v_role = 'superadmin' then
    insert into public.users (id, name, email, role, owner_id, join_status)
    values (new.id, v_name, coalesce(new.email, ''), 'superadmin', new.id, 'active');
  else
    insert into public.users (id, name, email, role, owner_id, join_status)
    values (new.id, v_name, coalesce(new.email, ''), 'seller', null, 'none');
  end if;
  return new;
end;
$$;

-- ── 2) cloudinary_delete_queue: клиент сәтсіз өшіруде URL-ды кезекке сала
--   алады (жазу ғана; оқу/өшіру — тек service_role/Edge Function).
drop policy if exists cdq_insert on public.cloudinary_delete_queue;
create policy cdq_insert on public.cloudinary_delete_queue
  for insert to authenticated with check (true);
