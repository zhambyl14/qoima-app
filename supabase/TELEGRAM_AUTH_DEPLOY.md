# Телефон + Telegram аутентификациясы — деплой нұсқаулығы

Барлық рөл (клиент/сатушы/админ/суперадмин) енді **телефон + құпиясөзбен**
тіркеледі әрі кіреді. Телефон **Telegram боты** (`@qoimashybot`) арқылы
расталады (SMS-сіз, тегін). Google-мен кіру толық жойылды.

## 1) Миграциялар (реті бойынша)
- `0012_phone_auth.sql` — `users.phone` + `email_for_phone` RPC + `handle_new_user`.
- `0013_telegram_verification.sql` — `telegram_verifications` кестесі + RPC-лар.
- `0014_migrate_admin_phones.sql` — ескі email-аккаунттарға телефон беру
  (нөмірлерді ТОЛТЫРЫП, `--` түсіріп, қолданыңыз).

## 2) Edge Functions (екеуінде де **Verify JWT = OFF**)
- `telegram-webhook` — Telegram-нан контакт қабылдап, нөмірді растайды.
- `tg-reset-password` — расталған токенмен парольді жаңартады.

## 3) Edge Function Secrets (Dashboard → Edge Functions → Manage secrets)
Екеуі де `telegram-webhook`-қа қажет (`tg-reset-password`-қа тек ендірілген
`SUPABASE_URL` / `SUPABASE_SERVICE_ROLE_KEY` жеткілікті):
- `TELEGRAM_BOT_TOKEN` — BotFather берген токен (`@qoimashybot`).
- `TELEGRAM_WEBHOOK_SECRET` — өзіңіз ойлап тапқан ұзын құпия жол
  (мыс. `openssl rand -hex 32`).

> CLI-мен: `supabase secrets set TELEGRAM_BOT_TOKEN=... TELEGRAM_WEBHOOK_SECRET=...`

## 4) Webhook-ты тіркеу
Секреттер қойылғаннан кейін браузерде/терминалда бір рет ашыңыз
(`<TOKEN>`, `<SECRET>` — 3-қадамдағы нақты мәндер):
```
https://api.telegram.org/bot<TOKEN>/setWebhook?url=https://ujpcdfgwxdholsepioji.supabase.co/functions/v1/telegram-webhook&secret_token=<SECRET>
```
`{"ok":true,"result":true,...}` қайтса — сәтті.

## 5) Dashboard баптауы
- Authentication → «Confirm email» **ӨШІРУЛІ** болуы керек (верификация жоқ —
  тіркелу бірден сессия ашады).

## Тексеру (E2E)
1. Клиент тіркелу: «Telegram арқылы растау» → ботта «Нөмірімді бөлісу» → нөмір
   жасыл «расталды» → пароль/аты/қала → ClientShell.
2. Шығып, сол телефон+парольмен кіру.
3. Сатушы мен админді солай тіркеу.
4. «Құпиясөзді ұмыттым» → Telegram растау → жаңа пароль → автоматты кіру.
5. Ескі (0014-пен телефон берілген) админ телефон + ЕСКІ парольмен кіреді.
