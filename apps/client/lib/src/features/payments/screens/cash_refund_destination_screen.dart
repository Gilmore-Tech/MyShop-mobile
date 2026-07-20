import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../core/di/providers.dart';

class CashRefundDestinationScreen extends ConsumerStatefulWidget {
  const CashRefundDestinationScreen({
    required this.disputeId,
    super.key,
  });

  final String disputeId;

  @override
  ConsumerState<CashRefundDestinationScreen> createState() =>
      _CashRefundDestinationScreenState();
}

class _CashRefundDestinationScreenState
    extends ConsumerState<CashRefundDestinationScreen> {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  String _method = 'momo_mtn';
  String _channel = 'sms';
  bool _loadingStatus = true;
  bool _requesting = false;
  bool _verifying = false;
  bool _codeRequested = false;
  bool _verified = false;
  String? _accountLast4;
  String? _verifiedMethod;
  String? _error;
  int _retryAfterSeconds = 0;
  Timer? _retryTimer;

  static const _methods = <String, String>{
    'momo_mtn': 'MTN MoMo',
    'momo_telecel': 'Telecel Cash',
    'momo_airteltigo': 'AT Money',
  };

  @override
  void initState() {
    super.initState();
    unawaited(_loadStatus());
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _loadStatus() async {
    try {
      final status = await ref
          .read(paymentServiceProvider)
          .getCashRefundDestinationStatus(widget.disputeId);
      if (!mounted) return;
      setState(() {
        _verified = status['verified'] == true;
        _accountLast4 = status['accountLast4'] as String?;
        _verifiedMethod = status['method'] as String?;
        _error = null;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = _messageFor(error));
    } finally {
      if (mounted) setState(() => _loadingStatus = false);
    }
  }

  String get _normalizedPhone =>
      _phoneController.text.replaceAll(RegExp(r'[\s\-()]'), '');

  bool get _validPhone =>
      RegExp(r'^(\+233|0)\d{9}$').hasMatch(_normalizedPhone);

  Future<void> _requestCode() async {
    if (_requesting || _retryAfterSeconds > 0) return;
    if (!_validPhone) {
      setState(() => _error = 'Enter a valid Ghana MoMo number.');
      return;
    }
    setState(() {
      _requesting = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(paymentServiceProvider)
          .requestCashRefundDestinationOtp(
            disputeId: widget.disputeId,
            method: _method,
            accountNumber: _normalizedPhone,
            channel: _channel,
          );
      if (!mounted) return;
      setState(() {
        _codeRequested = true;
        _retryAfterSeconds =
            (result['retryAfterSeconds'] as num?)?.toInt() ?? 60;
      });
      _startRetryTimer();
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = _messageFor(error));
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  void _startRetryTimer() {
    _retryTimer?.cancel();
    _retryTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_retryAfterSeconds <= 1) {
        timer.cancel();
        setState(() => _retryAfterSeconds = 0);
      } else {
        setState(() => _retryAfterSeconds--);
      }
    });
  }

  void _changeDestination() {
    _retryTimer?.cancel();
    setState(() {
      _codeRequested = false;
      _codeController.clear();
      _retryAfterSeconds = 0;
      _error = null;
    });
  }

  Future<void> _verifyCode() async {
    if (_verifying) return;
    final code = _codeController.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() => _error = 'Enter the 6-digit code we sent.');
      return;
    }
    setState(() {
      _verifying = true;
      _error = null;
    });
    try {
      final status =
          await ref.read(paymentServiceProvider).verifyCashRefundDestinationOtp(
                disputeId: widget.disputeId,
                code: code,
              );
      if (!mounted) return;
      _retryTimer?.cancel();
      setState(() {
        _verified = status['verified'] == true;
        _accountLast4 = status['accountLast4'] as String?;
        _verifiedMethod = status['method'] as String?;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = _messageFor(error));
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  String _messageFor(ApiException error) {
    return switch (error.errorCode) {
      'OTP_INVALID' => 'The code is incorrect. Check it and try again.',
      'OTP_EXPIRED' => 'The code expired. Request another code.',
      'OTP_ATTEMPTS_EXCEEDED' =>
        'Too many incorrect attempts. Request another code.',
      'NO_PENDING_REFUND_DESTINATION_OTP' =>
        'Request a new code before verifying.',
      'REFUND_DESTINATION_REJECTED' =>
        'The number and network did not match. Check both and try again.',
      'REFUND_DESTINATION_NETWORK_UNAVAILABLE' =>
        'The MoMo network could not verify this number. Try again shortly.',
      'REFUND_DESTINATION_LOCKED' =>
        'Refund processing has started, so this destination can no longer be changed.',
      'OTP_DELIVERY_RATE_LIMITED' =>
        'Too many code requests. Wait before trying again.',
      _ => userSafeApiErrorMessage(
          error,
          fallback:
              "We couldn't verify the refund destination. Please try again.",
          conflictMessage:
              'The refund state changed. Refresh it before trying again.',
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return Scaffold(
      backgroundColor: MyShopColors.offWhite,
      appBar: AppBar(
        backgroundColor: MyShopColors.surfaceWhite,
        title: const Text('Refund MoMo destination'),
      ),
      body: _loadingStatus
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(width * 0.05),
                child: _verified ? _buildVerified(width) : _buildForm(width),
              ),
            ),
    );
  }

  Widget _buildVerified(double width) {
    final label = _methods[_verifiedMethod] ?? 'MoMo';
    return Column(
      children: [
        const SizedBox(height: 48),
        const Icon(
          Icons.verified_rounded,
          color: MyShopColors.success,
          size: 72,
        ),
        const SizedBox(height: 20),
        Text(
          'Refund destination verified',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: MyShopColors.textPrimary,
            fontSize: width * 0.052,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '$label •••• ${_accountLast4 ?? '----'}',
          style: TextStyle(
            color: MyShopColors.textSecondary,
            fontSize: width * 0.04,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'If your dispute is approved, the refund will be sent only to this verified destination.',
          textAlign: TextAlign.center,
          style: TextStyle(color: MyShopColors.textSecondary, height: 1.5),
        ),
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => context.pop(true),
            child: const Text('Done'),
          ),
        ),
      ],
    );
  }

  Widget _buildForm(double width) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: MyShopColors.primaryGold.withAlpha(18),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Text(
            'This booking was paid in cash. Enter where a digital refund should be sent. We will never send money until this number is OTP-verified.',
            style: TextStyle(color: MyShopColors.textPrimary, height: 1.45),
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'MoMo network',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: _method,
          items: _methods.entries
              .map(
                (entry) => DropdownMenuItem(
                  value: entry.key,
                  child: Text(entry.value),
                ),
              )
              .toList(),
          onChanged: _codeRequested
              ? null
              : (value) => setState(() => _method = value ?? _method),
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        const SizedBox(height: 18),
        const Text(
          'MoMo number',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _phoneController,
          enabled: !_codeRequested,
          keyboardType: TextInputType.phone,
          autofillHints: const [AutofillHints.telephoneNumber],
          inputFormatters: [LengthLimitingTextInputFormatter(13)],
          decoration: const InputDecoration(
            hintText: '0241234567',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          'Send code by',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          children: [
            ChoiceChip(
              label: const Text('SMS'),
              selected: _channel == 'sms',
              onSelected: (_) => setState(() => _channel = 'sms'),
            ),
            ChoiceChip(
              label: const Text('WhatsApp'),
              selected: _channel == 'whatsapp',
              onSelected: (_) => setState(() => _channel = 'whatsapp'),
            ),
          ],
        ),
        if (_codeRequested) ...[
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Verification code',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              TextButton(
                onPressed: _changeDestination,
                child: const Text('Change number'),
              ),
            ],
          ),
          TextField(
            controller: _codeController,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            onSubmitted: (_) => _verifyCode(),
            decoration: const InputDecoration(
              hintText: '6-digit code',
              border: OutlineInputBorder(),
            ),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 14),
          Text(
            _error!,
            style: const TextStyle(color: MyShopColors.error),
          ),
        ],
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _codeRequested
                ? (_verifying ? null : _verifyCode)
                : (_requesting ? null : _requestCode),
            child: _requesting || _verifying
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(_codeRequested ? 'Verify destination' : 'Send code'),
          ),
        ),
        if (_codeRequested) ...[
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed:
                  _retryAfterSeconds == 0 && !_requesting ? _requestCode : null,
              child: Text(
                _retryAfterSeconds > 0
                    ? 'Resend in ${_retryAfterSeconds}s'
                    : 'Resend via ${_channel == 'sms' ? 'SMS' : 'WhatsApp'}',
              ),
            ),
          ),
        ],
      ],
    );
  }
}
