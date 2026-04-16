import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../app/router.dart';

// ── Screen ────────────────────────────────────────────────────────────────────
// PRD § 4.1 — 6-digit OTP sent via SMS (Africa's Talking).
// Auto-submits on last digit entry. Resend available after 30-second cooldown.
// EDD: POST /v1/auth/verify-otp → JWT issued.

class OtpVerificationScreen extends ConsumerStatefulWidget {
  const OtpVerificationScreen({super.key});

  @override
  ConsumerState<OtpVerificationScreen> createState() =>
      _OtpVerificationScreenState();
}

class _OtpVerificationScreenState
    extends ConsumerState<OtpVerificationScreen> {
  bool _isVerifying = false;
  String? _error;

  // In production passed from PhoneInputScreen via GoRouter extra.
  final String _phone = '+233 •••• •••• 42';

  Future<void> _verify(String code) async {
    setState(() {
      _isVerifying = true;
      _error = null;
    });

    // TODO: POST /v1/auth/verify-otp { phone, otp } → JWT
    await Future.delayed(const Duration(milliseconds: 900));

    if (!mounted) return;
    setState(() => _isVerifying = false);

    // Simulate wrong OTP — remove when wired to real API.
    if (code == '000000') {
      setState(() => _error = 'Incorrect code. Please try again.');
      return;
    }

    context.go(AppRoutes.home);
  }

  Future<void> _resend() async {
    setState(() => _error = null);
    // TODO: POST /v1/auth/register (re-sends OTP)
    await Future.delayed(const Duration(milliseconds: 600));
  }

  @override
  Widget build(BuildContext context) {
    return MyShopOtpVerificationScreen(
      phone: _phone,
      onVerify: _verify,
      onResend: _resend,
      isVerifying: _isVerifying,
      errorText: _error,
      onErrorCleared: () => setState(() => _error = null),
      resendCooldown: 30,
    );
  }
}
