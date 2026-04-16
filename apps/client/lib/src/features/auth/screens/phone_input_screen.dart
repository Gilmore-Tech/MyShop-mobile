import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../app/router.dart';

// ── Screen ────────────────────────────────────────────────────────────────────
// PRD § 4.1 — Passwordless login: phone number → OTP sent via SMS.
// Registration also starts here (same endpoint POST /v1/auth/register handles both).

class PhoneInputScreen extends ConsumerStatefulWidget {
  const PhoneInputScreen({super.key});

  @override
  ConsumerState<PhoneInputScreen> createState() => _PhoneInputScreenState();
}

class _PhoneInputScreenState extends ConsumerState<PhoneInputScreen> {
  bool _isLoading = false;
  String? _error;

  Future<void> _submit(String phone) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    // TODO: POST /v1/auth/register or /v1/auth/request-otp
    await Future.delayed(const Duration(milliseconds: 800));

    if (!mounted) return;
    setState(() => _isLoading = false);
    context.push(AppRoutes.authOtp);
  }

  @override
  Widget build(BuildContext context) {
    return MyShopPhoneInputScreen(
      title: 'Welcome to MyShop',
      subtitle: "We'll send a verification code to your number.",
      buttonLabel: 'Continue',
      isLoading: _isLoading,
      errorText: _error,
      onErrorCleared: () => setState(() => _error = null),
      onSubmit: _submit,
    );
  }
}
