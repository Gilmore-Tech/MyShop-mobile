import 'package:flutter/material.dart';
import 'myshop_colors.dart';

abstract final class MyShopTypography {
  static const _baseFamily = 'Raleway';

  // -- Display --
  static const display = TextStyle(
    fontFamily: _baseFamily,
    fontSize: 28,
    fontWeight: FontWeight.w700,
    color: MyShopColors.textPrimary,
    height: 1.3,
  );

  // -- Headings --
  static const h1 = TextStyle(
    fontFamily: _baseFamily,
    fontSize: 24,
    fontWeight: FontWeight.w700,
    color: MyShopColors.textPrimary,
    height: 1.3,
  );

  static const h2 = TextStyle(
    fontFamily: _baseFamily,
    fontSize: 20,
    fontWeight: FontWeight.w600,
    color: MyShopColors.textPrimary,
    height: 1.35,
  );

  static const h3 = TextStyle(
    fontFamily: _baseFamily,
    fontSize: 18,
    fontWeight: FontWeight.w700,
    color: MyShopColors.textPrimary,
    height: 1.28,
  );

  // -- Body --
  static const body1 = TextStyle(
    fontFamily: _baseFamily,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: MyShopColors.textPrimary,
    height: 1.43,
  );

  static const body2 = TextStyle(
    fontFamily: _baseFamily,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: MyShopColors.textSecondary,
    height: 1.42,
  );

  // -- Supporting --
  static const caption = TextStyle(
    fontFamily: _baseFamily,
    fontSize: 10,
    fontWeight: FontWeight.w400,
    color: MyShopColors.textSecondary,
    height: 1.6,
  );

  static const button = TextStyle(
    fontFamily: _baseFamily,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: MyShopColors.textOnPrimary,
    height: 1.57,
  );

  static const overline = TextStyle(
    fontFamily: _baseFamily,
    fontSize: 10,
    fontWeight: FontWeight.w900,
    color: MyShopColors.textSecondary,
    letterSpacing: 1.4,
    height: 1.4,
  );

  // -- Navigation --
  static const navLabel = TextStyle(
    fontFamily: _baseFamily,
    fontSize: 10,
    fontWeight: FontWeight.w700,
    color: MyShopColors.primaryGold,
    height: 1.6,
  );

  static const navLabelInactive = TextStyle(
    fontFamily: _baseFamily,
    fontSize: 10,
    fontWeight: FontWeight.w400,
    color: MyShopColors.darkSlate,
    height: 1.6,
  );

  // -- Special --
  static const price = TextStyle(
    fontFamily: _baseFamily,
    fontSize: 24,
    fontWeight: FontWeight.w700,
    color: MyShopColors.textPrimary,
    height: 1.2,
  );

  static const priceSmall = TextStyle(
    fontFamily: _baseFamily,
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: MyShopColors.textPrimary,
    height: 1.2,
  );
}
