import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_ui/shared_ui.dart';

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
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _nameFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _nameFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(clientAuthControllerProvider);
    final w = MediaQuery.sizeOf(context).width;
    final h = MediaQuery.sizeOf(context).height;

    // Extract state — works whether user came via checkPhone or direct link
    String? prefillPhone;
    bool isLoading = false;
    String? error;
    String? infoMessage;

    if (authState is AuthNeedsRegistration) {
      prefillPhone = authState.phone;
      isLoading = authState.isLoading;
      error = authState.error;
      infoMessage = authState.message;
    } else if (authState is AuthUnauthenticated) {
      isLoading = authState.isLoading;
      error = authState.error;
    }

    // Pre-fill phone from state if available and field is empty
    if (prefillPhone != null && _phoneController.text.isEmpty) {
      // Strip +233 prefix for display
      final display = prefillPhone.replaceFirst('+233', '');
      _phoneController.text = display;
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
                        _PhoneField(
                          controller: _phoneController,
                          w: w,
                          h: h,
                          onChanged: (_) => setState(() {}),
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
      _nameController.text.trim().length >= 2 &&
      _phoneController.text.replaceAll(RegExp(r'\D'), '').length == 9;

  void _submit() {
    final name = _nameController.text.trim();
    final rawPhone = _phoneController.text.replaceAll(RegExp(r'\D'), '');
    final phone = '+233$rawPhone';
    final email = _emailController.text.trim();
    ref.read(clientAuthControllerProvider.notifier).register(
          phone: phone,
          fullName: name,
          email: email.isNotEmpty ? email : null,
        );
  }
}

// ── Helpers ──────────────────────────────────────────────────────────────────

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.label, required this.w, this.optional = false});
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

class _PhoneField extends StatelessWidget {
  const _PhoneField({
    required this.controller,
    required this.w,
    required this.h,
    this.onChanged,
  });

  final TextEditingController controller;
  final double w;
  final double h;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.phone,
      style: TextStyle(fontSize: w * 0.038, color: MyShopColors.textPrimary),
      onChanged: onChanged,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(9),
      ],
      decoration: InputDecoration(
        hintText: '24 123 4567',
        hintStyle: TextStyle(color: MyShopColors.textHint, fontSize: w * 0.036),
        filled: true,
        fillColor: MyShopColors.surfaceGrey,
        contentPadding: EdgeInsets.symmetric(
          horizontal: w * 0.04,
          vertical: h * 0.018,
        ),
        prefixIcon: Padding(
          padding: EdgeInsets.only(left: w * 0.04, right: w * 0.02),
          child: Text(
            '+233',
            style: TextStyle(
              fontSize: w * 0.038,
              fontWeight: FontWeight.w600,
              color: MyShopColors.textPrimary,
            ),
          ),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
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
