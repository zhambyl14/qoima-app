-- ════════════════════════════════════════════════════════════════════════
-- 0067b: Жаңа функцияларды суперадмин қосып/өшіретін жалаушалар
--
-- Неге: AI (киіп көру, стилист, көмекші, тауар сипаттамасы), live-эфир,
-- тілек тізімі, сыйлық сілтемесі, қолдау чаты, қайтарылмайтын тауар —
-- бәрін суперадмин «Платформа баптаулары» бетінен қосып-өшіреді.
-- Мән app_settings-те 'feature_<атау>' = 'true'|'false' болып сақталады.
-- Сыртқы кілт (Anthropic/FASHN/LiveKit) керек функциялар әдепкіде ӨШІК —
-- кілт қойылған соң суперадмин қосады.
--
-- Тексеру сервер жағында да: әр RPC / edge function feature_enabled()
-- арқылы тексеріп, өшік болса 'feature_disabled' қатесін береді
-- (UI-да жасыру жеткіліксіз — ескі нұсқадағы клиент те шақыра алады).
-- 0068+ миграциялары осы функцияларға сүйенеді, сондықтан бұл бірінші.
-- ════════════════════════════════════════════════════════════════════════

insert into public.app_settings (key, value) values
  ('feature_ai_tryon',          'false'),
  ('feature_ai_stylist',        'false'),
  ('feature_ai_assistant',      'false'),
  ('feature_ai_product_assist', 'false'),
  ('feature_live_shopping',     'false'),
  ('feature_gift_registry',     'true'),
  ('feature_gift_links',        'true'),
  ('feature_support_chat',      'true'),
  ('feature_non_returnable',    'true')
on conflict (key) do nothing;

-- Барлық жалаушалар: {"ai_tryon": false, ...}.
-- Әдейі публиктік (anon да): guest те қай батырманы көрсету керегін білуі
-- керек; тек feature_* кілттері қайтады, құпия ештеңе жоқ.
create or replace function public.feature_flags()
returns jsonb
language sql stable security definer
set search_path = public
as $$
  select coalesce(
    jsonb_object_agg(substr(key, 9), value = 'true'),
    '{}'::jsonb)
  from public.app_settings
  where key like 'feature\_%';
$$;
revoke execute on function public.feature_flags() from public;
grant execute on function public.feature_flags() to anon, authenticated;

-- Бір жалауша. Белгісіз атау → false (жаңа функция әдепкіде жабық).
-- Әдейі публиктік: басқа SECURITY DEFINER RPC-лер мен edge function-дар
-- ішінде шақырылады, тек true/false қайтарады.
create or replace function public.feature_enabled(p_name text)
returns boolean
language sql stable security definer
set search_path = public
as $$
  select coalesce(
    (select value = 'true' from public.app_settings
      where key = 'feature_' || p_name),
    false);
$$;
revoke execute on function public.feature_enabled(text) from public;
grant execute on function public.feature_enabled(text) to anon, authenticated;
