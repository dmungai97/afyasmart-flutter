import 'package:flutter/material.dart';

/// "Clinical stationery": a warm paper background, deep ink text, one muted
/// accent used sparingly. No glow, no gradients, no glass, no drop shadows —
/// structure comes from thin rule lines, not cards.
///
/// Ported from src/onboarding/theme.ts and admin/theme.ts, which were the
/// source of truth in the React Native app. The RN screens inlined these as
/// local hex constants in StyleSheet.create calls; here they are a real
/// ThemeData, so a screen that forgets to reach for a token still lands in
/// the same palette instead of Material's purple defaults.
abstract final class AppColors {
  static const paper = Color(0xFFEEF1EA);
  static const ink = Color(0xFF16302B);
  static const inkMuted = Color(0xFF4B5C50);
  static const inkFaint = Color(0xFF6B7A70);
  static const accent = Color(0xFFC9A227);
  static const rule = Color(0xFFC7CFC2);
  static const ruleStrong = Color(0xFF6B8F82);

  /// Semantic colors for meaning that can't be conveyed by ink alone
  /// (urgency, status) — desaturated to stay in the same restrained family
  /// rather than reaching for saturated red/green/yellow.
  static const success = Color(0xFF3F7A5C);
  static const warning = accent;
  static const danger = Color(0xFF9C3B2E);

  /// Card/panel surface — a near-white, warm-tinted white rather than pure
  /// white, so bordered "cards" still read as paper rather than glossy
  /// chrome. The one deliberate departure from the cardless onboarding
  /// palette, for the data-dense admin console.
  static const surface = Color(0xFFFBFCF9);

  /// Muted status tints for badges and pills, instead of the saturated
  /// pastel fills a generic dashboard would reach for.
  static const tintSuccessBg = Color(0xFFE4EAE0);
  static const tintSuccessBorder = Color(0xFFB9C9BC);
  static const tintWarningBg = Color(0xFFF4EBD3);
  static const tintWarningBorder = Color(0xFFDDC98A);
  static const tintDangerBg = Color(0xFFF1E3DE);
  static const tintDangerBorder = Color(0xFFD9B3A8);
  static const tintNeutralBorder = Color(0xFFB9C9BC);

  /// The brand teal, used for the tab bar and primary actions on the
  /// patient-facing screens (it is also the Android adaptive icon
  /// background, so it cannot drift).
  static const brand = Color(0xFF0B6E6E);
}

/// The patient-facing app runs a warmer, more colourful palette than the
/// "clinical stationery" system above — soft tinted cards, a teal hero, a
/// near-white canvas. The two are deliberately distinct: onboarding and the
/// admin console read as one restrained product, the daily-use app reads as
/// friendlier. Keeping them in separate classes stops one bleeding into the
/// other by accident.
abstract final class AppPalette {
  static const teal = Color(0xFF005454);
  static const tealHero = Color(0xFF006A6A);
  static const canvas = Color(0xFFF7FAF9);
  static const hairline = Color(0xFFEDF0F2);

  static const textStrong = Color(0xFF1A1A1A);
  static const textBody = Color(0xFF3E4948);
  static const textMuted = Color(0xFF6E7979);

  static const purple = Color(0xFF712AE2);
  static const orange = Color(0xFFD47A00);
  static const red = Color(0xFFC62828);
  static const green = Color(0xFF0B845C);
  static const alert = Color(0xFFBA1A1A);

  /// Tinted card backgrounds paired with the accent colours above.
  static const purpleBg = Color(0xFFF3EEFF);
  static const greenBg = Color(0xFFD1F7E2);
  static const orangeBg = Color(0xFFFFEEDD);
  static const redBg = Color(0xFFFFE5E5);

  static const premiumBg = Color(0xFFEADDFF);
  static const premiumFg = Color(0xFF5A00C6);
}

/// Spacing scale. The RN screens used raw numbers; collecting them means a
/// gutter change is one edit rather than ninety.
abstract final class Insets {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
}

abstract final class Radii {
  static const sm = 6.0;
  static const md = 10.0;
  static const lg = 16.0;
  static const pill = 999.0;
}

ThemeData buildAppTheme() {
  const scheme = ColorScheme.light(
    primary: AppColors.brand,
    onPrimary: Colors.white,
    secondary: AppColors.accent,
    onSecondary: AppColors.ink,
    surface: AppColors.surface,
    onSurface: AppColors.ink,
    error: AppColors.danger,
    onError: Colors.white,
    outline: AppColors.rule,
  );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.paper,
  );

  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: AppColors.ink,
      displayColor: AppColors.ink,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.paper,
      foregroundColor: AppColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    // Structure comes from rule lines, so cards are bordered rather than
    // elevated. Setting this here keeps any stray Card() on-palette.
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.md),
        side: const BorderSide(color: AppColors.rule),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.rule,
      thickness: 1,
      space: 1,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: Insets.md,
        vertical: 14,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.md),
        borderSide: const BorderSide(color: AppColors.rule),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.md),
        borderSide: const BorderSide(color: AppColors.rule),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.md),
        borderSide: const BorderSide(color: AppColors.ruleStrong, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.md),
        borderSide: const BorderSide(color: AppColors.danger),
      ),
      hintStyle: const TextStyle(color: AppColors.inkFaint),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.ink,
        foregroundColor: AppColors.paper,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.md),
        ),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.ink,
        minimumSize: const Size.fromHeight(52),
        side: const BorderSide(color: AppColors.rule),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.md),
        ),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: AppColors.ruleStrong),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: AppColors.ink,
      contentTextStyle: TextStyle(color: AppColors.paper),
      behavior: SnackBarBehavior.floating,
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: AppColors.surface,
      selectedItemColor: AppColors.brand,
      unselectedItemColor: AppColors.inkFaint,
      type: BottomNavigationBarType.fixed,
      elevation: 0,
    ),
  );
}
