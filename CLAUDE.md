## graphify

This project has a knowledge graph at graphify-out/ with god nodes, community structure, and cross-file relationships.

Rules:
- For codebase questions, first run `graphify query "<question>"` when graphify-out/graph.json exists. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts. These return a scoped subgraph, usually much smaller than GRAPH_REPORT.md or raw grep output.
- If graphify-out/wiki/index.md exists, use it for broad navigation instead of raw source browsing.
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).

## Supabase қауіпсіздік ережелері (0065 аудитінен, толығы SECURITY_AUDIT_0065.md)

- Жаңа `SECURITY DEFINER` функцияда авторизация тексерісі **МІНДЕТТІ**
  (`auth.uid()` / `app_owner_uid()` / `is_superadmin()`), және соңында
  `revoke execute on function … from public;` жазу керек.
- **`revoke … from anon` ЖЕТКІЛІКСІЗ** — Postgres әдепкіде `EXECUTE TO PUBLIC`
  береді, ал PUBLIC anon-ды қамтиды. Әрқашан `from public` жазу.
  `create or replace function` PUBLIC грантын ҚАЙТА тудырады, сондықтан
  функцияны қайта жазған соң revoke-ты ҚАЙТА орындау керек.
  Тексеру: `select proacl from pg_proc where proname='…'` → ішінде `=X/` болмауы тиіс.
- RLS саясатында `using (true)` жазуға болмайды. Әдейі публиктік оқу болса —
  жанына неге екенін жазу.
- **RLS баған деңгейінде шектемейді.** Артықшылықты бағанды (`role`, `owner_id`,
  `subscription_*`, `blocked`, ақша өрістері) қорғау үшін BEFORE UPDATE триггері
  керек — `guard_users_privileged_columns`, `guard_orders_client_money` үлгісінде.
- `signUp` метадеректері (`raw_user_meta_data`) ЕШҚАШАН сенімді дереккөз емес —
  рөл, баға, лимит сол жерден алынбайды (ақ тізім міндетті).
- Қойма/ақша өзгертетін бәрі серверде, `for update` құлпымен, бір транзакцияда.
  Клиентте оқып-есептеп-жазуға болмайды.
- Статус/рөл жолдарының ақ тізімі екі жерде болса (Dart + SQL) — бір коммитте
  өзгерту. `OrderModel.status*` ↔ `claim_order_transition` ақ тізімі.
- Миграция жазған соң тірі БД-да объектінің БАР екенін `pg_proc` /
  `information_schema` арқылы тексеру. `list_migrations` бұл жобада шындықтың
  көзі ЕМЕС — 0049–0052, 0064 SQL editor-дан қолмен қолданылған (дрифт бар).
- `revoke`/`alter function` жазарда қолтаңбаны `pg_proc`-тан алу — жадыдан
  жазғанда қате шығады, миграция аборт болады.
