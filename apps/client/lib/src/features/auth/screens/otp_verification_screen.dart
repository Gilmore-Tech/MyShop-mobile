import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_ui/shared_ui.dart';

import '../providers/auth_controller.dart';

// ── Screen ────────────────────────────────────────────────────────────────────
// PRD § 4.1 — 6-digit OTP delivered via the configured SMS provider.
// Auto-submits on last digit entry. Resend available after 30-second cooldown.
// EDD: POST /v1/auth/verify-otp → JWT issued.

class OtpVerificationScreen extends ConsumerWidget {
  const OtpVerificationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(clientAuthControllerProvider);
    final whatsappAvailable = ref.watch(clientOtpChannelsProvider).maybeWhen(
          data: (channels) => channels.contains('whatsapp'),
          orElse: () => false,
        );

    // Extract state for the OTP screen
    String phone = '';
    bool isVerifying = false;
    String? error;

    if (authState is AuthOtpSent) {
      phone = _maskPhone(authState.phone);
      isVerifying = authState.isVerifying;
      error = authState.error;
    }

    return MyShopOtpVerificationScreen(
      phone: phone,
      onVerify: (code) {
        ref.read(clientAuthControllerProvider.notifier).verifyOtp(code);
      },
      onResend: () async {
        await ref.read(clientAuthControllerProvider.notifier).resendOtp();
      },
      onResendWhatsApp: whatsappAvailable
          ? () async {
              await ref
                  .read(clientAuthControllerProvider.notifier)
                  .resendOtp(channel: 'whatsapp');
            }
          : null,
      isVerifying: isVerifying,
      errorText: error,
      onErrorCleared: () {
        ref.read(clientAuthControllerProvider.notifier).clearError();
      },
      // An expired/consumed code cannot be resent: the backend resend endpoint
      // only re-delivers an active code. Give the user a real escape back to
      // phone entry so they can request a fresh one.
      onBack: () => ref.read(clientAuthControllerProvider.notifier).reset(),
      resendCooldown: 30,
    );
  }

  /// Mask phone for display: +233241234567 → +233 •••• •• 67
  String _maskPhone(String phone) {
    final cleaned = phone.replaceAll(RegExp(r'[^\d+]'), '');
    if (cleaned.length < 6) return phone;
    final prefix = cleaned.substring(0, 4);
    final suffix = cleaned.substring(cleaned.length - 2);
    return '$prefix •••• •• $suffix';
  }
}
