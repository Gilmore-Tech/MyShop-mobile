import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_ui/shared_ui.dart';

/// Modal bottom sheet shown when Paystack returns `data.status: 'send_otp'`
/// for a MoMo charge. The user types the OTP they got over SMS; on submit,
/// the caller forwards it to `/payments/submit-otp`.
///
/// Returns the entered OTP string when the user submits, or null if they
/// dismissed the sheet without finishing.
Future<String?> showOtpEntrySheet(
  BuildContext context, {
  String? errorMessage,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (_) => _OtpEntrySheet(initialError: errorMessage),
  );
}

class _OtpEntrySheet extends StatefulWidget {
  const _OtpEntrySheet({this.initialError});
  final String? initialError;

  @override
  State<_OtpEntrySheet> createState() => _OtpEntrySheetState();
}

class _OtpEntrySheetState extends State<_OtpEntrySheet> {
  final _ctrl = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    _error = widget.initialError;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _ctrl.text.trim();
    if (value.isEmpty) {
      setState(() => _error = 'Enter the OTP from the SMS.');
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final w = size.width;
    final h = size.height;
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final bottomPad = MediaQuery.paddingOf(context).bottom;

    return Container(
      decoration: const BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        w * 0.051,
        MyShopSpacing.sm,
        w * 0.051,
        viewInsets.bottom + bottomPad + MyShopSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 48,
              height: 5,
              margin: const EdgeInsets.only(bottom: MyShopSpacing.md),
              decoration: BoxDecoration(
                color: MyShopColors.divider,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          Center(
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: MyShopColors.primaryGold.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.sms_outlined,
                color: MyShopColors.primaryGold,
                size: 28,
              ),
            ),
          ),
          SizedBox(height: h * 0.014),
          Text(
            'Enter the OTP',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: w * 0.051,
              fontWeight: FontWeight.w800,
              color: MyShopColors.textPrimary,
            ),
          ),
          SizedBox(height: h * 0.006),
          Text(
            'Paystack just sent a one-time code to your mobile money '
            'number. Enter it here to complete the payment.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: w * 0.031,
              color: MyShopColors.textSecondary,
              height: 1.4,
            ),
          ),
          SizedBox(height: h * 0.020),
          TextField(
            controller: _ctrl,
            autofocus: true,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(8),
            ],
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: w * 0.062,
              fontWeight: FontWeight.w700,
              letterSpacing: 8,
              color: MyShopColors.textPrimary,
            ),
            decoration: InputDecoration(
              hintText: '••••',
              hintStyle: TextStyle(
                color: MyShopColors.textSecondary,
                letterSpacing: 8,
                fontSize: w * 0.062,
              ),
              filled: true,
              fillColor: MyShopColors.surfaceGrey,
              contentPadding: EdgeInsets.symmetric(
                horizontal: w * 0.031,
                vertical: h * 0.018,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(w * 0.021),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(w * 0.021),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(w * 0.021),
                borderSide: const BorderSide(
                  color: MyShopColors.primaryGold,
                  width: 1.5,
                ),
              ),
            ),
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null) ...[
            SizedBox(height: h * 0.010),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: w * 0.031,
                color: MyShopColors.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          SizedBox(height: h * 0.020),
          SizedBox(
            width: double.infinity,
            height: h * 0.062,
            child: ElevatedButton(
              onPressed: _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: MyShopColors.darkSlate,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(w * 0.021),
                ),
              ),
              child: Text(
                'Submit',
                style: TextStyle(
                  fontSize: w * 0.041,
                  fontWeight: FontWeight.w700,
                  color: MyShopColors.surfaceWhite,
                ),
              ),
            ),
          ),
          SizedBox(height: h * 0.010),
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: Text(
              'Cancel',
              style: TextStyle(
                fontSize: w * 0.036,
                color: MyShopColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
