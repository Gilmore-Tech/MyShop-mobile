import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/myshop_colors.dart';
import '../theme/myshop_typography.dart';
import 'myshop_otp_input.dart';
import 'myshop_primary_button.dart';

/// Shared OTP verification screen used by both client and provider apps.
///
/// Manages its own resend-countdown timer. Calls [onVerify] when the user
/// fills all 6 digits (auto-submit) or taps the "Verify" button.
class MyShopOtpVerificationScreen extends StatefulWidget {
  const MyShopOtpVerificationScreen({
    super.key,
    required this.phone,
    required this.onVerify,
    required this.onResend,
    this.onBack,
    this.isVerifying = false,
    this.errorText,
    this.onErrorCleared,
    this.resendCooldown = 30,
    this.buttonLabel = 'Verify',
  });

  final String phone;
  final ValueChanged<String> onVerify;
  final VoidCallback onResend;
  final VoidCallback? onBack;
  final bool isVerifying;
  final String? errorText;
  final VoidCallback? onErrorCleared;
  final int resendCooldown;
  final String buttonLabel;

  @override
  State<MyShopOtpVerificationScreen> createState() =>
      _MyShopOtpVerificationScreenState();
}

class _MyShopOtpVerificationScreenState
    extends State<MyShopOtpVerificationScreen> {
  String _code = '';
  late int _resendIn;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _resendIn = widget.resendCooldown;
    _startResendTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startResendTimer() {
    _timer?.cancel();
    setState(() => _resendIn = widget.resendCooldown);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_resendIn <= 0) {
        t.cancel();
      } else {
        setState(() => _resendIn--);
      }
    });
  }

  void _verify() {
    if (_code.length != 6) return;
    widget.onVerify(_code);
  }

  void _resend() {
    widget.onResend();
    _startResendTimer();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MyShopColors.surfaceWhite,
      appBar: AppBar(
        backgroundColor: MyShopColors.surfaceWhite,
        elevation: 0,
        foregroundColor: MyShopColors.textPrimary,
        leading: widget.onBack != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: widget.onBack,
              )
            : null,
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
                'We sent a 6-digit code to ${widget.phone}.',
                style: MyShopTypography.body2,
              ),
              const SizedBox(height: 32),
              MyShopOtpInput(
                onChanged: (v) {
                  setState(() => _code = v);
                  if (widget.errorText != null) {
                    widget.onErrorCleared?.call();
                  }
                },
                onCompleted: (_) => _verify(),
                hasError: widget.errorText != null,
              ),
              if (widget.errorText != null) ...[
                const SizedBox(height: 12),
                Text(
                  widget.errorText!,
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
                label: widget.buttonLabel,
                isLoading: widget.isVerifying,
                onPressed:
                    _code.length == 6 && !widget.isVerifying ? _verify : null,
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
