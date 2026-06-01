import 'package:flutter/material.dart';
import 'myshop_colors.dart';
import 'myshop_radius.dart';
import 'myshop_typography.dart';

abstract final class MyShopTheme {
  static ThemeData get light => ThemeData(
        useMaterial3: true,
        fontFamily: 'Raleway',
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(
          seedColor: MyShopColors.primaryGold,
          primary: MyShopColors.primaryGold,
          onPrimary: MyShopColors.textOnPrimary,
          surface: MyShopColors.surfaceWhite,
          onSurface: MyShopColors.textPrimary,
          error: MyShopColors.error,
          onError: MyShopColors.textOnPrimary,
        ),
        scaffoldBackgroundColor: MyShopColors.surfaceWhite,
        appBarTheme: const AppBarTheme(
          backgroundColor: MyShopColors.surfaceWhite,
          foregroundColor: MyShopColors.textPrimary,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: MyShopTypography.h3,
        ),
        // Global primary button style — pulls from MyShopColors.buttonPrimary
        // and MyShopRadius.button, so both can be updated in one place.
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: MyShopColors.buttonPrimary,
            foregroundColor: MyShopColors.textOnPrimary,
            minimumSize: const Size(double.infinity, 52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(MyShopRadius.button),
            ),
            textStyle: MyShopTypography.button,
            elevation: 0,
          ),
        ),
        cardTheme: CardThemeData(
          color: MyShopColors.surfaceWhite,
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: MyShopColors.surfaceWhite,
          selectedItemColor: MyShopColors.primaryGold,
          unselectedItemColor: MyShopColors.darkSlate,
          selectedLabelStyle: MyShopTypography.navLabel,
          unselectedLabelStyle: MyShopTypography.navLabelInactive,
          type: BottomNavigationBarType.fixed,
          elevation: 8,
        ),
        dividerTheme: const DividerThemeData(
          color: MyShopColors.divider,
          thickness: 1,
          space: 1,
        ),
      );

  // ── Dark theme ──────────────────────────────────────────────────────────────
  // Keeps the gold accent identical (brand stays consistent) and flips
  // surface/text. Screens that read colors via `Theme.of(context).colorScheme.*`
  // will track this automatically; screens that hardcode `MyShopColors.surfaceWhite`
  // etc. will continue to render light until they migrate.
  static const _darkSurface = Color(0xFF121417);
  static const _darkSurfaceElevated = Color(0xFF1B1F24);
  static const _darkOnSurface = Color(0xFFE8EAED);
  static const _darkOnSurfaceMuted = Color(0xFFA0A6AD);
  static const _darkDivider = Color(0xFF2A2F35);

  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        fontFamily: 'Raleway',
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: MyShopColors.primaryGold,
          brightness: Brightness.dark,
          primary: MyShopColors.primaryGold,
          onPrimary: MyShopColors.textPrimary,
          surface: _darkSurface,
          onSurface: _darkOnSurface,
          error: MyShopColors.error,
          onError: MyShopColors.textOnPrimary,
        ),
        scaffoldBackgroundColor: _darkSurface,
        appBarTheme: const AppBarTheme(
          backgroundColor: _darkSurface,
          foregroundColor: _darkOnSurface,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: MyShopTypography.h3,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: MyShopColors.primaryGold,
            foregroundColor: MyShopColors.textPrimary,
            minimumSize: const Size(double.infinity, 52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(MyShopRadius.button),
            ),
            textStyle: MyShopTypography.button,
            elevation: 0,
          ),
        ),
        cardTheme: CardThemeData(
          color: _darkSurfaceElevated,
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: _darkSurfaceElevated,
          selectedItemColor: MyShopColors.primaryGold,
          unselectedItemColor: _darkOnSurfaceMuted,
          selectedLabelStyle: MyShopTypography.navLabel,
          unselectedLabelStyle: MyShopTypography.navLabelInactive,
          type: BottomNavigationBarType.fixed,
          elevation: 8,
        ),
        dividerTheme: const DividerThemeData(
          color: _darkDivider,
          thickness: 1,
          space: 1,
        ),
      );
}
