import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../core/providers/availability_controller.dart';
import '../../../core/providers/provider_status_provider.dart';
import '../../profile/providers/verification_provider.dart';
import '../../profile/widgets/incomplete_profile_sheet.dart';

/// Segmented Online/Offline toggle at the top of the bottom sheet.
///
/// - Two segments: "Online" (left) and "Offline" (right)
/// - Animated sliding indicator behind the active segment
/// - Green accent when online, grey when offline
/// - Locked (non-interactive) when driver status is busy
/// - Gated by profile completion — shows missing items sheet when incomplete
class OnlineOfflineToggle extends ConsumerWidget {
  const OnlineOfflineToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(providerStatusProvider);
    final isOnline = status.isOnline || status.isBusy;
    final isLocked = status.isBusy;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: MyShopSpacing.md,
        vertical: MyShopSpacing.sm,
      ),
      child: Opacity(
        opacity: isLocked ? 0.5 : 1.0,
        child: GestureDetector(
          onTap: isLocked
              ? null
              : () => _handleToggle(context, ref, isOnline),
          child: Container(
            height: 48,
            decoration: BoxDecoration(
              color: MyShopColors.surfaceGrey,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Stack(
              children: [
                // Animated sliding indicator
                AnimatedAlign(
                  alignment:
                      isOnline ? Alignment.centerLeft : Alignment.centerRight,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeInOut,
                  child: Container(
                    width: MediaQuery.of(context).size.width / 2 -
                        MyShopSpacing.md -
                        2,
                    height: 44,
                    margin: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: isOnline
                          ? MyShopColors.online
                          : MyShopColors.darkSlate,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: (isOnline
                                  ? MyShopColors.online
                                  : MyShopColors.darkSlate)
                              .withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                ),

                // Labels row
                Row(
                  children: [
                    // Online segment
                    Expanded(
                      child: Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.bolt,
                              size: 18,
                              color: isOnline
                                  ? MyShopColors.textOnPrimary
                                  : MyShopColors.textSecondary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Online',
                              style: TextStyle(
                                fontFamily: 'Raleway',
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: isOnline
                                    ? MyShopColors.textOnPrimary
                                    : MyShopColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Offline segment
                    Expanded(
                      child: Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.power_settings_new,
                              size: 18,
                              color: !isOnline
                                  ? MyShopColors.textOnPrimary
                                  : MyShopColors.textSecondary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Offline',
                              style: TextStyle(
                                fontFamily: 'Raleway',
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: !isOnline
                                    ? MyShopColors.textOnPrimary
                                    : MyShopColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleToggle(
    BuildContext context,
    WidgetRef ref,
    bool isOnline,
  ) async {
    final availability = ref.read(availabilityControllerProvider);

    // Going offline: flip local state + fire backend offline POST so the
    // matcher stops dispatching. Fire-and-forget — the user shouldn't wait
    // on the network for an offline transition.
    if (isOnline) {
      availability.goOffline();
      return;
    }

    // Going online requires verification data to be loaded AND complete.
    // Blocking on isLoading prevents a race where the user goes online
    // while verification is still fetching — they'd bypass the incomplete
    // profile sheet.
    final completion = ref.read(profileCompletionProvider);
    if (completion.isLoading) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Checking your profile — please try again.'),
        ),
      );
      return;
    }

    if (!completion.isComplete) {
      showIncompleteProfileSheet(context, completion: completion);
      return;
    }

    final error = await availability.goOnline();
    if (error != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error)),
      );
    }
  }
}
