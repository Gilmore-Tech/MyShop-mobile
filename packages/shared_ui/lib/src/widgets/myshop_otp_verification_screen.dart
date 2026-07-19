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
    this.onResendWhatsApp,
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
  final VoidCallback? onResendWhatsApp;
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

  void _resendViaWhatsApp() {
    widget.onResendWhatsApp?.call();
    _startResendTimer();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // The auth state machine owns OTP navigation. If the host supplied an
      // explicit back action, route system-back through it as well as the app
      // bar so Android back/gestures cannot pop and be redirected straight
      // back to a stale OTP screen.
      canPop: widget.onBack == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) widget.onBack?.call();
      },
      child: Scaffold(
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
                const Text(
                  'Enter verification code',
                  style: MyShopTypography.h1,
                ),
                const SizedBox(height: 8),
                Text(
                  'Enter the 6-digit code for ${widget.phone}. '
                  'It may take a moment to arrive.',
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
                      : Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            TextButton(
                              onPressed: _resend,
                              child: const Text('Resend SMS'),
                            ),
                            if (widget.onResendWhatsApp != null)
                              TextButton.icon(
                                onPressed: _resendViaWhatsApp,
                                icon: const Icon(Icons.chat_outlined, size: 18),
                                label: const Text('Send via WhatsApp'),
                              ),
                          ],
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
      ),
    );
  }
}
