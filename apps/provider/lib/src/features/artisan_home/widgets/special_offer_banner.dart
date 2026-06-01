import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

/// Promo banner — black background with gold "SPECIAL OFFER" tag,
/// title, code, and a decorative red sale graphic on the right.
class SpecialOfferBanner extends StatelessWidget {
  const SpecialOfferBanner({
    super.key,
    required this.title,
    required this.code,
    this.onTap,
  });

  final String title;
  final String code;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: MyShopSpacing.md),
      child: GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            height: 130,
            decoration: const BoxDecoration(color: Color(0xFF161A1D)),
            child: Stack(
              children: [
                // Decorative SALE / 50% text on the right
                Positioned(
                  right: -10,
                  top: 0,
                  bottom: 0,
                  width: 220,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Text(
                        'SALE',
                        style: TextStyle(
                          fontFamily: 'Raleway',
                          fontWeight: FontWeight.w900,
                          fontSize: 60,
                          color: MyShopColors.error.withValues(alpha: 0.55),
                          letterSpacing: 2,
                        ),
                      ),
                      Positioned(
                        bottom: 14,
                        right: 18,
                        child: Text(
                          '50%',
                          style: TextStyle(
                            fontFamily: 'Raleway',
                            fontWeight: FontWeight.w900,
                            fontSize: 28,
                            color: MyShopColors.error.withValues(alpha: 0.85),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Foreground content
                Padding(
                  padding: const EdgeInsets.all(MyShopSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: MyShopColors.primaryGold,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'SPECIAL OFFER',
                          style: MyShopTypography.overline.copyWith(
                            color: MyShopColors.textPrimary,
                            fontWeight: FontWeight.w900,
                            fontSize: 10,
                          ),
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            style: MyShopTypography.h3.copyWith(
                              color: MyShopColors.textOnPrimary,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 4),
                          RichText(
                            text: TextSpan(
                              style: MyShopTypography.body2.copyWith(
                                color: MyShopColors.textOnPrimary,
                              ),
                              children: [
                                const TextSpan(text: 'Use code: '),
                                TextSpan(
                                  text: code,
                                  style: TextStyle(
                                    color: MyShopColors.primaryGold,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
