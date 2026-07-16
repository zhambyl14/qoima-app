-- ════════════════════════════════════════════════════════════════════════════
--  0016 · Пікірге дүкен жауабы + пікірлер realtime
-- ────────────────────────────────────────────────────────────────────────────
--  Дүкен иесі (немесе оның сатушысы) өз тауарының пікіріне жауап бере алады.
--  RLS update саясаты клиентке ғана ашық болғандықтан, жауап SECURITY DEFINER
--  RPC арқылы жазылады — тек reply өрістерін, тек өз дүкенінің пікіріне.
-- ════════════════════════════════════════════════════════════════════════════

alter table public.product_reviews
  add column if not exists seller_reply    text not null default '',
  add column if not exists seller_reply_at timestamptz;

-- Жауап жазу/өзгерту/өшіру (бос мәтін = жауапты өшіру).
create or replace function public.reply_to_review(p_review uuid, p_reply text)
returns void
language plpgsql security definer set search_path = public as $$
begin
  update public.product_reviews
     set seller_reply = coalesce(trim(p_reply), ''),
         seller_reply_at = case
           when coalesce(trim(p_reply), '') = '' then null else now() end
   where id = p_review
     and admin_uid = public.app_owner_uid();
  if not found then
    raise exception 'not_allowed';
  end if;
end;
$$;
grant execute on function public.reply_to_review(uuid, text) to authenticated;

-- Админ пікірлерді `.stream()` арқылы көреді → realtime публикациясына қосамыз.
alter publication supabase_realtime add table public.product_reviews;
