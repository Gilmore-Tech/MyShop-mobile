import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';

// ── Screen ─────────────────────────────────────────────────────────────────────
// PRD § 4.9 — Historical artisan job detail; client can view receipt or dispute.
// EDD: GET /v1/jobs/:id

class JobDetailScreen extends ConsumerWidget {
  const JobDetailScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final size  = MediaQuery.sizeOf(context);
    final w     = size.width;
    final h     = size.height;
    final jobId = GoRouterState.of(context).pathParameters['jobId'] ?? 'JOB-1092';

    return Scaffold(
      backgroundColor: MyShopColors.offWhite,
      appBar: AppBar(
        backgroundColor: MyShopColors.surfaceWhite,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back,
              color: MyShopColors.textPrimary),
          onPressed: () => context.pop(),
        ),
        title: Text('Job Detail',
            style: TextStyle(
                color:      MyShopColors.textPrimary,
                fontSize:   w * 0.044,
                fontWeight: FontWeight.w700)),
        centerTitle: false,
        actions: [
          TextButton(
            onPressed: () =>
                context.push(AppRoutes.jobReceiptPath(jobId)),
            child: Text('Receipt',
                style: TextStyle(
                    color:      MyShopColors.primaryGold,
                    fontSize:   w * 0.036,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(w * 0.05),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _StatusCard(w: w, h: h),
            SizedBox(height: h * 0.020),
            _ArtisanCard(w: w, h: h),
            SizedBox(height: h * 0.020),
            _JobInfoCard(w: w, h: h),
            SizedBox(height: h * 0.020),
            _CostCard(w: w, h: h),
            SizedBox(height: h * 0.024),
            _ActionRow(jobId: jobId, w: w, h: h),
          ],
        ),
      ),
    );
  }
}

// ── Status card ────────────────────────────────────────────────────────────────

class _StatusCard extends StatelessWidget {
  final double w, h;
  const _StatusCard({required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(w * 0.04),
      decoration: BoxDecoration(
        color:        MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color:      Colors.black.withAlpha(8),
              blurRadius: 8,
              offset:     const Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(w * 0.032),
            decoration: const BoxDecoration(
                color: MyShopColors.successLight, shape: BoxShape.circle),
            child: const Icon(Icons.work_rounded,
                color: MyShopColors.success, size: 24),
          ),
          SizedBox(width: w * 0.036),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Office Cleaning Service',
                    style: TextStyle(
                      color:      MyShopColors.textPrimary,
                      fontSize:   w * 0.040,
                      fontWeight: FontWeight.w700,
                    )),
                const SizedBox(height: 4),
                Text('Oct 23, 10:00 AM',
                    style: TextStyle(
                        color:    MyShopColors.textSecondary,
                        fontSize: w * 0.032)),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.symmetric(
                horizontal: w * 0.024, vertical: 5),
            decoration: BoxDecoration(
              color:        MyShopColors.successLight,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text('Completed',
                style: TextStyle(
                  color:      MyShopColors.success,
                  fontSize:   w * 0.028,
                  fontWeight: FontWeight.w600,
                )),
          ),
        ],
      ),
    );
  }
}

// ── Artisan card ───────────────────────────────────────────────────────────────

class _ArtisanCard extends StatelessWidget {
  final double w, h;
  const _ArtisanCard({required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(w * 0.04),
      decoration: BoxDecoration(
        color:        MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(12),
        border:       Border.all(color: MyShopColors.divider),
      ),
      child: Row(
        children: [
          Container(
            width:  w * 0.13,
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
                Text('Abena Osei',
                    style: TextStyle(
                      color:      MyShopColors.textPrimary,
                      fontSize:   w * 0.040,
                      fontWeight: FontWeight.w700,
                    )),
                const SizedBox(height: 3),
                Text('Professional Cleaner',
                    style: TextStyle(
                        color:    MyShopColors.textSecondary,
                        fontSize: w * 0.032)),
                const SizedBox(height: 4),
                Row(children: [
                  const Icon(Icons.star_rounded, color: MyShopColors.primaryGold, size: 14),
                  const SizedBox(width: 3),
                  Text('4.7  •  142 jobs',
                      style: TextStyle(
                        color:      MyShopColors.textPrimary,
                        fontSize:   w * 0.030,
                        fontWeight: FontWeight.w500,
                      )),
                ]),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.symmetric(
                horizontal: w * 0.020, vertical: 4),
            decoration: BoxDecoration(
              color:        MyShopColors.successLight,
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
                      color:      MyShopColors.success,
                      fontSize:   w * 0.026,
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
  final double w, h;
  const _JobInfoCard({required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(w * 0.04),
      decoration: BoxDecoration(
        color:        MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(12),
        border:       Border.all(color: MyShopColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Job Details',
              style: TextStyle(
                color:      MyShopColors.textPrimary,
                fontSize:   w * 0.036,
                fontWeight: FontWeight.w700,
              )),
          SizedBox(height: h * 0.012),
          _InfoRow(
              icon:  Icons.location_on_outlined,
              label: 'Location',
              value: 'Labone Heights Estate, Accra',
              w:     w),
          SizedBox(height: h * 0.010),
          _InfoRow(
              icon:  Icons.access_time_rounded,
              label: 'Duration',
              value: '3 hours',
              w:     w),
          SizedBox(height: h * 0.010),
          _InfoRow(
              icon:  Icons.tag_rounded,
              label: 'Job Ref',
              value: '#JOB-1092',
              w:     w),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String   label, value;
  final double   w;
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
                color:      MyShopColors.textPrimary,
                fontSize:   w * 0.033,
                fontWeight: FontWeight.w600,
              )),
        ),
      ],
    );
  }
}

// ── Cost card ──────────────────────────────────────────────────────────────────

class _CostCard extends StatelessWidget {
  final double w, h;
  const _CostCard({required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(w * 0.04),
      decoration: BoxDecoration(
        color:        MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(12),
        border:       Border.all(color: MyShopColors.divider),
      ),
      child: Column(
        children: [
          _CostLine(label: 'Labour',    value: 'GHS 120.00', w: w, h: h),
          _CostLine(label: 'Materials', value: 'GHS 35.00',  w: w, h: h),
          Padding(
            padding: EdgeInsets.symmetric(vertical: h * 0.010),
            child: const Divider(height: 1, color: MyShopColors.divider),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total',
                  style: TextStyle(
                    color:      MyShopColors.textPrimary,
                    fontSize:   w * 0.038,
                    fontWeight: FontWeight.w700,
                  )),
              Text('GHS 155.00',
                  style: TextStyle(
                    color:      MyShopColors.textPrimary,
                    fontSize:   w * 0.044,
                    fontWeight: FontWeight.w800,
                  )),
            ],
          ),
          SizedBox(height: h * 0.010),
          Row(
            children: [
              const Icon(Icons.lock_outline_rounded,
                  color: MyShopColors.success, size: 14),
              SizedBox(width: w * 0.016),
              Text('Released from escrow',
                  style: TextStyle(
                      color:    MyShopColors.textSecondary,
                      fontSize: w * 0.030)),
            ],
          ),
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
                color:      MyShopColors.textPrimary,
                fontSize:   w * 0.034,
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
  final double w, h;
  const _ActionRow(
      {required this.jobId, required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () =>
                context.push(AppRoutes.jobDisputePath(jobId)),
            icon: const Icon(Icons.flag_outlined, size: 18),
            label: const Text('Dispute'),
            style: OutlinedButton.styleFrom(
              foregroundColor: MyShopColors.error,
              side:  const BorderSide(color: MyShopColors.error),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              padding:
                  EdgeInsets.symmetric(vertical: h * 0.018),
            ),
          ),
        ),
        SizedBox(width: w * 0.030),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () =>
                context.push(AppRoutes.jobReceiptPath(jobId)),
            icon: const Icon(Icons.receipt_long_rounded, size: 18),
            label: const Text('View Receipt'),
            style: ElevatedButton.styleFrom(
              backgroundColor: MyShopColors.primaryGold,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              elevation: 0,
              padding:
                  EdgeInsets.symmetric(vertical: h * 0.018),
            ),
          ),
        ),
      ],
    );
  }
}
