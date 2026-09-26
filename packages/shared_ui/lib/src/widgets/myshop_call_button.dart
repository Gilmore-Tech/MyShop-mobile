import 'package:flutter/material.dart';

import '../theme/myshop_colors.dart';
import '../theme/myshop_spacing.dart';
import '../theme/myshop_typography.dart';
import '../utils/phone_dialer.dart';

/// Compact circular call affordance for an in-app and/or phone call.
///
/// Mirrors the 44×44 rounded-square treatment used by the in-app chat buttons
/// so the two peer-contact actions sit side by side consistently. When both
/// [onInAppCall] and a dialable [phoneNumber] are available, the user chooses
/// the call type. If only in-app calling is available, tapping starts it
/// directly. The widget renders nothing only when neither path is available.
class MyShopCallButton extends StatelessWidget {
  const MyShopCallButton({
    super.key,
    required this.phoneNumber,
    this.onInAppCall,
    this.resolvePhoneNumber,
    this.size = 44,
    this.color = MyShopColors.success,
    this.semanticLabel = 'Call',
  });

  final String? phoneNumber;
  final VoidCallback? onInAppCall;

  /// Optional active-booking contact refresh. This is used when a lean list
  /// payload mounted the button before the private booking detail (and its
  /// dialable number) arrived. The call choice waits for that single refresh
  /// instead of silently jumping straight into an in-app call.
  final Future<String?> Function()? resolvePhoneNumber;
  final double size;
  final Color color;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final number = normalizeDialablePhoneNumber(phoneNumber);
    if (number.isEmpty && onInAppCall == null && resolvePhoneNumber == null) {
      return const SizedBox.shrink();
    }

    return Semantics(
      button: true,
      label: semanticLabel,
      child: GestureDetector(
        onTap: () => _handleTap(context, number),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(size * 0.27),
          ),
          child: Icon(
            Icons.call_rounded,
            size: size * 0.45,
            color: MyShopColors.textOnPrimary,
          ),
        ),
      ),
    );
  }

  Future<void> _handleTap(BuildContext context, String number) async {
    final inApp = onInAppCall;
    var resolvedNumber = number;
    if (resolvedNumber.isEmpty && resolvePhoneNumber != null) {
      resolvedNumber = normalizeDialablePhoneNumber(
        await resolvePhoneNumber!.call(),
      );
      if (!context.mounted) return;
    }
    // A screen that supplied a resolver expects a deliberate channel choice.
    // If its contact refresh is temporarily unavailable, keep the phone row
    // visible but disabled instead of unexpectedly launching an in-app call.
    final shouldOfferChoice = inApp != null &&
        (resolvedNumber.isNotEmpty || resolvePhoneNumber != null);
    if (!shouldOfferChoice && resolvedNumber.isEmpty) {
      inApp?.call();
      return;
    }
    if (inApp == null) {
      await dialPhoneNumber(context, resolvedNumber);
      return;
    }

    final choice = await showModalBottomSheet<_CallChoice>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Container(
            decoration: const BoxDecoration(
              color: MyShopColors.surfaceWhite,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            padding: const EdgeInsets.fromLTRB(
              MyShopSpacing.md,
              MyShopSpacing.md,
              MyShopSpacing.md,
              MyShopSpacing.lg,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: MyShopColors.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: MyShopSpacing.md),
                _CallChoiceTile(
                  icon: Icons.wifi_calling_3_rounded,
                  iconBg: MyShopColors.success,
                  iconColor: MyShopColors.textOnPrimary,
                  title: 'Call in app',
                  subtitle: 'Use MyShop voice call',
                  onTap: () =>
                      Navigator.of(sheetContext).pop(_CallChoice.inApp),
                ),
                const SizedBox(height: MyShopSpacing.sm),
                _CallChoiceTile(
                  icon: Icons.call_rounded,
                  iconBg: MyShopColors.darkSlate,
                  iconColor: MyShopColors.textOnDarkSlate,
                  title: 'Phone call',
                  subtitle: resolvedNumber.isEmpty
                      ? 'Phone number unavailable'
                      : resolvedNumber,
                  onTap: resolvedNumber.isEmpty
                      ? null
                      : () => Navigator.of(sheetContext).pop(_CallChoice.phone),
                ),
              ],
            ),
          ),
        );
      },
    );

    switch (choice) {
      case _CallChoice.inApp:
        inApp();
      case _CallChoice.phone:
        await dialPhoneNumber(context, resolvedNumber);
      case null:
        break;
    }
  }
}

enum _CallChoice { inApp, phone }

/// Branded option row for the call-type sheet — mirrors the channel tiles
/// used in [MyShopContactSupportSheet] so choice sheets look consistent.
class _CallChoiceTile extends StatelessWidget {
  const _CallChoiceTile({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(MyShopSpacing.md),
          decoration: BoxDecoration(
            color: MyShopColors.surfaceWhite,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: MyShopColors.divider),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: iconBg,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: MyShopSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: MyShopTypography.h3.copyWith(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(subtitle, style: MyShopTypography.body2),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: MyShopColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
