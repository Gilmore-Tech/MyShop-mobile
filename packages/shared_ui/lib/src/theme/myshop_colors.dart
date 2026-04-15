import 'package:flutter/material.dart';

abstract final class MyShopColors {
  // -- Primary (from Figma) --
  static const primaryGold = Color(0xFFF5A623);
  static const primaryGoldDark = Color(0xFFD48E1A);
  static const primaryGoldLight = Color(0xFFFFF8EC);
  static const darkSlate = Color(0xFF46535D);

  /// Global primary button background. Alias of [darkSlate]. Change this
  /// single value to restyle every primary button in the app — the theme
  /// and any button that respects the theme inherits from here.
  static const buttonPrimary = darkSlate;
  static const darkText = Color(0xFF161A1D);
  static const offWhite = Color(0xFFF6F7F8);

  // -- Semantic --
  static const success = Color(0xFF27AE60);
  static const successLight = Color(0xFFE8F8EF);
  static const warning = Color(0xFFF2994A);
  static const warningLight = Color(0xFFFEF3E8);
  static const error = Color(0xFFEB5757);
  static const errorLight = Color(0xFFFDE8E8);
  static const info = Color(0xFF2F80ED);
  static const infoLight = Color(0xFFE8F0FD);

  // -- Surface --
  static const surfaceWhite = Color(0xFFFFFFFF);
  static const surfaceGrey = Color(0xFFF3F5F6);
  static const divider = Color(0xFFE0E0E0);
  static const disabled = Color(0xFFBDBDBD);
  static const shimmerBase = Color(0xFFE0E0E0);
  static const shimmerHighlight = Color(0xFFF5F5F5);
  static const avatarPlaceholder = Color(0xFFE0E6FF);

  // -- Text --
  static const textPrimary = Color(0xFF161A1D);
  static const textSecondary = Color(0xFF555E68);
  static const textHint = Color(0xFFBDBDBD);
  static const textOnPrimary = Color(0xFFFFFFFF);
  static const textOnDarkSlate = Color(0xFFFFFFFF);

  // -- Status-specific (Provider) --
  static const online = Color(0xFF27AE60);
  static const offline = Color(0xFFBDBDBD);
  static const busy = Color(0xFFF2994A);
  static const surge = Color(0xFFEB5757);

  // -- Rating --
  static const ratingStar = Color(0xFFF5A623);
  static const ratingStarEmpty = Color(0xFFE0E0E0);
}
