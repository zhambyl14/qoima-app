import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'theme/app_theme.dart';
import 'ui/auth/client_login_screen.dart';
import 'ui/auth/seller_join_screen.dart';
import 'ui/main_shell.dart';
import 'ui/profile/store_onboarding_screen.dart';
import 'ui/client/client_shell.dart';
import 'ui/admin/admin_shell.dart';
import 'data/services/auth_service.dart';
import 'data/services/firestore_service.dart';
import 'data/models/store_model.dart';
import 'core/app_user.dart';
import 'core/warehouse_context.dart';
import 'core/locale_context.dart';
import 'l10n/app_localizations.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ru', null);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );
  if (kDebugMode) {
    await FirebaseAuth.instance
        .setSettings(appVerificationDisabledForTesting: true);
  }
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
        textTheme: GoogleFonts.interTextTheme(AppTheme.theme.textTheme),
      ),
      locale: locale,
      supportedLocales: const [Locale('ru')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const _Splash();
          }
          if (snapshot.hasData) {
            return FutureBuilder<bool>(
              future: _loadSession(snapshot.data!.uid, context),
              builder: (_, futureSnap) {
                if (futureSnap.connectionState == ConnectionState.waiting) {
                  return const _Splash();
                }
                if (futureSnap.data != true) return const ClientLoginScreen();
                final user = context.read<AppUser>();
                if (user.isClient) return const ClientShell();
                if (user.isAdmin) return const _AdminHomeRouter();
                if (user.joinStatus == 'active') return const MainShell();
                return const SellerJoinScreen();
              },
            );
          }
          context.read<AppUser>().clear();
          context.read<WarehouseContext>().clear();
          return const ClientLoginScreen();
        },
      ),
    );
  }
}

Future<bool> _loadSession(String uid, BuildContext context) async {
  final wCtx = context.read<WarehouseContext>();
  final appUser = context.read<AppUser>();
  try {
    final authService = AuthService();

    // Try admin/seller doc first
    final userDoc = await authService.getUserDoc(uid);
    if (userDoc != null) {
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
      );
      await wCtx.load();
      return true;
    }

    // Try client doc
    final clientDoc = await authService.getClientDoc(uid);
    if (clientDoc != null) {
      appUser.set(
        uid: clientDoc.uid,
        ownerUid: '',
        name: clientDoc.name,
        email: '',
        role: 'client',
        phone: clientDoc.phone,
      );
      return true;
    }

    return false;
  } catch (_) {
    return false;
  }
}

class _AdminHomeRouter extends StatefulWidget {
  const _AdminHomeRouter();
  @override
  State<_AdminHomeRouter> createState() => _AdminHomeRouterState();
}

class _AdminHomeRouterState extends State<_AdminHomeRouter> {
  bool _forceMain = false;

  @override
  Widget build(BuildContext context) {
    if (_forceMain) return const AdminShell();
    return StreamBuilder<StoreModel?>(
      stream: FirestoreService().watchStore(),
      builder: (_, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const _Splash();
        }
        if (snap.data != null) return const AdminShell();
        return StoreOnboardingScreen(
          onDone: () => setState(() => _forceMain = true),
        );
      },
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();
  @override
  Widget build(BuildContext context) => const Scaffold(
        backgroundColor: AppTheme.primary,
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
