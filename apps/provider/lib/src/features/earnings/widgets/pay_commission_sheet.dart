import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:uuid/uuid.dart';

import '../../../core/di/providers.dart';
import '../../auth/providers/current_user_provider.dart';
import '../providers/earnings_providers.dart';
import '../services/cash_commission_remittance_poller.dart';

/// Driver / artisan tap "Pay Commission" → this sheet charges their own
/// MoMo to settle outstanding cash-commission debt.
///
/// Differences from the payout sheet:
///   - No OTP-*bind* step for wallet ownership. The provider is charging
///     an arbitrary MoMo number (usually their own) — no need to verify
///     "they own this wallet" the way a payout target would.
///   - Amount is editable between 1 pesewa and the server-authored debt shown
///     when the sheet opens. The backend rechecks the fresh provider-scoped
///     balance before creating a charge.
///   - The initial charge is idempotent. A transport retry reuses the same key
///     and exact body; editing the intent creates a new key.
///   - Charge flow branches on the backend's `chargeStatus`:
///     `pay_offline`/`pending` → the MoMo approval prompt goes straight
///     to the phone (awaiting screen). `send_otp` → Paystack first sends
///     an OTP/voucher SMS that must be forwarded via
///     POST /payments/cash-commission/remittances/:id/submit-otp before
///     the approval prompt arrives (OTP entry step). The backend's
///     reconciliation applies the funds once Paystack confirms.
Future<void> showPayCommissionSheet(
  BuildContext context, {
  required int owedPesewas,
  CashCommissionRemittancePoller poller =
      const CashCommissionRemittancePoller(),
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: MyShopColors.surfaceWhite,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _PayCommissionSheet(
      owedPesewas: owedPesewas,
      poller: poller,
    ),
  );
}

class _PayCommissionSheet extends ConsumerStatefulWidget {
  const _PayCommissionSheet({
    required this.owedPesewas,
    required this.poller,
  });

  /// Outstanding debt at the moment the sheet opens — drives the
  /// pre-filled amount and the headline "You owe…" label.
  final int owedPesewas;
  final CashCommissionRemittancePoller poller;

  @override
  ConsumerState<_PayCommissionSheet> createState() =>
      _PayCommissionSheetState();
}

enum _Step { enter, working, otp, awaiting, completed, failed, error }

enum _StartErrorDisposition { retrySameIntent, editIntent, closeAndRefresh }

/// Frozen backend codes for charge-start conflicts. Keep the mapping
/// centralized so every money-state conflict fails closed consistently.
const _staleOwedErrorCodes = <String>{
  'AMOUNT_EXCEEDS_OWED',
  'NO_CASH_COMMISSION_OWED',
};
const _remitInProgressErrorCodes = <String>{
  'CASH_COMMISSION_REMIT_IN_PROGRESS',
};
const _idempotencyMismatchErrorCodes = <String>{
  'IDEMPOTENCY_MISMATCH',
  'IDEMPOTENCY_KEY_REQUIRED',
};

class _RemittanceIntent {
  const _RemittanceIntent({
    required this.amountPesewas,
    required this.paymentMethod,
    required this.momoPhone,
    required this.idempotencyKey,
  });

  final int amountPesewas;
  final String paymentMethod;
  final String momoPhone;
  final String idempotencyKey;

  bool hasSameBody({
    required int amountPesewas,
    required String paymentMethod,
    required String momoPhone,
  }) =>
      this.amountPesewas == amountPesewas &&
      this.paymentMethod == paymentMethod &&
      this.momoPhone == momoPhone;
}

class _PayCommissionSheetState extends ConsumerState<_PayCommissionSheet> {
  _Step _step = _Step.enter;
  String _selectedMethod = 'momo_mtn';
  late final TextEditingController _amountCtl;
  late final TextEditingController _phoneCtl;
  late final TextEditingController _otpCtl;
  String? _errorMessage;
  String? _displayText;
  String? _otpError;
  bool _otpSubmitting = false;
  String? _remitId;
  int? _remittedPesewas;
  int? _remainingOwedPesewas;
  String? _gatewayStatus;
  bool _pollTimedOut = false;
  _RemittanceIntent? _activeIntent;
  _RemittanceIntent? _retryIntent;
  bool _closeOnlyError = false;

  @override
  void initState() {
    super.initState();
    final ghs = widget.owedPesewas / 100.0;
    _amountCtl = TextEditingController(text: ghs.toStringAsFixed(2));
    final phone = ref.read(currentUserProvider)?.phone ?? '';
    _phoneCtl = TextEditingController(text: phone);
    _otpCtl = TextEditingController();
  }

  @override
  void dispose() {
    _amountCtl.dispose();
    _phoneCtl.dispose();
    _otpCtl.dispose();
    super.dispose();
  }

  int? _parseAmountPesewas() {
    final raw = _amountCtl.text.trim();
    if (raw.isEmpty) return null;
    final ghs = double.tryParse(raw);
    if (ghs == null || ghs <= 0) return null;
    return (ghs * 100).round();
  }

  Future<void> _submit() async {
    final amount = _parseAmountPesewas();
    if (amount == null) {
      setState(() => _errorMessage = 'Enter an amount greater than 0.');
      return;
    }
    if (amount > widget.owedPesewas) {
      setState(() {
        _errorMessage =
            'Enter no more than GH₵ ${_fmtGhs(widget.owedPesewas)}, your '
            'current outstanding commission.';
      });
      return;
    }
    final phone = _phoneCtl.text.trim();
    if (phone.length < 9) {
      setState(() => _errorMessage = 'Enter your mobile money number.');
      return;
    }

    final existingIntent = _activeIntent;
    final intent = existingIntent != null &&
            existingIntent.hasSameBody(
              amountPesewas: amount,
              paymentMethod: _selectedMethod,
              momoPhone: phone,
            )
        ? existingIntent
        : _RemittanceIntent(
            amountPesewas: amount,
            paymentMethod: _selectedMethod,
            momoPhone: phone,
            idempotencyKey: const Uuid().v4(),
          );
    _activeIntent = intent;
    await _startRemittance(intent);
  }

  Future<void> _startRemittance(_RemittanceIntent intent) async {
    setState(() {
      _step = _Step.working;
      _errorMessage = null;
      _retryIntent = null;
      _closeOnlyError = false;
    });

    try {
      final res = await ref.read(paymentServiceProvider).remitCashCommission(
            amountPesewas: intent.amountPesewas,
            paymentMethod: intent.paymentMethod,
            momoPhone: intent.momoPhone,
            idempotencyKey: intent.idempotencyKey,
          );
      if (!mounted) return;
      final remitId = res['remitId'];
      if (remitId is! String || remitId.isEmpty) {
        throw const FormatException('Missing commission payment identifier');
      }

      // Paystack sometimes requires an OTP/voucher before the approval
      // prompt (always for Telecel vouchers; for MTN/AirtelTigo when its
      // risk rules require phone verification). The code must be forwarded
      // server-side, so show the entry step instead of the waiting screen.
      final needsOtp = res['chargeStatus'] == 'send_otp';

      setState(() {
        _remitId = remitId;
        _step = needsOtp ? _Step.otp : _Step.awaiting;
        _displayText = (res['displayText'] as String?) ??
            (needsOtp
                ? 'Enter the one-time code sent by your mobile money '
                    'provider.'
                : 'Authorise the prompt on '
                    'your phone to complete the payment.');
        _remittedPesewas = intent.amountPesewas;
        _pollTimedOut = false;
        _otpError = null;
        _otpCtl.clear();
      });
      if (!needsOtp) unawaited(_monitorRemittance(remitId));
    } on ApiException catch (e) {
      if (!mounted) return;
      final disposition = _startErrorDisposition(e);
      if (disposition == _StartErrorDisposition.closeAndRefresh) {
        _refreshEarnings();
      }
      setState(() {
        _step = _Step.error;
        _errorMessage = _friendlyError(e);
        _retryIntent = disposition == _StartErrorDisposition.retrySameIntent
            ? intent
            : null;
        _closeOnlyError = disposition == _StartErrorDisposition.closeAndRefresh;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _step = _Step.error;
        _errorMessage =
            "We couldn't confirm whether the payment request reached MyShop. "
            'Retry safely to reuse the same protected request.';
        _retryIntent = intent;
        _closeOnlyError = false;
      });
    }
  }

  Future<void> _submitOtp() async {
    final remitId = _remitId;
    if (remitId == null || _otpSubmitting) return;
    final otp = _otpCtl.text.trim();
    if (otp.length < 3) {
      setState(() => _otpError = 'Enter the code from the SMS.');
      return;
    }

    setState(() {
      _otpSubmitting = true;
      _otpError = null;
    });

    try {
      final res = await ref
          .read(paymentServiceProvider)
          .submitCashCommissionRemitOtp(remittanceId: remitId, otp: otp);
      if (!mounted) return;
      setState(() {
        _step = _Step.awaiting;
        _otpSubmitting = false;
        _displayText = (res['displayText'] as String?) ??
            'Authorise the prompt on '
                'your phone to complete the payment.';
      });
      unawaited(_monitorRemittance(remitId));
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.errorCode == 'REMIT_NOT_AWAITING_OTP') {
        // The charge already advanced (or closed) server-side — the poll
        // will surface the authoritative state.
        setState(() {
          _step = _Step.awaiting;
          _otpSubmitting = false;
        });
        unawaited(_monitorRemittance(remitId));
        return;
      }
      setState(() {
        _otpSubmitting = false;
        _otpError = e.errorCode == 'OTP_SUBMISSION_FAILED'
            ? 'The code could not be confirmed. Check it and try again.'
            : userSafeApiErrorMessage(
                e,
                fallback: "Couldn't confirm the code. Please try again.",
              );
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _otpSubmitting = false;
        _otpError = "Couldn't confirm the code. Please try again.";
      });
    }
  }

  Future<void> _monitorRemittance(String remitId) async {
    final result = await widget.poller.waitForTerminal(
      () => ref
          .read(paymentServiceProvider)
          .getCashCommissionRemittanceStatus(remitId),
    );
    if (!mounted) return;

    if (result == null) {
      _refreshEarnings();
      setState(() => _pollTimedOut = true);
      return;
    }

    _refreshEarnings();
    setState(() {
      _gatewayStatus = result.gatewayStatus;
      _remittedPesewas = result.amountPesewas;
      _remainingOwedPesewas = result.owedPesewas;
      // A terminal authoritative status closes this intent. A subsequent
      // attempt may safely receive a new idempotency key.
      _activeIntent = null;
      _retryIntent = null;
      _step = result.isCompleted ? _Step.completed : _Step.failed;
    });
  }

  void _refreshEarnings() {
    ref.read(invalidateEarningsCachesProvider)();
  }

  static _StartErrorDisposition _startErrorDisposition(ApiException error) {
    final code = error.errorCode;
    if (_staleOwedErrorCodes.contains(code) ||
        _remitInProgressErrorCodes.contains(code) ||
        _idempotencyMismatchErrorCodes.contains(code) ||
        error.statusCode == 409) {
      return _StartErrorDisposition.closeAndRefresh;
    }
    if (error.isNetworkError || error.isServerError) {
      return _StartErrorDisposition.retrySameIntent;
    }
    return _StartErrorDisposition.editIntent;
  }

  static String _friendlyError(ApiException error) {
    final code = error.errorCode;
    if (code == 'NO_CASH_COMMISSION_OWED') {
      return 'You have no commission owing right now. Close this sheet to '
          'refresh your balance.';
    }
    if (_staleOwedErrorCodes.contains(code)) {
      return 'Your commission balance changed, so this payment was stopped. '
          'Close this sheet and refresh before trying again.';
    }
    if (_remitInProgressErrorCodes.contains(code)) {
      return 'A commission payment is already in progress. Do not pay again. '
          'Close this sheet and wait for your balance to refresh.';
    }
    if (_idempotencyMismatchErrorCodes.contains(code)) {
      return "We couldn't safely match this request to its original payment "
          'attempt. Do not submit another payment. Close this sheet and '
          'refresh.';
    }
    if (error.statusCode == 409) {
      return 'A conflicting commission payment state was found. Do not pay '
          'again. Close this sheet and refresh your balance.';
    }
    if (error.isNetworkError || error.isServerError) {
      return "We couldn't confirm whether the payment request reached MyShop. "
          'Retry safely to reuse the same protected request.';
    }
    if (code == 'INVALID_AMOUNT') {
      return 'Enter an amount greater than 0.';
    }
    return userSafeApiErrorMessage(
      error,
      fallback: "Couldn't start the payment. Check the details and try again.",
      conflictMessage:
          'The commission balance changed. Close this sheet and refresh.',
    );
  }

  void _returnToEntryAfterTerminalFailure() {
    setState(() {
      _step = _Step.enter;
      _gatewayStatus = null;
      _pollTimedOut = false;
      _errorMessage = null;
      _retryIntent = null;
      // The poller supplied a terminal failed/cancelled state, so a new
      // submission is a new intent even when its visible fields are unchanged.
      _activeIntent = null;
    });
  }

  String _fmtGhs(int pesewas) {
    final ghs = pesewas / 100;
    if (ghs == ghs.truncateToDouble()) return ghs.toStringAsFixed(0);
    return ghs.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            MyShopSpacing.md,
            MyShopSpacing.md,
            MyShopSpacing.md,
            MyShopSpacing.lg,
          ),
          child: switch (_step) {
            _Step.enter => _buildEnter(),
            _Step.working => _buildWorking(),
            _Step.otp => _buildOtp(),
            _Step.awaiting => _buildAwaiting(),
            _Step.completed => _buildCompleted(),
            _Step.failed => _buildFailed(),
            _Step.error => _buildError(),
          },
        ),
      ),
    );
  }

  Widget _buildEnter() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _GrabHandle(),
        const SizedBox(height: 16),
        Text(
          'Pay Commission',
          style: MyShopTypography.h2.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 4),
        Text(
          'You owe MyShop GH₵ ${_fmtGhs(widget.owedPesewas)} in commission. '
          'You can pay all or part of this balance. The amount cannot be more '
          'than the outstanding commission shown here.',
          style: MyShopTypography.body2.copyWith(
            color: MyShopColors.textSecondary,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          'AMOUNT (GH₵)',
          style: TextStyle(
            fontFamily: 'Raleway',
            fontSize: 11,
            fontWeight: FontWeight.w900,
            color: MyShopColors.textSecondary,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _amountCtl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
          ],
          decoration: InputDecoration(
            hintText: '0.00',
            prefixText: 'GH₵  ',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(
                color: MyShopColors.divider,
                width: 1,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 14,
            ),
          ),
          style: const TextStyle(
            fontFamily: 'Raleway',
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'MOMO NETWORK',
          style: TextStyle(
            fontFamily: 'Raleway',
            fontSize: 11,
            fontWeight: FontWeight.w900,
            color: MyShopColors.textSecondary,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 6),
        _MomoPicker(
          value: _selectedMethod,
          onChanged: (m) => setState(() => _selectedMethod = m),
        ),
        const SizedBox(height: 16),
        const Text(
          'MOMO NUMBER',
          style: TextStyle(
            fontFamily: 'Raleway',
            fontSize: 11,
            fontWeight: FontWeight.w900,
            color: MyShopColors.textSecondary,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _phoneCtl,
          keyboardType: TextInputType.phone,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(12),
          ],
          decoration: InputDecoration(
            hintText: '0241234567',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(
                color: MyShopColors.divider,
                width: 1,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 14,
            ),
          ),
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 12),
          Text(
            _errorMessage!,
            style: const TextStyle(
              color: MyShopColors.error,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        const SizedBox(height: 18),
        ElevatedButton(
          onPressed: _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: MyShopColors.primaryGold,
            foregroundColor: MyShopColors.textOnPrimary,
            minimumSize: const Size(double.infinity, 50),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
          ),
          child: const Text(
            'PAY COMMISSION',
            style: TextStyle(
              fontFamily: 'Raleway',
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWorking() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: const [
        _GrabHandle(),
        SizedBox(height: 24),
        CircularProgressIndicator(color: MyShopColors.primaryGold),
        SizedBox(height: 16),
        Text(
          'Sending request to your MoMo wallet…',
          style: MyShopTypography.body1,
          textAlign: TextAlign.center,
        ),
        SizedBox(height: 24),
      ],
    );
  }

  Widget _buildOtp() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _GrabHandle(),
        const SizedBox(height: 16),
        const Text(
          'Enter the code',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Raleway',
            fontSize: 20,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _displayText ??
              'Enter the one-time code sent by your mobile money provider. '
                  'The approval prompt arrives after the code is confirmed.',
          textAlign: TextAlign.center,
          style: MyShopTypography.body2.copyWith(
            color: MyShopColors.textSecondary,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _otpCtl,
          enabled: !_otpSubmitting,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(12),
          ],
          decoration: InputDecoration(
            hintText: '123456',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(
                color: MyShopColors.divider,
                width: 1,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 14,
            ),
          ),
          style: const TextStyle(
            fontFamily: 'Raleway',
            fontSize: 22,
            fontWeight: FontWeight.w800,
            letterSpacing: 6,
          ),
        ),
        if (_otpError != null) ...[
          const SizedBox(height: 12),
          Text(
            _otpError!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: MyShopColors.error,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        const SizedBox(height: 18),
        ElevatedButton(
          onPressed: _otpSubmitting ? null : _submitOtp,
          style: ElevatedButton.styleFrom(
            backgroundColor: MyShopColors.primaryGold,
            foregroundColor: MyShopColors.textOnPrimary,
            minimumSize: const Size(double.infinity, 50),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
          ),
          child: _otpSubmitting
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: MyShopColors.textOnPrimary,
                  ),
                )
              : const Text(
                  'CONFIRM CODE',
                  style: TextStyle(
                    fontFamily: 'Raleway',
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildAwaiting() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _GrabHandle(),
        const SizedBox(height: 16),
        const Center(
          child: SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(color: MyShopColors.primaryGold),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Authorise on your phone',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Raleway',
            fontSize: 20,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _displayText ??
              'You should receive a MoMo prompt asking you to authorise the '
                  'payment. Once you approve it, your owed balance will update.',
          textAlign: TextAlign.center,
          style: MyShopTypography.body2.copyWith(
            color: MyShopColors.textSecondary,
            height: 1.45,
          ),
        ),
        if (_pollTimedOut) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: MyShopColors.primaryGoldLight,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              'Confirmation is taking longer than expected. Do not pay again. '
              'Close this sheet and refresh Earnings to check the latest status.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: MyShopColors.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
        ],
        const SizedBox(height: 18),
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          style: OutlinedButton.styleFrom(
            foregroundColor: MyShopColors.textPrimary,
            minimumSize: const Size(double.infinity, 50),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
          ),
          child: const Text(
            'CLOSE',
            style: TextStyle(
              fontFamily: 'Raleway',
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCompleted() {
    final paid = _remittedPesewas ?? 0;
    final remaining = _remainingOwedPesewas ?? 0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _GrabHandle(),
        const SizedBox(height: 16),
        const Icon(
          Icons.check_circle_rounded,
          color: MyShopColors.success,
          size: 56,
        ),
        const SizedBox(height: 12),
        const Text(
          'Payment confirmed',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Raleway',
            fontSize: 20,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'GH₵ ${_fmtGhs(paid)} was applied to your commission account. '
          'Your remaining Owings is GH₵ ${_fmtGhs(remaining)}.',
          textAlign: TextAlign.center,
          style: MyShopTypography.body2.copyWith(
            color: MyShopColors.textSecondary,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 18),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(),
          style: ElevatedButton.styleFrom(
            backgroundColor: MyShopColors.darkSlate,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 50),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
          ),
          child: const Text(
            'DONE',
            style: TextStyle(
              fontFamily: 'Raleway',
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFailed() {
    final cancelled = _gatewayStatus == 'abandoned';
    final reversed = _gatewayStatus == 'reversed';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _GrabHandle(),
        const SizedBox(height: 16),
        const Icon(Icons.cancel_outlined, color: MyShopColors.error, size: 52),
        const SizedBox(height: 12),
        Text(
          cancelled
              ? 'Payment cancelled'
              : reversed
                  ? 'Payment reversed'
                  : 'Payment not completed',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: 'Raleway',
            fontSize: 20,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          reversed
              ? 'The payment was reversed by the payment network. Your Owings '
                  'balance was not changed.'
              : 'No commission payment was applied. Your Owings balance was '
                  'not changed.',
          textAlign: TextAlign.center,
          style: MyShopTypography.body2.copyWith(
            color: MyShopColors.textSecondary,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 18),
        ElevatedButton(
          onPressed: _returnToEntryAfterTerminalFailure,
          style: ElevatedButton.styleFrom(
            backgroundColor: MyShopColors.primaryGold,
            foregroundColor: MyShopColors.textOnPrimary,
            minimumSize: const Size(double.infinity, 50),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
          ),
          child: const Text(
            'TRY AGAIN',
            style: TextStyle(
              fontFamily: 'Raleway',
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildError() {
    final retryIntent = _retryIntent;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _GrabHandle(),
        const SizedBox(height: 16),
        const Icon(Icons.error_outline, color: MyShopColors.error, size: 48),
        const SizedBox(height: 12),
        Text(
          _errorMessage ?? "Something went wrong.",
          textAlign: TextAlign.center,
          style: MyShopTypography.body1,
        ),
        const SizedBox(height: 18),
        ElevatedButton(
          onPressed: _closeOnlyError
              ? () => Navigator.of(context).pop()
              : retryIntent != null
                  ? () => _startRemittance(retryIntent)
                  : () => setState(() {
                        _step = _Step.enter;
                        _errorMessage = null;
                      }),
          style: ElevatedButton.styleFrom(
            backgroundColor: MyShopColors.primaryGold,
            foregroundColor: MyShopColors.textOnPrimary,
            minimumSize: const Size(double.infinity, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
          ),
          child: Text(
            _closeOnlyError
                ? 'CLOSE'
                : retryIntent != null
                    ? 'RETRY SAFELY'
                    : 'TRY AGAIN',
          ),
        ),
        if (retryIntent != null) ...[
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: OutlinedButton.styleFrom(
              foregroundColor: MyShopColors.textPrimary,
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
            ),
            child: const Text('CLOSE'),
          ),
        ],
      ],
    );
  }
}

class _GrabHandle extends StatelessWidget {
  const _GrabHandle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 44,
        height: 5,
        decoration: BoxDecoration(
          color: MyShopColors.divider,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    );
  }
}

class _MomoPicker extends StatelessWidget {
  const _MomoPicker({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  static const _options = [
    ('momo_mtn', 'MTN MoMo'),
    ('momo_telecel', 'Telecel Cash'),
    ('momo_airteltigo', 'AirtelTigo Money'),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: _options.map((opt) {
        final selected = opt.$1 == value;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: 6),
            child: InkWell(
              onTap: () => onChanged(opt.$1),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: selected
                      ? MyShopColors.primaryGoldLight
                      : Colors.transparent,
                  border: Border.all(
                    color: selected
                        ? MyShopColors.primaryGold
                        : MyShopColors.divider,
                    width: selected ? 1.5 : 1,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Text(
                  opt.$2,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Raleway',
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: selected
                        ? MyShopColors.textPrimary
                        : MyShopColors.textSecondary,
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
