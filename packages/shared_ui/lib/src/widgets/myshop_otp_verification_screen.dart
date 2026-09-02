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
    this.onResend,
    this.onResendAttempt,
    this.onResendWhatsApp,
    this.onResendWhatsAppAttempt,
    this.onBack,
    this.isVerifying = false,
    this.errorText,
    this.onErrorCleared,
    this.bottomAction,
    this.resendCooldown = 30,
    this.buttonLabel = 'Verify',
  }) : assert(
          onResend != null || onResendAttempt != null,
          'Provide an SMS resend callback.',
        );

  final String phone;
  final ValueChanged<String> onVerify;

  /// Legacy fire-and-forget resend callback. Its existing behaviour starts
  /// the local cooldown immediately after the tap.
  final VoidCallback? onResend;

  /// Result-aware resend callback. When supplied, the cooldown starts only
  /// after the host confirms that the resend succeeded.
  final Future<bool> Function()? onResendAttempt;
  final VoidCallback? onResendWhatsApp;
  final Future<bool> Function()? onResendWhatsAppAttempt;
  final VoidCallback? onBack;
  final bool isVerifying;
  final String? errorText;
  final VoidCallback? onErrorCleared;
  final Widget? bottomAction;
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
  bool _resendPending = false;

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

  Future<void> _resend() async {
    await _requestResend(
      fallback: widget.onResend,
      attempt: widget.onResendAttempt,
    );
  }

  Future<void> _resendViaWhatsApp() async {
    await _requestResend(
      fallback: widget.onResendWhatsApp,
      attempt: widget.onResendWhatsAppAttempt,
    );
  }

  Future<void> _requestResend({
    required VoidCallback? fallback,
    required Future<bool> Function()? attempt,
  }) async {
    if (_resendPending) return;
    if (attempt == null) {
      fallback?.call();
      _startResendTimer();
      return;
    }

    setState(() => _resendPending = true);
    var succeeded = false;
    try {
      succeeded = await attempt();
    } catch (_) {
      succeeded = false;
    } finally {
      if (mounted) setState(() => _resendPending = false);
    }
    if (mounted && succeeded) _startResendTimer();
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
                              onPressed: _resendPending ? null : _resend,
                              child: const Text('Resend SMS'),
                            ),
                            if (widget.onResendWhatsApp != null ||
                                widget.onResendWhatsAppAttempt != null)
                              TextButton.icon(
                                onPressed:
                                    _resendPending ? null : _resendViaWhatsApp,
                                icon: const Icon(Icons.chat_outlined, size: 18),
                                label: const Text('Send via WhatsApp'),
                              ),
                          ],
                        ),
                ),
                if (widget.bottomAction != null) ...[
                  const SizedBox(height: 8),
                  widget.bottomAction!,
                ],
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
