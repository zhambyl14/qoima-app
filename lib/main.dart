import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'core/supabase_config.dart';
import 'theme/app_theme.dart';
import 'ui/auth/blocked_screen.dart';
import 'ui/auth/complete_profile_screen.dart';
import 'ui/auth/seller_join_screen.dart';
import 'ui/superadmin/shop_requests_screen.dart';
import 'ui/guest/guest_shell.dart';
import 'ui/main_shell.dart';
import 'ui/client/client_shell.dart';
import 'ui/admin/admin_shell.dart';
import 'data/models/client_model.dart';
import 'data/models/user_model.dart';
import 'data/services/auth_service.dart';
import 'core/app_user.dart';
import 'core/warehouse_context.dart';
import 'core/locale_context.dart';
import 'l10n/app_localizations.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ru', null);
  await initializeDateFormatting('kk', null);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  // Тек тік (портрет) режим — телефонда автоповорот қосулы болса да
  // қосымша көлденеңге бұрылмайды (интерфейс тік бағдарға арналған).
  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  // Supabase инициализациясы. Кілт түрін автоматты анықтаймыз: ескі JWT
  // (eyJ...) → anonKey; жаңа кілт (sb_publishable_...) → publishableKey.
  final supaKey = SupabaseConfig.anonKey;
  final isLegacyJwt = supaKey.startsWith('eyJ');
  await Supabase.initialize(
    url: SupabaseConfig.url,
    anonKey: isLegacyJwt ? supaKey : null,
    publishableKey: isLegacyJwt ? null : supaKey,
  );
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppUser()),
        ChangeNotifierProvider(create: (_) => WarehouseContext()),
        ChangeNotifierProvider(create: (_) => LocaleContext()),
        ChangeNotifierProvider(create: (_) => CartProvider()),
      ],
      child: const QoimaApp(),
    ),
  );
}

class QoimaApp extends StatelessWidget {
  const QoimaApp({super.key});

  @override
  Widget build(BuildContext context) {
    final locale = context.watch<LocaleContext>().locale;
    return MaterialApp(
      title: 'Qoima',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme.copyWith(
        textTheme: GoogleFonts.manropeTextTheme(AppTheme.theme.textTheme),
        scaffoldBackgroundColor: const Color(0xFFF1F4F3),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00A862),
          brightness: Brightness.light,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF00713F),
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
          iconTheme: IconThemeData(color: Colors.white),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE7ECEA))),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE7ECEA))),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  const BorderSide(color: Color(0xFF00A862), width: 1.5)),
          errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFF0384B))),
          labelStyle: const TextStyle(color: Color(0xFF566B61), fontSize: 14),
          prefixIconColor: const Color(0xFF00A862),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF00A862),
            foregroundColor: Colors.white,
            elevation: 0,
            padding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
            textStyle:
                const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
      ),
      // Жүйелік «үлкен шрифт» баптауы интерфейсті бұзбауы үшін мәтін
      // масштабын шектейміз (дизайн тығыз — 1.1-дің өзінде батырма/навбар
      // мәтіндері тасып кететіні байқалды, сондықтан 1.0-ге бекітеміз).
      // Кішірейтуге рұқсат (min жоқ).
      builder: (context, child) => MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.0,
        child: child!,
      ),
      locale: locale,
      supportedLocales: const [Locale('kk'), Locale('ru')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: StreamBuilder<AuthState>(
        stream: Supabase.instance.client.auth.onAuthStateChange,
        builder: (context, snapshot) {
          // currentSession инициализация кезінде қалпына келтіріледі, сондықтан
          // оны тікелей оқимыз; ағын тек өзгерістерде қайта құрады.
          final session = Supabase.instance.client.auth.currentSession;
          if (session == null) {
            // clear() — notifyListeners шақырады, build фазасынан тыс орындаймыз.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              context.read<AppUser>().clear();
              context.read<WarehouseContext>().clear();
            });
            // Кірмеген пайдаланушы — каталогты шолып, корзинаға тауар сала алады.
            return const GuestShell();
          }
          return FutureBuilder<_SessState>(
            future: _loadSession(session.user.id, context),
            builder: (innerCtx, futureSnap) {
              // AppUser-ді бірінші тексереміз (реактивті — watch): тіркелу
              // экрандары AppUser.set() шақырғанда gate өзі дұрыс экранға ауысады.
              final user = innerCtx.watch<AppUser>();
              if (user.isLoaded) {
                // Жалпы блок — ешқандай әрекетке жол жоқ (seller босап шыға алады).
                if (user.blocked) return const BlockedScreen();
                if (user.isSuperadmin) return const ShopRequestsScreen();
                if (user.isClient) return const ClientShell();
                // Admin тіркелген соң бірден офлайн жұмысқа кіреді.
                if (user.isAdmin) return const _AdminHomeRouter();
                if (user.joinStatus == 'active') return const MainShell();
                return const SellerJoinScreen();
              }
              if (futureSnap.connectionState == ConnectionState.waiting) {
                return const _Splash();
              }
              // Сессия бар, профиль жоқ — Google-мен алғаш кірген: тіркелуді
              // аяқтау экраны (рөл + телефон/қала).
              if (futureSnap.data == _SessState.noProfile) {
                return const CompleteProfileScreen();
              }
              // Желі/басқа қате — қауіпсіз шығарамыз.
              return const _AuthFallback();
            },
          );
        },
      ),
    );
  }
}

/// Сессия жүктеу нәтижесі: loaded — профиль табылды (AppUser орнады);
/// noProfile — Auth сессиясы бар, бірақ users/clients жолы жоқ (Google-мен
/// алғаш кірген — профильді аяқтау керек); error — желі/басқа қате.
enum _SessState { loaded, noProfile, error }

Future<_SessState> _loadSession(String uid, BuildContext context) async {
  final wCtx = context.read<WarehouseContext>();
  final appUser = context.read<AppUser>();
  try {
    final authService = AuthService();
    final sb = Supabase.instance.client;

    // Auth email өзгерген болса (verifyBeforeUpdateEmail сілтемесі басылған),
    // индекстер мен профильді сәйкестендіреміз (best-effort).
    try {
      await authService.syncEmailIfChanged();
    } catch (_) {}

    // Try admin/seller doc first. МАҢЫЗДЫ: қатені жұтпайтын тікелей сұрау —
    // желі қатесі «профиль жоқ» (noProfile) болып қате танылмауы үшін.
    final uRow = await sb.from('users').select().eq('id', uid).maybeSingle();
    final userDoc = uRow == null ? null : UserModel.fromMap(uRow);
    if (userDoc != null) {
      // Жалпы блок: өзі немесе дүкен иесі блокталған ба (superadmin-ға қатысты емес).
      var blocked = false;
      var blockReason = '';
      var blockSource = '';
      if (!userDoc.isSuperadmin) {
        final bs = await authService.fetchBlockStatus();
        blocked = bs.blocked;
        blockReason = bs.reason;
        blockSource = bs.source;
      }
      appUser.set(
        uid: userDoc.uid,
        ownerUid: userDoc.ownerId.isNotEmpty ? userDoc.ownerId : userDoc.uid,
        name: userDoc.name,
        email: userDoc.email,
        role: userDoc.role,
        active: userDoc.active,
        businessCode: userDoc.businessCode,
        assignedWarehouseId: userDoc.assignedWarehouseId,
        joinStatus: userDoc.joinStatus,
        shopStatus: userDoc.shopStatus,
        termsAccepted: userDoc.termsAccepted,
        blocked: blocked,
        blockReason: blockReason,
        blockSource: blockSource,
      );
      if (!blocked) await wCtx.load();
      return _SessState.loaded;
    }

    // Try client doc (тікелей сұрау — қате жұтылмайды)
    final cRow = await sb.from('clients').select().eq('id', uid).maybeSingle();
    final clientDoc = cRow == null ? null : ClientModel.fromMap(cRow);
    if (clientDoc != null) {
      appUser.set(
        uid: clientDoc.uid,
        ownerUid: '',
        name: clientDoc.name,
        email: clientDoc.email,
        role: 'client',
        phone: clientDoc.phone,
        city: clientDoc.city,
        // Верификация жоқ — барлық клиент расталған деп есептеледі.
        emailVerified: true,
      );
      return _SessState.loaded;
    }

    // Екі сұрау да сәтті өтіп, екеуі де бос — Google-мен алғаш кірген.
    return _SessState.noProfile;
  } catch (_) {
    return _SessState.error;
  }
}

/// Кірген, бірақ профилі жоқ орфан күй: пайдаланушыны қауіпсіз шығарамыз да,
/// реактивті gate-ті қонақ/кіру экранына қайтарамыз.
class _AuthFallback extends StatefulWidget {
  const _AuthFallback();
  @override
  State<_AuthFallback> createState() => _AuthFallbackState();
}

class _AuthFallbackState extends State<_AuthFallback> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AuthService().signOut();
    });
  }

  @override
  Widget build(BuildContext context) => const _Splash();
}

class _AdminHomeRouter extends StatefulWidget {
  const _AdminHomeRouter();
  @override
  State<_AdminHomeRouter> createState() => _AdminHomeRouterState();
}

class _AdminHomeRouterState extends State<_AdminHomeRouter> {
  @override
  Widget build(BuildContext context) => const AdminShell();
}

class _Splash extends StatelessWidget {
  const _Splash();
  @override
  Widget build(BuildContext context) => const Scaffold(
        backgroundColor: Color(0xFF00A862),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Qoima',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 36,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1)),
              SizedBox(height: 24),
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2),
              ),
            ],
          ),
        ),
      );
}
