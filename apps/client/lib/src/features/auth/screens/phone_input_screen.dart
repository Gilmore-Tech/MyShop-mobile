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
  bool _takeoverDialogVisible = false;

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(clientAuthControllerProvider);

    ref.listen<ClientAuthState>(clientAuthControllerProvider, (prev, next) {
      if (next is AuthTakeoverPrompt && !_takeoverDialogVisible) {
        _takeoverDialogVisible = true;
        _showTakeoverDialog(context, next.phone);
      } else if (next is! AuthTakeoverPrompt && _takeoverDialogVisible) {
        _takeoverDialogVisible = false;
        if (Navigator.canPop(context)) Navigator.pop(context);
      }
    });

    final isLoading = (authState is AuthUnauthenticated && authState.isLoading) ||
        (authState is AuthTakeoverPrompt && authState.isLoading);
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

  Future<void> _showTakeoverDialog(BuildContext context, String phone) async {
    final controller = ref.read(clientAuthControllerProvider.notifier);
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Already signed in elsewhere'),
        content: Text(
          'This account ($phone) is signed in on another device. '
          'Continue here? The other device will be signed out.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              controller.cancelTakeover();
            },
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              controller.confirmTakeover();
            },
            child: const Text('Continue here'),
          ),
        ],
      ),
    );
    _takeoverDialogVisible = false;
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
