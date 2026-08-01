import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl_phone_field/countries.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:intl_phone_field/phone_number.dart';
import 'package:api_client/api_client.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_models/shared_models.dart';

import '../../../app/router.dart';
import '../../../core/constants/support_contacts.dart';
import '../../../core/deep_links/referral_deep_link.dart';
import '../providers/auth_controller.dart';
import '../../support/providers/support_providers.dart';

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
  RequiredLegalDocuments? _requiredLegal;
  Object? _legalLoadError;
  bool _loadingLegal = true;
  bool _termsAccepted = false;
  bool _privacyAccepted = false;
  bool _legalRefreshScheduled = false;

  @override
  void initState() {
    super.initState();

    // Prefill from the auth state set by the previous phone-input screen.
    // The number arrives as full E.164 (e.g. +233241234567, +447911123456);
    // split it into country + national parts for IntlPhoneField.
    final authState = ref.read(clientAuthControllerProvider);
    _referralController.text =
        ref.read(pendingReferralCodeProvider)?.trim().toUpperCase() ?? '';
    final prefill = authState is AuthNeedsRegistration ? authState.phone : null;
    if (prefill != null && prefill.isNotEmpty) {
      final parsed = _splitE164(prefill);
      _initialCountryCode = parsed.iso;
      _initialPhoneValue = parsed.national;
      final country = countries.firstWhere(
        (candidate) => candidate.code == parsed.iso,
        orElse: () => countries.firstWhere(
          (candidate) => candidate.code == 'GH',
        ),
      );
      final phone = PhoneNumber(
        countryISOCode: country.code,
        countryCode: '+${country.fullCountryCode}',
        number: parsed.national,
      );
      _phone = phone;
      _isValidPhone = _safeIsValidPhone(phone);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _nameFocus.requestFocus();
    });
    unawaited(_loadLegal());
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
    String? errorCode;
    String? infoMessage;
    bool requiresRoleRecoverySupport = false;

    if (authState is AuthNeedsRegistration) {
      isLoading = authState.isLoading;
      error = authState.error;
      errorCode = authState.errorCode;
      infoMessage = authState.message;
      requiresRoleRecoverySupport = authState.requiresRoleRecoverySupport;
      if (authState.requiresLegalRefresh && !_legalRefreshScheduled) {
        _legalRefreshScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() {
            _termsAccepted = false;
            _privacyAccepted = false;
          });
          unawaited(_loadLegal(refresh: true));
        });
      }
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

                        _FieldLabel(
                          label: 'Referral Code',
                          w: w,
                          optional: true,
                        ),
                        SizedBox(height: h * 0.008),
                        _StyledTextField(
                          controller: _referralController,
                          hint: 'MYSHOP-ABC123',
                          textCapitalization: TextCapitalization.characters,
                          w: w,
                          h: h,
                          onChanged: (_) => setState(() {}),
                        ),
                        if (_referralController.text.trim().isNotEmpty &&
                            !_validReferralCode) ...[
                          SizedBox(height: h * 0.006),
                          Text(
                            'Use the format MYSHOP- followed by 6 letters or numbers.',
                            style: TextStyle(
                              fontSize: w * 0.029,
                              color: MyShopColors.error,
                            ),
                          ),
                        ],
                        SizedBox(height: h * 0.022),

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
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  error,
                                  style: TextStyle(
                                    fontSize: w * 0.032,
                                    color: MyShopColors.error,
                                  ),
                                ),
                                if (requiresRoleRecoverySupport) ...[
                                  SizedBox(height: h * 0.008),
                                  Wrap(
                                    spacing: w * 0.025,
                                    children: [
                                      TextButton.icon(
                                        onPressed: _startRoleRecovery,
                                        style: TextButton.styleFrom(
                                          foregroundColor: MyShopColors.error,
                                          padding: EdgeInsets.zero,
                                        ),
                                        icon: const Icon(Icons.restore),
                                        label: const Text(
                                          'Request account recovery',
                                        ),
                                      ),
                                      TextButton.icon(
                                        onPressed: _contactRecoverySupport,
                                        style: TextButton.styleFrom(
                                          foregroundColor: MyShopColors.error,
                                          padding: EdgeInsets.zero,
                                        ),
                                        icon: const Icon(Icons.support_agent),
                                        label: const Text('Contact support'),
                                      ),
                                    ],
                                  ),
                                ],
                                if (AuthErrorMapper
                                        .isReferralRegistrationErrorCode(
                                      errorCode,
                                    ) &&
                                    _referralController.text
                                        .trim()
                                        .isNotEmpty) ...[
                                  SizedBox(height: h * 0.008),
                                  TextButton.icon(
                                    key: const Key(
                                      'client-remove-referral-and-continue',
                                    ),
                                    onPressed: isLoading
                                        ? null
                                        : _removeReferralCodeAndContinue,
                                    style: TextButton.styleFrom(
                                      foregroundColor: MyShopColors.error,
                                      padding: EdgeInsets.zero,
                                    ),
                                    icon: const Icon(Icons.link_off_rounded),
                                    label: const Text(
                                      'Remove code and continue',
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                // ── Bottom section ──
                _buildLegalAcceptance(w, h),
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
                    child: Wrap(
                      alignment: WrapAlignment.center,
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
      _nameController.text.trim().length >= 2 &&
      _isValidPhone &&
      _phone != null &&
      _validReferralCode &&
      !_loadingLegal &&
      _requiredLegal?.documents.length == 2 &&
      _termsAccepted &&
      _privacyAccepted;

  bool get _validReferralCode {
    final code = _referralController.text.trim().toUpperCase();
    return code.isEmpty || RegExp(r'^MYSHOP-[A-Z0-9]{6}$').hasMatch(code);
  }

  Future<void> _submit() async {
    final legal = _requiredLegal;
    if (legal == null || !_termsAccepted || !_privacyAccepted) return;
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final referralCode = _referralController.text.trim().toUpperCase();
    await ref.read(clientAuthControllerProvider.notifier).register(
          phone: _phone!.completeNumber,
          fullName: name,
          legalAcceptances: legal.selections,
          email: email.isNotEmpty ? email : null,
          referralCode: referralCode.isNotEmpty ? referralCode : null,
        );
    if (ref.read(clientAuthControllerProvider) is AuthOtpSent) {
      ref.read(pendingReferralCodeProvider.notifier).state = null;
    }
  }

  Future<void> _removeReferralCodeAndContinue() async {
    if (_referralController.text.trim().isEmpty) return;
    setState(_referralController.clear);
    ref.read(pendingReferralCodeProvider.notifier).state = null;
    ref.read(clientAuthControllerProvider.notifier).clearError();
    await _submit();
  }

  Future<void> _loadLegal({bool refresh = false}) async {
    if (mounted) {
      setState(() {
        _loadingLegal = true;
        _legalLoadError = null;
      });
    }
    try {
      final documents = refresh
          ? await ref.refresh(clientRegistrationLegalDocumentsProvider.future)
          : await ref.read(clientRegistrationLegalDocumentsProvider.future);
      final slugs =
          documents.documents.map((document) => document.slug).toSet();
      if (documents.documents.length != 2 ||
          !slugs.contains(LegalSlugs.terms) ||
          !slugs.contains(LegalSlugs.privacy) ||
          documents.documents.any((document) => document.documentId.isEmpty)) {
        throw const ApiException(
          message: 'The current legal documents are incomplete. Please retry.',
        );
      }
      if (!mounted) return;
      setState(() {
        _requiredLegal = documents;
        _loadingLegal = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _requiredLegal = null;
        _legalLoadError = error;
        _loadingLegal = false;
        _termsAccepted = false;
        _privacyAccepted = false;
      });
    }
  }

  Widget _buildLegalAcceptance(double w, double h) {
    if (_loadingLegal) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 10),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (_legalLoadError != null) {
      return Column(
        children: [
          Text(
            'Terms and Privacy could not be loaded. Registration is paused until they are available.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: w * 0.03, color: MyShopColors.error),
          ),
          TextButton(
            onPressed: () => unawaited(_loadLegal(refresh: true)),
            child: const Text('Retry'),
          ),
        ],
      );
    }
    final terms = _documentFor(LegalSlugs.terms);
    final privacy = _documentFor(LegalSlugs.privacy);
    return Column(
      children: [
        _legalRow(
          value: _termsAccepted,
          label: 'I accept the Terms of Service v${terms?.version ?? ''}',
          onChanged: (value) => setState(() => _termsAccepted = value),
          onOpen: terms == null
              ? null
              : () => context.push(AppRoutes.legalDocumentPath(terms.slug)),
          w: w,
        ),
        SizedBox(height: h * 0.004),
        _legalRow(
          value: _privacyAccepted,
          label: 'I acknowledge the Privacy Notice v${privacy?.version ?? ''}',
          onChanged: (value) => setState(() => _privacyAccepted = value),
          onOpen: privacy == null
              ? null
              : () => context.push(AppRoutes.legalDocumentPath(privacy.slug)),
          w: w,
        ),
      ],
    );
  }

  LegalDocument? _documentFor(String slug) {
    for (final document
        in _requiredLegal?.documents ?? const <LegalDocument>[]) {
      if (document.slug == slug) return document;
    }
    return null;
  }

  Widget _legalRow({
    required bool value,
    required String label,
    required ValueChanged<bool> onChanged,
    required VoidCallback? onOpen,
    required double w,
  }) {
    return Row(
      children: [
        Checkbox(
          value: value,
          onChanged: (next) => onChanged(next ?? false),
          activeColor: MyShopColors.primaryGold,
        ),
        Expanded(
          child: TextButton(
            onPressed: onOpen,
            style: TextButton.styleFrom(
              alignment: Alignment.centerLeft,
              padding: EdgeInsets.symmetric(horizontal: w * 0.01),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: w * 0.03,
                color: MyShopColors.primaryGoldDark,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _contactRecoverySupport() async {
    final opened = await SupportChannels.openEmail(
      to: clientSupportEmail,
      subject: 'Client role recovery request',
    );
    if (!opened && mounted) {
      MyShopToast.show(
        context,
        message: 'Email $clientSupportEmail for recovery help.',
        duration: const Duration(seconds: 5),
      );
    }
  }

  Future<void> _startRoleRecovery() async {
    final auth = ref.read(clientAuthControllerProvider);
    final phone = _phone?.completeNumber ??
        (auth is AuthNeedsRegistration ? auth.phone : null);
    if (phone == null || phone.isEmpty) {
      MyShopToast.show(
        context,
        message: 'Enter the phone number that owned the deleted client role.',
      );
      return;
    }
    final repository = ref.read(clientAuthRepositoryProvider);
    await showMyShopRoleAccountRecoveryDialog(
      context: context,
      phone: phone,
      role: 'client',
      requestKey: const Uuid().v4(),
      requestOtp: () => repository.requestRoleAccountRecoveryOtp(phone),
      verifyOtp: (otp, requestKey) async {
        await repository.verifyRoleAccountRecoveryOtp(
          phone: phone,
          code: otp,
          requestKey: requestKey,
        );
      },
      errorMessage: (error) => error is ApiException
          ? AuthErrorMapper.message(error)
          : 'Recovery could not be requested. Please try again.',
    );
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
  // Match the longest full country code first. This includes region codes for
  // countries sharing a dial prefix, so a redirected number is reconstructed
  // exactly instead of silently changing country.
  final sorted = [...countries]..sort(
      (a, b) => b.fullCountryCode.length.compareTo(a.fullCountryCode.length),
    );
  for (final c in sorted) {
    if (digits.startsWith(c.fullCountryCode)) {
      return (
        iso: c.code,
        national: digits.substring(c.fullCountryCode.length),
      );
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
