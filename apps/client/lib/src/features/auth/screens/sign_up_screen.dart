import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl_phone_field/countries.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:intl_phone_field/phone_number.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../app/router.dart';
import '../../../core/deep_links/referral_deep_link.dart';
import '../providers/auth_controller.dart';

/// PRD § 4.1 — Client registration requires: full name + phone.
/// Email is optional.
class SignUpScreen extends ConsumerStatefulWidget {
  const SignUpScreen({super.key});

  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends ConsumerState<SignUpScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _referralController = TextEditingController();
  final _nameFocus = FocusNode();

  // Phone state — IntlPhoneField manages its own text controller; we just
  // hold the parsed PhoneNumber so we can submit a full E.164 string.
  PhoneNumber? _phone;
  bool _isValidPhone = false;
  String _initialCountryCode = 'GH';
  String _initialPhoneValue = '';

  @override
  void initState() {
    super.initState();

    // Prefill from the auth state set by the previous phone-input screen.
    // The number arrives as full E.164 (e.g. +233241234567, +447911123456);
    // split it into country + national parts for IntlPhoneField.
    final authState = ref.read(clientAuthControllerProvider);
    final prefill = authState is AuthNeedsRegistration ? authState.phone : null;
    if (prefill != null && prefill.isNotEmpty) {
      final parsed = _splitE164(prefill);
      _initialCountryCode = parsed.iso;
      _initialPhoneValue = parsed.national;
    }

    // Prefill the referral code if the user arrived via a referral deep link
    // (myshop://refer?code=…) captured before they reached this screen.
    final pendingReferral = ref.read(pendingReferralCodeProvider);
    if (pendingReferral != null && pendingReferral.isNotEmpty) {
      _referralController.text = pendingReferral;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _nameFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _referralController.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(clientAuthControllerProvider);
    final w = MediaQuery.sizeOf(context).width;
    final h = MediaQuery.sizeOf(context).height;

    // Extract state — works whether user came via checkPhone or direct link.
    // Phone prefill is consumed once in initState (via _splitE164); we don't
    // re-prefill on rebuilds because IntlPhoneField owns its own text state.
    bool isLoading = false;
    String? error;
    String? infoMessage;

    if (authState is AuthNeedsRegistration) {
      isLoading = authState.isLoading;
      error = authState.error;
      infoMessage = authState.message;
    } else if (authState is AuthUnauthenticated) {
      isLoading = authState.isLoading;
      error = authState.error;
    }

    return Scaffold(
      backgroundColor: MyShopColors.surfaceWhite,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: w * 0.062),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: h * 0.015),

                // Back button
                GestureDetector(
                  onTap: () {
                    ref.read(clientAuthControllerProvider.notifier).reset();
                    context.go(AppRoutes.authPhone);
                  },
                  child: Container(
                    width: w * 0.1,
                    height: w * 0.1,
                    decoration: BoxDecoration(
                      color: MyShopColors.surfaceGrey,
                      borderRadius: BorderRadius.circular(w * 0.025),
                    ),
                    child: Icon(
                      Icons.arrow_back_rounded,
                      size: w * 0.05,
                      color: MyShopColors.textPrimary,
                    ),
                  ),
                ),
                SizedBox(height: h * 0.025),

                // Title
                Text(
                  'Create your account',
                  style: TextStyle(
                    fontSize: w * 0.065,
                    fontWeight: FontWeight.w800,
                    color: MyShopColors.textPrimary,
                    height: 1.2,
                  ),
                ),
                SizedBox(height: h * 0.006),
                Text(
                  'Just a few details to get you started.',
                  style: TextStyle(
                    fontSize: w * 0.035,
                    color: MyShopColors.textSecondary,
                  ),
                ),
                // Info message (shown when redirected from sign-in)
                if (infoMessage != null) ...[
                  SizedBox(height: h * 0.015),
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(w * 0.035),
                    decoration: BoxDecoration(
                      color: MyShopColors.info.withAlpha(20),
                      borderRadius: BorderRadius.circular(w * 0.02),
                      border: Border.all(
                        color: MyShopColors.info.withAlpha(60),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          size: w * 0.045,
                          color: MyShopColors.info,
                        ),
                        SizedBox(width: w * 0.025),
                        Expanded(
                          child: Text(
                            infoMessage,
                            style: TextStyle(
                              fontSize: w * 0.032,
                              color: MyShopColors.info,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                SizedBox(height: h * 0.025),

                // ── Form fields ──
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Full name
                        _FieldLabel(label: 'Full Name', w: w),
                        SizedBox(height: h * 0.008),
                        _StyledTextField(
                          controller: _nameController,
                          focusNode: _nameFocus,
                          hint: 'e.g. Ama Mensah',
                          textCapitalization: TextCapitalization.words,
                          w: w,
                          h: h,
                          onChanged: (_) => setState(() {}),
                        ),
                        SizedBox(height: h * 0.022),

                        // Phone number
                        _FieldLabel(label: 'Phone Number', w: w),
                        SizedBox(height: h * 0.008),
                        IntlPhoneField(
                          initialCountryCode: _initialCountryCode,
                          initialValue: _initialPhoneValue,
                          disableLengthCheck: false,
                          style: TextStyle(
                              fontSize: w * 0.038,
                              color: MyShopColors.textPrimary),
                          dropdownTextStyle: TextStyle(
                            fontSize: w * 0.038,
                            fontWeight: FontWeight.w600,
                            color: MyShopColors.textPrimary,
                          ),
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: MyShopColors.surfaceGrey,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: w * 0.04,
                              vertical: h * 0.018,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(w * 0.025),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(w * 0.025),
                              borderSide: const BorderSide(
                                color: MyShopColors.primaryGold,
                                width: 1.5,
                              ),
                            ),
                          ),
                          onChanged: (phone) {
                            setState(() {
                              _phone = phone;
                              _isValidPhone = _safeIsValidPhone(phone);
                            });
                          },
                        ),
                        SizedBox(height: h * 0.022),

                        // Email (optional)
                        _FieldLabel(label: 'Email', w: w, optional: true),
                        SizedBox(height: h * 0.008),
                        _StyledTextField(
                          controller: _emailController,
                          hint: 'you@example.com',
                          keyboardType: TextInputType.emailAddress,
                          w: w,
                          h: h,
                        ),
                        SizedBox(height: h * 0.022),

                        // Referral code (optional) — auto-filled when the user
                        // arrives via a myshop://refer?code=… deep link.
                        _FieldLabel(
                            label: 'Referral Code', w: w, optional: true),
                        SizedBox(height: h * 0.008),
                        _StyledTextField(
                          controller: _referralController,
                          hint: 'e.g. AMA10',
                          textCapitalization: TextCapitalization.characters,
                          w: w,
                          h: h,
                        ),

                        // Error message
                        if (error != null) ...[
                          SizedBox(height: h * 0.015),
                          Container(
                            width: double.infinity,
                            padding: EdgeInsets.all(w * 0.035),
                            decoration: BoxDecoration(
                              color: MyShopColors.error.withAlpha(20),
                              borderRadius: BorderRadius.circular(w * 0.02),
                            ),
                            child: Text(
                              error,
                              style: TextStyle(
                                fontSize: w * 0.032,
                                color: MyShopColors.error,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                // ── Bottom section ──
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: w * 0.02),
                  child: Text(
                    'By creating an account, you agree to our Terms of Service and Privacy Policy.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: w * 0.028,
                      color: MyShopColors.textHint,
                      height: 1.4,
                    ),
                  ),
                ),
                SizedBox(height: h * 0.012),

                // Submit button
                SizedBox(
                  width: double.infinity,
                  height: h * 0.062,
                  child: ElevatedButton(
                    onPressed: _canSubmit && !isLoading ? _submit : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: MyShopColors.primaryGold,
                      disabledBackgroundColor:
                          MyShopColors.primaryGold.withAlpha(100),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(w * 0.025),
                      ),
                      elevation: 0,
                    ),
                    child: isLoading
                        ? SizedBox(
                            width: w * 0.05,
                            height: w * 0.05,
                            child: const CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            'Create Account',
                            style: TextStyle(
                              fontSize: w * 0.038,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),

                // Sign-in link
                GestureDetector(
                  onTap: () {
                    ref.read(clientAuthControllerProvider.notifier).reset();
                    context.go(AppRoutes.authPhone);
                  },
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: h * 0.012),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Already have an account? ',
                          style: TextStyle(
                            fontSize: w * 0.035,
                            color: MyShopColors.textSecondary,
                          ),
                        ),
                        Text(
                          'Sign In',
                          style: TextStyle(
                            fontSize: w * 0.035,
                            fontWeight: FontWeight.w700,
                            color: MyShopColors.primaryGold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: h * 0.015),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool get _canSubmit =>
      _nameController.text.trim().length >= 2 && _isValidPhone && _phone != null;

  void _submit() {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final referral = _referralController.text.trim();
    ref.read(clientAuthControllerProvider.notifier).register(
          phone: _phone!.completeNumber,
          fullName: name,
          email: email.isNotEmpty ? email : null,
          referralCode: referral.isNotEmpty ? referral : null,
        );
    // One-shot: clear the captured code so it can't bleed into a later,
    // unrelated registration on the same install.
    ref.read(pendingReferralCodeProvider.notifier).state = null;
  }
}

// intl_phone_field's PhoneNumber.isValidNumber() throws NumberTooShortException
// (and NumberTooLongException) while the user is mid-typing instead of returning
// false. Wrap it so partial input doesn't crash the form.
bool _safeIsValidPhone(PhoneNumber phone) {
  try {
    return phone.isValidNumber();
  } catch (_) {
    return false;
  }
}

// Split an E.164 number (e.g. "+233241234567") into ISO country code and the
// national portion ("GH", "241234567"). Falls back to Ghana when the prefix
// doesn't match any known dial code. Used to seed IntlPhoneField when the
// previous screen has already captured a number for the new user.
({String iso, String national}) _splitE164(String e164) {
  if (!e164.startsWith('+')) return (iso: 'GH', national: e164);
  final digits = e164.substring(1);
  // Match longest dial code first so '+1xxx' doesn't beat '+1xxx' regions etc.
  final sorted = [...countries]
    ..sort((a, b) => b.dialCode.length.compareTo(a.dialCode.length));
  for (final c in sorted) {
    if (digits.startsWith(c.dialCode)) {
      return (iso: c.code, national: digits.substring(c.dialCode.length));
    }
  }
  return (iso: 'GH', national: digits);
}

// ── Helpers ──────────────────────────────────────────────────────────────────

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(
      {required this.label, required this.w, this.optional = false});
  final String label;
  final double w;
  final bool optional;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: w * 0.033,
            fontWeight: FontWeight.w600,
            color: MyShopColors.textPrimary,
          ),
        ),
        if (optional) ...[
          SizedBox(width: w * 0.015),
          Text(
            '(optional)',
            style: TextStyle(fontSize: w * 0.028, color: MyShopColors.textHint),
          ),
        ],
      ],
    );
  }
}

class _StyledTextField extends StatelessWidget {
  const _StyledTextField({
    required this.controller,
    required this.hint,
    required this.w,
    required this.h,
    this.focusNode,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final double w;
  final double h;
  final FocusNode? focusNode;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      style: TextStyle(fontSize: w * 0.038, color: MyShopColors.textPrimary),
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: MyShopColors.textHint, fontSize: w * 0.036),
        filled: true,
        fillColor: MyShopColors.surfaceGrey,
        contentPadding: EdgeInsets.symmetric(
          horizontal: w * 0.04,
          vertical: h * 0.018,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(w * 0.025),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(w * 0.025),
          borderSide: const BorderSide(
            color: MyShopColors.primaryGold,
            width: 1.5,
          ),
        ),
      ),
    );
  }
}

