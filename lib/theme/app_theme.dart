import 'package:flutter/material.dart';

class AppTheme {
  // ── Brand ────────────────────────────────────────────────────────────────────
  static const Color primary      = Color(0xFF1E3A8A);
  static const Color primaryDark  = Color(0xFF0F1F5C);
  static const Color primaryLight = Color(0xFF3B5FCC);
  static const Color primarySoft  = Color(0xFFEEF1FB);
  static const Color primaryHair  = Color(0xFFD5DDF3);

  // ── Semantic ─────────────────────────────────────────────────────────────────
  static const Color success      = Color(0xFF0F9D58);
  static const Color successDark  = Color(0xFF0A6E3E);
  static const Color successSoft  = Color(0xFFE5F4ED);

  static const Color hot          = Color(0xFFF26B5C);
  static const Color hotDark      = Color(0xFFC84A3D);
  static const Color hotSoft      = Color(0xFFFEEDEA);

  static const Color warning      = Color(0xFFD97706);
  static const Color warningSoft  = Color(0xFFFFF7E6);
  static const Color warningInk   = Color(0xFF92400E);

  static const Color danger       = Color(0xFFEF4444);
  static const Color dangerSoft   = Color(0xFFFEF2F2);

  // ── Surface ──────────────────────────────────────────────────────────────────
  static const Color background   = Color(0xFFF5F7FB);
  static const Color surface      = Color(0xFFFFFFFF);
  static const Color surface2     = Color(0xFFFAFBFD);
  static const Color border       = Color(0xFFE6EAF1);
  static const Color borderDark   = Color(0xFFD1D5DB);

  // ── Text ─────────────────────────────────────────────────────────────────────
  static const Color text         = Color(0xFF0F172A);
  static const Color text2        = Color(0xFF1E293B);
  static const Color textMuted    = Color(0xFF475569);
  static const Color textHint     = Color(0xFF94A3B8);

  // ── Backward-compat aliases ──────────────────────────────────────────────────
  static const Color textPrimary   = Color(0xFF1F2937);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color successLight  = successSoft;
  static const Color dangerLight   = Color(0xFFFEE2E2);
  static const Color warningLight  = Color(0xFFFEF3C7);

  // ── Gradients ────────────────────────────────────────────────────────────────
  static const LinearGradient gradBrand = LinearGradient(
    begin: Alignment.topLeft, end: Alignment.bottomRight,
    colors: [Color(0xFF0F1F5C), Color(0xFF1E3A8A), Color(0xFF2D4FB5)],
  );
  static const LinearGradient gradSuccess = LinearGradient(
    begin: Alignment.topLeft, end: Alignment.bottomRight,
    colors: [Color(0xFF0A6E3E), Color(0xFF0F9D58)],
  );
  static const LinearGradient gradHot = LinearGradient(
    begin: Alignment.topLeft, end: Alignment.bottomRight,
    colors: [Color(0xFFC84A3D), Color(0xFFF26B5C)],
  );
  // backward-compat alias
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft, end: Alignment.bottomRight,
    colors: [Color(0xFF2D4FB5), Color(0xFF1E3A8A)],
  );

  // ── Shadows (premium multi-layer) ────────────────────────────────────────────
  static List<BoxShadow> get shadowSm => const [
    BoxShadow(color: Color(0x0A0F172A), blurRadius: 2, offset: Offset(0, 1)),
    BoxShadow(color: Color(0x080F172A), blurRadius: 1),
  ];
  static List<BoxShadow> get shadowMd => const [
    BoxShadow(color: Color(0x0D0F172A), blurRadius: 3, offset: Offset(0, 1)),
    BoxShadow(color: Color(0x0D0F172A), blurRadius: 24, offset: Offset(0, 8)),
  ];
  static List<BoxShadow> get shadowLg => const [
    BoxShadow(color: Color(0x100F172A), blurRadius: 8, offset: Offset(0, 4)),
    BoxShadow(color: Color(0x140F172A), blurRadius: 48, offset: Offset(0, 24)),
  ];
  static List<BoxShadow> get shadowBrand => const [
    BoxShadow(color: Color(0x471E3A8A), blurRadius: 20, offset: Offset(0, 8)),
    BoxShadow(color: Color(0x0F000000), blurRadius: 2, offset: Offset(0, 1)),
  ];
  static List<BoxShadow> get shadowSuccess => const [
    BoxShadow(color: Color(0x470F9D58), blurRadius: 20, offset: Offset(0, 8)),
    BoxShadow(color: Color(0x0F000000), blurRadius: 2, offset: Offset(0, 1)),
  ];
  static List<BoxShadow> get shadowHot => const [
    BoxShadow(color: Color(0x47F26B5C), blurRadius: 20, offset: Offset(0, 8)),
    BoxShadow(color: Color(0x0F000000), blurRadius: 2, offset: Offset(0, 1)),
  ];
  // backward-compat aliases
  static List<BoxShadow> get shadowButton        => shadowBrand;
  static List<BoxShadow> get shadowButtonSuccess => shadowSuccess;

  // backward-compat shadow aliases
  static List<BoxShadow> get cardShadow    => shadowMd;
  static List<BoxShadow> get softShadow    => shadowSm;
  static List<BoxShadow> get premiumShadow => shadowLg;

  // ── Radius ───────────────────────────────────────────────────────────────────
  static const double radius   = 14.0;
  static const double radiusLg = 18.0;
  static const double radiusXl = 22.0;
  // backward-compat radius names
  static const double r8  = 8.0;
  static const double r12 = 12.0;
  static const double r16 = 16.0;
  static const double r20 = 20.0;
  static const double r24 = 24.0;

  // ── ThemeData ─────────────────────────────────────────────────────────────────
  static ThemeData get theme => ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: background,
        fontFamily: 'Roboto',
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
            color: Colors.white, fontSize: 20,
            fontWeight: FontWeight.w700, letterSpacing: -0.3,
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
        textTheme: const TextTheme(
          displayLarge:  TextStyle(fontSize: 32, fontWeight: FontWeight.w800,
              color: textPrimary, letterSpacing: -0.5),
          headlineLarge: TextStyle(fontSize: 24, fontWeight: FontWeight.w700,
              color: textPrimary, letterSpacing: -0.3),
          headlineMedium:TextStyle(fontSize: 20, fontWeight: FontWeight.w600,
              color: textPrimary, letterSpacing: -0.2),
          titleLarge:    TextStyle(fontSize: 17, fontWeight: FontWeight.w600,
              color: textPrimary),
          titleMedium:   TextStyle(fontSize: 15, fontWeight: FontWeight.w500,
              color: textPrimary),
          bodyLarge:     TextStyle(fontSize: 15, color: textPrimary),
          bodyMedium:    TextStyle(fontSize: 13, color: textSecondary),
          labelLarge:    TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
              color: textPrimary),
          labelSmall:    TextStyle(fontSize: 11, fontWeight: FontWeight.w500,
              color: textHint, letterSpacing: 0.3),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primary,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(radius)),
            textStyle: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.w600),
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
          backgroundColor: background,
          selectedColor: primary.withValues(alpha: 0.12),
          labelStyle: const TextStyle(
              fontSize: 13, fontWeight: FontWeight.w500),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(r8)),
          side: BorderSide.none,
        ),
        dividerTheme: const DividerThemeData(
          color: border, thickness: 1, space: 0,
        ),
      );
}

// ── top-level backward-compat getters ────────────────────────────────────────
List<BoxShadow> get cardShadow => AppTheme.cardShadow;
List<BoxShadow> get softShadow => AppTheme.softShadow;
