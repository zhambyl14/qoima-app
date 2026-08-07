-- ════════════════════════════════════════════════════════════════════════════
--  0046 · Тауар бойынша сұрақ-жауап («Вопросы и ответы», Wildberries үлгісі)
-- ────────────────────────────────────────────────────────────────────────────
--  0015-дегі product_reviews идиомасының қарапайымдалған нұсқасы: рейтингсіз,
--  сатып алу расталуынсыз (кез келген клиент сұрай алады — сатып алғанға
--  ДЕЙІН сұрақ қою — бүкіл мағынасы осында). Оқу публичті (guest те көреді).
--  Жауап тек SECURITY DEFINER RPC арқылы (0016-дағы reply_to_review
--  идиомасымен бірдей) — дүкен иесі/сатушысы, тек өз тауарына.
-- ════════════════════════════════════════════════════════════════════════════

create table public.product_questions (
  id          uuid primary key default gen_random_uuid(),
  product_id  uuid not null references public.products(id) on delete cascade,
  admin_uid   uuid not null,                       -- дүкен иесі (сүзу үшін)
  client_uid  uuid not null references auth.users(id) on delete cascade,
  client_name text not null default '',
  question    text not null,
  answer      text not null default '',
  answered_at timestamptz,
  created_at  timestamptz not null default now()
);
create index product_questions_product_idx on public.product_questions(product_id);
create index product_questions_admin_idx   on public.product_questions(admin_uid);

alter table public.product_questions enable row level security;

-- Сұрақтар: оқу публичті; жазу — кез келген авторизацияланған клиент (сатып
-- алу міндетті емес); өшіру — өз сұрағы (әлі жауап жоқ кезде) немесе superadmin.
create policy product_questions_select on public.product_questions
  for select using (true);

create policy product_questions_insert on public.product_questions
  for insert with check (client_uid = auth.uid());

create policy product_questions_delete on public.product_questions
  for delete using (
    (client_uid = auth.uid() and answer = '') or public.is_superadmin()
  );

-- Жауап жазу/өзгерту/өшіру (бос мәтін = жауапты өшіру).
create or replace function public.answer_product_question(p_question uuid, p_answer text)
returns void
language plpgsql security definer set search_path = public as $$
begin
  update public.product_questions
     set answer = coalesce(trim(p_answer), ''),
         answered_at = case
           when coalesce(trim(p_answer), '') = '' then null else now() end
   where id = p_question
     and admin_uid = public.app_owner_uid();
  if not found then
    raise exception 'not_allowed';
  end if;
end;
$$;
grant execute on function public.answer_product_question(uuid, text) to authenticated;

-- ── Push: жаңа сұрақ → дүкен иесі+сатушыларына ───────────────────────────────
create or replace function public.on_question_push() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_uids uuid[];
begin
  select array_agg(id) into v_uids
    from public.users
    where id = new.admin_uid or (owner_id = new.admin_uid and role = 'seller');
  perform public.notify_push(
    coalesce(v_uids, array[new.admin_uid]),
    'Новый вопрос о товаре',
    left(new.question, 100),
    jsonb_build_object('type', 'product_question', 'productId', new.product_id)
  );
  return new;
end;
$$;
drop trigger if exists trg_question_push on public.product_questions;
create trigger trg_question_push after insert on public.product_questions
  for each row execute function public.on_question_push();

-- ── Push: жауап берілді → клиентке ────────────────────────────────────────────
create or replace function public.on_question_answer_push() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if coalesce(old.answer, '') = '' and coalesce(new.answer, '') <> '' then
    perform public.notify_push(
      array[new.client_uid],
      'Ответ на ваш вопрос',
      left(new.answer, 100),
      jsonb_build_object('type', 'question_answer', 'productId', new.product_id)
    );
  end if;
  return new;
end;
$$;
drop trigger if exists trg_question_answer_push on public.product_questions;
create trigger trg_question_answer_push after update on public.product_questions
  for each row execute function public.on_question_answer_push();

-- Админ/клиент `.stream()` арқылы көреді → realtime публикациясына қосамыз.
alter publication supabase_realtime add table public.product_questions;
