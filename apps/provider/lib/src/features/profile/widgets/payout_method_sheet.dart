import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../auth/providers/auth_controller.dart';
import '../data/payout_method_otp_service.dart';
import '../providers/payout_method_otp_provider.dart';

/// Two-step bottom sheet for setting the payout method:
///
///   1. **Form step** — pick MoMo network + enter account number → tap
///      "Send code" → server stashes a candidate and SMS-sends a 6-digit
///      code.
///   2. **OTP step** — enter the code → tap "Verify" → server commits the
///      candidate and flips `payoutLocked = true`.
///
/// The sheet refuses to open when the profile is already locked — callers
/// should gate on `payoutLocked == true` and surface "Contact support"
/// instead. Bank transfers are intentionally excluded; the backend rejects
/// them with `BANK_TRANSFER_NOT_SUPPORTED`.
Future<void> showPayoutMethodSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    builder: (_) => const _PayoutMethodSheet(),
  );
}

enum _SheetStep { form, otp }

class _PayoutMethodSheet extends ConsumerStatefulWidget {
  const _PayoutMethodSheet();

  @override
  ConsumerState<_PayoutMethodSheet> createState() => _PayoutMethodSheetState();
}

class _PayoutMethodSheetState extends ConsumerState<_PayoutMethodSheet> {
  final _accountController = TextEditingController();
  final _codeController = TextEditingController();
  final _accountFormKey = GlobalKey<FormFieldState<String>>();
  final _codeFormKey = GlobalKey<FormFieldState<String>>();

  String _method = 'momo_mtn';
  _SheetStep _step = _SheetStep.form;
  bool _isSending = false;
  bool _isVerifying = false;
  String? _serverError;

  /// Seconds remaining before the user can re-request a code. Starts at
  /// the server-supplied [PayoutOtpResult.retryAfterSeconds] (default 60).
  int _resendSeconds = 0;
  Timer? _cooldownTimer;

  static const _allMethods = [
    'momo_mtn',
    'momo_telecel',
    'momo_airteltigo',
  ];

  @override
  void dispose() {
    _accountController.dispose();
    _codeController.dispose();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  void _startCooldown(int seconds) {
    _cooldownTimer?.cancel();
    if (seconds <= 0) {
      setState(() => _resendSeconds = 0);
      return;
    }
    setState(() => _resendSeconds = seconds);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        if (_resendSeconds <= 1) {
          _resendSeconds = 0;
          t.cancel();
        } else {
          _resendSeconds -= 1;
        }
      });
    });
  }

  Future<void> _onSendCode() async {
    if (_isSending || _resendSeconds > 0) return;
    if (!(_accountFormKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isSending = true;
      _serverError = null;
    });

    final result = await ref.read(payoutMethodOtpServiceProvider).requestOtp(
          method: _method,
          accountNumber: _accountController.text.trim(),
        );

    if (!mounted) return;

    if (result.success) {
      _startCooldown(result.retryAfterSeconds ?? 60);
      setState(() {
        _isSending = false;
        _step = _SheetStep.otp;
      });
      return;
    }

    // 409 means the user already has a verified payout method but their
    // local profile is stale. Force a refresh + bounce out so the screen
    // can render the locked card.
    if (result.code == 'PAYOUT_METHOD_LOCKED') {
      await ref.read(authControllerProvider.notifier).refreshProfile();
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message ?? 'Payout method already verified.'),
        ),
      );
      return;
    }

    if (result.code == 'OTP_RATE_LIMIT' && result.retryAfterSeconds != null) {
      _startCooldown(result.retryAfterSeconds!);
    }

    setState(() {
      _isSending = false;
      _serverError = result.message ?? 'Could not send code.';
    });
  }

  Future<void> _onVerify() async {
    if (_isVerifying) return;
    if (!(_codeFormKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isVerifying = true;
      _serverError = null;
    });

    final result = await ref
        .read(payoutMethodOtpServiceProvider)
        .verifyOtp(code: _codeController.text.trim());

    if (!mounted) return;

    if (result.success) {
      // Pull the freshly committed profile so `payoutLocked` propagates
      // to every screen watching `currentUserProvider`.
      await ref.read(authControllerProvider.notifier).refreshProfile();
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Payout method verified and locked.'),
        ),
      );
      return;
    }

    // Errors that mean "candidate is gone" — bounce to step 1 so the user
    // can re-request rather than re-typing a code that won't ever match.
    final bouncing = result.code == 'OTP_EXPIRED' ||
        result.code == 'OTP_ATTEMPTS_EXCEEDED' ||
        result.code == 'NO_PENDING_OTP';

    setState(() {
      _isVerifying = false;
      _serverError = result.message ?? 'Verification failed.';
      if (bouncing) {
        _step = _SheetStep.form;
        _codeController.clear();
      }
    });
  }

  void _onEditNumber() {
    setState(() {
      _step = _SheetStep.form;
      _serverError = null;
      _codeController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.viewInsetsOf(context).bottom;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: viewInsets),
        child: Container(
          decoration: const BoxDecoration(
            color: MyShopColors.surfaceWhite,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          // SingleChildScrollView lets the keyboard push the field into
          // view without overflowing the column when the sheet's natural
          // height exceeds the remaining viewport.
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              MyShopSpacing.lg,
              MyShopSpacing.md,
              MyShopSpacing.lg,
              MyShopSpacing.lg,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Drag handle
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: MyShopColors.divider,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: MyShopSpacing.lg),
                if (_step == _SheetStep.form) ..._buildFormStep()
                else
                  ..._buildOtpStep(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Step 1: Form ─────────────────────────────────────────────────────────

  List<Widget> _buildFormStep() {
    return [
      Text('Set your payout number', style: MyShopTypography.h3),
      const SizedBox(height: 4),
      Text(
        'Pick the MoMo wallet you want to be paid into. We\'ll send a '
        '6-digit code to verify it. After you verify, it can\'t be '
        'changed without contacting support.',
        style: MyShopTypography.body2.copyWith(
          color: MyShopColors.textSecondary,
          height: 1.4,
        ),
      ),
      const SizedBox(height: MyShopSpacing.md),
      ..._allMethods.map(_buildMethodTile),
      const SizedBox(height: MyShopSpacing.md),
      Text(
        'Mobile money number',
        style: MyShopTypography.body1.copyWith(fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 6),
      TextFormField(
        key: _accountFormKey,
        controller: _accountController,
        keyboardType: TextInputType.phone,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s]')),
          LengthLimitingTextInputFormatter(17),
        ],
        decoration: _inputDecoration(hint: '024 123 4567'),
        validator: _validateAccount,
        autovalidateMode: AutovalidateMode.onUserInteraction,
      ),
      if (_serverError != null) ...[
        const SizedBox(height: 8),
        Text(
          _serverError!,
          style: MyShopTypography.body2.copyWith(color: MyShopColors.error),
        ),
      ],
      const SizedBox(height: MyShopSpacing.lg),
      _PrimaryButton(
        label: _resendSeconds > 0
            ? 'Try again in ${_resendSeconds}s'
            : 'Send verification code',
        onPressed: (_isSending || _resendSeconds > 0) ? null : _onSendCode,
        loading: _isSending,
      ),
    ];
  }

  // ── Step 2: OTP ──────────────────────────────────────────────────────────

  List<Widget> _buildOtpStep() {
    final masked = _maskNumber(_accountController.text.trim());
    return [
      Row(
        children: [
          IconButton(
            onPressed: _onEditNumber,
            icon: const Icon(Icons.arrow_back_rounded),
            color: MyShopColors.textPrimary,
            tooltip: 'Edit number',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text('Enter verification code', style: MyShopTypography.h3),
          ),
        ],
      ),
      const SizedBox(height: 4),
      Text(
        'We sent a 6-digit code to $masked. The code expires in 10 minutes.',
        style: MyShopTypography.body2.copyWith(
          color: MyShopColors.textSecondary,
          height: 1.4,
        ),
      ),
      const SizedBox(height: MyShopSpacing.md),
      TextFormField(
        key: _codeFormKey,
        controller: _codeController,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(6),
        ],
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontFamily: 'Raleway',
          fontSize: 22,
          fontWeight: FontWeight.w800,
          color: MyShopColors.textPrimary,
          letterSpacing: 6,
        ),
        decoration: _inputDecoration(hint: '••••••'),
        validator: (raw) {
          final v = (raw ?? '').trim();
          if (v.length != 6) return 'Enter the 6-digit code';
          return null;
        },
        autovalidateMode: AutovalidateMode.onUserInteraction,
      ),
      if (_serverError != null) ...[
        const SizedBox(height: 8),
        Text(
          _serverError!,
          style: MyShopTypography.body2.copyWith(color: MyShopColors.error),
        ),
      ],
      const SizedBox(height: MyShopSpacing.md),
      Row(
        children: [
          Expanded(
            child: TextButton(
              onPressed:
                  (_resendSeconds > 0 || _isSending) ? null : _onSendCode,
              style: TextButton.styleFrom(
                foregroundColor: MyShopColors.primaryGold,
                disabledForegroundColor: MyShopColors.textSecondary,
              ),
              child: Text(
                _resendSeconds > 0
                    ? 'Resend in ${_resendSeconds}s'
                    : 'Resend code',
                style: const TextStyle(
                  fontFamily: 'Raleway',
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: MyShopSpacing.sm),
      _PrimaryButton(
        label: 'Verify and lock',
        onPressed: _isVerifying ? null : _onVerify,
        loading: _isVerifying,
      ),
    ];
  }

  // ── Shared bits ──────────────────────────────────────────────────────────

  Widget _buildMethodTile(String method) {
    final selected = _method == method;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => setState(() => _method = method),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: MyShopSpacing.md,
            vertical: 12,
          ),
          decoration: BoxDecoration(
            color: selected
                ? MyShopColors.primaryGold.withValues(alpha: 0.08)
                : MyShopColors.surfaceWhite,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? MyShopColors.primaryGold
                  : MyShopColors.divider,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: MyShopColors.surfaceGrey,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.smartphone,
                  size: 20,
                  color: MyShopColors.darkSlate,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  payoutMethodLabel(method),
                  style: const TextStyle(
                    fontFamily: 'Raleway',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: MyShopColors.textPrimary,
                  ),
                ),
              ),
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 20,
                color: selected
                    ? MyShopColors.primaryGold
                    : MyShopColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({required String hint}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: MyShopTypography.body1.copyWith(
        color: MyShopColors.textSecondary,
      ),
      filled: true,
      fillColor: MyShopColors.offWhite,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: MyShopColors.divider),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: MyShopColors.divider),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(
          color: MyShopColors.primaryGold,
          width: 1.5,
        ),
      ),
    );
  }

  String? _validateAccount(String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) return 'Enter your mobile money number';
    final digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 10 || digits.length > 12) {
      return 'Enter a valid Ghanaian mobile number';
    }
    return null;
  }

  String _maskNumber(String raw) {
    if (raw.length < 4) return raw;
    final tail = raw.substring(raw.length - 3);
    return '••• ••• $tail';
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.onPressed,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: MyShopColors.darkSlate,
          foregroundColor: MyShopColors.textOnDarkSlate,
          disabledBackgroundColor:
              MyShopColors.darkSlate.withValues(alpha: 0.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Raleway',
            fontSize: 15,
            fontWeight: FontWeight.w800,
          ),
        ),
        child: loading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    MyShopColors.textOnDarkSlate,
                  ),
                ),
              )
            : Text(label),
      ),
    );
  }
}

/// Friendly label for a `payoutMethod` enum value. Public so the payout
/// methods screen can render the same wording on the saved-card row.
String payoutMethodLabel(String method) {
  switch (method.toLowerCase()) {
    case 'momo_mtn':
    case 'mtn':
    case 'momo':
      return 'MTN Mobile Money';
    case 'momo_telecel':
    case 'telecel':
    case 'vodafone':
      return 'Telecel Cash';
    case 'momo_airteltigo':
    case 'airteltigo':
      return 'AirtelTigo Money';
    case 'bank':
      return 'Bank transfer';
    default:
      return method.isEmpty ? 'Payout method' : method;
  }
}
