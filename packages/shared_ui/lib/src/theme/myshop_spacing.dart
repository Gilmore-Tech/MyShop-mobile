import 'package:flutter/material.dart';

abstract final class MyShopSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;

  // Common paddings
  static const screenHorizontal = EdgeInsets.symmetric(horizontal: xl);
  static const screenAll = EdgeInsets.all(md);
  static const cardContent = EdgeInsets.all(md);
  static const sectionGap = SizedBox(height: lg);
  static const itemGap = SizedBox(height: sm);
  static const tightGap = SizedBox(height: xs);
}
