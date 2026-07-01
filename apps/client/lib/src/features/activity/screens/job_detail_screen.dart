import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../providers/job_activity_detail_provider.dart';

// ── Screen ─────────────────────────────────────────────────────────────────────
// PRD § 4.9 — Historical artisan job detail; client can view receipt or dispute.
// EDD: GET /v1/jobs/:id

class JobDetailScreen extends ConsumerWidget {
  const JobDetailScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final size = MediaQuery.sizeOf(context);
    final w = size.width;
    final h = size.height;
    final jobId = GoRouterState.of(context).pathParameters['jobId'] ?? '';

    final asyncDetail = ref.watch(jobActivityDetailProvider(jobId));

    return Scaffold(
      backgroundColor: MyShopColors.offWhite,
      appBar: AppBar(
        backgroundColor: MyShopColors.surfaceWhite,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: MyShopColors.textPrimary),
          onPressed: () => context.pop(),
        ),
        title: Text('Job Detail',
            style: TextStyle(
                color: MyShopColors.textPrimary,
                fontSize: w * 0.044,
                fontWeight: FontWeight.w700)),
        centerTitle: false,
        actions: [
          TextButton(
            onPressed: () => context.push(AppRoutes.jobReceiptPath(jobId)),
            child: Text('Receipt',
                style: TextStyle(
                    color: MyShopColors.primaryGold,
                    fontSize: w * 0.036,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      body: asyncDetail.when(
        loading: () => _LoadingSkeleton(w: w, h: h),
        error: (e, _) => _ErrorView(
          message: 'Could not load job details.',
          onRetry: () => ref.invalidate(jobActivityDetailProvider(jobId)),
          w: w,
          h: h,
        ),
        data: (data) => _JobDetailBody(
          data: data,
          jobId: jobId,
          w: w,
          h: h,
        ),
      ),
    );
  }
}

// ── Body ──────────────────────────────────────────────────────────────────────

class _JobDetailBody extends StatelessWidget {
  final JobActivityDetail data;
  final String jobId;
  final double w, h;

  const _JobDetailBody({
    required this.data,
    required this.jobId,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(w * 0.05),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StatusCard(data: data, w: w, h: h),
          SizedBox(height: h * 0.020),
          if (data.hasArtisan) _ArtisanCard(data: data, w: w, h: h),
          if (data.hasArtisan) SizedBox(height: h * 0.020),
          _JobInfoCard(data: data, w: w, h: h),
          SizedBox(height: h * 0.020),
          _CostCard(data: data, w: w, h: h),
          SizedBox(height: h * 0.024),
          _ActionRow(jobId: jobId, data: data, w: w, h: h),
        ],
      ),
    );
  }
}

// ── Status card ────────────────────────────────────────────────────────────────

class _StatusCard extends StatelessWidget {
  final JobActivityDetail data;
  final double w, h;
  const _StatusCard({required this.data, required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    final (badgeBg, badgeFg) = _statusColors(data.status);

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
            padding: EdgeInsets.all(w * 0.032),
            decoration: BoxDecoration(color: badgeBg, shape: BoxShape.circle),
            child: Icon(Icons.work_rounded, color: badgeFg, size: 24),
          ),
          SizedBox(width: w * 0.036),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(data.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: MyShopColors.textPrimary,
                      fontSize: w * 0.038,
                      fontWeight: FontWeight.w700,
                    )),
                const SizedBox(height: 2),
                Text(data.dateTimeLabel,
                    style: TextStyle(
                        color: MyShopColors.textSecondary,
                        fontSize: w * 0.032)),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.symmetric(horizontal: w * 0.024, vertical: 5),
            decoration: BoxDecoration(
              color: badgeBg,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(data.statusLabel,
                style: TextStyle(
                  color: badgeFg,
                  fontSize: w * 0.028,
                  fontWeight: FontWeight.w600,
                )),
          ),
        ],
      ),
    );
  }

  (Color bg, Color fg) _statusColors(String status) {
    return switch (status) {
      'completed' => (MyShopColors.successLight, MyShopColors.success),
      'cancelled' => (MyShopColors.errorLight, MyShopColors.error),
      'in_progress' ||
      'artisan_marked_complete' ||
      'artisan_en_route' ||
      'en_route' ||
      'arrived' =>
        (MyShopColors.warningLight, MyShopColors.warning),
      _ => (MyShopColors.infoLight, MyShopColors.info),
    };
  }
}

// ── Artisan card ───────────────────────────────────────────────────────────────

class _ArtisanCard extends StatelessWidget {
  final JobActivityDetail data;
  final double w, h;
  const _ArtisanCard({required this.data, required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(w * 0.04),
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MyShopColors.divider),
      ),
      child: Row(
        children: [
          Container(
            width: w * 0.13,
            height: w * 0.13,
            decoration: const BoxDecoration(
                color: MyShopColors.darkSlate, shape: BoxShape.circle),
            child: Icon(Icons.person_rounded,
                color: Colors.white, size: w * 0.065),
          ),
          SizedBox(width: w * 0.030),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(data.artisanName ?? '',
                    style: TextStyle(
                      color: MyShopColors.textPrimary,
                      fontSize: w * 0.040,
                      fontWeight: FontWeight.w700,
                    )),
                if (data.artisanSpecialty != null) ...[
                  const SizedBox(height: 3),
                  Text(data.artisanSpecialty!,
                      style: TextStyle(
                          color: MyShopColors.textSecondary,
                          fontSize: w * 0.032)),
                ],
                // Read-only number, visible only during the 24h post-job
                // contact window (gated in the provider). No call button —
                // this is a history page.
                if ((data.artisanPhone ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(children: [
                    Icon(Icons.phone_rounded,
                        size: w * 0.034, color: MyShopColors.textSecondary),
                    SizedBox(width: w * 0.012),
                    Text(data.artisanPhone!,
                        style: TextStyle(
                          color: MyShopColors.textPrimary,
                          fontSize: w * 0.032,
                          fontWeight: FontWeight.w600,
                        )),
                  ]),
                ],
                if (data.artisanRating != null) ...[
                  const SizedBox(height: 4),
                  Row(children: [
                    const Icon(Icons.star_rounded,
                        color: MyShopColors.primaryGold, size: 14),
                    const SizedBox(width: 3),
                    Text(
                        '${data.artisanRating!.toStringAsFixed(1)}'
                        '${data.artisanJobCount != null ? '  •  ${data.artisanJobCount} jobs' : ''}',
                        style: TextStyle(
                          color: MyShopColors.textPrimary,
                          fontSize: w * 0.030,
                          fontWeight: FontWeight.w500,
                        )),
                  ]),
                ],
              ],
            ),
          ),
          if (data.artisanVerified)
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
                        fontSize: w * 0.026,
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

// ── Job info card ──────────────────────────────────────────────────────────────

class _JobInfoCard extends StatelessWidget {
  final JobActivityDetail data;
  final double w, h;
  const _JobInfoCard({required this.data, required this.w, required this.h});

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
          Text('Job Details',
              style: TextStyle(
                color: MyShopColors.textPrimary,
                fontSize: w * 0.036,
                fontWeight: FontWeight.w700,
              )),
          SizedBox(height: h * 0.006),
          if (data.location.isNotEmpty)
            _InfoRow(
                icon: Icons.location_on_outlined,
                label: 'Location',
                value: data.location,
                w: w),
          if (data.location.isNotEmpty) SizedBox(height: h * 0.006),
          if (data.categoryName.isNotEmpty)
            _InfoRow(
                icon: Icons.category_outlined,
                label: 'Category',
                value: data.categoryName,
                w: w),
          if (data.categoryName.isNotEmpty) SizedBox(height: h * 0.006),
          _InfoRow(
              icon: Icons.people_alt_outlined,
              label: 'Bids',
              value:
                  '${data.bidCount} bid${data.bidCount == 1 ? '' : 's'} received',
              w: w),
          SizedBox(height: h * 0.006),
          _InfoRow(
              icon: Icons.tag_rounded,
              label: 'Job Ref',
              value: '#${data.jobId}',
              w: w),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label, value;
  final double w;
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.w,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: MyShopColors.textSecondary, size: 16),
        SizedBox(width: w * 0.024),
        Text('$label:  ',
            style: TextStyle(
                color: MyShopColors.textSecondary, fontSize: w * 0.033)),
        Expanded(
          child: Text(value,
              style: TextStyle(
                color: MyShopColors.textPrimary,
                fontSize: w * 0.033,
                fontWeight: FontWeight.w600,
              )),
        ),
      ],
    );
  }
}

// ── Cost card ──────────────────────────────────────────────────────────────────

class _CostCard extends StatelessWidget {
  final JobActivityDetail data;
  final double w, h;
  const _CostCard({required this.data, required this.w, required this.h});

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
        children: [
          _CostLine(
              label: 'Agreed price',
              value: data.agreedPriceDisplay,
              w: w,
              h: h),
          if (data.hasSupplement)
            _CostLine(
                label: 'Supplement', value: data.supplementDisplay, w: w, h: h),
          Padding(
            padding: EdgeInsets.symmetric(vertical: h * 0.010),
            child: const Divider(height: 1, color: MyShopColors.divider),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total',
                  style: TextStyle(
                    color: MyShopColors.textPrimary,
                    fontSize: w * 0.038,
                    fontWeight: FontWeight.w700,
                  )),
              Text(data.totalDisplay,
                  style: TextStyle(
                    color: MyShopColors.textPrimary,
                    fontSize: w * 0.044,
                    fontWeight: FontWeight.w800,
                  )),
            ],
          ),
          if (data.paymentStatus != null) ...[
            SizedBox(height: h * 0.006),
            Row(
              children: [
                Icon(
                    data.isCompleted
                        ? Icons.lock_outline_rounded
                        : Icons.lock_open_rounded,
                    color: data.isCompleted
                        ? MyShopColors.success
                        : MyShopColors.textSecondary,
                    size: 14),
                SizedBox(width: w * 0.016),
                Text(
                    data.isCompleted
                        ? 'Released from escrow'
                        : 'Held in escrow',
                    style: TextStyle(
                        color: MyShopColors.textSecondary,
                        fontSize: w * 0.030)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _CostLine extends StatelessWidget {
  final String label, value;
  final double w, h;
  const _CostLine({
    required this.label,
    required this.value,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: h * 0.008),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  color: MyShopColors.textSecondary, fontSize: w * 0.034)),
          Text(value,
              style: TextStyle(
                color: MyShopColors.textPrimary,
                fontSize: w * 0.034,
                fontWeight: FontWeight.w500,
              )),
        ],
      ),
    );
  }
}

// ── Action row ─────────────────────────────────────────────────────────────────

class _ActionRow extends StatelessWidget {
  final String jobId;
  final JobActivityDetail data;
  final double w, h;
  const _ActionRow({
    required this.jobId,
    required this.data,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (data.isCompleted)
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => context.push(AppRoutes.jobDisputePath(jobId)),
              icon: const Icon(Icons.flag_outlined, size: 18),
              label: const Text('Dispute'),
              style: OutlinedButton.styleFrom(
                foregroundColor: MyShopColors.error,
                side: const BorderSide(color: MyShopColors.error),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                padding: EdgeInsets.symmetric(vertical: h * 0.018),
              ),
            ),
          ),
        if (data.isCompleted) SizedBox(width: w * 0.030),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () => context.push(AppRoutes.jobReceiptPath(jobId)),
            icon: const Icon(Icons.receipt_long_rounded, size: 18),
            label: const Text('View Receipt'),
            style: ElevatedButton.styleFrom(
              backgroundColor: MyShopColors.primaryGold,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              elevation: 0,
              padding: EdgeInsets.symmetric(vertical: h * 0.018),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Loading skeleton ──────────────────────────────────────────────────────────

class _LoadingSkeleton extends StatelessWidget {
  final double w, h;
  const _LoadingSkeleton({required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(w * 0.05),
      child: Column(
        children: [
          _ShimmerBox(w: double.infinity, h: h * 0.10),
          SizedBox(height: h * 0.020),
          _ShimmerBox(w: double.infinity, h: h * 0.12),
          SizedBox(height: h * 0.020),
          _ShimmerBox(w: double.infinity, h: h * 0.10),
          SizedBox(height: h * 0.020),
          _ShimmerBox(w: double.infinity, h: h * 0.14),
        ],
      ),
    );
  }
}

class _ShimmerBox extends StatelessWidget {
  final double w, h;
  const _ShimmerBox({required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: MyShopColors.divider,
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }
}

// ── Error view ────────────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final double w, h;
  const _ErrorView({
    required this.message,
    required this.onRetry,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: w * 0.088),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off_rounded,
                size: w * 0.15, color: MyShopColors.textHint),
            SizedBox(height: h * 0.018),
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: MyShopColors.textSecondary,
                  fontSize: w * 0.038,
                )),
            SizedBox(height: h * 0.022),
            GestureDetector(
              onTap: onRetry,
              child: Container(
                padding: EdgeInsets.symmetric(
                    horizontal: w * 0.064, vertical: h * 0.014),
                decoration: BoxDecoration(
                  color: MyShopColors.darkSlate,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('Retry',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: w * 0.036,
                      fontWeight: FontWeight.w600,
                    )),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
