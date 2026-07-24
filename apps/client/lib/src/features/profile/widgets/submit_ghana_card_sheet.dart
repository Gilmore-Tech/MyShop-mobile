import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_ui/shared_ui.dart';

import '../providers/privacy_security_provider.dart';

// ── Public entry-point ────────────────────────────────────────────────────────

/// Opens the Ghana Card submission sheet.
///
/// Flow:
///   1. User snaps / picks an image of the front of their Ghana Card.
///   2. Types the card number (auto-formatted as `GHA-XXXXXXXXX-X`).
///   3. Tap Submit → sheet uploads the image, hits POST /users/me/ghana-card,
///      refreshes the auth profile, and closes on success.
///
/// On failure the sheet stays open with an inline error so the user can
/// fix the input and retry without losing their progress.
Future<void> showSubmitGhanaCardSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (_) => const _SubmitGhanaCardSheet(),
  );
}

// Backend's expected pattern: `GHA-XXXXXXXXX-X`. Mirrored client-side so we
// can disable the Submit button before the user fires off a 400.
final RegExp _ghanaCardPattern = RegExp(r'^GHA-\d{9}-\d$');

// ── Sheet root ────────────────────────────────────────────────────────────────

class _SubmitGhanaCardSheet extends ConsumerStatefulWidget {
  const _SubmitGhanaCardSheet();

  @override
  ConsumerState<_SubmitGhanaCardSheet> createState() =>
      _SubmitGhanaCardSheetState();
}

class _SubmitGhanaCardSheetState extends ConsumerState<_SubmitGhanaCardSheet> {
  final _numberCtrl = TextEditingController();
  File? _selectedImage;
  String? _errorMessage;

  @override
  void dispose() {
    _numberCtrl.dispose();
    super.dispose();
  }

  bool get _isValidNumber =>
      _ghanaCardPattern.hasMatch(_numberCtrl.text.trim());

  bool get _canSubmit =>
      _selectedImage != null &&
      _isValidNumber &&
      !ref.watch(privacySecurityProvider).isSubmittingKyc;

  Future<void> _pickImage() async {
    final picked = await MediaPickerHelper.pickImage(context);
    if (picked == null || !mounted) return;
    setState(() {
      _selectedImage = picked;
      _errorMessage = null;
    });
  }

  Future<void> _submit() async {
    final image = _selectedImage;
    final number = _numberCtrl.text.trim();
    if (image == null || !_ghanaCardPattern.hasMatch(number)) return;

    setState(() => _errorMessage = null);
    final error = await ref
        .read(privacySecurityProvider.notifier)
        .submitGhanaCard(imageFile: image, cardNumber: number);
    if (!mounted) return;
    if (error != null) {
      setState(() => _errorMessage = error);
      return;
    }
    Navigator.of(context).pop();
    MyShopToast.show(
      context,
      message: "Ghana Card submitted — we'll let you know once it's reviewed.",
      duration: const Duration(seconds: 5),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final w = size.width;
    final h = size.height;
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    final isSubmitting = ref.watch(privacySecurityProvider).isSubmittingKyc;

    return Container(
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.vertical(top: Radius.circular(w * 0.041)),
      ),
      padding: EdgeInsets.only(bottom: inset),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: h * 0.014),
            Container(
              width: w * 0.103,
              height: h * 0.005,
              decoration: BoxDecoration(
                color: MyShopColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            SizedBox(height: h * 0.019),
            _Header(w: w, h: h),
            SizedBox(height: h * 0.024),

            // ── Image picker ─────────────────────────────────────────────
            _SectionLabel(text: 'GHANA CARD PHOTO', w: w, h: h),
            SizedBox(height: h * 0.012),
            _ImagePickerTile(
              file: _selectedImage,
              onTap: isSubmitting ? null : _pickImage,
              w: w,
              h: h,
            ),

            SizedBox(height: h * 0.024),

            // ── Number input ─────────────────────────────────────────────
            _SectionLabel(text: 'CARD NUMBER', w: w, h: h),
            SizedBox(height: h * 0.012),
            _NumberField(
              controller: _numberCtrl,
              onChanged: (_) => setState(() => _errorMessage = null),
              isValid: _isValidNumber,
              isEmpty: _numberCtrl.text.isEmpty,
              enabled: !isSubmitting,
              w: w,
              h: h,
            ),
            if (_numberCtrl.text.isNotEmpty && !_isValidNumber) ...[
              SizedBox(height: h * 0.008),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: w * 0.041),
                child: Text(
                  'Format: GHA-XXXXXXXXX-X (9 digits, dash, 1 check digit).',
                  style: TextStyle(
                    fontSize: w * 0.026,
                    color: MyShopColors.textSecondary,
                    height: 1.4,
                  ),
                ),
              ),
            ],

            // ── Disclaimer ───────────────────────────────────────────────
            SizedBox(height: h * 0.018),
            _Disclaimer(w: w, h: h),

            // ── Error + Submit ───────────────────────────────────────────
            if (_errorMessage != null) ...[
              SizedBox(height: h * 0.014),
              _InlineError(message: _errorMessage!, w: w),
            ],
            SizedBox(height: h * 0.024),
            _SubmitButton(
              isLoading: isSubmitting,
              canSubmit: _canSubmit,
              onPressed: _submit,
              w: w,
              h: h,
            ),
            SizedBox(height: h * 0.014),
            GestureDetector(
              onTap: isSubmitting ? null : () => Navigator.of(context).pop(),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: EdgeInsets.symmetric(
                  vertical: h * 0.009,
                  horizontal: w * 0.041,
                ),
                child: Text(
                  'Cancel',
                  style: TextStyle(
                    fontSize: w * 0.033,
                    fontWeight: FontWeight.w500,
                    color: isSubmitting
                        ? MyShopColors.disabled
                        : MyShopColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            SizedBox(height: h * 0.028),
          ],
        ),
      ),
    );
  }
}

// ── Header + section labels ───────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final double w, h;
  const _Header({required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: w * 0.041),
      child: Column(
        children: [
          Text(
            'Verify your Ghana Card',
            style: TextStyle(
              fontSize: w * 0.051,
              fontWeight: FontWeight.w700,
              color: MyShopColors.textPrimary,
            ),
          ),
          SizedBox(height: h * 0.007),
          Text(
            "We'll review your submission manually and let you know "
            'when a decision is available.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: w * 0.031,
              color: MyShopColors.textSecondary,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  final double w, h;
  const _SectionLabel({required this.text, required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: w * 0.041),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          style: TextStyle(
            fontSize: w * 0.026,
            fontWeight: FontWeight.w900,
            color: MyShopColors.textSecondary,
            letterSpacing: 0.8,
          ),
        ),
      ),
    );
  }
}

// ── Image picker tile ─────────────────────────────────────────────────────────

class _ImagePickerTile extends StatelessWidget {
  final File? file;
  final VoidCallback? onTap;
  final double w, h;

  const _ImagePickerTile({
    required this.file,
    required this.onTap,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    final hasImage = file != null;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: w * 0.041),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: h * 0.205,
          decoration: BoxDecoration(
            color:
                hasImage ? MyShopColors.surfaceGrey : MyShopColors.surfaceWhite,
            borderRadius: BorderRadius.circular(w * 0.026),
            border: Border.all(
              color: hasImage ? MyShopColors.primaryGold : MyShopColors.divider,
              width: 1.5,
              style: hasImage ? BorderStyle.solid : BorderStyle.solid,
            ),
          ),
          child: hasImage
              ? Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(w * 0.026),
                      child: Image.file(file!, fit: BoxFit.cover),
                    ),
                    Positioned(
                      bottom: w * 0.020,
                      right: w * 0.020,
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: w * 0.026,
                          vertical: w * 0.013,
                        ),
                        decoration: BoxDecoration(
                          color: MyShopColors.darkSlate.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.refresh_rounded,
                              size: w * 0.036,
                              color: MyShopColors.surfaceWhite,
                            ),
                            SizedBox(width: w * 0.013),
                            Text(
                              'Retake',
                              style: TextStyle(
                                fontSize: w * 0.028,
                                color: MyShopColors.surfaceWhite,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: w * 0.144,
                      height: w * 0.144,
                      decoration: const BoxDecoration(
                        color: MyShopColors.surfaceGrey,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.add_a_photo_outlined,
                        size: w * 0.064,
                        color: MyShopColors.textSecondary,
                      ),
                    ),
                    SizedBox(height: h * 0.012),
                    Text(
                      'Tap to add front of card',
                      style: TextStyle(
                        fontSize: w * 0.036,
                        fontWeight: FontWeight.w600,
                        color: MyShopColors.textPrimary,
                      ),
                    ),
                    SizedBox(height: h * 0.005),
                    Text(
                      'JPG or PNG · max 10 MB',
                      style: TextStyle(
                        fontSize: w * 0.028,
                        color: MyShopColors.textSecondary,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

// ── Number input ──────────────────────────────────────────────────────────────

class _NumberField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final bool isValid;
  final bool isEmpty;
  final bool enabled;
  final double w, h;

  const _NumberField({
    required this.controller,
    required this.onChanged,
    required this.isValid,
    required this.isEmpty,
    required this.enabled,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    final showError = !isEmpty && !isValid;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: w * 0.041),
      child: Container(
        decoration: BoxDecoration(
          color: MyShopColors.surfaceGrey,
          borderRadius: BorderRadius.circular(w * 0.021),
          border: Border.all(
            color: showError
                ? MyShopColors.error
                : isValid
                    ? MyShopColors.primaryGold
                    : MyShopColors.divider,
            width: 1.5,
          ),
        ),
        child: TextField(
          controller: controller,
          onChanged: onChanged,
          enabled: enabled,
          keyboardType: TextInputType.text,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: [_GhanaCardFormatter()],
          style: TextStyle(
            fontSize: w * 0.038,
            fontFamily: 'monospace',
            color: MyShopColors.textPrimary,
            letterSpacing: 1.2,
          ),
          decoration: InputDecoration(
            hintText: 'GHA-XXXXXXXXX-X',
            hintStyle: TextStyle(
              fontSize: w * 0.036,
              fontFamily: 'monospace',
              color: MyShopColors.textHint,
              letterSpacing: 1.2,
            ),
            prefixIcon: Icon(
              Icons.badge_outlined,
              size: w * 0.046,
              color: MyShopColors.textSecondary,
            ),
            suffixIcon: isValid
                ? Icon(
                    Icons.check_circle_rounded,
                    size: w * 0.046,
                    color: MyShopColors.success,
                  )
                : null,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            disabledBorder: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(
              horizontal: w * 0.020,
              vertical: h * 0.017,
            ),
          ),
        ),
      ),
    );
  }
}

/// Auto-formats keystrokes into the canonical `GHA-XXXXXXXXX-X` form so the
/// user doesn't have to type the dashes themselves and we can pattern-match
/// against the backend regex without trimming.
class _GhanaCardFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final raw =
        newValue.text.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

    final buf = StringBuffer();
    var idx = 0;

    // GHA prefix — always present once any input lands.
    if (raw.isNotEmpty) {
      final prefix = raw.startsWith('GHA') ? 'GHA' : 'GHA';
      buf.write(prefix);
      idx = raw.startsWith('GHA') ? 3 : 0;
    }

    // 9 digits.
    if (idx < raw.length) {
      buf.write('-');
      final digits = raw.substring(idx).replaceAll(RegExp(r'[^0-9]'), '');
      final nineDigits = digits.length > 9 ? digits.substring(0, 9) : digits;
      buf.write(nineDigits);

      if (digits.length > 9) {
        // Final check digit.
        buf.write('-');
        buf.write(digits.substring(9, digits.length.clamp(9, 10)));
      }
    }

    final formatted = buf.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

// ── Disclaimer ────────────────────────────────────────────────────────────────

class _Disclaimer extends StatelessWidget {
  final double w, h;
  const _Disclaimer({required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: w * 0.041),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: w * 0.031,
          vertical: h * 0.012,
        ),
        decoration: BoxDecoration(
          color: MyShopColors.surfaceGrey,
          borderRadius: BorderRadius.circular(w * 0.021),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.lock_outline_rounded,
              size: w * 0.038,
              color: MyShopColors.textSecondary,
            ),
            SizedBox(width: w * 0.020),
            Expanded(
              child: Text(
                'Your card number is encrypted at rest. Only the masked '
                'form is shown back in the app.',
                style: TextStyle(
                  fontSize: w * 0.028,
                  color: MyShopColors.textSecondary,
                  height: 1.45,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Submit button + inline error ──────────────────────────────────────────────

class _SubmitButton extends StatelessWidget {
  final bool isLoading;
  final bool canSubmit;
  final VoidCallback onPressed;
  final double w, h;

  const _SubmitButton({
    required this.isLoading,
    required this.canSubmit,
    required this.onPressed,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: w * 0.041),
      child: SizedBox(
        width: double.infinity,
        height: h * 0.062,
        child: ElevatedButton(
          onPressed: canSubmit ? onPressed : null,
          style: ElevatedButton.styleFrom(
            backgroundColor:
                canSubmit ? MyShopColors.darkSlate : MyShopColors.surfaceGrey,
            foregroundColor:
                canSubmit ? MyShopColors.surfaceWhite : MyShopColors.disabled,
            disabledBackgroundColor: MyShopColors.surfaceGrey,
            disabledForegroundColor: MyShopColors.disabled,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(w * 0.021),
            ),
          ),
          child: isLoading
              ? SizedBox(
                  width: w * 0.051,
                  height: w * 0.051,
                  child: const CircularProgressIndicator(
                    strokeWidth: 2,
                    color: MyShopColors.surfaceWhite,
                  ),
                )
              : Text(
                  'Submit for review',
                  style: TextStyle(
                    fontSize: w * 0.036,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
        ),
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  final String message;
  final double w;
  const _InlineError({required this.message, required this.w});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: w * 0.041),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.error_outline_rounded,
            size: w * 0.041,
            color: MyShopColors.error,
          ),
          SizedBox(width: w * 0.020),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: w * 0.031,
                fontWeight: FontWeight.w500,
                color: MyShopColors.error,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
