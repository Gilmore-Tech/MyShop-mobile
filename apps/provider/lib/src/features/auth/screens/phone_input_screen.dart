import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../profile/providers/provider_type_provider.dart';
import '../../registration/providers/registration_controller.dart';
import '../providers/auth_controller.dart';

/// Phone number input.
///
/// Used by both sign-in (`mode = signIn`) and the final step of sign-up
/// (`mode = signUp`). In sign-up mode, the registration draft data is sent
/// along with the phone via POST /auth/register.
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
    return Validators.ghanaPhone(raw);
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
      // Sign-in: check phone roles, then send OTP (or show role picker)
      await notifier.checkPhoneAndLogin(phone: phone);
    } else {
      // Sign-up: send registration data + phone via POST /auth/register
      final role = widget.signUpRole ?? ProviderType.driver;

      if (role == ProviderType.driver) {
        final draft = ref.read(driverRegistrationProvider);
        await notifier.registerAndSendOtp(
          phone: phone,
          fullName: draft.fullName,
          type: 'driver',
          privacyPolicyAccepted: true,
          role: role,
          email: draft.email.isNotEmpty ? draft.email : null,
        );
      } else {
        final draft = ref.read(artisanRegistrationProvider);
        await notifier.registerAndSendOtp(
          phone: phone,
          fullName: draft.fullName,
          type: 'artisan',
          privacyPolicyAccepted: true,
          role: role,
          email: draft.email.isNotEmpty ? draft.email : null,
          categories: draft.serviceCategories.isNotEmpty
              ? draft.serviceCategories
              : null,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authControllerProvider);

    String? remoteError;
    bool isLoading = false;

    if (state is AuthUnauthenticated) {
      remoteError = state.error;
      isLoading = state.isLoading;
    }

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
                enabled: !isLoading,
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
                onChanged: (_) {
                  // Clear errors as the user types.
                  if (_localError != null) setState(() => _localError = null);
                  if (remoteError != null) {
                    ref.read(authControllerProvider.notifier).clearError();
                  }
                },
                onSubmitted: (_) => _submit(),
              ),
              const Spacer(),
              MyShopPrimaryButton(
                label: 'Send code',
                isLoading: isLoading,
                onPressed: isLoading ? null : _submit,
              ),
              if (widget.mode == PhoneInputMode.signIn) ...[
                const SizedBox(height: 12),
                TextButton(
                  onPressed: isLoading
                      ? null
                      : () => context.go('/signup/role'),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48),
                    foregroundColor: MyShopColors.primaryGoldDark,
                  ),
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: "Don't have an account? ",
                          style: MyShopTypography.body1.copyWith(
                            color: MyShopColors.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        TextSpan(
                          text: 'Sign up',
                          style: MyShopTypography.body1.copyWith(
                            color: MyShopColors.primaryGoldDark,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
