import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Centralized desktop theme so feature screens stay visually consistent.
class AppTheme {
  static ThemeData light() {
    return _build(Brightness.light);
  }

  static ThemeData dark() {
    return _build(Brightness.dark);
  }

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final textColor = dark ? const Color(0xFFE8ECEF) : AppColors.text;
    final mutedColor = dark ? const Color(0xFF9AA6AD) : AppColors.muted;
    return ThemeData(
      useMaterial3: true,
      fontFamily: 'Microsoft YaHei',
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: brightness,
      ),
      scaffoldBackgroundColor: dark
          ? const Color(0xFF101416)
          : AppColors.background,
      cardColor: dark ? const Color(0xFF171D20) : Colors.white,
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      textTheme: TextTheme(
        displaySmall: TextStyle(
          fontSize: 36,
          fontWeight: FontWeight.w800,
          color: textColor,
        ),
        displayMedium: const TextStyle(
          fontSize: 48,
          fontWeight: FontWeight.w800,
          color: AppColors.primary,
        ),
        headlineSmall: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: textColor,
        ),
        titleMedium: TextStyle(fontSize: 17, color: mutedColor),
      ),
    );
  }
}
