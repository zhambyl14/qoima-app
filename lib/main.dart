import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'core/supabase_config.dart';
import 'theme/app_theme.dart';
import 'theme/qoima_design.dart';
import 'ui/auth/blocked_screen.dart';
import 'ui/auth/seller_join_screen.dart';
import 'ui/auth/subscription_gate.dart';
import 'ui/superadmin/shop_requests_screen.dart';
import 'ui/guest/guest_shell.dart';
import 'ui/main_shell.dart';
import 'ui/client/client_shell.dart';
import 'ui/courier/courier_pending_screen.dart';
import 'ui/courier/courier_shell.dart';
import 'ui/admin/admin_shell.dart';
import 'ui/shared/error_view.dart';
import 'data/models/client_model.dart';
import 'data/models/user_model.dart';
import 'data/services/auth_service.dart';
import 'data/services/push_service.dart';
import 'data/services/local_notification_service.dart';
import 'core/app_user.dart';
import 'core/lang.dart';
import 'core/warehouse_context.dart';
import 'core/locale_context.dart';
import 'core/push_navigation.dart';
import 'core/deep_links.dart';
import 'l10n/app_localizations.dart';

/// ҚОСЫМШАНЫҢ ІСКЕ ҚОСЫЛУЫ — ЕҢ МАҢЫЗДЫ ЕРЕЖЕ:
/// `runApp` бірінші кадрды кешіктірмеу үшін ЕШҚАНДАЙ желі/плагин
/// инициализациясын КҮТПЕЙДІ. Бұрын main() ішінде Supabase/Firebase/
/// хабарлама сервистері `await`-пен шақырылатын да, сол қадамдардың бірі
/// (мыс. интернет жоқ кездегі плагин шақыруы) қатып қалса, runApp мүлде
/// орындалмай, пайдаланушы АҚ ЭКРАН көретін (қосымша «ашылмай» қалатын).
/// Енді: бірден splash салынады → инициализация [_QoimaBootState._boot]
/// ішінде, әр қадамы таймаутпен әрі try/catch-пен жүреді → қате болса
/// «Қайталау» батырмасы бар түсінікті экран шығады.
void main() {
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));
    // Виджет құру кезіндегі қате: релизде әдепкі сұр/қара экранның орнына
    // түсінікті хабар (қосымша толық «өліп» қалмайды).
    ErrorWidget.builder = (details) {
      debugPrint('UI build error: ${details.exception}');
      return const _UiErrorBox();
    };
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      debugPrint('FlutterError: ${details.exception}');
    };
    runApp(const QoimaBoot());
  }, (error, stack) {
    // Ұсталмаған асинхронды қате қосымшаны құлатпасын — тек логқа.
    debugPrint('Uncaught async error: $error\n$stack');
  });
}

/// Инициализация кезеңдері.
enum _BootStage { loading, ready, failed }

/// Инициализацияны бірінші кадрдан КЕЙІН, қауіпсіз түрде жүргізетін қабық.
class QoimaBoot extends StatefulWidget {
  const QoimaBoot({super.key});

  @override
  State<QoimaBoot> createState() => _QoimaBootState();
}

class _QoimaBootState extends State<QoimaBoot> {
  _BootStage _stage = _BootStage.loading;
  Object? _error;
  Locale _locale = const Locale('ru');

  /// Supabase бір-ақ рет көтеріледі («Қайталау» басылғанда қайта шақырмаймыз).
  static bool _supabaseReady = false;
  static bool _notificationsStarted = false;
  static bool _deepLinksStarted = false;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  /// Қосымша жұмысы үшін МІНДЕТТІ жалғыз қадам — Supabase. Қалғаны
  /// «best-effort»: сәтсіз болса да қосымша ашылады.
  Future<void> _boot() async {
    if (mounted) {
      setState(() {
        _stage = _BootStage.loading;
        _error = null;
      });
    }

    // Тек тік (портрет) режим.
    await _bestEffort(
      'orientation',
      () => SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]),
    );
    // Күн/ай атаулары (intl) — жүктелмесе тек формат әдепкі болады.
    await _bestEffort('intl', () async {
      await initializeDateFormatting('ru', null);
      await initializeDateFormatting('kk', null);
    });
    // Сақталған тіл — алғашқы кадрдан дұрыс тілмен ашылу үшін.
    try {
      _locale =
          await LocaleContext.loadSaved().timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('boot: locale load skipped: $e');
    }

    // ── Supabase (міндетті) ────────────────────────────────────────────────
    // Кілт түрін автоматты анықтаймыз: ескі JWT (eyJ...) → anonKey;
    // жаңа кілт (sb_publishable_...) → publishableKey.
    if (!_supabaseReady) {
      try {
        final supaKey = SupabaseConfig.anonKey;
        final isLegacyJwt = supaKey.startsWith('eyJ');
        await Supabase.initialize(
          url: SupabaseConfig.url,
          anonKey: isLegacyJwt ? supaKey : null,
          publishableKey: isLegacyJwt ? null : supaKey,
        ).timeout(const Duration(seconds: 25));
        _supabaseReady = true;
      } catch (e, s) {
        debugPrint('boot: Supabase init failed: $e\n$s');
        if (!mounted) return;
        setState(() {
          _stage = _BootStage.failed;
          _error = e;
        });
        return;
      }
    }

    if (!mounted) return;
    setState(() => _stage = _BootStage.ready);

    // ── Хабарламалар (міндетті емес) ───────────────────────────────────────
    // Бірінші кадрдан КЕЙІН, фонда: Firebase/APNs шақырулары кейде ұзаққа
    // созылады, ал олар интерфейсті бөгемеуі керек.
    if (!_notificationsStarted) {
      _notificationsStarted = true;
      WidgetsBinding.instance
          .addPostFrameCallback((_) => unawaited(_initNotifications()));
    }

    // ── Терең сілтемелер (сыйлық / тілек тізімі / эфир) ────────────────────
    // Navigator дайын болғанша DeepLinks өзі күтеді; қате қосымшаны бөгемейді.
    if (!_deepLinksStarted) {
      _deepLinksStarted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(
          _bestEffort('deep links', () => DeepLinks.instance.init())));
    }
  }

  /// Қатесі де, кідірісі де қосымшаны тоқтатпайтын қадам.
  Future<void> _bestEffort(String name, Future<void> Function() step) async {
    try {
      await step().timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('boot: $name skipped: $e');
    }
  }

  Future<void> _initNotifications() async {
    // Жергілікті хабарлама плагині PushService-тен БҰРЫН дайын болуы керек —
    // foreground FCM хабарламасы сол арқылы көрсетіледі (Android).
    await _bestEffort(
        'local notifications', () => LocalNotificationService.instance.init());
    // Push тапталғанда экранға секіру хендлерін init()-тен БҰРЫН тіркейміз —
    // cold-start getInitialMessage init() ішінде тексеріледі.
    PushService.instance.onNotificationOpen = handlePushOpen;
    try {
      await PushService.instance.init().timeout(const Duration(seconds: 30));
    } catch (e) {
      debugPrint('boot: push init skipped: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (_stage) {
      case _BootStage.loading:
        return const _BootShell(child: _Splash());
      case _BootStage.failed:
        return _BootShell(
          child: Scaffold(
            backgroundColor: cBg,
            body: SafeArea(
              child: AppErrorView(error: _error, onRetry: _boot),
            ),
          ),
        );
      case _BootStage.ready:
        return MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => AppUser()),
            ChangeNotifierProvider(create: (_) => WarehouseContext()),
            ChangeNotifierProvider(create: (_) => LocaleContext(_locale)),
            ChangeNotifierProvider(create: (_) => CartProvider()),
          ],
          child: const QoimaApp(),
        );
    }
  }
}

/// Инициализация кезіндегі минималды қабық (провайдерлерсіз, l10n-сыз).
class _BootShell extends StatelessWidget {
  final Widget child;
  const _BootShell({required this.child});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Qoima',
        theme: AppTheme.theme,
        home: child,
      );
}

/// Виджет құру қатесі кезінде көрсетіледі (ErrorWidget.builder).
/// Ешбір ата-виджетке тәуелді болмауы керек — сол себепті Directionality өзінде.
class _UiErrorBox extends StatelessWidget {
  const _UiErrorBox();

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.ltr,
        child: Container(
          color: cBg,
          alignment: Alignment.center,
          padding: const EdgeInsets.all(24),
          child: Text(
            tr('Не удалось отобразить этот экран. Попробуйте ещё раз.',
                'Бұл экранды көрсету мүмкін болмады. Қайталап көріңіз.'),
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 14,
                color: cInk2,
                fontWeight: FontWeight.w500,
                decoration: TextDecoration.none),
          ),
        ),
      );
}

class QoimaApp extends StatelessWidget {
  const QoimaApp({super.key});

  @override
  Widget build(BuildContext context) {
    final locale = context.watch<LocaleContext>().locale;
    return MaterialApp(
      // Тіл ауысқанда бүкіл ағашты мәжбүрлеп қайта құрамыз. tr() статикалық
      // currentLang оқитындықтан (InheritedWidget-ке жазылмайды), кэштелген
      // маршрут мазмұны өздігінен жаңармайды — key өзгеруі MaterialApp астындағы
      // Navigator/экрандардың бәрін жаңа тілде сол сәтте қайта салады.
      key: ValueKey(locale.languageCode),
      // Push тапталғанда (background/cold-start/foreground) ағымдағы
      // shell/таб үстіне дұрыс экранды салу үшін — lib/core/push_navigation.dart.
      navigatorKey: rootNavigatorKey,
      title: 'Qoima',
      debugShowCheckedModeBanner: false,
      // Жаһандық тема — түстер мен радиустар theme/qoima_design.dart
      // токендерінен алынады (бұрын осы жерде hex-тер қайта жазылып,
      // дизайн жүйесінен ажырап қалатын).
      theme: AppTheme.theme.copyWith(
        textTheme: GoogleFonts.interTextTheme(AppTheme.theme.textTheme),
        scaffoldBackgroundColor: cBg,
        colorScheme: ColorScheme.fromSeed(
          seedColor: cGreen,
          brightness: Brightness.light,
          surface: cSurface,
        ),
        splashColor: cGreen.withValues(alpha: 0.08),
        highlightColor: cGreen.withValues(alpha: 0.04),
        appBarTheme: AppBarTheme(
          backgroundColor: cGreenDeep,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: false,
          systemOverlayStyle: SystemUiOverlayStyle.light.copyWith(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.light,
            statusBarBrightness: Brightness.dark,
          ),
          titleTextStyle: manrope(19.5, FontWeight.w800, color: Colors.white),
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: cSurface,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(kR14),
              borderSide: const BorderSide(color: cLine)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(kR14),
              borderSide: const BorderSide(color: cLine)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(kR14),
              borderSide: const BorderSide(color: cGreen, width: 1.6)),
          errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(kR14),
              borderSide: const BorderSide(color: cRed)),
          focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(kR14),
              borderSide: const BorderSide(color: cRed, width: 1.6)),
          labelStyle: manrope(14, FontWeight.w500, color: cInk2),
          hintStyle: manrope(14, FontWeight.w500, color: cInk3),
          errorStyle: manrope(12, FontWeight.w600, color: cRedInk),
          prefixIconColor: cGreen,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: cGreen,
            foregroundColor: Colors.white,
            disabledBackgroundColor: cLine,
            disabledForegroundColor: cInk3,
            elevation: 0,
            shadowColor: Colors.transparent,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(kR16)),
            textStyle: manrope(15, FontWeight.w700, color: Colors.white),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: cGreenDeep,
            side: const BorderSide(color: cGreenTint2, width: 1.4),
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(kR16)),
            textStyle: manrope(14.5, FontWeight.w700, color: cGreenDeep),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: cGreenDeep,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(kR12)),
            textStyle: manrope(14, FontWeight.w700, color: cGreenDeep),
          ),
        ),
        // Хабарлама «қалқымалы» әрі дөңгелек — экран түбіне жабысып
        // тұрған тікбұрышты жолақтан гөрі жеңіл көрінеді.
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: cInk,
          contentTextStyle: manrope(13.5, FontWeight.w600, color: Colors.white),
          actionTextColor: cGreenBright,
          elevation: 6,
          insetPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(kR14)),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: cSurface,
          surfaceTintColor: Colors.transparent,
          elevation: 12,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(kR24)),
          titleTextStyle: manrope(18, FontWeight.w800, color: cInk),
          contentTextStyle: manrope(14, FontWeight.w500, color: cInk2),
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: cSurface,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(kR24))),
        ),
        dividerTheme: const DividerThemeData(
          color: cLine,
          thickness: 1,
          space: 1,
        ),
        // Курьер қабығы Material NavigationBar қолданады — қалған үш
        // қабықтағы қолдан жасалған навбармен бірдей көрінуі үшін.
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: cSurface,
          surfaceTintColor: Colors.transparent,
          indicatorColor: cGreenTint,
          indicatorShape: const StadiumBorder(),
          elevation: 0,
          height: 68,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
              size: 24,
              color: s.contains(WidgetState.selected) ? cGreenDeep : cInk3)),
          labelTextStyle: WidgetStateProperty.resolveWith((s) => manrope(
              11,
              s.contains(WidgetState.selected)
                  ? FontWeight.w700
                  : FontWeight.w600,
              color: s.contains(WidgetState.selected) ? cGreen : cInk3)),
        ),
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: cGreen,
          circularTrackColor: cGreenTint,
        ),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith((s) =>
              s.contains(WidgetState.selected) ? Colors.white : cSurface),
          trackColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.selected) ? cGreen : cLine),
          trackOutlineColor: WidgetStateProperty.resolveWith((s) =>
              s.contains(WidgetState.selected)
                  ? cGreen
                  : const Color(0xFFDCE4E0)),
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
      home: const _RootGate(),
    );
  }
}

/// Түбірлік «қақпа»: сессия бар/жоқ → профильді жүктеу → рөлге сай экран.
///
/// Бұрын бұл `home:` ішіндегі StreamBuilder болатын да, әр rebuild сайын
/// профильді ҚАЙТА сұрайтын, ал желі қатесінде пайдаланушыны ЕСЕПТЕН
/// ШЫҒАРЫП жіберетін (интернет жоқ кезде «өзі шығып кетті» деген шағым).
/// Енді: сұрау uid бойынша бір рет жасалады, желі қатесінде сессия сақталады
/// да, «Қайталау» батырмасы бар экран көрсетіледі.
class _RootGate extends StatefulWidget {
  const _RootGate();

  @override
  State<_RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<_RootGate> {
  Future<_SessResult>? _future;
  String? _loadedUid;

  void _retry(String uid) {
    setState(() {
      _loadedUid = uid;
      _future = _loadSession(uid, context);
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        // currentSession инициализация кезінде қалпына келтіріледі, сондықтан
        // оны тікелей оқимыз; ағын тек өзгерістерде қайта құрады.
        final session = Supabase.instance.client.auth.currentSession;
        if (session == null) {
          _future = null;
          _loadedUid = null;
          // clear() — notifyListeners шақырады, build фазасынан тыс орындаймыз.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            context.read<AppUser>().clear();
            context.read<WarehouseContext>().clear();
          });
          // Кірмеген пайдаланушы — каталогты шолып, корзинаға тауар сала алады.
          return const GuestShell();
        }

        final uid = session.user.id;
        if (_future == null || _loadedUid != uid) {
          _loadedUid = uid;
          _future = _loadSession(uid, context);
        }

        return FutureBuilder<_SessResult>(
          future: _future,
          builder: (innerCtx, futureSnap) {
            // AppUser-ді бірінші тексереміз (реактивті — watch): тіркелу
            // экрандары AppUser.set() шақырғанда gate өзі дұрыс экранға ауысады.
            final user = innerCtx.watch<AppUser>();
            if (user.isLoaded) {
              // Жалпы блок — ешқандай әрекетке жол жоқ (seller босап шыға алады).
              if (user.blocked) return const BlockedScreen();
              if (user.isSuperadmin) return const ShopRequestsScreen();
              if (user.isClient) return const ClientShell();
              // Курьер модераторға бағынады: бекітілмейінше тапсырыс көрмейді.
              if (user.isCourier) {
                return user.isActiveCourier
                    ? const CourierShell()
                    : const CourierPendingScreen();
              }
              // Жазылым «заморозкасы»: мерзім өткеніне 3 күннен асты —
              // иесі де, сатушылары да тек тауарларды көре алады.
              if (user.subFrozen) return const SubscriptionFrozenScreen();
              // Admin тіркелген соң бірден офлайн жұмысқа кіреді.
              // Мерзімі жаңа өткендерге (0–3 күн) — жабылатын ескерту.
              if (user.isAdmin) {
                return const SubscriptionExpiryNotice(
                    child: _AdminHomeRouter());
              }
              if (user.joinStatus == 'active') {
                return const SubscriptionExpiryNotice(child: MainShell());
              }
              return const SellerJoinScreen();
            }
            if (futureSnap.connectionState == ConnectionState.waiting) {
              return const _Splash();
            }
            final result = futureSnap.data;
            // Желі/сервер қатесі — ЕСЕПТЕН ШЫҒАРМАЙМЫЗ: сессия орнында қалады,
            // пайдаланушы интернет қосылған соң «Қайталау» басады.
            if (result == null || result.state == _SessState.error) {
              return _SessionErrorScreen(
                error: result?.error,
                onRetry: () async => _retry(uid),
              );
            }
            // Сессия бар, бірақ профиль жоқ (орфан) — қауіпсіз шығарамыз да,
            // реактивті gate кіру экранына қайтарады.
            return const _AuthFallback();
          },
        );
      },
    );
  }
}

/// Сессия жүктеу нәтижесі: loaded — профиль табылды (AppUser орнады);
/// orphan — Auth сессиясы бар, бірақ users/clients жолы жоқ (қауіпсіз шығару);
/// error — желі/басқа қате.
enum _SessState { loaded, orphan, error }

class _SessResult {
  final _SessState state;
  final Object? error;
  const _SessResult(this.state, [this.error]);
}

Future<_SessResult> _loadSession(String uid, BuildContext context) async {
  final wCtx = context.read<WarehouseContext>();
  final appUser = context.read<AppUser>();
  try {
    final authService = AuthService();
    final sb = Supabase.instance.client;

    // Try admin/seller doc first. МАҢЫЗДЫ: қатені жұтпайтын тікелей сұрау —
    // желі қатесі «профиль жоқ» (noProfile) болып қате танылмауы үшін.
    final uRow = await sb.from('users').select().eq('id', uid).maybeSingle();
    final userDoc = uRow == null ? null : UserModel.fromMap(uRow);
    if (userDoc != null) {
      // Жалпы блок: өзі немесе дүкен иесі блокталған ба (superadmin-ға қатысты емес).
      var blocked = false;
      var blockReason = '';
      var blockSource = '';
      DateTime? subUntil;
      if (!userDoc.isSuperadmin) {
        final bs = await authService.fetchBlockStatus();
        blocked = bs.blocked;
        blockReason = bs.reason;
        blockSource = bs.source;
        // Жазылым мерзімі (admin → өзі, seller → иесі): біткенде ескерту,
        // 3 күннен кейін «заморозка» (тек оқу).
        if (!blocked) subUntil = await authService.fetchSubscriptionUntil();
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
        subscriptionUntil: subUntil,
        city: userDoc.city,
        courierStatus: userDoc.courierStatus,
      );
      if (!blocked) await wCtx.load();
      // Push токенін тіркейміз (рұқсат диалогы логинді бөгемеуі үшін await жоқ).
      if (!blocked) {
        PushService.instance.registerForUser(role: userDoc.role);
      }
      return const _SessResult(_SessState.loaded);
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
      PushService.instance.registerForUser(role: 'client');
      return const _SessResult(_SessState.loaded);
    }

    // Екі сұрау да сәтті өтіп, екеуі де бос — профилі жоқ орфан сессия.
    return const _SessResult(_SessState.orphan);
  } catch (e) {
    debugPrint('_loadSession failed: $e');
    return _SessResult(_SessState.error, e);
  }
}

/// Профильді жүктеу сәтсіз (көбіне интернет жоқ) — шығармай, қайталау ұсынамыз.
class _SessionErrorScreen extends StatelessWidget {
  final Object? error;
  final Future<void> Function() onRetry;
  const _SessionErrorScreen({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: cBg,
        body: SafeArea(
          child: Column(
            children: [
              Expanded(child: AppErrorView(error: error, onRetry: onRetry)),
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: TextButton(
                  onPressed: () => AuthService().signOut(),
                  child: Text(
                    tr('Выйти из аккаунта', 'Аккаунттан шығу'),
                    style: const TextStyle(color: cInk3),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
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
