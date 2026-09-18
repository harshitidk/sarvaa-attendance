import 'package:flutter/material.dart';

/// Palette mirrored from the Expo app's theme.
class AppColors {
  const AppColors._();

  static const Color background = Color(0xFFF8FAFC);
  static const Color card = Color(0xFFFFFFFF);
  static const Color foreground = Color(0xFF0F172A);
  static const Color muted = Color(0xFF64748B);
  static const Color border = Color(0xFFE2E8F0);
  static const Color primary = Color(0xFF2563EB);
  static const Color primaryForeground = Color(0xFFFFFFFF);
  static const Color positive = Color(0xFF059669);
  static const Color positiveSoft = Color(0xFFD1FAE5);
  static const Color info = Color(0xFF2563EB);
  static const Color infoSoft = Color(0xFFDBEAFE);
  static const Color warning = Color(0xFFD97706);
  static const Color warningSoft = Color(0xFFFEF3C7);
  static const Color danger = Color(0xFFDC2626);
  static const Color neutral = Color(0xFF475569);
  static const Color neutralSoft = Color(0xFFF1F5F9);
}

class StatusTone {
  const StatusTone(this.background, this.foreground);

  final Color background;
  final Color foreground;
}

const Map<String, StatusTone> statusTones = {
  'PRESENT': StatusTone(AppColors.positiveSoft, AppColors.positive),
  'CHECKED_OUT': StatusTone(AppColors.positiveSoft, AppColors.positive),
  'WFH': StatusTone(AppColors.infoSoft, AppColors.info),
  'HOLIDAY': StatusTone(AppColors.neutralSoft, AppColors.neutral),
  'LEAVE': StatusTone(AppColors.neutralSoft, AppColors.neutral),
  'ABSENT': StatusTone(AppColors.warningSoft, AppColors.warning),
  'MANUAL_OVERRIDE': StatusTone(AppColors.infoSoft, AppColors.info),
};

StatusTone toneFor(String? status) =>
    statusTones[status] ?? const StatusTone(AppColors.neutralSoft, AppColors.neutral);

ThemeData buildAppTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary),
    scaffoldBackgroundColor: AppColors.background,
  );

  return base.copyWith(
    cardTheme: const CardThemeData(
      color: AppColors.card,
      elevation: 0,
      margin: EdgeInsets.zero,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.card,
      foregroundColor: AppColors.foreground,
      elevation: 0,
      centerTitle: false,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.background,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.border),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.primaryForeground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        foregroundColor: AppColors.foreground,
        side: const BorderSide(color: AppColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
  );
}
