// CupertinoPageTransitionsBuilder кейбір Flutter SDK нұсқаларында (мыс. 3.44
// candidate) material.dart-тан осы файлға көшірілген; екеуін де импорттау SDK
// нұсқасына тәуелсіз derlenуін қамтамасыз етеді.
// ignore: unnecessary_import
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// НАЗАР: түстердің ЖАЛҒЫЗ көзі — theme/qoima_design.dart. Мұндағы мәндер
/// сол токендердің көшірмесі (бұл файл ескі экрандар үшін қалды, дизайн
/// жүйесіне тәуелділік енгізбеу үшін hex күйінде қайталанады). Бірін
/// өзгертсең — екіншісін де түзет.
class AppTheme {
  // ── Brand ────────────────────────────────────────────────────────────────────
  static const Color primary = Color(0xFF00A862);
  static const Color primaryDark = Color(0xFF00713F);
  static const Color primaryLight = Color(0xFF16D888);
  static const Color primarySoft = Color(0xFFE9FBF2);
  static const Color primaryHair = Color(0xFFD3F4E3);

  // ── Semantic ─────────────────────────────────────────────────────────────────
  static const Color success = Color(0xFF00A862);
  static const Color successDark = Color(0xFF00713F);
  static const Color successSoft = Color(0xFFE9FBF2);

  static const Color hot = Color(0xFFFF6B4A);
  static const Color hotDark = Color(0xFFD44021);
  static const Color hotSoft = Color(0xFFFFEDE7);

  static const Color warning = Color(0xFFFFA51F);
  static const Color warningSoft = Color(0xFFFFF4DE);
  static const Color warningInk = Color(0xFF8F6103);

  static const Color danger = Color(0xFFF23B4F);
  static const Color dangerSoft = Color(0xFFFFEBEE);

  // ── Surface ──────────────────────────────────────────────────────────────────
  static const Color background = Color(0xFFF4F7F6);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surface2 = Color(0xFFF3F7F5);
  static const Color border = Color(0xFFE9EFEC);
  static const Color borderDark = Color(0xFFDCE4E0);

  // ── Text ─────────────────────────────────────────────────────────────────────
  static const Color text = Color(0xFF0B1512);
  static const Color text2 = Color(0xFF1B2B25);
  static const Color textMuted = Color(0xFF4A5F57);
  static const Color textHint = Color(0xFF7C8F87);

  // ── Backward-compat aliases ──────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFF0B1512);
  static const Color textSecondary = Color(0xFF4A5F57);
  static const Color successLight = successSoft;
  static const Color dangerLight = Color(0xFFFFE0E4);
  static const Color warningLight = Color(0xFFFFF0D2);

  // ── Gradients ────────────────────────────────────────────────────────────────
  static const LinearGradient gradBrand = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF00693C), Color(0xFF00A862), Color(0xFF16CC80)],
  );
  static const LinearGradient gradSuccess = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF00713F), Color(0xFF00A862)],
  );
  static const LinearGradient gradHot = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFD44021), Color(0xFFFF6B4A)],
  );
  // backward-compat alias
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF00B96A), Color(0xFF00814B)],
  );

  // ── Shadows (premium multi-layer) ────────────────────────────────────────────
  static List<BoxShadow> get shadowSm => const [
        BoxShadow(
            color: Color(0x0A0B1512), blurRadius: 3, offset: Offset(0, 1)),
        BoxShadow(
            color: Color(0x0D0B1512), blurRadius: 12, offset: Offset(0, 4)),
      ];
  static List<BoxShadow> get shadowMd => const [
        BoxShadow(
            color: Color(0x0D0B1512), blurRadius: 4, offset: Offset(0, 2)),
        BoxShadow(
            color: Color(0x140B1512), blurRadius: 24, offset: Offset(0, 10)),
      ];
  static List<BoxShadow> get shadowLg => const [
        BoxShadow(
            color: Color(0x100B1512), blurRadius: 8, offset: Offset(0, 4)),
        BoxShadow(
            color: Color(0x1A0B1512), blurRadius: 40, offset: Offset(0, 20)),
      ];
  static List<BoxShadow> get shadowBrand => const [
        BoxShadow(
            color: Color(0x4700A862), blurRadius: 22, offset: Offset(0, 9)),
        BoxShadow(
            color: Color(0x140B1512), blurRadius: 3, offset: Offset(0, 1)),
      ];
  static List<BoxShadow> get shadowSuccess => const [
        BoxShadow(
            color: Color(0x4700A862), blurRadius: 22, offset: Offset(0, 9)),
        BoxShadow(
            color: Color(0x140B1512), blurRadius: 3, offset: Offset(0, 1)),
      ];
  static List<BoxShadow> get shadowHot => const [
        BoxShadow(
            color: Color(0x47FF6B4A), blurRadius: 22, offset: Offset(0, 9)),
        BoxShadow(
            color: Color(0x140B1512), blurRadius: 3, offset: Offset(0, 1)),
      ];
  // backward-compat aliases
  static List<BoxShadow> get shadowButton => shadowBrand;
  static List<BoxShadow> get shadowButtonSuccess => shadowSuccess;

  // backward-compat shadow aliases
  static List<BoxShadow> get cardShadow => shadowMd;
  static List<BoxShadow> get softShadow => shadowSm;
  static List<BoxShadow> get premiumShadow => shadowLg;

  // ── Radius ───────────────────────────────────────────────────────────────────
  static const double radius = 16.0;
  static const double radiusLg = 20.0;
  static const double radiusXl = 24.0;
  // backward-compat radius names
  static const double r8 = 8.0;
  static const double r12 = 12.0;
  static const double r16 = 16.0;
  static const double r20 = 20.0;
  static const double r24 = 24.0;

  // ── ThemeData ─────────────────────────────────────────────────────────────────
  static ThemeData get theme => ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: background,
        fontFamily: 'Roboto',
        // Material 3-тің Android әдепкі ZoomPageTransitionsBuilder-і жаңа
        // экранды ҚАРА фон үстінде «үлкейтіп» шығарады — push тапталғанда
        // (lib/core/push_navigation.dart) қара экран жарқ етіп көрінетін.
        // Cupertino стилі — жай ғана бүйірден жылжу, қара фон жоқ.
        pageTransitionsTheme: const PageTransitionsTheme(builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
        }),
        colorScheme: ColorScheme.fromSeed(
          seedColor: primary,
          brightness: Brightness.light,
          surface: surface,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: primary,
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
        cardTheme: CardThemeData(
          color: surface,
          elevation: 0,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radius)),
          margin: EdgeInsets.zero,
        ),
        // Типографиялық баспалдақ: тақырып неғұрлым ірі болса, әріп аралығы
        // тығызырақ әрі жол биіктігі жинақы; кіші мәтінде — керісінше,
        // жолдар арасы ауқымды (оқуға жеңіл).
        textTheme: const TextTheme(
          displayLarge: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w800,
              color: textPrimary,
              letterSpacing: -1.0,
              height: 1.14),
          headlineLarge: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: textPrimary,
              letterSpacing: -0.7,
              height: 1.18),
          headlineMedium: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: textPrimary,
              letterSpacing: -0.5,
              height: 1.2),
          titleLarge: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: textPrimary,
              letterSpacing: -0.4,
              height: 1.24),
          titleMedium: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: textPrimary,
              letterSpacing: -0.15,
              height: 1.28),
          bodyLarge: TextStyle(fontSize: 15, color: textPrimary, height: 1.4),
          bodyMedium:
              TextStyle(fontSize: 13, color: textSecondary, height: 1.42),
          labelLarge: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: textPrimary,
              height: 1.3),
          labelSmall: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: textHint,
              letterSpacing: 0.4,
              height: 1.3),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primary,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(radius)),
            textStyle:
                const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: surface,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(r12),
              borderSide: const BorderSide(color: border)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(r12),
              borderSide: const BorderSide(color: border)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(r12),
              borderSide: const BorderSide(color: primary, width: 1.5)),
          errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(r12),
              borderSide: const BorderSide(color: danger)),
          labelStyle: const TextStyle(color: textSecondary, fontSize: 14),
          prefixIconColor: primary,
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: surface,
          selectedItemColor: primary,
          unselectedItemColor: textHint,
          type: BottomNavigationBarType.fixed,
          elevation: 0,
        ),
        chipTheme: ChipThemeData(
          backgroundColor: surface,
          selectedColor: primarySoft,
          checkmarkColor: primaryDark,
          labelStyle: const TextStyle(
              fontSize: 13, fontWeight: FontWeight.w600, color: textMuted),
          secondaryLabelStyle: const TextStyle(
              fontSize: 13, fontWeight: FontWeight.w700, color: primaryDark),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          // Толық дөңгелек чип — сүзгі жолағы жеңіл әрі заманауи көрінеді.
          shape: const StadiumBorder(side: BorderSide(color: border)),
          side: BorderSide.none,
        ),
        dividerTheme: const DividerThemeData(
          color: border,
          thickness: 1,
          space: 0,
        ),
      );
}

// ── top-level backward-compat getters ────────────────────────────────────────
List<BoxShadow> get cardShadow => AppTheme.cardShadow;
List<BoxShadow> get softShadow => AppTheme.softShadow;
