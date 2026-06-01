import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../core/providers/availability_controller.dart';
import '../../../core/providers/provider_status_provider.dart';
import '../../auth/providers/auth_controller.dart';
import '../../profile/providers/verification_provider.dart';
import '../../profile/widgets/incomplete_profile_sheet.dart';

/// Segmented Online/Offline toggle at the top of the bottom sheet.
///
/// - Two segments: "Online" (left) and "Offline" (right)
/// - Animated sliding indicator behind the active segment
/// - Green accent when online, grey when offline
/// - Locked (non-interactive) when driver status is busy
/// - Gated by profile completion — shows missing items sheet when incomplete
/// - While going online, the Online segment swaps its bolt icon for a spinner
///   so the user sees the verification + availability checks in flight.
class OnlineOfflineToggle extends ConsumerStatefulWidget {
  const OnlineOfflineToggle({super.key});

  @override
  ConsumerState<OnlineOfflineToggle> createState() =>
      _OnlineOfflineToggleState();
}

class _OnlineOfflineToggleState extends ConsumerState<OnlineOfflineToggle> {
  bool _isGoingOnline = false;

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(providerStatusProvider);
    final isOnline = status.isOnline || status.isBusy;
    final isLocked = status.isBusy || _isGoingOnline;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: MyShopSpacing.md,
        vertical: MyShopSpacing.sm,
      ),
      child: Opacity(
        opacity: status.isBusy ? 0.5 : 1.0,
        child: GestureDetector(
          onTap: isLocked ? null : () => _handleToggle(isOnline),
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
                            _OnlineSegmentLeading(
                              isActive: isOnline,
                              isWorking: _isGoingOnline,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _isGoingOnline ? 'Checking…' : 'Online',
                              style: TextStyle(
                                fontFamily: 'Raleway',
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: isOnline || _isGoingOnline
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

  Future<void> _handleToggle(bool isOnline) async {
    final availability = ref.read(availabilityControllerProvider);

    // Going offline: flip local state + fire backend offline POST so the
    // matcher stops dispatching. Fire-and-forget — the user shouldn't wait
    // on the network for an offline transition.
    if (isOnline) {
      availability.goOffline();
      return;
    }

    setState(() => _isGoingOnline = true);
    try {
      // Force a fresh read of both the verification docs and the user
      // profile before deciding completeness. The home screen warms the
      // verification provider once on mount and Riverpod caches it for the
      // session; without invalidating, an approval (or vehicle/photo
      // update) that happened server-side mid-session never reaches the
      // toggle and the user sees a stale "incomplete profile" sheet.
      ref.invalidate(verificationStatusProvider);
      await Future.wait<void>([
        ref
            .read(verificationStatusProvider.future)
            .then<void>((_) {})
            .catchError((_) {}),
        ref
            .read(authControllerProvider.notifier)
            .refreshProfile()
            .then<void>((_) {}),
      ]);

      final completion = ref.read(profileCompletionProvider);
      if (!mounted) return;

      if (!completion.isComplete) {
        showIncompleteProfileSheet(context, completion: completion);
        return;
      }

      final error = await availability.goOnline();
      if (error != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error)),
        );
      }
    } finally {
      if (mounted) setState(() => _isGoingOnline = false);
    }
  }
}

class _OnlineSegmentLeading extends StatelessWidget {
  const _OnlineSegmentLeading({
    required this.isActive,
    required this.isWorking,
  });

  final bool isActive;
  final bool isWorking;

  @override
  Widget build(BuildContext context) {
    if (isWorking) {
      return const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(MyShopColors.textOnPrimary),
        ),
      );
    }
    return Icon(
      Icons.bolt,
      size: 18,
      color: isActive ? MyShopColors.textOnPrimary : MyShopColors.textSecondary,
    );
  }
}
