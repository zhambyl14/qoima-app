-- ════════════════════════════════════════════════════════════════════════════
--  0047 · Сұрақ-жауап: спамға шек + дүкен иесі өшіре алады + шағымдану
-- ────────────────────────────────────────────────────────────────────────────
--  0046-да байқалған 3 олқылық:
--   1) Клиент шексіз сұрақ жаза беруі мүмкін еді (спам).
--   2) Дүкен иесінде спам/жалған сұрақты өшіру мүмкіндігі жоқ еді (тек
--      superadmin немесе сұрақ авторының өзі, тек жауап жоқ кезде).
--   3) content_reports target_type тізімінде 'question' жоқ еді — сұраққа
--      шағымдану мүмкін емес еді.
-- ════════════════════════════════════════════════════════════════════════════

-- ── 1) Спамға шек: бір клиент — бір САТУШЫҒА (admin_uid, оның барлық
--    тауарлары бойынша жиынтық) бір ЖАУАПСЫЗ сұрақ қана. Сол сатушы жауап
--    бергеннен кейін ғана осы клиент оған жаңа сұрақ жаза алады (басқа
--    сатушыға сұрақ қоюға бұл кедергі жасамайды) ────────────────────────────
create unique index product_questions_client_admin_pending_uidx
  on public.product_questions(client_uid, admin_uid)
  where answer = '';

-- ── 2) Спамға шек: 24 сағатта 15-тен көп сұрақ жазуға болмайды (барлық
--    тауарлар бойынша жиынтық — әр түрлі тауарға таратып спам жасауды
--    болдырмайды) ───────────────────────────────────────────────────────────
create or replace function public.check_question_rate_limit() returns trigger
language plpgsql as $$
declare v_recent integer;
begin
  select count(*) into v_recent
    from public.product_questions
    where client_uid = new.client_uid
      and created_at > now() - interval '24 hours';
  if v_recent >= 15 then
    raise exception 'question_rate_limit';
  end if;
  return new;
end;
$$;
drop trigger if exists trg_question_rate_limit on public.product_questions;
create trigger trg_question_rate_limit before insert on public.product_questions
  for each row execute function public.check_question_rate_limit();

-- ── 3) Дүкен иесі/сатушысы өз тауарындағы сұрақты өшіре алады (спам/жалған
--    мазмұнды тез тазалау үшін — superadmin кезегін күтпей) ─────────────────
drop policy if exists product_questions_delete on public.product_questions;
create policy product_questions_delete on public.product_questions for delete using (
  (client_uid = auth.uid() and answer = '')
  or admin_uid = public.app_owner_uid()
  or public.is_superadmin()
);

-- ── 4) Шағымдану: content_reports енді 'question' target_type-ін де қабылдайды
alter table public.content_reports
  drop constraint content_reports_target_type_check;
alter table public.content_reports
  add constraint content_reports_target_type_check
    check (target_type in ('product', 'store', 'review', 'question'));
