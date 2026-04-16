import 'package:flutter/material.dart';

import '../theme/myshop_colors.dart';
import '../theme/myshop_radius.dart';

/// Full-width primary CTA button — the MyShop brand button.
///
/// Color and corner radius are pulled from `MyShopColors.buttonPrimary`
/// (#46535D) and `MyShopRadius.button` (10). Change those two tokens once
/// and every primary button in the app updates. Height is a fixed 52dp.
///
/// Pass [icon] for a leading icon, [trailingIcon] for a trailing one
/// (e.g. `Icons.chevron_right_rounded` on a "Confirm" CTA).
class MyShopPrimaryButton extends StatelessWidget {
  const MyShopPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.icon,
    this.trailingIcon,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;

  /// Optional leading icon.
  final IconData? icon;

  /// Optional trailing icon (e.g. a chevron on a Confirm CTA).
  final IconData? trailingIcon;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !isLoading;
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: enabled ? onPressed : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: MyShopColors.buttonPrimary,
          disabledBackgroundColor: MyShopColors.disabled,
          foregroundColor: MyShopColors.textOnPrimary,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(MyShopRadius.button),
          ),
        ),
        child: isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor:
                      AlwaysStoppedAnimation<Color>(MyShopColors.textOnPrimary),
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 18),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (trailingIcon != null) ...[
                    const SizedBox(width: 6),
                    Icon(trailingIcon, size: 20),
                  ],
                ],
              ),
      ),
    );
  }
}
