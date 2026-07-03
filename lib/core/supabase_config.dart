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
  //  Google-мен кіру: WEB application түріндегі OAuth client-тің ID-і.
  //  ⚠️ МІНДЕТТІ ТЕКСЕРУ: Google Cloud Console → Credentials тізімінде
  //  Type бағаны «Web application» болып тұрған client-тің ID-і осында тұруы
  //  керек (Android/iOS ID ЕМЕС!). Қате болса Google кіру «токен алынбады»
  //  қатесін береді.
  // ════════════════════════════════════════════════════════════════════════
  static const String googleWebClientId =
      '536773855283-f6ledrtslna1ke0i5tjui45lf54o7k8a.apps.googleusercontent.com';
}
