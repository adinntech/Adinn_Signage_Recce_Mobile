import 'package:flutter/material.dart';

/// Adinn brand palette: white surfaces with a strong red accent.
class AdinnColors {
  AdinnColors._();

  static const Color red = Color(0xFFD71920);
  static const Color redDark = Color(0xFFA50F15);
  static const Color redLight = Color(0xFFFDECEC);
  static const Color ink = Color(0xFF1D1D1F);
  static const Color muted = Color(0xFF6B6F76);
  static const Color line = Color(0xFFE6E6EA);
  static const Color canvas = Color(0xFFF7F7F9);
  static const Color white = Colors.white;

  static const Color success = Color(0xFF1E8E3E);
  static const Color warning = Color(0xFFE37400);
  static const Color info = Color(0xFF1A73E8);
  static const Color purple = Color(0xFF7B1FA2);
}

class AppTheme {
  AppTheme._();

  static ThemeData light() {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: AdinnColors.red,
          brightness: Brightness.light,
        ).copyWith(
          primary: AdinnColors.red,
          onPrimary: Colors.white,
          primaryContainer: AdinnColors.redLight,
          onPrimaryContainer: AdinnColors.redDark,
          secondary: AdinnColors.ink,
          surface: Colors.white,
          onSurface: AdinnColors.ink,
          error: const Color(0xFFB3261E),
        );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AdinnColors.canvas,
      visualDensity: VisualDensity.standard,
    );

    return base.copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: AdinnColors.ink,
        surfaceTintColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: AdinnColors.ink,
          fontSize: 19,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AdinnColors.line),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AdinnColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AdinnColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AdinnColors.red, width: 1.6),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AdinnColors.red,
          foregroundColor: Colors.white,
          minimumSize: const Size(64, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AdinnColors.red,
          foregroundColor: Colors.white,
          minimumSize: const Size(64, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AdinnColors.red,
          minimumSize: const Size(64, 46),
          side: const BorderSide(color: AdinnColors.red),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        indicatorColor: AdinnColors.redLight,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? AdinnColors.red
                : AdinnColors.muted,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? AdinnColors.red
                : AdinnColors.muted,
          ),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        selectedColor: AdinnColors.redLight,
        side: const BorderSide(color: AdinnColors.line),
        labelStyle: const TextStyle(color: AdinnColors.ink),
      ),
      dividerTheme: const DividerThemeData(color: AdinnColors.line, space: 1),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
