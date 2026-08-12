-- ── Дүкен өзі беру + «өлшеп көру» свопы ────────────────────────────────────
--  Бұрын: дүкен/сатушы тапсырысты ӨЗІ (курьерсіз) клиентке бергенде,
--  release_fitting_holds ӘРҚАШАН «клиент негізгі өлшемді алды» деп есептеп,
--  altSize броньын жай босататын. Егер клиент іс жүзінде ҚОСАЛҚЫ өлшемді
--  алса (примерка кезінде ауыстырса), қойма/сатылым дұрыс есептелмейтін:
--  altSize сатылды деп саналмайды, ал негізгі өлшем қоймаға қайтарылмайды.
--
--  courier_complete_order (0052) курьер үшін осы свопты дұрыс есептейді,
--  бірақ ол ТЕК courier_uid = auth.uid() шартында жұмыс істейді — дүкен
--  өзі бергенде шақыра алмайды. Сондықтан осы функция сол логиканы дүкен
--  үшін қайталайды, тек «қайту жолы» (return_leg) керек емес: тауар
--  физикалық түрде ҚАЗІРдің өзінде дүкенде, курьер жолда емес, сондықтан
--  негізгі өлшем БІРДЕН қоймаға қайтады (кідіріссіз).
create or replace function public.store_handover_fitting(
  p_order uuid,
  p_swaps integer[] default '{}'
) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_order   public.orders;
  v_items   jsonb;
  v_item    jsonb;
  v_alt     text;
  v_qty     int;
  v_swapped boolean;
  i         integer;
begin
  select * into v_order from public.orders where id = p_order for update;
  if not found then raise exception 'order_not_found'; end if;
  if not (
    v_order.admin_uid = auth.uid()
    or v_order.admin_uid = public.app_owner_uid()
    or public.is_superadmin()
  ) then
    raise exception 'not_your_order';
  end if;

  v_items := v_order.items;
  if v_items is null then return; end if;

  for i in 0 .. jsonb_array_length(v_items) - 1 loop
    v_item := v_items -> i;
    v_alt  := coalesce(v_item ->> 'altSize', '');
    if v_alt = '' then continue; end if;          -- примеркасыз позиция
    v_qty     := coalesce((v_item ->> 'qty')::int, 1);
    v_swapped := i = any(coalesce(p_swaps, '{}'::integer[]));

    if v_swapped then
      -- Клиент ҚОСАЛҚЫ өлшемді алды: сатылды — броньнан шығып, қоймадан да алынады.
      perform public.adjust_batch_sizes((v_item ->> 'batchId')::uuid,
        jsonb_build_object(v_alt, -v_qty), 'reserved_sizes', false);
      perform public.adjust_batch_sizes((v_item ->> 'batchId')::uuid,
        jsonb_build_object(v_alt, -v_qty), 'sizes_quantity', false);
      -- Негізгі өлшем ДӘЛ ҚАЗІР дүкенге қайтады (курьер жоқ — кідіріс жоқ).
      perform public.adjust_batch_sizes((v_item ->> 'batchId')::uuid,
        jsonb_build_object(v_item ->> 'size', v_qty), 'sizes_quantity', false);
      -- Тапсырыс жазбасы нақты сатылған өлшемді көрсетуі үшін.
      v_items := jsonb_set(v_items, array[i::text],
        (v_item - 'altSize')
          || jsonb_build_object('size', v_alt, 'swappedFrom', v_item ->> 'size'));
    else
      -- Негізгі өлшем қалды (тапсырыс кезінде сатылған) — тек бронь босайды.
      perform public.adjust_batch_sizes((v_item ->> 'batchId')::uuid,
        jsonb_build_object(v_alt, -v_qty), 'reserved_sizes', false);
      v_items := jsonb_set(v_items, array[i::text], v_item - 'altSize');
    end if;
  end loop;

  update public.orders set items = v_items where id = p_order;

  perform public.recompute_product_status(q.pid)
    from (select distinct (it ->> 'productId')::uuid as pid
            from jsonb_array_elements(v_items) it) q;
end;
$$;
grant execute on function public.store_handover_fitting(uuid, integer[]) to authenticated;
