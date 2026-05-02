import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../app/router.dart';
import '../providers/ride_payment_method_provider.dart';
import '../providers/ride_payment_provider.dart';
import '../providers/ride_provider.dart';

/// Inserted between ride completion and the receipt when the rider chose
/// in-app payment. Drives the existing Paystack `/payments/initiate` flow
/// against `bookingType: 'ride'`. Cash trips skip this screen entirely.
///
/// Phases:
///   - idle / processing → MoMo phone form + "Pay now" button
///   - awaitingOtp       → OTP entry sheet (Paystack `send_otp`)
///   - awaitingSettlement → "Approve on your phone" + status polling
///   - settled           → auto-advance to /ride-complete (rate sheet → receipt)
///   - failed            → retry CTA + error copy from Paystack
class RidePaymentScreen extends ConsumerStatefulWidget {
  const RidePaymentScreen({super.key, required this.rideId});

  final String rideId;

  @override
  ConsumerState<RidePaymentScreen> createState() => _RidePaymentScreenState();
}

class _RidePaymentScreenState extends ConsumerState<RidePaymentScreen> {
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  String _amountDisplay() {
    final receipt = ref.read(rideReceiptProvider);
    final pesewas = receipt?.totalPaidPesewas ?? 0;
    return 'GHS ${(pesewas / 100).toStringAsFixed(2)}';
  }

  RidePaymentMethod _activeMethod() {
    final receipt = ref.read(rideReceiptProvider);
    return ridePaymentMethodFromWire(receipt?.paymentMethod) ??
        ref.read(selectedRidePaymentMethodProvider);
  }

  @override
  Widget build(BuildContext context) {
    // Auto-advance to the receipt flow once the charge settles.
    ref.listen<RidePaymentState>(ridePaymentNotifierProvider, (prev, next) {
      if (prev?.phase == next.phase) return;
      if (next.phase == RidePaymentPhase.settled) {
        context.go(AppRoutes.rideComplete);
      }
    });

    final state = ref.watch(ridePaymentNotifierProvider);
    final method = _activeMethod();

    return Scaffold(
      backgroundColor: MyShopColors.surfaceWhite,
      appBar: AppBar(
        backgroundColor: MyShopColors.surfaceWhite,
        elevation: 0,
        leading: IconButton(
          icon:
              const Icon(Icons.close_rounded, color: MyShopColors.textPrimary),
          // Pay-later escape hatch: rider can always continue to the
          // receipt; the backend keeps the charge attempt alive and the
          // Activity tab shows it as `pending_payment` so the rider can
          // settle from there.
          onPressed: () => context.go(AppRoutes.rideComplete),
        ),
        title: const Text(
          'Trip Payment',
          style: TextStyle(
            fontFamily: 'Raleway',
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: MyShopColors.textPrimary,
          ),
        ),
        centerTitle: false,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _AmountCard(
                amount: _amountDisplay(),
                methodLabel: method.label,
              ),
              const SizedBox(height: 20),
              _PhaseBody(
                state: state,
                phoneController: _phoneController,
                otpController: _otpController,
                onPay: () {
                  final phone = _phoneController.text.trim();
                  ref.read(ridePaymentNotifierProvider.notifier).initiate(
                        rideId: widget.rideId,
                        paymentMethod: method.wireValue,
                        momoPhone: phone.isEmpty ? null : phone,
                      );
                },
                onSubmitOtp: () {
                  final otp = _otpController.text.trim();
                  if (otp.isEmpty) return;
                  ref.read(ridePaymentNotifierProvider.notifier).submitOtp(otp);
                },
                onCancel: () async {
                  await ref.read(ridePaymentNotifierProvider.notifier).cancel();
                  if (!context.mounted) return;
                  context.go(AppRoutes.rideComplete);
                },
                onRetry: () => ref
                    .read(ridePaymentNotifierProvider.notifier)
                    .resetForRetry(),
                onMarkPaid: () => ref
                    .read(ridePaymentNotifierProvider.notifier)
                    .markSettledLocally(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AmountCard extends StatelessWidget {
  const _AmountCard({required this.amount, required this.methodLabel});

  final String amount;
  final String methodLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: MyShopColors.offWhite,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'AMOUNT DUE',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: MyShopColors.textSecondary,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            amount,
            style: const TextStyle(
              fontFamily: 'Raleway',
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: MyShopColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Charging to $methodLabel',
            style: const TextStyle(
              fontSize: 12,
              color: MyShopColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _PhaseBody extends StatelessWidget {
  const _PhaseBody({
    required this.state,
    required this.phoneController,
    required this.otpController,
    required this.onPay,
    required this.onSubmitOtp,
    required this.onCancel,
    required this.onRetry,
    required this.onMarkPaid,
  });

  final RidePaymentState state;
  final TextEditingController phoneController;
  final TextEditingController otpController;
  final VoidCallback onPay;
  final VoidCallback onSubmitOtp;
  final VoidCallback onCancel;
  final VoidCallback onRetry;
  final VoidCallback onMarkPaid;

  @override
  Widget build(BuildContext context) {
    switch (state.phase) {
      case RidePaymentPhase.idle:
      case RidePaymentPhase.processing:
        return _PhoneForm(
          controller: phoneController,
          isProcessing: state.phase == RidePaymentPhase.processing,
          errorMessage: state.errorMessage,
          onPay: onPay,
        );
      case RidePaymentPhase.awaitingOtp:
        return _OtpForm(
          controller: otpController,
          displayText: state.displayText,
          errorMessage: state.errorMessage,
          onSubmit: onSubmitOtp,
          onCancel: onCancel,
        );
      case RidePaymentPhase.awaitingSettlement:
        return _AwaitingSettlement(
          displayText: state.displayText,
          onMarkPaid: onMarkPaid,
          onCancel: onCancel,
        );
      case RidePaymentPhase.settled:
        // Listener in screen body navigates away — render a brief
        // success state in case there's a frame between phase change
        // and route push.
        return const _Success();
      case RidePaymentPhase.failed:
        return _Failed(
          errorMessage: state.errorMessage,
          onRetry: onRetry,
          onSkip: onCancel,
        );
    }
  }
}

class _PhoneForm extends StatelessWidget {
  const _PhoneForm({
    required this.controller,
    required this.isProcessing,
    required this.errorMessage,
    required this.onPay,
  });

  final TextEditingController controller;
  final bool isProcessing;
  final String? errorMessage;
  final VoidCallback onPay;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Mobile Money number',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: MyShopColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: TextInputType.phone,
          enabled: !isProcessing,
          decoration: InputDecoration(
            hintText: '0244 123 4567',
            filled: true,
            fillColor: MyShopColors.offWhite,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
          ),
        ),
        if (errorMessage != null) ...[
          const SizedBox(height: 10),
          Text(
            errorMessage!,
            style: const TextStyle(
              fontSize: 12,
              color: MyShopColors.error,
            ),
          ),
        ],
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: isProcessing ? null : onPay,
            style: ElevatedButton.styleFrom(
              backgroundColor: MyShopColors.darkSlate,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              elevation: 0,
            ),
            child: isProcessing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Text(
                    'Pay now',
                    style: TextStyle(
                      fontFamily: 'Raleway',
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

class _OtpForm extends StatelessWidget {
  const _OtpForm({
    required this.controller,
    required this.displayText,
    required this.errorMessage,
    required this.onSubmit,
    required this.onCancel,
  });

  final TextEditingController controller;
  final String? displayText;
  final String? errorMessage;
  final VoidCallback onSubmit;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          displayText ??
              "We sent an OTP to your phone. Enter it to confirm the payment.",
          style: const TextStyle(
            fontSize: 13,
            color: MyShopColors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            hintText: 'OTP',
            filled: true,
            fillColor: MyShopColors.offWhite,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
          ),
        ),
        if (errorMessage != null) ...[
          const SizedBox(height: 10),
          Text(
            errorMessage!,
            style: const TextStyle(fontSize: 12, color: MyShopColors.error),
          ),
        ],
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: onSubmit,
            style: ElevatedButton.styleFrom(
              backgroundColor: MyShopColors.darkSlate,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              elevation: 0,
            ),
            child: const Text(
              'Submit OTP',
              style: TextStyle(
                fontFamily: 'Raleway',
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: onCancel,
          child: const Text(
            'Cancel and pay later',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: MyShopColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

class _AwaitingSettlement extends StatelessWidget {
  const _AwaitingSettlement({
    required this.displayText,
    required this.onMarkPaid,
    required this.onCancel,
  });

  final String? displayText;
  final VoidCallback onMarkPaid;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 12),
        const SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
        const SizedBox(height: 18),
        Text(
          displayText ??
              'Approve the prompt on your phone to complete the payment.',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 13,
            color: MyShopColors.textPrimary,
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: OutlinedButton(
            onPressed: onMarkPaid,
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: MyShopColors.divider),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              "I've completed the payment",
              style: TextStyle(
                fontFamily: 'Raleway',
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: MyShopColors.textPrimary,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: onCancel,
          child: const Text(
            'Cancel and pay later',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: MyShopColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

class _Success extends StatelessWidget {
  const _Success();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        Icon(Icons.check_circle, size: 48, color: MyShopColors.success),
        SizedBox(height: 12),
        Text(
          'Payment successful',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: MyShopColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _Failed extends StatelessWidget {
  const _Failed({
    required this.errorMessage,
    required this.onRetry,
    required this.onSkip,
  });

  final String? errorMessage;
  final VoidCallback onRetry;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.error_outline, size: 36, color: MyShopColors.error),
        const SizedBox(height: 8),
        const Text(
          'Payment failed',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: MyShopColors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          errorMessage ?? 'The payment did not go through.',
          style: const TextStyle(
            fontSize: 13,
            color: MyShopColors.textSecondary,
          ),
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: onRetry,
            style: ElevatedButton.styleFrom(
              backgroundColor: MyShopColors.darkSlate,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              elevation: 0,
            ),
            child: const Text(
              'Try again',
              style: TextStyle(
                fontFamily: 'Raleway',
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: onSkip,
          child: const Text(
            'Pay later',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: MyShopColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}
