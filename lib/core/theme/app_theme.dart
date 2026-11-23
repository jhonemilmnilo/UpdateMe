import 'package:flutter/material.dart';

/// Storm Cloud Green Design System Tokens
/// Moody, Mono, Ocean, Forest aesthetic.
class AppColors {
  AppColors._();

  /// #4E5A54 — Canvas, Scaffold background
  static const Color background = Color(0xFF4E5A54);

  /// #6E7A70 — Primary accent, active buttons, highlighted borders
  static const Color primaryAccent = Color(0xFF6E7A70);

  /// #2E3832 — Deep surface, cards, bottom bar, glass tint base
  static const Color secondarySurface = Color(0xFF2E3832);

  /// #8E9A8E — Supporting accent, body text, muted icons, timestamps
  static const Color supportingText = Color(0xFF8E9A8E);

  /// #E8ECE9 — High contrast headline / mint white text
  static const Color textHighContrast = Color(0xFFE8ECE9);

  /// Frosted glass tint with alpha
  static Color glassTint = const Color(0xFF2E3832).withValues(alpha: 0.55);

  /// Subtle glass border
  static Color glassBorder = const Color(0xFF8E9A8E).withValues(alpha: 0.20);
}

class AppTheme {
  AppTheme._();

  static ThemeData get stormCloudTheme {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: const ColorScheme(
        brightness: Brightness.dark,
        primary: AppColors.primaryAccent,
        onPrimary: AppColors.textHighContrast,
        secondary: AppColors.secondarySurface,
        onSecondary: AppColors.textHighContrast,
        surface: AppColors.secondarySurface,
        onSurface: AppColors.textHighContrast,
        error: Colors.redAccent,
        onError: Colors.white,
      ),
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          color: AppColors.textHighContrast,
          fontWeight: FontWeight.bold,
          letterSpacing: -0.5,
        ),
        titleMedium: TextStyle(
          color: AppColors.textHighContrast,
          fontWeight: FontWeight.w600,
        ),
        bodyMedium: TextStyle(
          color: AppColors.supportingText,
          fontSize: 14,
        ),
        bodySmall: TextStyle(
          color: AppColors.supportingText,
          fontSize: 12,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.secondarySurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: AppColors.glassBorder),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryAccent,
          foregroundColor: AppColors.textHighContrast,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        ),
      ),
    );
  }
}
