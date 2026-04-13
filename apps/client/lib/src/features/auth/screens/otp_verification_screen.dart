import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';

// ── Design tokens ──────────────────────────────────────────────────────────────
const _bg            = Color(0xFFF6F7F8);
const _surfaceWhite  = Color(0xFFFFFFFF);
const _textPrimary   = Color(0xFF161A1D);
const _textSecondary = Color(0xFF555E68);
const _gold          = Color(0xFFF5A623);
const _danger        = Color(0xFFEB5757);
const _success       = Color(0xFF27AE60);
const _divider       = Color(0xFFE8EAEC);

// ── Screen ─────────────────────────────────────────────────────────────────────
// PRD § 4.1 — 6-digit OTP sent via SMS (Africa's Talking).
// Auto-submits on last digit entry. Resend available after 60-second cooldown.
// EDD: POST /v1/auth/verify-otp → JWT issued.

class OtpVerificationScreen extends ConsumerStatefulWidget {
  const OtpVerificationScreen({super.key});

  @override
  ConsumerState<OtpVerificationScreen> createState() =>
      _OtpVerificationScreenState();
}

class _OtpVerificationScreenState
    extends ConsumerState<OtpVerificationScreen> {
  static const _length         = 6;
  static const _resendCooldown = 60;

  final List<TextEditingController> _controllers =
      List.generate(_length, (_) => TextEditingController());
  final List<FocusNode> _focusNodes =
      List.generate(_length, (_) => FocusNode());

  bool    _isLoading   = false;
  bool    _isResending = false;
  String? _errorMsg;
  int     _resendTimer = _resendCooldown;
  Timer?  _timer;

  // In production passed from PhoneInputScreen via GoRouter extra.
  final String _maskedPhone = '+233 •••• •••• 42';

  @override
  void initState() {
    super.initState();
    _startResendTimer();
  }

  @override
  void dispose() {
    for (final c in _controllers) { c.dispose(); }
    for (final f in _focusNodes)  { f.dispose(); }
    _timer?.cancel();
    super.dispose();
  }

  void _startResendTimer() {
    _resendTimer = _resendCooldown;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() {
        if (_resendTimer > 0) {
          _resendTimer--;
        } else {
          t.cancel();
        }
      });
    });
  }

  String get _otp => _controllers.map((c) => c.text).join();
  bool   get _isFull => _otp.length == _length;

  void _onDigitChanged(int index, String value) {
    setState(() => _errorMsg = null);
    if (value.length == 1 && index < _length - 1) {
      _focusNodes[index + 1].requestFocus();
    } else if (value.length == 1 && index == _length - 1) {
      _focusNodes[index].unfocus();
      _submit();
    }
  }

  void _onBackspace(int index) {
    if (_controllers[index].text.isEmpty && index > 0) {
      _controllers[index - 1].clear();
      _focusNodes[index - 1].requestFocus();
    }
  }

  Future<void> _submit() async {
    if (!_isFull || _isLoading) return;
    setState(() { _isLoading = true; _errorMsg = null; });

    // TODO: POST /v1/auth/verify-otp { phone, otp } → JWT
    await Future.delayed(const Duration(milliseconds: 900));

    if (!mounted) return;
    setState(() => _isLoading = false);

    // Simulate wrong OTP — remove when wired to real API.
    if (_otp == '000000') {
      setState(() => _errorMsg = 'Incorrect code. Please try again.');
      for (final c in _controllers) { c.clear(); }
      _focusNodes[0].requestFocus();
      return;
    }

    context.go(AppRoutes.home);
  }

  Future<void> _resend() async {
    if (_resendTimer > 0 || _isResending) return;
    setState(() { _isResending = true; _errorMsg = null; });

    // TODO: POST /v1/auth/register (re-sends OTP)
    await Future.delayed(const Duration(milliseconds: 600));

    if (!mounted) return;
    setState(() => _isResending = false);
    _startResendTimer();
    for (final c in _controllers) { c.clear(); }
    _focusNodes[0].requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final w    = size.width;
    final h    = size.height;
    final top  = MediaQuery.paddingOf(context).top;
    final bot  = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: _bg,
      body: Column(
        children: [
          Container(
            color: _surfaceWhite,
            padding: EdgeInsets.only(top: top),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => context.pop(),
                  icon: const Icon(Icons.arrow_back_ios_new_rounded,
                      color: _textPrimary),
                ),
                Text(
                  'Verify your number',
                  style: TextStyle(
                    color: _textPrimary,
                    fontSize: w * 0.044,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: w * 0.06),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(height: h * 0.06),
                  Container(
                    width:  w * 0.18,
                    height: w * 0.18,
                    decoration: BoxDecoration(
                      color: _gold.withAlpha(20),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.lock_outline_rounded,
                        color: _gold, size: w * 0.09),
                  ),
                  SizedBox(height: h * 0.028),
                  Text(
                    'Enter verification code',
                    style: TextStyle(
                      color: _textPrimary,
                      fontSize: w * 0.056,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: h * 0.010),
                  Text.rich(
                    TextSpan(
                      style: TextStyle(
                          color: _textSecondary,
                          fontSize: w * 0.036,
                          height: 1.5),
                      children: [
                        const TextSpan(text: 'We sent a 6-digit code to\n'),
                        TextSpan(
                          text: _maskedPhone,
                          style: const TextStyle(
                              color: _textPrimary,
                              fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: h * 0.048),
                  _OtpRow(
                    controllers: _controllers,
                    focusNodes:  _focusNodes,
                    hasError:    _errorMsg != null,
                    onChanged:   _onDigitChanged,
                    onBackspace: _onBackspace,
                    w: w,
                  ),
                  if (_errorMsg != null) ...[
                    SizedBox(height: h * 0.016),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline_rounded,
                            color: _danger, size: 16),
                        SizedBox(width: w * 0.016),
                        Text(
                          _errorMsg!,
                          style: TextStyle(
                              color: _danger, fontSize: w * 0.034),
                        ),
                      ],
                    ),
                  ],
                  SizedBox(height: h * 0.036),
                  _ResendRow(
                    timer:       _resendTimer,
                    isResending: _isResending,
                    onResend:    _resend,
                    w: w,
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
                w * 0.06, 0, w * 0.06, bot + h * 0.028),
            child: _VerifyButton(
              enabled: _isFull,
              loading: _isLoading,
              onTap:   _submit,
              w: w,
              h: h,
            ),
          ),
        ],
      ),
    );
  }
}

// ── OTP row ────────────────────────────────────────────────────────────────────

class _OtpRow extends StatelessWidget {
  final List<TextEditingController>  controllers;
  final List<FocusNode>              focusNodes;
  final bool                         hasError;
  final void Function(int, String)   onChanged;
  final void Function(int)           onBackspace;
  final double w;

  const _OtpRow({
    required this.controllers,
    required this.focusNodes,
    required this.hasError,
    required this.onChanged,
    required this.onBackspace,
    required this.w,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(6, (i) {
        return Padding(
          padding: EdgeInsets.only(right: i < 5 ? w * 0.04 : 0),
          child: _OtpBox(
            controller:  controllers[i],
            focusNode:   focusNodes[i],
            hasError:    hasError,
            onChanged:   (v) => onChanged(i, v),
            onBackspace: () => onBackspace(i),
            size:        (w - w * 0.12 - w * 0.04 * 5) / 6,
            w: w,
          ),
        );
      }),
    );
  }
}

class _OtpBox extends StatefulWidget {
  final TextEditingController  controller;
  final FocusNode              focusNode;
  final bool                   hasError;
  final ValueChanged<String>   onChanged;
  final VoidCallback           onBackspace;
  final double                 size;
  final double                 w;

  const _OtpBox({
    required this.controller,
    required this.focusNode,
    required this.hasError,
    required this.onChanged,
    required this.onBackspace,
    required this.size,
    required this.w,
  });

  @override
  State<_OtpBox> createState() => _OtpBoxState();
}

class _OtpBoxState extends State<_OtpBox> {
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (mounted) setState(() => _focused = widget.focusNode.hasFocus);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChange);
    super.dispose();
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.backspace) {
      widget.onBackspace();
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final filled = widget.controller.text.isNotEmpty;
    final Color borderColor;
    if (widget.hasError)  { borderColor = _danger; }
    else if (_focused)    { borderColor = _gold; }
    else if (filled)      { borderColor = _success; }
    else                  { borderColor = _divider; }

    return KeyboardListener(
      focusNode: FocusNode(skipTraversal: true),
      onKeyEvent: _handleKeyEvent,
      child: Container(
        width:  widget.size,
        height: widget.size * 1.18,
        decoration: BoxDecoration(
          color:        _surfaceWhite,
          borderRadius: BorderRadius.circular(12),
          border:       Border.all(
              color: borderColor, width: _focused ? 2 : 1.5),
          boxShadow: [
            BoxShadow(
              color: (_focused ? _gold : Colors.black)
                  .withAlpha(_focused ? 30 : 8),
              blurRadius: _focused ? 10 : 4,
            ),
          ],
        ),
        child: TextField(
          controller:      widget.controller,
          focusNode:       widget.focusNode,
          keyboardType:    TextInputType.number,
          textAlign:       TextAlign.center,
          maxLength:       1,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged:       widget.onChanged,
          style: TextStyle(
            color:      _textPrimary,
            fontSize:   widget.w * 0.054,
            fontWeight: FontWeight.w700,
          ),
          decoration: const InputDecoration(
            border:         InputBorder.none,
            counterText:    '',
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ),
    );
  }
}

// ── Resend row ─────────────────────────────────────────────────────────────────

class _ResendRow extends StatelessWidget {
  final int          timer;
  final bool         isResending;
  final VoidCallback onResend;
  final double       w;

  const _ResendRow({
    required this.timer,
    required this.isResending,
    required this.onResend,
    required this.w,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          "Didn't receive the code? ",
          style: TextStyle(
              color: _textSecondary, fontSize: w * 0.035),
        ),
        if (timer > 0)
          Text(
            'Resend in ${timer}s',
            style: TextStyle(
                color: _textSecondary, fontSize: w * 0.035),
          )
        else if (isResending)
          const SizedBox(
            width: 16, height: 16,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: _gold),
          )
        else
          GestureDetector(
            onTap: onResend,
            child: Text(
              'Resend',
              style: TextStyle(
                color:      _gold,
                fontSize:   w * 0.035,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }
}

// ── Verify button ──────────────────────────────────────────────────────────────

class _VerifyButton extends StatelessWidget {
  final bool         enabled;
  final bool         loading;
  final VoidCallback onTap;
  final double       w, h;

  const _VerifyButton({
    required this.enabled,
    required this.loading,
    required this.onTap,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity:  enabled ? 1.0 : 0.45,
      duration: const Duration(milliseconds: 200),
      child: SizedBox(
        width:  double.infinity,
        height: h * 0.066,
        child: Material(
          color:        _gold,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap:        enabled ? onTap : null,
            borderRadius: BorderRadius.circular(12),
            child: Center(
              child: loading
                  ? SizedBox(
                      width: w * 0.052, height: w * 0.052,
                      child: const CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.5),
                    )
                  : Text(
                      'Verify & Continue',
                      style: TextStyle(
                        color:       Colors.white,
                        fontSize:    w * 0.042,
                        fontWeight:  FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
