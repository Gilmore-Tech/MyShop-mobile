import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../core/di/providers.dart';
import '../../auth/providers/current_user_provider.dart';
import '../providers/earnings_providers.dart';
import '../services/cash_commission_remittance_poller.dart';

/// Driver / artisan tap "Pay Commission" → this sheet charges their own
/// MoMo to settle outstanding cash-commission debt.
///
/// Differences from the payout sheet:
///   - No OTP-bind step. The provider is charging an arbitrary MoMo
///     number (usually their own) — no need to verify "they own this
///     wallet" the way a payout target would.
///   - Amount is editable. They can pay any amount > 0; underpayment
///     chips away at oldest clawbacks, overpayment lands as a
///     ProviderCredit that auto-nets the next cash commission.
///   - Single hop: POST /payments/cash-commission/remit → MoMo USSD
///     prompt → done. The success state tells them to authorise the
///     push on their phone; the backend's webhook applies the funds
///     once Paystack confirms.
Future<void> showPayCommissionSheet(
  BuildContext context, {
  required int owedPesewas,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: MyShopColors.surfaceWhite,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _PayCommissionSheet(owedPesewas: owedPesewas),
  );
}

class _PayCommissionSheet extends ConsumerStatefulWidget {
  const _PayCommissionSheet({required this.owedPesewas});

  /// Outstanding debt at the moment the sheet opens — drives the
  /// pre-filled amount and the headline "You owe…" label.
  final int owedPesewas;

  @override
  ConsumerState<_PayCommissionSheet> createState() =>
      _PayCommissionSheetState();
}

enum _Step { enter, working, awaiting, completed, failed, error }

class _PayCommissionSheetState extends ConsumerState<_PayCommissionSheet> {
  _Step _step = _Step.enter;
  String _selectedMethod = 'momo_mtn';
  late final TextEditingController _amountCtl;
  late final TextEditingController _phoneCtl;
  String? _errorMessage;
  String? _displayText;
  int? _surplusPesewas;
  int? _remittedPesewas;
  int? _remainingOwedPesewas;
  String? _gatewayStatus;
  bool _pollTimedOut = false;

  @override
  void initState() {
    super.initState();
    final ghs = widget.owedPesewas / 100.0;
    _amountCtl = TextEditingController(text: ghs.toStringAsFixed(2));
    final phone = ref.read(currentUserProvider)?.phone ?? '';
    _phoneCtl = TextEditingController(text: phone);
  }

  @override
  void dispose() {
    _amountCtl.dispose();
    _phoneCtl.dispose();
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
    final phone = _phoneCtl.text.trim();
    if (phone.length < 9) {
      setState(() => _errorMessage = 'Enter your mobile money number.');
      return;
    }

    setState(() {
      _step = _Step.working;
      _errorMessage = null;
    });

    try {
      final res = await ref
          .read(paymentServiceProvider)
          .remitCashCommission(
            amountPesewas: amount,
            paymentMethod: _selectedMethod,
            momoPhone: phone,
          );
      if (!mounted) return;
      final remitId = res['remitId'];
      if (remitId is! String || remitId.isEmpty) {
        throw const FormatException('Missing commission payment identifier');
      }

      setState(() {
        _step = _Step.awaiting;
        _displayText =
            (res['displayText'] as String?) ??
            'Authorise the prompt on '
                'your phone to complete the payment.';
        _surplusPesewas = (res['surplusPesewas'] as num?)?.toInt() ?? 0;
        _remittedPesewas = amount;
        _pollTimedOut = false;
      });
      unawaited(_monitorRemittance(remitId));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _step = _Step.error;
        _errorMessage = _friendlyError(e);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _step = _Step.error;
        _errorMessage = "Couldn't start the payment. Please try again.";
      });
    }
  }

  Future<void> _monitorRemittance(String remitId) async {
    final result = await const CashCommissionRemittancePoller().waitForTerminal(
      () => ref
          .read(paymentServiceProvider)
          .getCashCommissionRemittanceStatus(remitId),
    );
    if (!mounted) return;

    if (result == null) {
      setState(() => _pollTimedOut = true);
      return;
    }

    _refreshEarnings();
    setState(() {
      _gatewayStatus = result.gatewayStatus;
      _remittedPesewas = result.amountPesewas;
      _remainingOwedPesewas = result.owedPesewas;
      _step = result.isCompleted ? _Step.completed : _Step.failed;
    });
  }

  void _refreshEarnings() {
    ref.invalidate(todayCardProvider);
    ref.invalidate(earningsSummaryProvider);
    ref.invalidate(earningsReportProvider);
  }

  static String _friendlyError(ApiException e) {
    switch (e.errorCode) {
      case 'NO_CASH_COMMISSION_OWED':
        return 'You have no commission owing right now.';
      case 'INVALID_AMOUNT':
        return 'Enter an amount greater than 0.';
      default:
        return userSafeApiErrorMessage(
          e,
          fallback: "Couldn't start the payment. Please try again.",
          conflictMessage:
              'The commission balance changed. Refresh it before trying again.',
        );
    }
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
          'You owe MyShop GHS ${_fmtGhs(widget.owedPesewas)} in commission. '
          'Pay any amount — partial payments chip away at the oldest debt; '
          'overpayments roll into a credit against your next ride.',
          style: MyShopTypography.body2.copyWith(
            color: MyShopColors.textSecondary,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          'AMOUNT (GHS)',
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
            prefixText: 'GHS  ',
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
              'We will keep checking safely in the background.',
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
    final surplus = _surplusPesewas ?? 0;
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
          'GHS ${_fmtGhs(paid)} was applied to your commission account. '
          'Your remaining Owings is GHS ${_fmtGhs(remaining)}.',
          textAlign: TextAlign.center,
          style: MyShopTypography.body2.copyWith(
            color: MyShopColors.textSecondary,
            height: 1.45,
          ),
        ),
        if (surplus > 0) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: MyShopColors.primaryGoldLight,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              'GHS ${_fmtGhs(surplus)} is held as commission credit for '
              'your next cash booking.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: MyShopColors.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
        ],
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
          onPressed: () => setState(() {
            _step = _Step.enter;
            _gatewayStatus = null;
            _pollTimedOut = false;
          }),
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
          onPressed: () => setState(() => _step = _Step.enter),
          style: ElevatedButton.styleFrom(
            backgroundColor: MyShopColors.primaryGold,
            foregroundColor: MyShopColors.textOnPrimary,
            minimumSize: const Size(double.infinity, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
          ),
          child: const Text('TRY AGAIN'),
        ),
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
