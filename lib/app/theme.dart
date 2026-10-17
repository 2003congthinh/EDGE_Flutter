import 'package:flutter/material.dart';

/// Dark "control room" palette. State colours always come with a shape too:
/// amber ring = scanning, solid cyan brackets = recognized, red dashes = unknown.
abstract final class AppColors {
  static const bg = Color(0xFF0A0E13);
  static const surface = Color(0xFF111821);
  static const surfaceHigh = Color(0xFF18212D);
  static const outline = Color(0xFF273343);
  static const text = Color(0xFFE6EDF3);
  static const muted = Color(0xFF8B98A9);
  static const cyan = Color(0xFF2DD4E6);
  static const amber = Color(0xFFF5B841);
  static const red = Color(0xFFF0524D);
}

/// System monospace; no font is downloaded at runtime.
const monoFont = 'monospace';

ThemeData buildTheme() {
  const scheme = ColorScheme.dark(
    primary: AppColors.cyan,
    onPrimary: Color(0xFF00242A),
    secondary: AppColors.amber,
    onSecondary: Color(0xFF2A1D00),
    error: AppColors.red,
    onError: Colors.white,
    surface: AppColors.surface,
    onSurface: AppColors.text,
    onSurfaceVariant: AppColors.muted,
    surfaceContainerHighest: AppColors.surfaceHigh,
    surfaceContainerHigh: AppColors.surfaceHigh,
    surfaceContainer: AppColors.surface,
    outline: AppColors.outline,
    outlineVariant: AppColors.outline,
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme);
  return base.copyWith(
    scaffoldBackgroundColor: AppColors.bg,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.bg,
      foregroundColor: AppColors.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    textTheme: base.textTheme.copyWith(
      headlineMedium: base.textTheme.headlineMedium
          ?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -.3),
      titleLarge: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.outline),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        side: const BorderSide(color: AppColors.outline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.outline),
      ),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.outline, space: 1),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
