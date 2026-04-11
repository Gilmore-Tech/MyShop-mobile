import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../profile/providers/provider_type_provider.dart';
import '../providers/auth_controller.dart';

/// Phone number input.
///
/// Used by both sign-in (`mode = signIn`) and the final step of sign-up
/// (`mode = signUp`). The screen behaves identically; only the auth call
/// differs.
enum PhoneInputMode { signIn, signUp }

class ProviderPhoneInputScreen extends ConsumerStatefulWidget {
  const ProviderPhoneInputScreen({
    super.key,
    required this.mode,
    this.signUpRole,
  });

  final PhoneInputMode mode;
  final ProviderType? signUpRole;

  @override
  ConsumerState<ProviderPhoneInputScreen> createState() =>
      _ProviderPhoneInputScreenState();
}

class _ProviderPhoneInputScreenState
    extends ConsumerState<ProviderPhoneInputScreen> {
  final _controller = TextEditingController();
  String? _localError;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String? _validate(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length != 9) {
      return 'Enter a 9-digit Ghana phone number.';
    }
    return null;
  }

  Future<void> _submit() async {
    final raw = _controller.text;
    final err = _validate(raw);
    if (err != null) {
      setState(() => _localError = err);
      return;
    }
    setState(() => _localError = null);
    final phone = '+233${raw.replaceAll(RegExp(r'\D'), '')}';
    final notifier = ref.read(authControllerProvider.notifier);
    if (widget.mode == PhoneInputMode.signIn) {
      await notifier.requestSignInOtp(phone);
    } else {
      await notifier.requestSignUpOtp(
        phone: phone,
        role: widget.signUpRole ?? ProviderType.driver,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authControllerProvider);
    final remoteError =
        state is AuthUnauthenticated ? state.error : null;

    final title = widget.mode == PhoneInputMode.signIn
        ? 'Welcome back'
        : 'Verify your phone';
    final subtitle = widget.mode == PhoneInputMode.signIn
        ? 'Sign in with your registered phone number.'
        : "We'll send a code to confirm your number and finish your account.";

    return Scaffold(
      backgroundColor: MyShopColors.surfaceWhite,
      appBar: AppBar(
        backgroundColor: MyShopColors.surfaceWhite,
        elevation: 0,
        foregroundColor: MyShopColors.textPrimary,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              Text(title, style: MyShopTypography.h1),
              const SizedBox(height: 8),
              Text(subtitle, style: MyShopTypography.body2),
              const SizedBox(height: 32),
              MyShopTextField(
                controller: _controller,
                label: 'Phone number',
                hint: '24 123 4567',
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.done,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(9),
                ],
                prefix: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Align(
                    alignment: Alignment.center,
                    widthFactor: 1,
                    child: Text(
                      '+233',
                      style: TextStyle(
                        fontFamily: 'Raleway',
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: MyShopColors.textPrimary,
                      ),
                    ),
                  ),
                ),
                errorText: _localError ?? remoteError,
                onSubmitted: (_) => _submit(),
              ),
              const Spacer(),
              MyShopPrimaryButton(
                label: 'Send code',
                onPressed: _submit,
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
