import 'package:flutter/material.dart';
import 'myshop_colors.dart';
import 'myshop_radius.dart';
import 'myshop_typography.dart';

abstract final class MyShopTheme {
  static ThemeData get light => ThemeData(
        useMaterial3: true,
        fontFamily: 'Raleway',
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
}
