/// Supabase жобасының қосылым параметрлері.
///
/// ⚠️ ҚАУІПСІЗДІК: Клиентке (Flutter app) ТЕК `anon`/`publishable` кілтін
/// салыңыз. `service_role`/`sb_secret_...` кілтін ЕШҚАШАН осында салмаңыз.
class SupabaseConfig {
  /// Project URL: Supabase → Settings → API → Project URL.
  static const String url = 'https://ujpcdfgwxdholsepioji.supabase.co';

  // ════════════════════════════════════════════════════════════════════════
  //  ⬇️⬇️⬇️  ОСЫ ЖЕРГЕ КІЛТТІ ҚОЙЫҢЫЗ  ⬇️⬇️⬇️
  //  Supabase → Settings → API. Екеуінің БІРЕУІ жарайды:
  //   • жаңа "Publishable key":  sb_publishable_....   (ұсынылады)
  //   • ескі "anon public" JWT:  eyJhbGci....
  //  main.dart кілт түрін өзі анықтайды.
  // ════════════════════════════════════════════════════════════════════════
  static const String anonKey = String.fromEnvironment(
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVqcGNkZmd3eGRob2xzZXBpb2ppIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODI4MDYxMzcsImV4cCI6MjA5ODM4MjEzN30.E2AIz2quumSuU0K3lzONM8alw26NLzje3zvWWFUMk7o',
    defaultValue: 'sb_publishable_7Ytv1U1Saqh7i38EmTj7zA_-aQbA_GW',
  );

  /// Кілт қойылды ма (placeholder емес пе) — main.dart ескерту көрсету үшін.
  static bool get isConfigured =>
      anonKey.isNotEmpty && !anonKey.startsWith('eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVqcGNkZmd3eGRob2xzZXBpb2ppIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODI4MDYxMzcsImV4cCI6MjA5ODM4MjEzN30.E2AIz2quumSuU0K3lzONM8alw26NLzje3zvWWFUMk7o');

  // ════════════════════════════════════════════════════════════════════════
  //  Telegram растау боты: тіркелуде/парольді қалпына келтіруде телефон нөмірі
  //  осы бот арқылы (SMS-сіз, тегін) расталады. Тек username (@-сыз).
  //  Бот токені осында ЕМЕС — ол тек Edge Function secret-інде (TELEGRAM_BOT_
  //  TOKEN) тұрады. Мұнда деректо-сілтеме құрастыру үшін username жеткілікті.
  // ════════════════════════════════════════════════════════════════════════
  static const String telegramBot = 'qoimashybot';

  /// Растау сессиясының терең сілтемесі: `t.me/<bot>?start=<token>`.
  /// Веб/қор нұсқасы — браузер немесе App Links арқылы ашылады.
  static String telegramStartUrl(String token) =>
      'https://t.me/$telegramBot?start=$token';

  /// Telegram қосымшасын ТІКЕЛЕЙ ашатын deep link:
  /// `tg://resolve?domain=<bot>&start=<token>`.
  /// Браузерді де, `t.me` DNS-ін де мүлде айналып өтеді — сол себепті
  /// t.me бөгелген/DNS шешілмеген желіде де (DNS_PROBE_FINISHED_NXDOMAIN)
  /// Telegram орнатылған болса ашыла береді.
  static String telegramAppUrl(String token) =>
      'tg://resolve?domain=$telegramBot&start=$token';

  // ════════════════════════════════════════════════════════════════════════
  //  Тауарды бөлісу бетінің базалық URL-і (Deno Deploy).
  //  ⚠️ Supabase-тің тегін домені HTML-ді рендерлемейді, сол себепті share-бет
  //  Deno Deploy-да тұрады (тегін *.deno.dev). deno-deploy/main.ts деплой етіп,
  //  алынған URL-ді осында қойыңыз (соңында '/' БОЛМАСЫН). Мысалы:
  //    'https://qoima-product.deno.dev'
  //  Бос болса — бөлісу батырмасы ескерту көрсетеді.
  // ════════════════════════════════════════════════════════════════════════
  static const String shareBaseUrl = 'https://qoima.zhambyl14.deno.net';

  /// Тауар сілтемесін құрастырады: `shareBaseUrl/?id=productId`.
  static String productShareUrl(String productId) =>
      shareBaseUrl.isEmpty ? '' : '$shareBaseUrl/?id=$productId';
}
