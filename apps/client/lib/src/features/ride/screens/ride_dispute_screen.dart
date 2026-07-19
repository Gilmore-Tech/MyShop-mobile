import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/di/providers.dart';

// ── Screen ─────────────────────────────────────────────────────────────────────
// Client disputes a ride fare within 24 hours of ride.completedAt.
// Admin reviews GPS trail vs optimal Google Maps route.
// EDD: POST /v1/rides/:id/dispute

class RideDisputeScreen extends ConsumerStatefulWidget {
  const RideDisputeScreen({required this.rideId, super.key});

  final String rideId;

  @override
  ConsumerState<RideDisputeScreen> createState() => _RideDisputeScreenState();
}

class _RideDisputeScreenState extends ConsumerState<RideDisputeScreen> {
  final _detailsController = TextEditingController();
  String? _selectedReason;
  bool _isSubmitting = false;
  bool _submitted = false;
  bool _refundDestinationRequired = false;
  bool _refundDestinationVerified = false;
  String? _disputeId;
  String? _error;

  static const _reasons = [
    'Route was longer than expected',
    'Driver took an unnecessary detour',
    'Fare was higher than the estimate shown',
    'I was charged for a trip I didn\'t take',
    'Other',
  ];

  bool get _canSubmit =>
      _selectedReason != null &&
      (_selectedReason != 'Other' ||
          _detailsController.text.trim().length >= 10);

  @override
  void dispose() {
    _detailsController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_canSubmit || _isSubmitting) return;
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    final selectedReason = _selectedReason!;
    final details = _detailsController.text.trim();
    try {
      final result = await ref.read(rideServiceProvider).disputeRide(
            widget.rideId,
            reason: selectedReason == 'Other' ? details : selectedReason,
            details: selectedReason != 'Other' && details.isNotEmpty
                ? details
                : null,
          );
      if (!mounted) return;
      final disputeId = result['disputeId'] as String?;
      final destinationRequired = result['refundDestinationRequired'] == true;
      setState(() {
        _submitted = true;
        _disputeId = disputeId;
        _refundDestinationRequired = destinationRequired;
      });
      if (destinationRequired && disputeId != null && mounted) {
        final verified = await context.push<bool>(
          AppRoutes.cashRefundDestinationPath(disputeId),
        );
        if (mounted && verified == true) {
          setState(() => _refundDestinationVerified = true);
        }
      }
    } on ApiException catch (error) {
      if (!mounted) return;
      if (await _resumeExistingDispute(error)) return;
      setState(() => _error = _disputeErrorMessage(error));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<bool> _resumeExistingDispute(ApiException error) async {
    if (error.errorCode != 'DISPUTE_ALREADY_OPEN') return false;
    final disputeId = error.details?['disputeId'];
    if (disputeId is! String || disputeId.isEmpty) return false;
    final destinationRequired =
        error.details?['refundDestinationRequired'] == true;
    setState(() {
      _submitted = true;
      _disputeId = disputeId;
      _refundDestinationRequired = destinationRequired;
      _error = null;
    });
    if (destinationRequired && mounted) {
      final verified = await context.push<bool>(
        AppRoutes.cashRefundDestinationPath(disputeId),
      );
      if (mounted && verified == true) {
        setState(() => _refundDestinationVerified = true);
      }
    }
    return true;
  }

  Future<void> _verifyRefundDestination() async {
    final disputeId = _disputeId;
    if (disputeId == null) return;
    final verified = await context.push<bool>(
      AppRoutes.cashRefundDestinationPath(disputeId),
    );
    if (mounted && verified == true) {
      setState(() => _refundDestinationVerified = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final w = size.width;
    final h = size.height;
    final bot = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: MyShopColors.offWhite,
      appBar: AppBar(
        backgroundColor: MyShopColors.surfaceWhite,
        leading: IconButton(
          icon:
              const Icon(Icons.close_rounded, color: MyShopColors.textPrimary),
          onPressed: () => context.pop(),
        ),
        title: Text('Dispute Ride Fare',
            style: TextStyle(
                color: MyShopColors.textPrimary,
                fontSize: w * 0.044,
                fontWeight: FontWeight.w700)),
        centerTitle: false,
      ),
      body: _submitted
          ? _SuccessBody(
              w: w,
              h: h,
              onDone: () => context.pop(),
              refundDestinationRequired: _refundDestinationRequired,
              refundDestinationVerified: _refundDestinationVerified,
              onVerifyRefundDestination: _verifyRefundDestination,
            )
          : Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(w * 0.05),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _InfoBanner(w: w, h: h),
                        SizedBox(height: h * 0.028),
                        _SectionTitle(text: 'What\'s the issue?', w: w),
                        SizedBox(height: h * 0.016),
                        ..._reasons.map((r) => _ReasonTile(
                              reason: r,
                              isSelected: _selectedReason == r,
                              onTap: () => setState(() {
                                _selectedReason = r;
                              }),
                              w: w,
                              h: h,
                            )),
                        SizedBox(height: h * 0.024),
                        _SectionTitle(
                            text: 'Additional details'
                                '${_selectedReason == 'Other' ? ' (required)' : ' (optional)'}',
                            w: w),
                        SizedBox(height: h * 0.012),
                        _DetailsField(
                            controller: _detailsController,
                            onChanged: (_) => setState(() {}),
                            w: w,
                            h: h),
                        SizedBox(height: h * 0.016),
                        _PolicyNote(w: w),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                      w * 0.05, 0, w * 0.05, bot + h * 0.028),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_error != null) ...[
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: MyShopColors.error),
                        ),
                        const SizedBox(height: 10),
                      ],
                      _SubmitButton(
                        enabled: _canSubmit,
                        loading: _isSubmitting,
                        onTap: _submit,
                        w: w,
                        h: h,
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

// ── Info banner ────────────────────────────────────────────────────────────────

class _InfoBanner extends StatelessWidget {
  final double w, h;
  const _InfoBanner({required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(w * 0.04),
      decoration: BoxDecoration(
        color: MyShopColors.errorLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MyShopColors.error.withAlpha(60)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded,
              color: MyShopColors.error, size: 20),
          SizedBox(width: w * 0.030),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    'Disputes must be raised within 24 hours of ride completion.',
                    style: TextStyle(
                      color: MyShopColors.error,
                      fontSize: w * 0.034,
                      fontWeight: FontWeight.w600,
                    )),
                SizedBox(height: 4),
                Text(
                    'Our team reviews GPS data against the optimal route and will respond within 24 hours.',
                    style: TextStyle(
                        color: MyShopColors.error.withAlpha(180),
                        fontSize: w * 0.030,
                        height: 1.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Reason tile ────────────────────────────────────────────────────────────────

class _ReasonTile extends StatelessWidget {
  final String reason;
  final bool isSelected;
  final VoidCallback onTap;
  final double w, h;

  const _ReasonTile({
    required this.reason,
    required this.isSelected,
    required this.onTap,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: EdgeInsets.only(bottom: h * 0.010),
        padding:
            EdgeInsets.symmetric(horizontal: w * 0.04, vertical: h * 0.018),
        decoration: BoxDecoration(
          color: isSelected
              ? MyShopColors.primaryGold.withAlpha(16)
              : MyShopColors.surfaceWhite,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color:
                  isSelected ? MyShopColors.primaryGold : MyShopColors.divider,
              width: isSelected ? 1.5 : 1),
        ),
        child: Row(
          children: [
            Container(
              width: w * 0.052,
              height: w * 0.052,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected
                    ? MyShopColors.primaryGold
                    : MyShopColors.surfaceGrey,
                border: Border.all(
                    color: isSelected
                        ? MyShopColors.primaryGold
                        : MyShopColors.divider),
              ),
              child: isSelected
                  ? const Icon(Icons.check_rounded,
                      color: Colors.white, size: 14)
                  : null,
            ),
            SizedBox(width: w * 0.032),
            Expanded(
              child: Text(reason,
                  style: TextStyle(
                    color: MyShopColors.textPrimary,
                    fontSize: w * 0.036,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  )),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Details field ──────────────────────────────────────────────────────────────

class _DetailsField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final double w, h;

  const _DetailsField({
    required this.controller,
    required this.onChanged,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MyShopColors.divider),
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        maxLines: 5,
        minLines: 4,
        style: TextStyle(color: MyShopColors.textPrimary, fontSize: w * 0.036),
        decoration: InputDecoration(
          hintText: 'Describe the issue in detail…',
          hintStyle: TextStyle(
              color: MyShopColors.textSecondary.withAlpha(120),
              fontSize: w * 0.034),
          contentPadding: EdgeInsets.all(w * 0.04),
          border: InputBorder.none,
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  final double w;
  const _SectionTitle({required this.text, required this.w});

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: TextStyle(
          color: MyShopColors.textPrimary,
          fontSize: w * 0.038,
          fontWeight: FontWeight.w700,
        ));
  }
}

class _PolicyNote extends StatelessWidget {
  final double w;
  const _PolicyNote({required this.w});

  @override
  Widget build(BuildContext context) {
    return Text(
      'Our team will compare the recorded route with the expected route when reviewing your dispute.',
      style: TextStyle(
          color: MyShopColors.textSecondary, fontSize: w * 0.030, height: 1.6),
    );
  }
}

// ── Submit button ──────────────────────────────────────────────────────────────

class _SubmitButton extends StatelessWidget {
  final bool enabled;
  final bool loading;
  final VoidCallback onTap;
  final double w, h;

  const _SubmitButton({
    required this.enabled,
    required this.loading,
    required this.onTap,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: enabled ? 1.0 : 0.45,
      duration: const Duration(milliseconds: 200),
      child: SizedBox(
        width: double.infinity,
        height: h * 0.066,
        child: Material(
          color: MyShopColors.error,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.circular(12),
            child: Center(
              child: loading
                  ? SizedBox(
                      width: w * 0.052,
                      height: w * 0.052,
                      child: const CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.5))
                  : Text('Submit Dispute',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: w * 0.042,
                        fontWeight: FontWeight.w700,
                      )),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Success state ──────────────────────────────────────────────────────────────

class _SuccessBody extends StatelessWidget {
  final double w, h;
  final VoidCallback onDone;
  final bool refundDestinationRequired;
  final bool refundDestinationVerified;
  final VoidCallback onVerifyRefundDestination;
  const _SuccessBody({
    required this.w,
    required this.h,
    required this.onDone,
    required this.refundDestinationRequired,
    required this.refundDestinationVerified,
    required this.onVerifyRefundDestination,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(w * 0.08),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: w * 0.22,
            height: w * 0.22,
            decoration: const BoxDecoration(
              color: MyShopColors.successLight,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_circle_outline_rounded,
                color: MyShopColors.success, size: 56),
          ),
          SizedBox(height: h * 0.032),
          Text('Dispute submitted',
              style: TextStyle(
                color: MyShopColors.textPrimary,
                fontSize: w * 0.056,
                fontWeight: FontWeight.w800,
              )),
          SizedBox(height: h * 0.012),
          Text(
            'Our team will review the GPS data. You\'ll be notified via the app after the review.',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: MyShopColors.textSecondary,
                fontSize: w * 0.036,
                height: 1.6),
          ),
          if (refundDestinationRequired) ...[
            SizedBox(height: h * 0.024),
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(w * 0.04),
              decoration: BoxDecoration(
                color: refundDestinationVerified
                    ? MyShopColors.successLight
                    : MyShopColors.primaryGold.withAlpha(20),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Text(
                    refundDestinationVerified
                        ? 'Refund MoMo destination verified'
                        : 'Refund MoMo verification required',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  if (!refundDestinationVerified) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'Because this ride was paid in cash, verify where any approved digital refund should be sent.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: onVerifyRefundDestination,
                      child: const Text('Verify refund MoMo'),
                    ),
                  ],
                ],
              ),
            ),
          ],
          SizedBox(height: h * 0.048),
          SizedBox(
            width: double.infinity,
            height: h * 0.066,
            child: ElevatedButton(
              onPressed: onDone,
              style: ElevatedButton.styleFrom(
                backgroundColor: MyShopColors.primaryGold,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: Text('Back to Activity',
                  style: TextStyle(
                      fontSize: w * 0.042, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}

String _disputeErrorMessage(ApiException error) {
  return switch (error.errorCode) {
    'DISPUTE_WINDOW_EXPIRED' =>
      'The 24-hour dispute window for this ride has ended.',
    'DISPUTE_ALREADY_OPEN' =>
      'A dispute has already been submitted for this ride.',
    'PAYMENT_NOT_READY' ||
    'PAYMENT_NOT_SETTLED' =>
      'The ride payment is still being confirmed. Please try again shortly.',
    'RIDE_NOT_COMPLETED' => 'This ride is not marked complete yet.',
    'NOT_YOUR_RIDE' => 'This ride does not belong to this client account.',
    _ => userSafeApiErrorMessage(
        error,
        fallback: "Couldn't submit the dispute. Please try again.",
        conflictMessage:
            'The ride or dispute state changed. Refresh and try again.',
      ),
  };
}
