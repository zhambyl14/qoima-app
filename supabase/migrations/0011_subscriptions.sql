-- ════════════════════════════════════════════════════════════════════════════
--  0011 · Дүкен иелерінің жазылымы (подписка мониторингі — модератор үшін)
-- ────────────────────────────────────────────────────────────────────────────
--  ⚠️ БАЗАҒА ҚОЛДАНУ КЕРЕК (MCP apply_migration немесе Supabase SQL editor).
--  Алдымен тірі схеманы салыстыр (жад: db_schema_drift) — егер users кестесінде
--  бұл бағандар бұрыннан болса, `if not exists` оларды қайталамайды (қауіпсіз).
--
--  Модель: төлем аппликациядан ТЫС ("өз арамызда") — база тек мерзімді сақтайды.
--  subscription_until = null  → жазылым берілмеген (жаңа иеге әдепкі).
--  Модератор мерзімді қолмен ұзартады (+1/+3/+6/+12 ай) немесе нақты күн қояды.
--  Блоктау автоматты ЕМЕС — модератор асып кеткендерді көреді де, қолмен блоктайды
--  (қолданыстағы users.blocked / stores.status арқылы, 0005 қараңыз).
-- ════════════════════════════════════════════════════════════════════════════

alter table public.users
  add column if not exists subscription_until      timestamptz,
  add column if not exists subscription_started_at timestamptz,
  add column if not exists subscription_plan       text default '',
  add column if not exists subscription_note       text default '';

-- Мерзімі жақындағандарды/асқандарды жылдам сұрыптау үшін.
create index if not exists users_subscription_until_idx
  on public.users(subscription_until)
  where role = 'admin';

-- ── RLS ескертпесі ───────────────────────────────────────────────────────────
--  Жаңа RLS саясаты ҚАЖЕТ ЕМЕС: users_write саясаты (0001) superadmin-ге кез
--  келген users жолын жаңартуға рұқсат береді (is_superadmin()). Иенің өзі мен
--  сатушылар бұл бағандарды тек оқи алады (жаңарта алмайды) — қолданыстағы
--  users_select/users_write шектеулерімен бірдей.
