import 'package:flutter/material.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:intl_phone_field/phone_number.dart';

import '../theme/myshop_colors.dart';
import '../theme/myshop_typography.dart';
import 'myshop_primary_button.dart';

/// Shared phone-number input screen used by both client and provider apps.
///
/// Accepts callbacks so each app can wire its own state management and
/// navigation. The country picker defaults to Ghana but accepts any country;
/// the value passed to [onSubmit] is always a full E.164 string
/// (e.g. `+233241234567`, `+447911123456`).
class MyShopPhoneInputScreen extends StatefulWidget {
  const MyShopPhoneInputScreen({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onSubmit,
    this.buttonLabel = 'Send code',
    this.isLoading = false,
    this.errorText,
    this.onErrorCleared,
    this.bottomAction,
  });

  final String title;
  final String subtitle;
  final ValueChanged<String> onSubmit;
  final String buttonLabel;
  final bool isLoading;
  final String? errorText;
  final VoidCallback? onErrorCleared;
  final Widget? bottomAction;

  @override
  State<MyShopPhoneInputScreen> createState() => _MyShopPhoneInputScreenState();
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

class _MyShopPhoneInputScreenState extends State<MyShopPhoneInputScreen> {
  PhoneNumber? _phone;
  bool _isValid = false;
  String? _localError;

  void _submit() {
    if (!_isValid || _phone == null) {
      setState(() => _localError = 'Enter a valid phone number.');
      return;
    }
    setState(() => _localError = null);
    widget.onSubmit(_phone!.completeNumber);
  }

  @override
  Widget build(BuildContext context) {
    final error = _localError ?? widget.errorText;

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
              Text(widget.title, style: MyShopTypography.h1),
              const SizedBox(height: 8),
              Text(widget.subtitle, style: MyShopTypography.body2),
              const SizedBox(height: 32),
              IntlPhoneField(
                enabled: !widget.isLoading,
                initialCountryCode: 'GH',
                disableLengthCheck: false,
                decoration: InputDecoration(
                  labelText: 'Phone number',
                  filled: true,
                  fillColor: MyShopColors.surfaceGrey,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(
                      color: MyShopColors.primaryGold,
                      width: 1.5,
                    ),
                  ),
                  errorText: error,
                ),
                style: const TextStyle(
                  fontFamily: 'Raleway',
                  fontSize: 14,
                  color: MyShopColors.textPrimary,
                ),
                dropdownTextStyle: const TextStyle(
                  fontFamily: 'Raleway',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: MyShopColors.textPrimary,
                ),
                onChanged: (phone) {
                  setState(() {
                    _phone = phone;
                    _isValid = _safeIsValidPhone(phone);
                    if (_localError != null) _localError = null;
                  });
                  widget.onErrorCleared?.call();
                },
                onSubmitted: (_) => _submit(),
              ),
              const Spacer(),
              MyShopPrimaryButton(
                label: widget.buttonLabel,
                isLoading: widget.isLoading,
                onPressed: widget.isLoading ? null : _submit,
              ),
              if (widget.bottomAction != null) ...[
                const SizedBox(height: 12),
                widget.bottomAction!,
              ],
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
