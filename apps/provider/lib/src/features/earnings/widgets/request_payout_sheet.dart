import 'dart:async';
import 'dart:math';

import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../core/di/providers.dart';
import '../../auth/providers/auth_controller.dart';
import '../../auth/providers/current_user_provider.dart';
import '../../profile/providers/provider_type_provider.dart';
import '../providers/earnings_providers.dart';

/// Driver / artisan tap "Request Payout" → this sheet handles the whole
/// flow:
///
///   * Already bound (user.payoutMethod + payoutAccountNumber set):
///     confirm + fire `requestPayout` → success screen.
///
///   * Not yet bound: show MoMo network picker + account-number field →
///     request OTP → SMS code entry → verify → kick straight into the
///     payout call. Single-session UX.
///
/// On success the relevant earnings providers (today card, summary,
/// payouts list) are invalidated so the dashboard reflects the new
/// pending payout within one frame.
Future<void> showRequestPayoutSheet(BuildContext context) {
  return _showPayoutSheet(context, mode: _PayoutSheetMode.legacyRequest);
}

Future<void> showWithdrawEarningsSheet(
  BuildContext context, {
  required int expectedWithdrawablePesewas,
}) {
  return _showPayoutSheet(
    context,
    mode: _PayoutSheetMode.withdraw,
    expectedWithdrawablePesewas: expectedWithdrawablePesewas,
  );
}

Future<void> showPayoutMethodSetupSheet(BuildContext context) {
  return _showPayoutSheet(context, mode: _PayoutSheetMode.setupOnly);
}

Future<void> _showPayoutSheet(
  BuildContext context, {
  required _PayoutSheetMode mode,
  int? expectedWithdrawablePesewas,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: MyShopColors.surfaceWhite,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _RequestPayoutSheet(
      mode: mode,
      expectedWithdrawablePesewas: expectedWithdrawablePesewas,
    ),
  );
}

enum _PayoutSheetMode { legacyRequest, withdraw, setupOnly }

class _RequestPayoutSheet extends ConsumerStatefulWidget {
  const _RequestPayoutSheet({
    required this.mode,
    this.expectedWithdrawablePesewas,
  });

  final _PayoutSheetMode mode;
  final int? expectedWithdrawablePesewas;

  @override
  ConsumerState<_RequestPayoutSheet> createState() =>
      _RequestPayoutSheetState();
}

enum _Step { confirm, bindEnter, bindOtp, working, done, error }

class _RequestPayoutSheetState extends ConsumerState<_RequestPayoutSheet> {
  late _Step _step;
  String _selectedMethod = 'momo_mtn';
  final _accountCtl = TextEditingController();
  final _otpCtl = TextEditingController();
  String? _errorMessage;
  String? _successMessage;
  String? _successTitle;
  String? _idempotencyKey;
  ProviderWithdrawalStatus? _withdrawalStatus;
  bool _withdrawalCanRetry = false;

  @override
  void initState() {
    super.initState();
    if (widget.mode == _PayoutSheetMode.setupOnly) {
      _step = _Step.bindEnter;
    } else {
      _step = _hasBoundPayoutMethod() ? _Step.confirm : _Step.bindEnter;
    }
  }

  @override
  void dispose() {
    _accountCtl.dispose();
    _otpCtl.dispose();
    super.dispose();
  }

  bool _hasBoundPayoutMethod() {
    final user = ref.read(currentUserProvider);
    if (user == null) return false;
    final role = ref.read(providerTypeProvider);
    final method = role.isDriver
        ? user.driverProfile?.payoutMethod
        : user.artisanProfile?.payoutMethod;
    final account = role.isDriver
        ? user.driverProfile?.payoutAccountNumber
        : user.artisanProfile?.payoutAccountNumber;
    return (method ?? '').isNotEmpty && (account ?? '').isNotEmpty;
  }

  String? _boundAccountMasked() {
    final user = ref.read(currentUserProvider);
    if (user == null) return null;
    final role = ref.read(providerTypeProvider);
    final account = role.isDriver
        ? user.driverProfile?.payoutAccountNumber
        : user.artisanProfile?.payoutAccountNumber;
    if (account == null || account.length < 4) return account;
    return '••• ${account.substring(account.length - 3)}';
  }

  String _boundMethodLabel() {
    final user = ref.read(currentUserProvider);
    final role = ref.read(providerTypeProvider);
    final method = (role.isDriver
            ? user?.driverProfile?.payoutMethod
            : user?.artisanProfile?.payoutMethod) ??
        '';
    return _methodLabel(method);
  }

  String _methodLabel(String code) {
    switch (code) {
      case 'momo_mtn':
        return 'MTN MoMo';
      case 'momo_telecel':
        return 'Telecel Cash';
      case 'momo_airteltigo':
        return 'AirtelTigo Money';
      default:
        return code;
    }
  }

  // ── Step transitions ───────────────────────────────────────────────

  Future<void> _onRequestOtp() async {
    if (_accountCtl.text.trim().isEmpty) {
      setState(() => _errorMessage = 'Enter the MoMo number.');
      return;
    }
    setState(() {
      _errorMessage = null;
      _withdrawalCanRetry = false;
      _step = _Step.working;
    });
    try {
      await ref.read(paymentServiceProvider).requestPayoutMethodOtp(
            method: _selectedMethod,
            accountNumber: _accountCtl.text.trim(),
          );
      if (!mounted) return;
      setState(() => _step = _Step.bindOtp);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = _payoutMethodOtpError(e, requesting: true);
        _step = _Step.bindEnter;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Could not send the verification code. Try again.';
        _step = _Step.bindEnter;
      });
    }
  }

  Future<void> _onVerifyOtp() async {
    if (_otpCtl.text.trim().length != 6) {
      setState(() => _errorMessage = 'Enter the 6-digit code.');
      return;
    }
    setState(() {
      _errorMessage = null;
      _step = _Step.working;
    });
    try {
      await ref
          .read(paymentServiceProvider)
          .verifyPayoutMethodOtp(code: _otpCtl.text.trim());
      // Refresh the user so the dashboard reads the newly-bound payoutMethod.
      await ref.read(authControllerProvider.notifier).refreshProfile();
      if (!mounted) return;
      if (widget.mode == _PayoutSheetMode.setupOnly ||
          widget.mode == _PayoutSheetMode.withdraw) {
        ref.read(invalidateEarningsCachesProvider)();
        setState(() {
          _successTitle = 'Payout method verified';
          _successMessage = widget.mode == _PayoutSheetMode.withdraw
              ? 'Your balance is being refreshed. Close this sheet, then use WITHDRAW when it is available.'
              : 'Your verified payout destination is ready.';
          _step = _Step.done;
        });
        return;
      }
      await _firePayoutRequest();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = _payoutMethodOtpError(e, requesting: false);
        _step = _Step.bindOtp;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Verification failed. Try again.';
        _step = _Step.bindOtp;
      });
    }
  }

  Future<void> _firePayoutRequest() async {
    setState(() {
      _errorMessage = null;
      _step = _Step.working;
    });
    // Per-attempt idempotency key — replayed if the user backs out and
    // taps Confirm again on the same session, so we never double-disburse.
    _idempotencyKey ??=
        '${widget.mode == _PayoutSheetMode.withdraw ? 'withdraw' : 'payout'}-'
        '${DateTime.now().millisecondsSinceEpoch}-'
        '${Random().nextInt(1 << 30)}';
    try {
      if (widget.mode == _PayoutSheetMode.withdraw) {
        final expected = widget.expectedWithdrawablePesewas;
        if (expected == null ||
            expected < EarningsSummary.requiredMinimumWithdrawalPesewas) {
          throw const ApiException(
            message: 'Withdrawal amount authority is unavailable.',
            errorCode: 'WITHDRAWAL_AUTHORITY_UNAVAILABLE',
          );
        }
        final result =
            await ref.read(paymentServiceProvider).withdrawProviderEarnings(
                  expectedWithdrawablePesewas: expected,
                  idempotencyKey: _idempotencyKey!,
                );
        _withdrawalStatus = result;
        ref.read(refreshEarningsAfterSettlementProvider)();
        if (!mounted) return;
        setState(() {
          _successTitle = result.isTerminal
              ? _withdrawalStatusTitle(result.status)
              : 'Withdrawal request accepted';
          _successMessage = result.isTerminal
              ? _withdrawalStatusMessage(result)
              : _withdrawalAcceptedMessage(result);
          _step = _Step.done;
        });
        if (!result.isTerminal) {
          unawaited(_pollWithdrawalStatus(result.withdrawalId));
        }
        return;
      }

      final user = ref.read(currentUserProvider);
      final role = ref.read(providerTypeProvider);
      final method = (role.isDriver
              ? user?.driverProfile?.payoutMethod
              : user?.artisanProfile?.payoutMethod) ??
          _selectedMethod;
      final result = await ref.read(paymentServiceProvider).requestPayout(
            method: method,
            idempotencyKey: _idempotencyKey,
          );
      if (!isConfirmedQueuedPayoutResponse(result)) {
        throw const ApiException(
          message: 'Payout response did not confirm a queued payout.',
          errorCode: 'PAYOUT_NOT_CONFIRMED',
        );
      }
      ref.read(refreshEarningsAfterSettlementProvider)();
      if (!mounted) return;
      setState(() {
        _successTitle = 'Payout queued';
        _successMessage = 'Payout queued. Funds usually arrive in 2–5 minutes.';
        _step = _Step.done;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      final canRetryWithdrawal = widget.mode == _PayoutSheetMode.withdraw &&
          (e.isNetworkError ||
              e.isServerError ||
              (e.statusCode != null && e.statusCode! >= 500));
      if (widget.mode == _PayoutSheetMode.withdraw && !canRetryWithdrawal) {
        ref.read(invalidateEarningsCachesProvider)();
      }
      setState(() {
        _errorMessage = _payoutRequestError(e);
        _withdrawalCanRetry = canRetryWithdrawal;
        _step = _Step.error;
      });
    } on FormatException {
      if (!mounted) return;
      setState(() {
        _errorMessage = widget.mode == _PayoutSheetMode.withdraw
            ? 'The request may have been accepted, but its status could not be confirmed. Retry safely with the same protected request.'
            : 'The payout response could not be confirmed. Refresh payout history before retrying.';
        _withdrawalCanRetry = widget.mode == _PayoutSheetMode.withdraw;
        _step = _Step.error;
      });
    } catch (_) {
      if (!mounted) return;
      if (widget.mode == _PayoutSheetMode.withdraw) {
        ref.read(invalidateEarningsCachesProvider)();
      }
      setState(() {
        _errorMessage = widget.mode == _PayoutSheetMode.withdraw
            ? 'Could not safely classify the withdrawal result. Close this sheet and refresh earnings before taking another action.'
            : 'Could not request payout. Try again in a moment.';
        _withdrawalCanRetry = false;
        _step = _Step.error;
      });
    }
  }

  Future<void> _pollWithdrawalStatus(String withdrawalId) async {
    const delays = <Duration>[
      Duration(seconds: 2),
      Duration(seconds: 4),
      Duration(seconds: 8),
    ];
    for (final delay in delays) {
      await Future<void>.delayed(delay);
      if (!mounted || _withdrawalStatus?.isTerminal == true) return;
      try {
        final status = await ref
            .read(paymentServiceProvider)
            .getProviderWithdrawalStatus(withdrawalId);
        if (!mounted || status.withdrawalId != withdrawalId) return;
        ref.read(invalidateEarningsCachesProvider)();
        setState(() {
          _withdrawalStatus = status;
          _successTitle = _withdrawalStatusTitle(status.status);
          _successMessage = _withdrawalStatusMessage(status);
        });
        if (status.isTerminal) return;
      } catch (_) {
        // Keep the accepted 202 state visible. The provider can close the
        // sheet and the earnings-updated event/resume refresh remains the
        // authoritative recovery path.
      }
    }
  }

  String _withdrawalAcceptedMessage(ProviderWithdrawalStatus status) {
    final queued = _formatMoney(status.transferQueuedPesewas);
    final deductions = _formatMoney(status.deductionsAppliedPesewas);
    return 'MyShop accepted this request. GH₵ $queued is queued for transfer. '
        'Your balance reflects GH₵ $deductions in applied deductions. '
        'This does not mean the transfer has been paid yet.';
  }

  String _withdrawalStatusTitle(ProviderWithdrawalGroupStatus status) {
    return switch (status) {
      ProviderWithdrawalGroupStatus.completed => 'Withdrawal completed',
      ProviderWithdrawalGroupStatus.partialSuccess =>
        'Withdrawal partly completed',
      ProviderWithdrawalGroupStatus.needsReview => 'Withdrawal needs review',
      ProviderWithdrawalGroupStatus.queued ||
      ProviderWithdrawalGroupStatus.processing =>
        'Withdrawal in progress',
      ProviderWithdrawalGroupStatus.unknown => 'Withdrawal status unavailable',
    };
  }

  String _withdrawalStatusMessage(ProviderWithdrawalStatus status) {
    final queued = _formatMoney(status.transferQueuedPesewas);
    final debt = _formatMoney(status.remainingDebtPesewas);
    return switch (status.status) {
      ProviderWithdrawalGroupStatus.completed =>
        'The withdrawal group completed. Transfer total: GH₵ $queued. Remaining debt: GH₵ $debt.',
      ProviderWithdrawalGroupStatus.partialSuccess =>
        'Some exact payouts completed and others did not. Do not submit another withdrawal; review your payout history.',
      ProviderWithdrawalGroupStatus.needsReview =>
        _withdrawalReviewMessage(status.reviewReason),
      ProviderWithdrawalGroupStatus.queued ||
      ProviderWithdrawalGroupStatus.processing =>
        'The request is still being processed. GH₵ $queued is assigned to the transfer group.',
      ProviderWithdrawalGroupStatus.unknown =>
        'The server returned a status this app does not recognise. Refresh earnings before taking another action.',
    };
  }

  String _withdrawalReviewMessage(ProviderWithdrawalReviewReason reason) {
    return switch (reason) {
      ProviderWithdrawalReviewReason.payoutDestinationReview =>
        'This withdrawal is held because the verified MoMo destination changed or needs review. Check your payout method or contact support.',
      ProviderWithdrawalReviewReason.transferFailed =>
        'The transfer did not complete. Your withdrawal remains held while MyShop verifies a safe retry.',
      ProviderWithdrawalReviewReason.transferReversed =>
        'The transfer was reversed. The amount remains under review and must not be requested again.',
      ProviderWithdrawalReviewReason.withdrawalRecordsReview =>
        'The withdrawal records need reconciliation. The amount remains held while MyShop reviews them.',
      ProviderWithdrawalReviewReason.withdrawalRequiresReview ||
      ProviderWithdrawalReviewReason.none ||
      ProviderWithdrawalReviewReason.unknown =>
        'MyShop is reviewing this withdrawal. The amount remains held; do not submit another request.',
    };
  }

  String _formatMoney(int pesewas) => (pesewas / 100).toStringAsFixed(2);

  String _payoutMethodOtpError(
    ApiException error, {
    required bool requesting,
  }) {
    return switch (error.errorCode) {
      'OTP_INVALID' ||
      'INVALID_OTP' =>
        'The code is incorrect. Check it and try again.',
      'OTP_EXPIRED' => 'The code expired. Request another code.',
      'OTP_ATTEMPTS_EXCEEDED' ||
      'TOO_MANY_OTP_ATTEMPTS' =>
        'Too many incorrect attempts. Request another code.',
      'OTP_DELIVERY_RATE_LIMITED' ||
      'OTP_COOLDOWN' =>
        'Too many code requests. Wait before trying again.',
      'PAYOUT_DESTINATION_LOCKED' =>
        'This payout destination is locked. Contact support to change it.',
      _ => userSafeApiErrorMessage(
          error,
          fallback: requesting
              ? 'Could not send the verification code. Try again.'
              : 'Verification failed. Try again.',
          conflictMessage:
              'The payout destination changed. Refresh it before trying again.',
        ),
    };
  }

  String _payoutRequestError(ApiException error) {
    return switch (error.errorCode) {
      'WITHDRAWABLE_BALANCE_CHANGED' ||
      'STALE_WITHDRAWABLE_BALANCE' =>
        'Your withdrawable balance changed. Close this sheet and refresh earnings before trying again.',
      'WITHDRAWAL_IN_PROGRESS' =>
        'A withdrawal is already in progress. Check payout history before trying again.',
      'WITHDRAWAL_AUTHORITY_UNAVAILABLE' =>
        'This balance is not authorised for withdrawal. Refresh earnings.',
      'RECONCILIATION_REQUIRED' =>
        'This balance needs review before another withdrawal.',
      'AGGREGATE_PAYOUTS_DISABLED' =>
        'Payout requests are temporarily unavailable. Your earnings remain safe.',
      'PAYOUT_DESTINATION_UNVERIFIED' ||
      'PAYOUT_DESTINATION_REQUIRED' ||
      'NO_PAYOUT_METHOD' =>
        'Verify and lock a MoMo payout destination before requesting payout.',
      'PAYOUT_METHOD_MISMATCH' =>
        'The selected payout method no longer matches your verified destination. Refresh and try again.',
      'PAYOUT_IN_PROGRESS' =>
        'A payout is already in progress. Wait for it to complete.',
      'INSUFFICIENT_BALANCE' =>
        'Your available balance is below the payout minimum.',
      'PARTIAL_PAYOUT_NOT_SUPPORTED' =>
        'Only the full available balance can be requested right now.',
      'PAYOUT_NOT_CONFIRMED' =>
        "We couldn't confirm that the payout was queued. Refresh your payout history before retrying.",
      _ => userSafeApiErrorMessage(
          error,
          fallback: 'Could not request payout. Try again in a moment.',
          conflictMessage:
              'The payout state changed. Refresh your earnings before trying again.',
        ),
    };
  }

  // ── Render ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 24 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
          const SizedBox(height: 16),
          ..._buildStep(),
        ],
      ),
    );
  }

  List<Widget> _buildStep() {
    switch (_step) {
      case _Step.confirm:
        return _confirmStep();
      case _Step.bindEnter:
        return _bindEnterStep();
      case _Step.bindOtp:
        return _bindOtpStep();
      case _Step.working:
        return _workingStep();
      case _Step.done:
        return _doneStep();
      case _Step.error:
        return _errorStep();
    }
  }

  List<Widget> _confirmStep() {
    final masked = _boundAccountMasked() ?? '—';
    final method = _boundMethodLabel();
    final isWithdrawal = widget.mode == _PayoutSheetMode.withdraw;
    final expected = widget.expectedWithdrawablePesewas;
    return [
      Text(isWithdrawal ? 'Withdraw earnings' : 'Request Payout',
          style: const TextStyle(
              fontFamily: 'Raleway',
              fontSize: 18,
              fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      Text(
        isWithdrawal
            ? 'Request GH₵ ${_formatMoney(expected ?? 0)} from your current server-confirmed withdrawable balance. MyShop will recheck it before accepting.'
            : 'We\'ll send your available balance to your registered MoMo account.',
        style: MyShopTypography.body2,
      ),
      const SizedBox(height: 20),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: MyShopColors.surfaceGrey,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          const Icon(Icons.account_balance_wallet_outlined,
              color: MyShopColors.primaryGold),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(method,
                    style: const TextStyle(
                        fontFamily: 'Raleway', fontWeight: FontWeight.w700)),
                Text(masked, style: MyShopTypography.body2),
              ],
            ),
          ),
        ]),
      ),
      if (_errorMessage != null) ...[
        const SizedBox(height: 12),
        Text(_errorMessage!,
            style: TextStyle(color: MyShopColors.error, fontSize: 12)),
      ],
      const SizedBox(height: 20),
      MyShopPrimaryButton(
        label: isWithdrawal ? 'CONFIRM WITHDRAWAL' : 'CONFIRM PAYOUT',
        onPressed: _firePayoutRequest,
      ),
      const SizedBox(height: 8),
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
    ];
  }

  List<Widget> _bindEnterStep() {
    return [
      const Text('Link your MoMo for payouts',
          style: TextStyle(
              fontFamily: 'Raleway',
              fontSize: 18,
              fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      Text(
        'We\'ll send a verification code to confirm the number before locking it in. Once verified, only support can change it.',
        style: MyShopTypography.body2,
      ),
      const SizedBox(height: 20),
      DropdownButtonFormField<String>(
        initialValue: _selectedMethod,
        decoration: const InputDecoration(
          labelText: 'MoMo network',
          border: OutlineInputBorder(),
        ),
        items: const [
          DropdownMenuItem(value: 'momo_mtn', child: Text('MTN MoMo')),
          DropdownMenuItem(value: 'momo_telecel', child: Text('Telecel Cash')),
          DropdownMenuItem(
              value: 'momo_airteltigo', child: Text('AirtelTigo Money')),
        ],
        onChanged: (v) =>
            setState(() => _selectedMethod = v ?? _selectedMethod),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _accountCtl,
        keyboardType: TextInputType.phone,
        decoration: const InputDecoration(
          labelText: 'MoMo number',
          hintText: '0241234567',
          border: OutlineInputBorder(),
        ),
      ),
      if (_errorMessage != null) ...[
        const SizedBox(height: 12),
        Text(_errorMessage!,
            style: TextStyle(color: MyShopColors.error, fontSize: 12)),
      ],
      const SizedBox(height: 20),
      MyShopPrimaryButton(
        label: 'SEND CODE',
        onPressed: _onRequestOtp,
      ),
      const SizedBox(height: 8),
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
    ];
  }

  List<Widget> _bindOtpStep() {
    return [
      const Text('Enter verification code',
          style: TextStyle(
              fontFamily: 'Raleway',
              fontSize: 18,
              fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      Text('6-digit code sent to ${_accountCtl.text}',
          style: MyShopTypography.body2),
      const SizedBox(height: 20),
      TextField(
        controller: _otpCtl,
        keyboardType: TextInputType.number,
        maxLength: 6,
        decoration: const InputDecoration(
          labelText: 'OTP',
          counterText: '',
          border: OutlineInputBorder(),
        ),
      ),
      if (_errorMessage != null) ...[
        const SizedBox(height: 12),
        Text(_errorMessage!,
            style: TextStyle(color: MyShopColors.error, fontSize: 12)),
      ],
      const SizedBox(height: 20),
      MyShopPrimaryButton(
        label: widget.mode == _PayoutSheetMode.legacyRequest
            ? 'VERIFY & REQUEST PAYOUT'
            : 'VERIFY PAYOUT METHOD',
        onPressed: _onVerifyOtp,
      ),
      const SizedBox(height: 8),
      TextButton(
        onPressed: () => setState(() {
          _otpCtl.clear();
          _errorMessage = null;
          _step = _Step.bindEnter;
        }),
        child: const Text('Change number'),
      ),
    ];
  }

  List<Widget> _workingStep() {
    return const [
      Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Column(
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('Working…'),
          ],
        ),
      ),
    ];
  }

  List<Widget> _doneStep() {
    final status = _withdrawalStatus?.status;
    final needsAttention =
        status == ProviderWithdrawalGroupStatus.needsReview ||
            status == ProviderWithdrawalGroupStatus.partialSuccess ||
            status == ProviderWithdrawalGroupStatus.unknown;
    return [
      Icon(
        needsAttention ? Icons.info_outline : Icons.check_circle,
        size: 56,
        color: needsAttention ? MyShopColors.primaryGold : MyShopColors.success,
      ),
      const SizedBox(height: 12),
      Text(_successTitle ?? 'Request accepted',
          textAlign: TextAlign.center,
          style: const TextStyle(
              fontFamily: 'Raleway',
              fontSize: 18,
              fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      Text(_successMessage ?? '',
          textAlign: TextAlign.center, style: MyShopTypography.body2),
      const SizedBox(height: 20),
      MyShopPrimaryButton(
        label: 'DONE',
        onPressed: () => Navigator.of(context).pop(),
      ),
    ];
  }

  List<Widget> _errorStep() {
    final closeOnly =
        widget.mode == _PayoutSheetMode.withdraw && !_withdrawalCanRetry;
    return [
      const Icon(Icons.error_outline, size: 56, color: MyShopColors.error),
      const SizedBox(height: 12),
      Text(
          widget.mode == _PayoutSheetMode.withdraw
              ? 'Withdrawal not confirmed'
              : 'Payout failed',
          textAlign: TextAlign.center,
          style: const TextStyle(
              fontFamily: 'Raleway',
              fontSize: 18,
              fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      Text(_errorMessage ?? 'Unknown error',
          textAlign: TextAlign.center, style: MyShopTypography.body2),
      const SizedBox(height: 20),
      MyShopPrimaryButton(
        label: closeOnly ? 'CLOSE' : 'TRY AGAIN',
        onPressed: closeOnly
            ? () => Navigator.of(context).pop()
            : () {
                // Reuse the same idempotency key. A timeout can happen after
                // the backend accepts the group; changing keys here could
                // double-send.
                _firePayoutRequest();
              },
      ),
      if (!closeOnly) ...[
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    ];
  }
}

bool isConfirmedQueuedPayoutResponse(Map<String, dynamic> response) {
  final status = response['status']?.toString();
  final payoutId = response['payoutId']?.toString();
  return (status == 'pending' || status == 'processing' || status == 'paid') &&
      payoutId != null &&
      payoutId.isNotEmpty;
}
