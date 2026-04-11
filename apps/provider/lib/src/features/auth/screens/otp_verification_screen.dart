import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../profile/providers/provider_type_provider.dart';
import '../../registration/providers/registration_controller.dart';
import '../providers/auth_controller.dart';

/// 6-digit OTP verification. Drives both sign-in and the final step of
/// sign-up — the auth state determines which.
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
  bool _submittingRegistration = false;

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
    final state = ref.read(authControllerProvider);
    final notifier = ref.read(authControllerProvider.notifier);
    if (state is AuthSignInOtp) {
      await notifier.requestSignInOtp(state.phone);
    } else if (state is AuthSignUpOtp) {
      await notifier.requestSignUpOtp(phone: state.phone, role: state.role);
    } else {
      return;
    }
    _startResendTimer();
  }

  Future<void> _submitRegistration(AuthSignUpReady ready) async {
    if (_submittingRegistration) return;
    _submittingRegistration = true;
    final ok = ready.role == ProviderType.driver
        ? await ref
            .read(driverRegistrationProvider.notifier)
            .submit(ready.phone)
        : await ref
            .read(artisanRegistrationProvider.notifier)
            .submit(ready.phone);
    _submittingRegistration = false;
    if (!ok && mounted) {
      // Surface error via the relevant draft state on the form screen.
      ref.read(authControllerProvider.notifier).reset();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Auto-submit registration once the sign-up OTP succeeds.
    ref.listen<AuthState>(authControllerProvider, (_, next) {
      if (next is AuthSignUpReady) {
        _submitRegistration(next);
      }
    });

    final state = ref.watch(authControllerProvider);

    String phone = '';
    String? error;
    bool isVerifying = false;
    if (state is AuthSignInOtp) {
      phone = state.phone;
      error = state.error;
      isVerifying = state.isVerifying;
    } else if (state is AuthSignUpOtp) {
      phone = state.phone;
      error = state.error;
      isVerifying = state.isVerifying;
    } else if (state is AuthSignUpReady) {
      phone = state.phone;
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
                onChanged: (v) => setState(() => _code = v),
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
                onPressed: _code.length == 6 ? _verify : null,
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
