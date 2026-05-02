import 'package:flutter/material.dart';

abstract final class AppColors {
  static const Color navy = Color(0xFF1A233B);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFF8E99A8);
  static const Color textMuted = Color(0xFFB0B8C4);
  static const Color textOnNavy = Color(0xFFFFFFFF);
  static const Color textPrimary = Color(0xFF1A233B);
}

abstract final class AppTheme {
  static ThemeData get material => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: AppColors.navy,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.navy,
          brightness: Brightness.light,
          surface: AppColors.surface,
          onSurface: AppColors.textPrimary,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: AppColors.textOnNavy,
          centerTitle: true,
        ),
        sliderTheme: SliderThemeData(
          activeTrackColor: AppColors.navy.withOpacity(0.85),
          inactiveTrackColor: AppColors.textMuted.withOpacity(0.35),
          thumbColor: AppColors.navy,
          overlayColor: AppColors.navy.withOpacity(0.12),
          trackHeight: 3,
        ),
        textTheme: const TextTheme(
          titleLarge: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 22,
            color: AppColors.textPrimary,
            letterSpacing: -0.5,
          ),
          titleMedium: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 16,
            color: AppColors.textPrimary,
          ),
          bodyMedium: TextStyle(
            fontSize: 14,
            color: AppColors.textSecondary,
          ),
          bodySmall: TextStyle(
            fontSize: 12,
            color: AppColors.textMuted,
          ),
          labelSmall: TextStyle(
            fontSize: 11,
            color: AppColors.textMuted,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
}
