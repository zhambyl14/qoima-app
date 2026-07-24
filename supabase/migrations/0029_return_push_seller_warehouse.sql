-- ════════════════════════════════════════════════════════════════════════════
--  0029 · Возврат push-хабарламасын байыту: офлайн возвратта КІМ (сатушы) және
--  ҚАЙ СКЛАДТАН (warehouse) екенін көрсетеміз. Бұрын тек сома + client_name
--  (офлайн возвратта client_name әрқашан бос болғандықтан «Клиент» деп жалпы
--  көрінетін еді — түбірлік мәселе осы).
-- ────────────────────────────────────────────────────────────────────────────
--  returns.seller_id (text) — offline возвратта createOfflineReturn() арқылы
--  AppUser.current.uid (нақты users.id) жазылады, online возвратта әлі бос
--  (клиент сұранысы, сатушы әлі белгіленбеген) — сол себепті тек офлайн
--  тармақта іздейміз. Cast сәтсіз болып қалуы мүмкін жағдайға (күтпеген
--  формат) қарсы ішкі BEGIN/EXCEPTION блогымен қорғаймыз — триггер негізгі
--  INSERT-ті ешқашан бұзбауы керек.
-- ════════════════════════════════════════════════════════════════════════════

create or replace function public.on_return_push() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_title  text;
  v_uids   uuid[];
  v_first  text;
  v_seller text;
  v_wh     text;
begin
  v_first := coalesce(new.items->0->>'productName', 'товар');

  if new.type = 'online' then
    v_title := '↩️ Онлайн-возврат';
    select array_agg(id) into v_uids
      from public.users
      where id = new.admin_uid or (owner_id = new.admin_uid and role = 'seller');
    perform public.notify_push(
      coalesce(v_uids, array[new.admin_uid]),
      v_title || ' · ' || new.total_amount::int || ' ₸',
      coalesce(nullif(new.client_name, ''), 'Клиент') || E'\n' || v_first,
      jsonb_build_object('type', 'return', 'returnId', new.id)
    );
  else
    v_title := '↩️ Новый возврат';

    if new.seller_id is not null and new.seller_id <> '' then
      begin
        select name into v_seller from public.users where id = new.seller_id::uuid;
      exception when others then
        v_seller := null; -- күтпеген формат — сатушы атынсыз жалғастырамыз
      end;
    end if;
    if new.warehouse_id is not null then
      select name into v_wh from public.warehouses where id = new.warehouse_id;
    end if;

    perform public.notify_push(
      array[new.admin_uid],
      v_title || ' · ' || new.total_amount::int || ' ₸',
      coalesce(nullif(v_seller, ''), 'Сотрудник') || ' оформил(а) возврат'
        || coalesce(E'\n📍 ' || v_wh, '')
        || E'\n' || v_first,
      jsonb_build_object('type', 'return', 'returnId', new.id)
    );
  end if;
  return new;
end;
$$;
