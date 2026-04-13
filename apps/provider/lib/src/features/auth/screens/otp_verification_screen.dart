import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_ui/shared_ui.dart';

import '../providers/auth_controller.dart';

/// 6-digit OTP verification screen.
///
/// Used for both sign-in and sign-up flows. The auth state determines context.
/// On successful verify, the controller fetches the user profile and
/// transitions directly to [AuthAuthenticated].
class ProviderOtpVerificationScreen extends ConsumerStatefulWidget {
  const ProviderOtpVerificationScreen({super.key});

  @override
  ConsumerState<ProviderOtpVerificationScreen> createState() =>
      _ProviderOtpVerificationScreenState();
}

class _ProviderOtpVerificationScreenState
    extends ConsumerState<ProviderOtpVerificationScreen> {
  String _code = '';
  int _resendIn = 30;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startResendTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startResendTimer() {
    _timer?.cancel();
    setState(() => _resendIn = 30);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_resendIn <= 0) {
        t.cancel();
      } else {
        setState(() => _resendIn--);
      }
    });
  }

  Future<void> _verify() async {
    if (_code.length != 6) return;
    await ref.read(authControllerProvider.notifier).verifyOtp(_code);
  }

  Future<void> _resend() async {
    try {
      await ref.read(authControllerProvider.notifier).resendOtp();
      _startResendTimer();
    } catch (_) {
      // Silently fail — user can try again
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authControllerProvider);

    String phone = '';
    String? error;
    bool isVerifying = false;

    if (state is AuthOtpSent) {
      phone = state.phone;
      error = state.error;
      isVerifying = state.isVerifying;
    } else if (state is AuthAuthenticated) {
      // Keep loading visible while router redirects to /home.
      isVerifying = true;
    }

    return Scaffold(
      backgroundColor: MyShopColors.surfaceWhite,
      appBar: AppBar(
        backgroundColor: MyShopColors.surfaceWhite,
        elevation: 0,
        foregroundColor: MyShopColors.textPrimary,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              ref.read(authControllerProvider.notifier).reset(),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              Text('Enter verification code', style: MyShopTypography.h1),
              const SizedBox(height: 8),
              Text(
                'We sent a 6-digit code to $phone.',
                style: MyShopTypography.body2,
              ),
              const SizedBox(height: 32),
              MyShopOtpInput(
                onChanged: (v) {
                  setState(() => _code = v);
                  // Clear error as the user types a new code.
                  if (error != null) {
                    ref.read(authControllerProvider.notifier).clearError();
                  }
                },
                onCompleted: (_) => _verify(),
                hasError: error != null,
              ),
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(
                  error,
                  style: MyShopTypography.caption
                      .copyWith(color: MyShopColors.error),
                ),
              ],
              const SizedBox(height: 24),
              Center(
                child: _resendIn > 0
                    ? Text(
                        'Resend code in $_resendIn s',
                        style: MyShopTypography.body2,
                      )
                    : TextButton(
                        onPressed: _resend,
                        child: const Text('Resend code'),
                      ),
              ),
              const Spacer(),
              MyShopPrimaryButton(
                label: 'Verify',
                isLoading: isVerifying,
                onPressed: _code.length == 6 && !isVerifying ? _verify : null,
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
