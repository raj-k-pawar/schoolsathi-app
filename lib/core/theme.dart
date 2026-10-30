import 'package:flutter/material.dart';

import 'config.dart';

/// Colours of one app. Each app has its own accent so staff never confuse them.
class Brand {
  const Brand(this.primary, this.secondary, this.dark);

  final Color primary;
  final Color secondary;
  final Color dark;

  static Brand get current => switch (AppConfig.kind) {
        AppKind.parent => const Brand(Color(0xFF2F5BFF), Color(0xFF7A4DFF), Color(0xFF0B1530)),
        AppKind.teacher => const Brand(Color(0xFF0E9F8E), Color(0xFF1F6FEB), Color(0xFF072B2E)),
        AppKind.driver => const Brand(Color(0xFFFF8A3D), Color(0xFFFF5C7A), Color(0xFF2B1608)),
        AppKind.gate => const Brand(Color(0xFF12B886), Color(0xFF2F5BFF), Color(0xFF07231B)),
      };

  LinearGradient get gradient => LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [primary, secondary]);

  LinearGradient get darkGradient => LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [dark, Color.lerp(dark, primary, 0.55)!]);
}

class AppColors {
  static const ink = Color(0xFF0B1530);
  static const soft = Color(0xFF5B6680);
  static const line = Color(0xFFE6EAF3);
  static const bg = Color(0xFFF4F6FB);
  static const green = Color(0xFF12B886);
  static const red = Color(0xFFE5484D);
  static const amber = Color(0xFFF5A524);
  static const blue = Color(0xFF2F5BFF);
}

ThemeData buildTheme() {
  final brand = Brand.current;
  final scheme = ColorScheme.fromSeed(seedColor: brand.primary, primary: brand.primary, secondary: brand.secondary, surface: Colors.white);

  final base = ThemeData(useMaterial3: true, colorScheme: scheme, fontFamily: 'Jakarta', scaffoldBackgroundColor: AppColors.bg);

  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: AppColors.ink, displayColor: AppColors.ink),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.bg,
      foregroundColor: AppColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      centerTitle: false,
      titleTextStyle: TextStyle(fontFamily: 'Jakarta', fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.ink),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: AppColors.line)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontFamily: 'Jakarta', fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        side: const BorderSide(color: AppColors.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontFamily: 'Jakarta', fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.line)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.line)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: brand.primary, width: 2)),
      labelStyle: const TextStyle(color: AppColors.soft),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      elevation: 8,
      height: 68,
      indicatorColor: brand.primary.withValues(alpha: 0.14),
      labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
            fontFamily: 'Jakarta',
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected) ? FontWeight.w800 : FontWeight.w600,
            color: states.contains(WidgetState.selected) ? brand.primary : AppColors.soft,
          )),
      iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(color: states.contains(WidgetState.selected) ? brand.primary : AppColors.soft)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.ink,
      contentTextStyle: const TextStyle(fontFamily: 'Jakarta', color: Colors.white, fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.line, space: 1),
    chipTheme: base.chipTheme.copyWith(side: const BorderSide(color: AppColors.line), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999))),
  );
}
