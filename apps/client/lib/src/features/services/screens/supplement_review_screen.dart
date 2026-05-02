import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';

// ── Screen ─────────────────────────────────────────────────────────────────────
// PRD § 4.5.3 — Artisan requests additional materials/cost mid-job.
// Client has the option to approve or decline the supplement.
// EDD: PATCH /v1/jobs/:id/supplement/respond  { approved: bool }

class SupplementReviewScreen extends ConsumerStatefulWidget {
  const SupplementReviewScreen({super.key});

  @override
  ConsumerState<SupplementReviewScreen> createState() =>
      _SupplementReviewScreenState();
}

class _SupplementReviewScreenState
    extends ConsumerState<SupplementReviewScreen> {
  bool _isApproving = false;
  bool _isDeclining = false;

  bool get _isBusy => _isApproving || _isDeclining;

  Future<void> _approve(String jobId) async {
    if (_isBusy) return;
    setState(() => _isApproving = true);
    // TODO: PATCH /v1/jobs/:id/supplement/respond { approved: true }
    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    setState(() => _isApproving = false);
    context.go(AppRoutes.jobActivePath(jobId));
  }

  Future<void> _decline(String jobId) async {
    if (_isBusy) return;
    setState(() => _isDeclining = true);
    // TODO: PATCH /v1/jobs/:id/supplement/respond { approved: false }
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    setState(() => _isDeclining = false);
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final w = size.width;
    final h = size.height;
    final bot = MediaQuery.paddingOf(context).bottom;
    final jobId = GoRouterState.of(context).pathParameters['jobId'] ?? '';

    return Scaffold(
      backgroundColor: MyShopColors.offWhite,
      appBar: AppBar(
        backgroundColor: MyShopColors.surfaceWhite,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: MyShopColors.textPrimary),
          onPressed: () => context.pop(),
        ),
        title: Text('Supplement Request',
            style: TextStyle(
                color: MyShopColors.textPrimary,
                fontSize: w * 0.044,
                fontWeight: FontWeight.w700)),
        centerTitle: false,
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(w * 0.05),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _AlertBanner(w: w),
                  SizedBox(height: h * 0.022),
                  _ArtisanRow(w: w),
                  SizedBox(height: h * 0.022),
                  _SupplementCard(w: w, h: h),
                  SizedBox(height: h * 0.022),
                  _CostBreakdown(w: w, h: h),
                  SizedBox(height: h * 0.016),
                  _PolicyNote(w: w),
                ],
              ),
            ),
          ),
          _ActionBar(
            onApprove: () => _approve(jobId),
            onDecline: () => _decline(jobId),
            isApproving: _isApproving,
            isDeclining: _isDeclining,
            w: w,
            h: h,
            bot: bot,
          ),
        ],
      ),
    );
  }
}

// ── Alert banner ───────────────────────────────────────────────────────────────

class _AlertBanner extends StatelessWidget {
  final double w;
  const _AlertBanner({required this.w});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(w * 0.04),
      decoration: BoxDecoration(
        color: MyShopColors.warningLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MyShopColors.warning.withAlpha(80)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded,
              color: MyShopColors.warning, size: 20),
          SizedBox(width: w * 0.030),
          Expanded(
            child: Text(
              'Your artisan has paused work and is requesting additional materials. '
              'Review the request below and approve or decline.',
              style: TextStyle(
                  color: MyShopColors.warning,
                  fontSize: w * 0.033,
                  height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Artisan row ────────────────────────────────────────────────────────────────

class _ArtisanRow extends StatelessWidget {
  final double w;
  const _ArtisanRow({required this.w});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(w * 0.04),
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withAlpha(8),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: w * 0.13,
            height: w * 0.13,
            decoration: const BoxDecoration(
                color: Color(0xFF37474F), shape: BoxShape.circle),
            child: Icon(Icons.person_rounded,
                color: Colors.white, size: w * 0.065),
          ),
          SizedBox(width: w * 0.036),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Kofi Mensah',
                    style: TextStyle(
                      color: MyShopColors.textPrimary,
                      fontSize: w * 0.040,
                      fontWeight: FontWeight.w700,
                    )),
                const SizedBox(height: 3),
                Text('Master Electrician',
                    style: TextStyle(
                        color: MyShopColors.textSecondary,
                        fontSize: w * 0.033)),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.symmetric(horizontal: w * 0.020, vertical: 4),
            decoration: BoxDecoration(
              color: MyShopColors.successLight,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.verified_rounded,
                    color: MyShopColors.success, size: 13),
                const SizedBox(width: 3),
                Text('Verified',
                    style: TextStyle(
                      color: MyShopColors.success,
                      fontSize: w * 0.028,
                      fontWeight: FontWeight.w600,
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Supplement card ────────────────────────────────────────────────────────────

class _SupplementCard extends StatelessWidget {
  final double w, h;
  const _SupplementCard({required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(w * 0.04),
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MyShopColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(w * 0.022),
                decoration: BoxDecoration(
                  color: MyShopColors.warningLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.add_shopping_cart_rounded,
                    color: MyShopColors.warning, size: w * 0.050),
              ),
              SizedBox(width: w * 0.030),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Materials Request',
                        style: TextStyle(
                          color: MyShopColors.textPrimary,
                          fontSize: w * 0.038,
                          fontWeight: FontWeight.w700,
                        )),
                    const SizedBox(height: 2),
                    Text('Submitted 5 minutes ago',
                        style: TextStyle(
                            color: MyShopColors.textSecondary,
                            fontSize: w * 0.030)),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: h * 0.016),
          const Divider(height: 1, color: MyShopColors.divider),
          SizedBox(height: h * 0.016),
          Text('Reason for request',
              style: TextStyle(
                color: MyShopColors.textSecondary,
                fontSize: w * 0.030,
                fontWeight: FontWeight.w600,
              )),
          SizedBox(height: h * 0.008),
          Text(
            'The circuit breaker panel requires a 40A double-pole breaker '
            'that wasn\'t included in the original estimate. This is needed '
            'to safely complete the repair.',
            style: TextStyle(
                color: MyShopColors.textPrimary,
                fontSize: w * 0.035,
                height: 1.6),
          ),
          SizedBox(height: h * 0.016),
          Container(
            padding: EdgeInsets.all(w * 0.036),
            decoration: BoxDecoration(
              color: MyShopColors.primaryGoldLight,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: MyShopColors.primaryGold.withAlpha(60)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Additional Cost',
                    style: TextStyle(
                        color: MyShopColors.textSecondary,
                        fontSize: w * 0.033)),
                Text('GHS 45.00',
                    style: TextStyle(
                      color: MyShopColors.textPrimary,
                      fontSize: w * 0.042,
                      fontWeight: FontWeight.w800,
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Cost breakdown ─────────────────────────────────────────────────────────────

class _CostBreakdown extends StatelessWidget {
  final double w, h;
  const _CostBreakdown({required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(w * 0.04),
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MyShopColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Updated Cost Summary',
              style: TextStyle(
                color: MyShopColors.textPrimary,
                fontSize: w * 0.036,
                fontWeight: FontWeight.w700,
              )),
          SizedBox(height: h * 0.016),
          _CostRow(label: 'Original Bid', value: 'GHS 235.00', w: w),
          SizedBox(height: h * 0.010),
          _CostRow(
              label: 'Supplement',
              value: '+ GHS 45.00',
              valueColor: MyShopColors.warning,
              w: w),
          SizedBox(height: h * 0.012),
          const Divider(height: 1, color: MyShopColors.divider),
          SizedBox(height: h * 0.012),
          _CostRow(
            label: 'New Total',
            value: 'GHS 280.00',
            valueColor: MyShopColors.textPrimary,
            bold: true,
            w: w,
          ),
        ],
      ),
    );
  }
}

class _CostRow extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;
  final bool bold;
  final double w;

  const _CostRow({
    required this.label,
    required this.value,
    this.valueColor = MyShopColors.textSecondary,
    this.bold = false,
    required this.w,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: TextStyle(
              color:
                  bold ? MyShopColors.textPrimary : MyShopColors.textSecondary,
              fontSize: w * 0.034,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
            )),
        Text(value,
            style: TextStyle(
              color: valueColor,
              fontSize: bold ? w * 0.040 : w * 0.034,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
            )),
      ],
    );
  }
}

// ── Policy note ────────────────────────────────────────────────────────────────

class _PolicyNote extends StatelessWidget {
  final double w;
  const _PolicyNote({required this.w});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.lock_outline_rounded,
            color: MyShopColors.success, size: 16),
        SizedBox(width: w * 0.020),
        Expanded(
          child: Text(
            'If approved, the additional amount will be added to the escrow '
            'and released to the artisan after you confirm job completion.',
            style: TextStyle(
                color: MyShopColors.textSecondary,
                fontSize: w * 0.030,
                height: 1.5),
          ),
        ),
      ],
    );
  }
}

// ── Action bar ─────────────────────────────────────────────────────────────────

class _ActionBar extends StatelessWidget {
  final VoidCallback onApprove;
  final VoidCallback onDecline;
  final bool isApproving;
  final bool isDeclining;
  final double w, h, bot;

  const _ActionBar({
    required this.onApprove,
    required this.onDecline,
    required this.isApproving,
    required this.isDeclining,
    required this.w,
    required this.h,
    required this.bot,
  });

  @override
  Widget build(BuildContext context) {
    final busy = isApproving || isDeclining;
    return Container(
      color: MyShopColors.surfaceWhite,
      padding:
          EdgeInsets.fromLTRB(w * 0.05, h * 0.016, w * 0.05, bot + h * 0.020),
      child: Row(
        children: [
          // Decline
          SizedBox(
            height: h * 0.062,
            child: OutlinedButton(
              onPressed: busy ? null : onDecline,
              style: OutlinedButton.styleFrom(
                foregroundColor: MyShopColors.error,
                side: const BorderSide(color: MyShopColors.error),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                padding: EdgeInsets.symmetric(horizontal: w * 0.06),
              ),
              child: isDeclining
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          color: MyShopColors.error, strokeWidth: 2))
                  : Text('Decline',
                      style: TextStyle(
                          fontSize: w * 0.038, fontWeight: FontWeight.w600)),
            ),
          ),
          SizedBox(width: w * 0.030),
          // Approve
          Expanded(
            child: SizedBox(
              height: h * 0.062,
              child: ElevatedButton(
                onPressed: busy ? null : onApprove,
                style: ElevatedButton.styleFrom(
                  backgroundColor: MyShopColors.primaryGold,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor:
                      MyShopColors.primaryGold.withAlpha(120),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
                child: isApproving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2.5))
                    : Text('Approve  GHS 45.00',
                        style: TextStyle(
                          fontSize: w * 0.038,
                          fontWeight: FontWeight.w700,
                        )),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
