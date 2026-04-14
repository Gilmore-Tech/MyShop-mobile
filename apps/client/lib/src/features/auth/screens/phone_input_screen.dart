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
const _goldDark      = Color(0xFFD48E1A);
const _danger  = Color(0xFFEB5757);
const _divider = Color(0xFFE8EAEC);

// ── Screen ─────────────────────────────────────────────────────────────────────
// PRD § 4.1 — Passwordless login: phone number → OTP sent via SMS.
// Registration also starts here (same endpoint POST /v1/auth/register handles both).
// Ghana phone format: +233 XX XXX XXXX (10 local digits starting with 0, or 9 without leading 0).

class PhoneInputScreen extends ConsumerStatefulWidget {
  const PhoneInputScreen({super.key});

  @override
  ConsumerState<PhoneInputScreen> createState() => _PhoneInputScreenState();
}

class _PhoneInputScreenState extends ConsumerState<PhoneInputScreen> {
  final _controller = TextEditingController();
  final _focusNode  = FocusNode();
  bool  _isLoading  = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  bool get _isValid {
    final digits = _controller.text.replaceAll(RegExp(r'\D'), '');
    return digits.length == 9 || digits.length == 10;
  }

  Future<void> _submit() async {
    if (!_isValid || _isLoading) return;
    setState(() { _isLoading = true; _error = null; });

    // TODO: POST /v1/auth/register or /v1/auth/request-otp
    await Future.delayed(const Duration(milliseconds: 800));

    if (!mounted) return;
    setState(() => _isLoading = false);
    context.push(AppRoutes.authOtp);
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
          _Header(w: w, h: h, top: top),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: w * 0.06),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(height: h * 0.042),
                  Text(
                    'Enter your\nphone number',
                    style: TextStyle(
                      color: _textPrimary,
                      fontSize: w * 0.072,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                    ),
                  ),
                  SizedBox(height: h * 0.012),
                  Text(
                    'We\'ll send a verification code to your number.',
                    style: TextStyle(
                      color: _textSecondary,
                      fontSize: w * 0.036,
                    ),
                  ),
                  SizedBox(height: h * 0.042),
                  _PhoneField(
                    controller: _controller,
                    focusNode: _focusNode,
                    error: _error,
                    onChanged: (_) => setState(() { _error = null; }),
                    onSubmit: _submit,
                    w: w,
                    h: h,
                  ),
                  if (_error != null) ...[
                    SizedBox(height: h * 0.012),
                    Row(
                      children: [
                        const Icon(Icons.error_outline_rounded,
                            color: _danger, size: 16),
                        SizedBox(width: w * 0.016),
                        Text(
                          _error!,
                          style: TextStyle(
                            color: _danger,
                            fontSize: w * 0.032,
                          ),
                        ),
                      ],
                    ),
                  ],
                  SizedBox(height: h * 0.032),
                  _TermsNote(w: w),
                ],
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
                w * 0.06, 0, w * 0.06, bot + h * 0.028),
            child: _ContinueButton(
              enabled: _isValid,
              loading: _isLoading,
              onTap: _submit,
              w: w,
              h: h,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Header ─────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final double w, h, top;
  const _Header({required this.w, required this.h, required this.top});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _surfaceWhite,
      padding: EdgeInsets.fromLTRB(w * 0.04, top + h * 0.012, w * 0.04, h * 0.016),
      child: Row(
        children: [
          _LogoMark(w: w),
          SizedBox(width: w * 0.024),
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: 'My',
                  style: TextStyle(
                    color: _textPrimary,
                    fontSize: w * 0.048,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                TextSpan(
                  text: 'Shop',
                  style: TextStyle(
                    color: _gold,
                    fontSize: w * 0.048,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LogoMark extends StatelessWidget {
  final double w;
  const _LogoMark({required this.w});

  @override
  Widget build(BuildContext context) {
    return Container(
      width:  w * 0.10,
      height: w * 0.10,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_gold, _goldDark],
        ),
      ),
      child: Icon(Icons.shopping_bag_rounded,
          color: Colors.white, size: w * 0.056),
    );
  }
}

// ── Phone field ────────────────────────────────────────────────────────────────

class _PhoneField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String? error;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmit;
  final double w, h;

  const _PhoneField({
    required this.controller,
    required this.focusNode,
    required this.error,
    required this.onChanged,
    required this.onSubmit,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _surfaceWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: error != null ? _danger : _divider,
          width: error != null ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(8),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Ghana flag + country code
          Container(
            padding: EdgeInsets.symmetric(
                horizontal: w * 0.038, vertical: h * 0.02),
            decoration: const BoxDecoration(
              border: Border(
                right: BorderSide(color: _divider),
              ),
            ),
            child: Row(
              children: [
                Text('🇬🇭', style: TextStyle(fontSize: w * 0.048)),
                SizedBox(width: w * 0.016),
                Text(
                  '+233',
                  style: TextStyle(
                    color: _textPrimary,
                    fontSize: w * 0.038,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(width: w * 0.008),
                const Icon(Icons.keyboard_arrow_down_rounded,
                    color: _textSecondary, size: 18),
              ],
            ),
          ),
          // Number input
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.done,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(10),
              ],
              onChanged: onChanged,
              onSubmitted: (_) => onSubmit(),
              style: TextStyle(
                color: _textPrimary,
                fontSize: w * 0.042,
                fontWeight: FontWeight.w500,
              ),
              decoration: InputDecoration(
                hintText: '0XX XXX XXXX',
                hintStyle: TextStyle(
                  color: _textSecondary.withAlpha(100),
                  fontSize: w * 0.038,
                ),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(
                    horizontal: w * 0.038, vertical: h * 0.022),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Terms note ─────────────────────────────────────────────────────────────────

class _TermsNote extends StatelessWidget {
  final double w;
  const _TermsNote({required this.w});

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        style: TextStyle(
            color: _textSecondary, fontSize: w * 0.032, height: 1.5),
        children: const [
          TextSpan(text: 'By continuing you agree to our '),
          TextSpan(
            text: 'Terms of Service',
            style: TextStyle(
                color: _gold, fontWeight: FontWeight.w600),
          ),
          TextSpan(text: ' and '),
          TextSpan(
            text: 'Privacy Policy',
            style: TextStyle(
                color: _gold, fontWeight: FontWeight.w600),
          ),
          TextSpan(text: '.'),
        ],
      ),
    );
  }
}

// ── Continue button ────────────────────────────────────────────────────────────

class _ContinueButton extends StatelessWidget {
  final bool enabled;
  final bool loading;
  final VoidCallback onTap;
  final double w, h;

  const _ContinueButton({
    required this.enabled,
    required this.loading,
    required this.onTap,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: enabled ? 1.0 : 0.45,
      duration: const Duration(milliseconds: 200),
      child: SizedBox(
        width: double.infinity,
        height: h * 0.066,
        child: Material(
          color: _gold,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.circular(12),
            child: Center(
              child: loading
                  ? SizedBox(
                      width: w * 0.052,
                      height: w * 0.052,
                      child: const CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                    )
                  : Text(
                      'Continue',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: w * 0.042,
                        fontWeight: FontWeight.w700,
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
