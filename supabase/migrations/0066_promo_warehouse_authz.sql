-- 0066: 0065 аудитінен қалып қойған екі SECURITY DEFINER функцияға авторизация.
--
--  adjust_promo_usage(p_promo, p_client, p_delta) — авторизациясыз еді: кез
--    келген authenticated пайдаланушы КЕЗ КЕЛГЕН промокодтың used_count/
--    promo_redemptions санағын өз бетінше өзгерте алатын. Соның салдары —
--    промокод лимитін айналып өту (used_count-ты 0-ге дейін кему) немесе
--    бөтен дүкеннің промокодын бұзу (used_count-ты max_uses-тен асырып жіберу).
--    Дұрыс шақырушылар: тапсырыс иесі клиент (p_client = auth.uid()) немесе
--    сол промокодтың дүкен иесі (promos.admin_uid = app_owner_uid(), — админ
--    cancelOnlineOrder-де шақырады) немесе superadmin.
--
--  increment_warehouse_totals(p_wh, p_pairs, p_products) — авторизациясыз
--    еді: кез келген authenticated пайдаланушы КЕЗ КЕЛГЕН қойманың
--    көрсеткіш санағын (total_pairs/total_products — косметикалық, нақты
--    қойма ақиқаты batches.sizes_quantity-де) бұрмалай алатын. Тек сол
--    қойманың иесі немесе superadmin өзгерте алуы керек.
--
-- Ереже (CLAUDE.md): SECURITY DEFINER-де auth.uid()/app_owner_uid()/
-- is_superadmin() тексерісі МІНДЕТТІ. `create or replace function` PUBLIC
-- грантын ҚАЙТА тудырады, сондықтан revoke-ты ҚАЙТА орындаймыз.

create or replace function public.adjust_promo_usage(p_promo uuid, p_client uuid, p_delta integer)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if not (
    public.is_superadmin()
    or (p_client is not null and p_client = auth.uid())
    or exists (
      select 1 from public.promos pr
       where pr.id = p_promo and pr.admin_uid = public.app_owner_uid()
    )
  ) then
    raise exception 'not_authorized';
  end if;

  update public.promos
    set used_count = greatest(0, used_count + p_delta) where id = p_promo;
  if p_client is not null then
    insert into public.promo_redemptions(promo_id, client_uid, count)
      values (p_promo, p_client, greatest(0, p_delta))
    on conflict (promo_id, client_uid) do update
      set count = greatest(0, public.promo_redemptions.count + p_delta),
          updated_at = now();
  end if;
end;
$function$;

revoke execute on function public.adjust_promo_usage(uuid, uuid, integer) from public;


create or replace function public.increment_warehouse_totals(p_wh uuid, p_pairs integer, p_products integer)
returns void
language sql
security definer
set search_path to 'public'
as $function$
  update public.warehouses
    set total_pairs = total_pairs + p_pairs,
        total_products = total_products + p_products
    where id = p_wh
      and (owner_uid = public.app_owner_uid() or public.is_superadmin());
$function$;

revoke execute on function public.increment_warehouse_totals(uuid, integer, integer) from public;
