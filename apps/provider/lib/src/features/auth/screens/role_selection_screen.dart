import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_ui/shared_ui.dart';

import '../providers/auth_controller.dart';

/// Shown when a phone number has both driver and artisan accounts.
/// The user picks which role to sign in as, then OTP is sent.
class SignInRoleSelectionScreen extends ConsumerStatefulWidget {
  const SignInRoleSelectionScreen({super.key});

  @override
  ConsumerState<SignInRoleSelectionScreen> createState() =>
      _SignInRoleSelectionScreenState();
}

class _SignInRoleSelectionScreenState
    extends ConsumerState<SignInRoleSelectionScreen> {
  bool _blockedDialogVisible = false;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authControllerProvider);

    ref.listen<AuthState>(authControllerProvider, (prev, next) {
      if (next is AuthBlockedByOtherDevice && !_blockedDialogVisible) {
        _blockedDialogVisible = true;
        _showBlockedDialog(context, next.phone);
      } else if (next is! AuthBlockedByOtherDevice && _blockedDialogVisible) {
        _blockedDialogVisible = false;
        if (Navigator.canPop(context)) Navigator.pop(context);
      }
    });

    String? error;
    bool isLoading = false;

    if (state is AuthRoleSelection) {
      error = state.error;
      isLoading = state.isLoading;
    }

    return Scaffold(
      backgroundColor: MyShopColors.surfaceWhite,
      appBar: AppBar(
        backgroundColor: MyShopColors.surfaceWhite,
        elevation: 0,
        foregroundColor: MyShopColors.textPrimary,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => ref.read(authControllerProvider.notifier).reset(),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              Text('Choose your account', style: MyShopTypography.h1),
              const SizedBox(height: 8),
              Text(
                'This phone number has multiple accounts. '
                'Which one would you like to sign in to?',
                style: MyShopTypography.body2,
              ),
              const SizedBox(height: 32),
              _RoleOption(
                icon: Icons.directions_car_filled_rounded,
                title: 'Driver',
                subtitle: 'Pick up rides and earn on your schedule',
                accent: MyShopColors.darkSlate,
                isLoading: isLoading,
                onTap: isLoading
                    ? null
                    : () => ref
                        .read(authControllerProvider.notifier)
                        .selectRoleAndLogin(role: 'driver'),
              ),
              const SizedBox(height: 16),
              _RoleOption(
                icon: Icons.handyman_rounded,
                title: 'Artisan',
                subtitle: 'Bid on jobs and offer skilled services',
                accent: MyShopColors.primaryGoldDark,
                isLoading: isLoading,
                onTap: isLoading
                    ? null
                    : () => ref
                        .read(authControllerProvider.notifier)
                        .selectRoleAndLogin(role: 'artisan'),
              ),
              if (error != null) ...[
                const SizedBox(height: 16),
                Text(
                  error,
                  style: MyShopTypography.caption
                      .copyWith(color: MyShopColors.error),
                  textAlign: TextAlign.center,
                ),
              ],
              if (isLoading) ...[
                const SizedBox(height: 24),
                const Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showBlockedDialog(BuildContext context, String phone) async {
    final controller = ref.read(authControllerProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return Consumer(
          builder: (context, ref, _) {
            final state = ref.watch(authControllerProvider);
            final blocked = state is AuthBlockedByOtherDevice ? state : null;
            final recoveryStatus =
                blocked?.recoveryRequestStatus ?? RecoveryRequestStatus.idle;
            final sendingRecovery =
                recoveryStatus == RecoveryRequestStatus.sending;
            final takingOver = blocked?.isTakingOver ?? false;
            final takeoverError = blocked?.takeoverError;
            final anyInFlight = sendingRecovery || takingOver;
            return AlertDialog(
              title: const Text('Already signed in elsewhere'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'This account ($phone) is signed in on another device. '
                    'Choose "Sign me in here" to take over the session — '
                    "we'll send an OTP to confirm it's you and sign out the "
                    'other device. '
                    "If you don't recognise the other device, tap "
                    'Contact support instead.',
                  ),
                  if (takeoverError != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      takeoverError,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed:
                      anyInFlight ? null : () => controller.forceTakeover(),
                  child: takingOver
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Sign me in here'),
                ),
                TextButton(
                  onPressed: anyInFlight
                      ? null
                      : () async {
                          await controller.requestSessionRecovery();
                          if (!dialogContext.mounted) return;
                          final after = ref.read(authControllerProvider);
                          if (after is AuthBlockedByOtherDevice) {
                            if (after.recoveryRequestStatus ==
                                RecoveryRequestStatus.sent) {
                              messenger.showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Support has been notified. '
                                    "We'll get back to you shortly.",
                                  ),
                                ),
                              );
                            } else if (after.recoveryRequestStatus ==
                                RecoveryRequestStatus.failed) {
                              messenger.showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    "Couldn't reach support. "
                                    'Please check your connection and try again.',
                                  ),
                                ),
                              );
                            }
                          }
                        },
                  child: sendingRecovery
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Contact support'),
                ),
                TextButton(
                  onPressed: anyInFlight
                      ? null
                      : () {
                          Navigator.of(dialogContext).pop();
                          controller.dismissBlockedLogin();
                        },
                  child: const Text('Cancel'),
                ),
              ],
            );
          },
        );
      },
    );
    _blockedDialogVisible = false;
  }
}

class _RoleOption extends StatelessWidget {
  const _RoleOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.isLoading,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final bool isLoading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: isLoading ? 0.6 : 1.0,
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: MyShopColors.surfaceWhite,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: MyShopColors.divider),
              boxShadow: [
                BoxShadow(
                  color: MyShopColors.darkText.withValues(alpha: 0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, size: 28, color: accent),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: MyShopTypography.h3),
                      const SizedBox(height: 2),
                      Text(subtitle, style: MyShopTypography.body2),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 16,
                  color: MyShopColors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
