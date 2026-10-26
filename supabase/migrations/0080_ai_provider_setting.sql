-- ════════════════════════════════════════════════════════════════════════════
--  0080 · AI провайдерін суперадмин таңдайды + киіп көру нәтижелерінің қоймасы
-- ────────────────────────────────────────────────────────────────────────────
--   • app_settings.ai_provider: 'auto' | 'gemini' | 'anthropic'.
--     Edge функциялар (_shared/llm.ts) оны service_role арқылы оқиды (60 с кэш).
--     'auto' — Claude кілті бар болса Claude, әйтпесе Gemini.
--     Киіп көру: 'gemini' → Gemini сурет моделі; әйтпесе FASHN кілті болса FASHN.
--   • storage bucket 'tryon-results' — ЖАБЫҚ (public=false), клиенттің RLS
--     саясаты ЖОҚ: жазу/оқу тек service_role (edge функция) арқылы, клиент
--     1 сағаттық signed URL алады. Ескі нәтижелер сол пайдаланушы келесі рет
--     шақырғанда өшіріледі (адам суретінің өзі ЕШҚАШАН сақталмайды).
-- ════════════════════════════════════════════════════════════════════════════

insert into public.app_settings (key, value)
values ('ai_provider', 'gemini')
on conflict (key) do nothing;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('tryon-results', 'tryon-results', false, 10485760,
        array['image/png', 'image/jpeg', 'image/webp'])
on conflict (id) do nothing;
