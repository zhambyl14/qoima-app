import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'theme/app_theme.dart';
import 'ui/auth/login_screen.dart';
import 'ui/main_shell.dart';
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
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => WarehouseContext()),
        ChangeNotifierProvider(create: (_) => LocaleContext()),
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
      theme: AppTheme.theme,
      locale: locale,
      supportedLocales: const [Locale('kk'), Locale('ru')],
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
                if (futureSnap.data != true) return const LoginScreen();
                return const MainShell();
              },
            );
          }
          AppUser.clear();
          context.read<WarehouseContext>().clear();
          return const LoginScreen();
        },
      ),
    );
  }
}

Future<bool> _loadSession(String uid, BuildContext context) async {
  final wCtx = context.read<WarehouseContext>();
  try {
    final authService = AuthService();
    final userDoc = await authService.getUserDoc(uid);
    if (userDoc == null) return false;
    AppUser.set(
      uid:                 userDoc.uid,
      ownerUid:            userDoc.ownerId.isNotEmpty ? userDoc.ownerId : userDoc.uid,
      name:                userDoc.name,
      email:               userDoc.email,
      role:                userDoc.role,
      active:              userDoc.active,
      businessCode:        userDoc.businessCode,
      assignedWarehouseId: userDoc.assignedWarehouseId,
      joinStatus:          userDoc.joinStatus,
    );
    // Admin болса қоймаларды жүктейміз
    if (AppUser.isAdmin) {
      await wCtx.load();
    }
    return true;
  } catch (_) {
    return false;
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
                  color: Colors.white, fontSize: 36,
                  fontWeight: FontWeight.w800, letterSpacing: -1)),
          SizedBox(height: 24),
          SizedBox(
            width: 24, height: 24,
            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
          ),
        ],
      ),
    ),
  );
}
