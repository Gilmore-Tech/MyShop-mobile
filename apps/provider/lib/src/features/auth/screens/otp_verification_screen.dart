import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_ui/shared_ui.dart';

import '../providers/auth_controller.dart';

/// 6-digit OTP verification screen.
///
/// Used for both sign-in and sign-up flows. The auth state determines context.
/// On successful verify, the controller fetches the user profile and
/// transitions directly to [AuthAuthenticated].
class ProviderOtpVerificationScreen extends ConsumerWidget {
  const ProviderOtpVerificationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(authControllerProvider);

    String phone = '';
    String? error;
    bool isVerifying = false;

    if (state is AuthOtpSent) {
      phone = state.phone;
      error = state.error;
      isVerifying = state.isVerifying;
    } else if (state is AuthAuthenticated) {
      isVerifying = true;
    }

    return MyShopOtpVerificationScreen(
      phone: phone,
      isVerifying: isVerifying,
      errorText: error,
      onErrorCleared: () =>
          ref.read(authControllerProvider.notifier).clearError(),
      onVerify: (code) =>
          ref.read(authControllerProvider.notifier).verifyOtp(code),
      onResend: () async {
        try {
          await ref.read(authControllerProvider.notifier).resendOtp();
        } catch (_) {}
      },
      onBack: () => ref.read(authControllerProvider.notifier).reset(),
    );
  }
}
