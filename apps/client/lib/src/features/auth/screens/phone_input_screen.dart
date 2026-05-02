import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../app/router.dart';
import '../providers/auth_controller.dart';

// ── Screen ────────────────────────────────────────────────────────────────────
// PRD § 4.1 — Passwordless login: phone number → OTP sent via SMS.
// Returning users sign in here. New users tap "Sign up" below.

class PhoneInputScreen extends ConsumerStatefulWidget {
  const PhoneInputScreen({super.key});

  @override
  ConsumerState<PhoneInputScreen> createState() => _PhoneInputScreenState();
}

class _PhoneInputScreenState extends ConsumerState<PhoneInputScreen> {
  bool _blockedDialogVisible = false;

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(clientAuthControllerProvider);

    ref.listen<ClientAuthState>(clientAuthControllerProvider, (prev, next) {
      if (next is AuthBlockedByOtherDevice && !_blockedDialogVisible) {
        _blockedDialogVisible = true;
        _showBlockedDialog(context, next.phone);
      } else if (next is! AuthBlockedByOtherDevice && _blockedDialogVisible) {
        _blockedDialogVisible = false;
        if (Navigator.canPop(context)) Navigator.pop(context);
      }
    });

    final isLoading = authState is AuthUnauthenticated && authState.isLoading;
    final error = authState is AuthUnauthenticated ? authState.error : null;

    return MyShopPhoneInputScreen(
      title: 'Welcome back',
      subtitle: 'Enter your phone number to sign in.',
      buttonLabel: 'Sign In',
      isLoading: isLoading,
      errorText: error,
      onErrorCleared: () {
        ref.read(clientAuthControllerProvider.notifier).clearError();
      },
      onSubmit: (phone) {
        ref.read(clientAuthControllerProvider.notifier).submitPhone(
              phone: phone,
            );
      },
      bottomAction: _SignUpLink(
        onTap: () => context.go(AppRoutes.authSignUp),
      ),
    );
  }

  Future<void> _showBlockedDialog(BuildContext context, String phone) async {
    final controller = ref.read(clientAuthControllerProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return Consumer(
          builder: (context, ref, _) {
            final state = ref.watch(clientAuthControllerProvider);
            final status = state is AuthBlockedByOtherDevice
                ? state.recoveryRequestStatus
                : RecoveryRequestStatus.idle;
            final sending = status == RecoveryRequestStatus.sending;
            return AlertDialog(
              title: const Text('Already signed in elsewhere'),
              content: Text(
                'This account ($phone) is signed in on another device. '
                'Please log out there first to continue. '
                'If you no longer have access to that device, '
                'tap Contact support.',
              ),
              actions: [
                TextButton(
                  onPressed: sending
                      ? null
                      : () async {
                          await controller.requestSessionRecovery();
                          if (!dialogContext.mounted) return;
                          final after = ref
                              .read(clientAuthControllerProvider);
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
                  child: sending
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Contact support'),
                ),
                TextButton(
                  onPressed: sending
                      ? null
                      : () {
                          Navigator.of(dialogContext).pop();
                          controller.dismissBlockedLogin();
                        },
                  child: const Text('OK'),
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

class _SignUpLink extends StatelessWidget {
  const _SignUpLink({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              "Don't have an account? ",
              style: TextStyle(
                fontSize: 14,
                color: MyShopColors.textSecondary,
              ),
            ),
            Text(
              'Sign Up',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: MyShopColors.primaryGold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
