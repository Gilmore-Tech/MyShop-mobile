import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../providers/active_job_provider.dart';

// ── Screen ─────────────────────────────────────────────────────────────────────
// PRD § 4.5.3 — Artisan requests additional materials/cost mid-job.
// Client has the option to approve or decline the supplement.
// EDD: PATCH /v1/jobs/:id/supplement/respond  { approved: bool }

class SupplementReviewScreen extends ConsumerWidget {
  const SupplementReviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final size = MediaQuery.sizeOf(context);
    final w = size.width;
    final h = size.height;
    final bot = MediaQuery.paddingOf(context).bottom;
    final jobId = GoRouterState.of(context).pathParameters['jobId'] ?? '';

    final jobAsync = ref.watch(activeJobProvider(jobId));
    final response = ref.watch(supplementResponseProvider);

    // Surface server-side errors as a snackbar so the user can retry without
    // losing context. Approve/decline both clear themselves on the next
    // response, so duplicates are safe.
    ref.listen<SupplementResponseState>(supplementResponseProvider,
        (prev, next) {
      if (next.errorMessage != null && next.errorMessage != prev?.errorMessage) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(next.errorMessage!)));
      }
    });

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
      body: jobAsync.when(
        loading: () => _LoadingSkeleton(w: w, h: h),
        error: (_, __) => _ErrorState(
          onRetry: () => ref.invalidate(activeJobProvider(jobId)),
        ),
        data: (job) {
          final supplement = job.pendingSupplement;
          if (supplement == null) {
            return _NoSupplementState(onBack: () => context.pop());
          }
          return Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(w * 0.05),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _AlertBanner(w: w),
                      SizedBox(height: h * 0.022),
                      _ArtisanRow(w: w, artisan: job.artisan),
                      SizedBox(height: h * 0.022),
                      _SupplementCard(
                          w: w, h: h, supplement: supplement),
                      SizedBox(height: h * 0.022),
                      _CostBreakdown(w: w, h: h, supplement: supplement),
                      SizedBox(height: h * 0.016),
                      _PolicyNote(w: w),
                    ],
                  ),
                ),
              ),
              _ActionBar(
                onApprove: () => _respond(
                  context,
                  ref,
                  jobId: jobId,
                  approve: true,
                ),
                onDecline: () => _respond(
                  context,
                  ref,
                  jobId: jobId,
                  approve: false,
                ),
                isApproving: response.isApproving,
                isDeclining: response.isDeclining,
                approveLabel:
                    'Approve  ${supplement.additionalDisplay}',
                w: w,
                h: h,
                bot: bot,
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _respond(
    BuildContext context,
    WidgetRef ref, {
    required String jobId,
    required bool approve,
  }) async {
    final ok = await ref
        .read(supplementResponseProvider.notifier)
        .respond(jobId: jobId, approve: approve);
    if (!context.mounted || !ok) return;
    if (approve) {
      context.go(AppRoutes.jobActivePath(jobId));
    } else {
      context.pop();
    }
  }
}

// ── Loading skeleton ──────────────────────────────────────────────────────────

class _LoadingSkeleton extends StatelessWidget {
  final double w, h;
  const _LoadingSkeleton({required this.w, required this.h});

  Widget _bar({double? width, double height = 14}) => Container(
        width: width ?? double.infinity,
        height: height,
        decoration: BoxDecoration(
          color: MyShopColors.surfaceGrey,
          borderRadius: BorderRadius.circular(6),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(w * 0.05),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 64,
            decoration: BoxDecoration(
              color: MyShopColors.surfaceGrey,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          SizedBox(height: h * 0.022),
          Container(
            padding: EdgeInsets.all(w * 0.04),
            decoration: BoxDecoration(
              color: MyShopColors.surfaceWhite,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(children: [
              CircleAvatar(
                  radius: w * 0.065,
                  backgroundColor: MyShopColors.surfaceGrey),
              SizedBox(width: w * 0.030),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _bar(width: w * 0.5),
                    const SizedBox(height: 6),
                    _bar(width: w * 0.3, height: 12),
                  ],
                ),
              ),
            ]),
          ),
          SizedBox(height: h * 0.022),
          Container(
            height: 160,
            decoration: BoxDecoration(
              color: MyShopColors.surfaceGrey,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Error / empty states ──────────────────────────────────────────────────────

class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                color: MyShopColors.error, size: 48),
            const SizedBox(height: 12),
            const Text(
              "We couldn't load the supplement request. Check your connection and try again.",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: MyShopColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: onRetry,
              child: const Text(
                'Retry',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: MyShopColors.primaryGold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoSupplementState extends StatelessWidget {
  final VoidCallback onBack;
  const _NoSupplementState({required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.task_alt_rounded,
                color: MyShopColors.success, size: 48),
            const SizedBox(height: 12),
            const Text(
              'No supplement to review.',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: MyShopColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              "There's nothing pending from the artisan right now.",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: MyShopColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: onBack,
              child: const Text(
                'Back',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: MyShopColors.primaryGold,
                ),
              ),
            ),
          ],
        ),
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
  final ActiveJobArtisan artisan;
  const _ArtisanRow({required this.w, required this.artisan});

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
          _Avatar(w: w, artisan: artisan),
          SizedBox(width: w * 0.036),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(artisan.name,
                    style: TextStyle(
                      color: MyShopColors.textPrimary,
                      fontSize: w * 0.040,
                      fontWeight: FontWeight.w700,
                    )),
                if (artisan.specialty.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(artisan.specialty,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: MyShopColors.textSecondary,
                          fontSize: w * 0.033)),
                ],
              ],
            ),
          ),
          if (artisan.isVerified)
            Container(
              padding: EdgeInsets.symmetric(
                  horizontal: w * 0.020, vertical: 4),
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

class _Avatar extends StatelessWidget {
  final double w;
  final ActiveJobArtisan artisan;
  const _Avatar({required this.w, required this.artisan});

  @override
  Widget build(BuildContext context) {
    final size = w * 0.13;
    if (artisan.photoUrl.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          artisan.photoUrl,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _initials(size),
        ),
      );
    }
    return _initials(size);
  }

  Widget _initials(double size) {
    final initial = artisan.firstName.isNotEmpty
        ? artisan.firstName.substring(0, 1).toUpperCase()
        : '?';
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: artisan.avatarColor,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.45,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ── Supplement card ────────────────────────────────────────────────────────────

class _SupplementCard extends StatelessWidget {
  final double w, h;
  final SupplementRequest supplement;
  const _SupplementCard(
      {required this.w, required this.h, required this.supplement});

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
                    if (supplement.submittedAt.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text('Submitted ${supplement.submittedAt}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: MyShopColors.textSecondary,
                              fontSize: w * 0.030)),
                    ],
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
            supplement.reason.isNotEmpty
                ? supplement.reason
                : 'No reason provided.',
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
                Text(supplement.additionalDisplay,
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
  final SupplementRequest supplement;
  const _CostBreakdown(
      {required this.w, required this.h, required this.supplement});

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
          _CostRow(
              label: 'Original Bid',
              value: supplement.originalBidDisplay,
              w: w),
          SizedBox(height: h * 0.010),
          _CostRow(
              label: 'Supplement',
              value: '+ ${supplement.additionalDisplay}',
              valueColor: MyShopColors.warning,
              w: w),
          SizedBox(height: h * 0.012),
          const Divider(height: 1, color: MyShopColors.divider),
          SizedBox(height: h * 0.012),
          _CostRow(
            label: 'New Total',
            value: supplement.newTotalDisplay,
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
  final String approveLabel;
  final double w, h, bot;

  const _ActionBar({
    required this.onApprove,
    required this.onDecline,
    required this.isApproving,
    required this.isDeclining,
    required this.approveLabel,
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
                  ? const SizedBox(
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
                    : Text(approveLabel,
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
