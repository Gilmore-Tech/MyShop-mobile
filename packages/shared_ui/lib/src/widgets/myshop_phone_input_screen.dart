import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/myshop_colors.dart';
import '../theme/myshop_typography.dart';
import '../utils/validators.dart';
import 'myshop_primary_button.dart';
import 'myshop_text_field.dart';

/// Shared phone-number input screen used by both client and provider apps.
///
/// Accepts callbacks so each app can wire its own state management and
/// navigation. Validates with [Validators.ghanaPhone] and formats the
/// number as `+233XXXXXXXXX` before calling [onSubmit].
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

class _MyShopPhoneInputScreenState extends State<MyShopPhoneInputScreen> {
  final _controller = TextEditingController();
  String? _localError;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String? _validate(String raw) => Validators.ghanaPhone(raw);

  void _submit() {
    final raw = _controller.text;
    final err = _validate(raw);
    if (err != null) {
      setState(() => _localError = err);
      return;
    }
    setState(() => _localError = null);
    // Validator already accepted both "24XXXXXXX" and "024XXXXXXX";
    // strip the leading 0 so the wire form is always +233 + 9 digits.
    final phone = '+233${Validators.normalizeGhanaPhoneDigits(raw)}';
    widget.onSubmit(phone);
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
              MyShopTextField(
                controller: _controller,
                label: 'Phone number',
                hint: '24 123 4567',
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.done,
                enabled: !widget.isLoading,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  // Accept either 9 digits (24XXXXXXX) or 10 with leading 0
                  // (024XXXXXXX) — Validators.ghanaPhone normalises both.
                  LengthLimitingTextInputFormatter(10),
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
                errorText: error,
                onChanged: (_) {
                  if (_localError != null) setState(() => _localError = null);
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
