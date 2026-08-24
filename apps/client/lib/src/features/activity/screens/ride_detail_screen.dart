import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../providers/ride_detail_provider.dart';

// ── Screen ─────────────────────────────────────────────────────────────────────
// PRD § 4.9 — Historical ride detail; client can view receipt or raise a dispute.
// EDD: GET /v1/rides/:id

class RideDetailScreen extends ConsumerWidget {
  const RideDetailScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final size = MediaQuery.sizeOf(context);
    final w = size.width;
    final h = size.height;
    final rideId = GoRouterState.of(context).pathParameters['rideId'] ?? '';

    final asyncDetail = ref.watch(rideDetailByIdProvider(rideId));

    return Scaffold(
      backgroundColor: MyShopColors.offWhite,
      appBar: AppBar(
        backgroundColor: MyShopColors.surfaceWhite,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: MyShopColors.textPrimary),
          onPressed: () => context.pop(),
        ),
        title: Text('Ride Detail',
            style: TextStyle(
                color: MyShopColors.textPrimary,
                fontSize: w * 0.044,
                fontWeight: FontWeight.w700)),
        centerTitle: false,
        actions: [
          if (asyncDetail.maybeWhen(
            data: (d) => d.isCompleted,
            orElse: () => false,
          ))
            TextButton(
              onPressed: () => context.push(AppRoutes.rideReceiptPath(rideId)),
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
          message: 'Could not load ride details.',
          onRetry: () => ref.invalidate(rideDetailByIdProvider(rideId)),
          w: w,
          h: h,
        ),
        data: (data) => _RideDetailBody(
          data: data,
          rideId: rideId,
          w: w,
          h: h,
        ),
      ),
    );
  }
}

// ── Body ──────────────────────────────────────────────────────────────────────

class _RideDetailBody extends StatelessWidget {
  final RideDetailData data;
  final String rideId;
  final double w, h;

  const _RideDetailBody({
    required this.data,
    required this.rideId,
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
          _RouteCard(data: data, w: w, h: h),
          SizedBox(height: h * 0.020),
          _DriverCard(data: data, w: w, h: h),
          SizedBox(height: h * 0.020),
          if (data.isCompleted)
            _FareCard(data: data, w: w, h: h)
          else
            _CancelledFareNotice(w: w, h: h),
          SizedBox(height: h * 0.024),
          _ActionRow(rideId: rideId, data: data, w: w, h: h),
        ],
      ),
    );
  }
}

// ── Status card ────────────────────────────────────────────────────────────────

class _StatusCard extends StatelessWidget {
  final RideDetailData data;
  final double w, h;
  const _StatusCard({required this.data, required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    final (badgeBg, badgeFg, badgeLabel) = _statusStyle(data.status);

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
            child: Icon(Icons.directions_car_rounded, color: badgeFg, size: 24),
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
                const SizedBox(height: 4),
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
            child: Text(badgeLabel,
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

  (Color bg, Color fg, String label) _statusStyle(String status) {
    return switch (status) {
      'completed' => (
          MyShopColors.successLight,
          MyShopColors.success,
          'Completed'
        ),
      'cancelled' => (MyShopColors.errorLight, MyShopColors.error, 'Cancelled'),
      'in_progress' => (
          MyShopColors.warningLight,
          MyShopColors.warning,
          'In Progress'
        ),
      _ => (MyShopColors.infoLight, MyShopColors.info, 'Pending'),
    };
  }
}

// ── Route card ─────────────────────────────────────────────────────────────────

class _RouteCard extends StatelessWidget {
  final RideDetailData data;
  final double w, h;
  const _RouteCard({required this.data, required this.w, required this.h});

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
          _RouteRow(
            icon: Icons.radio_button_checked_rounded,
            color: MyShopColors.primaryGold,
            label: 'Pickup',
            address: data.pickupAddress,
            time: data.pickupTime ?? '',
            w: w,
          ),
          Padding(
            padding: EdgeInsets.only(left: w * 0.045),
            child: Column(
              children: List.generate(
                  3,
                  (_) => Container(
                        height: 6,
                        width: 1.5,
                        margin: const EdgeInsets.symmetric(vertical: 2),
                        color: MyShopColors.divider,
                      )),
            ),
          ),
          _RouteRow(
            icon: Icons.location_on_rounded,
            color: MyShopColors.error,
            label: 'Drop-off',
            address: data.dropoffAddress,
            time: data.dropoffTime ?? '',
            w: w,
          ),
        ],
      ),
    );
  }
}

class _RouteRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label, address, time;
  final double w;

  const _RouteRow({
    required this.icon,
    required this.color,
    required this.label,
    required this.address,
    required this.time,
    required this.w,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 20),
        SizedBox(width: w * 0.030),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(
                      color: MyShopColors.textSecondary, fontSize: w * 0.028)),
              const SizedBox(height: 2),
              Text(address,
                  style: TextStyle(
                    color: MyShopColors.textPrimary,
                    fontSize: w * 0.036,
                    fontWeight: FontWeight.w600,
                  )),
            ],
          ),
        ),
        if (time.isNotEmpty)
          Text(time,
              style: TextStyle(
                  color: MyShopColors.textSecondary, fontSize: w * 0.030)),
      ],
    );
  }
}

// ── Driver card ────────────────────────────────────────────────────────────────

class _DriverCard extends StatelessWidget {
  final RideDetailData data;
  final double w, h;
  const _DriverCard({required this.data, required this.w, required this.h});

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
                color: Color(0xFF2C3E50), shape: BoxShape.circle),
            child: Icon(Icons.person_rounded,
                color: Colors.white, size: w * 0.065),
          ),
          SizedBox(width: w * 0.030),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(data.driverName,
                    style: TextStyle(
                      color: MyShopColors.textPrimary,
                      fontSize: w * 0.040,
                      fontWeight: FontWeight.w700,
                    )),
                const SizedBox(height: 3),
                Text(data.vehicleDisplay,
                    style: TextStyle(
                        color: MyShopColors.textSecondary,
                        fontSize: w * 0.032)),
                // Read-only number, visible only during the 24h post-trip
                // contact window (gated in the provider). No call button —
                // history is informational; once completed you're done.
                if ((data.driverPhone ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(children: [
                    Icon(Icons.phone_rounded,
                        size: w * 0.034, color: MyShopColors.textSecondary),
                    SizedBox(width: w * 0.012),
                    Text(data.driverPhone!,
                        style: TextStyle(
                          color: MyShopColors.textPrimary,
                          fontSize: w * 0.032,
                          fontWeight: FontWeight.w600,
                        )),
                  ]),
                ],
                if (data.driverRating > 0) ...[
                  const SizedBox(height: 4),
                  Row(children: [
                    const Icon(Icons.star_rounded,
                        color: MyShopColors.primaryGold, size: 14),
                    const SizedBox(width: 3),
                    Text(data.driverRating.toStringAsFixed(1),
                        style: TextStyle(
                          color: MyShopColors.textPrimary,
                          fontSize: w * 0.032,
                          fontWeight: FontWeight.w600,
                        )),
                  ]),
                ],
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(data.durationDisplay,
                  style: TextStyle(
                    color: MyShopColors.textPrimary,
                    fontSize: w * 0.036,
                    fontWeight: FontWeight.w700,
                  )),
              const SizedBox(height: 2),
              Text(data.distanceDisplay,
                  style: TextStyle(
                      color: MyShopColors.textSecondary, fontSize: w * 0.028)),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Fare card ──────────────────────────────────────────────────────────────────

class _FareCard extends StatelessWidget {
  final RideDetailData data;
  final double w, h;
  const _FareCard({required this.data, required this.w, required this.h});

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
          if (data.baseFarePesewas > 0)
            _FareRow(
                label: 'Base fare', value: data.baseFareDisplay, w: w, h: h),
          if (data.distanceFarePesewas > 0)
            _FareRow(
                label: 'Distance (${data.distanceDisplay})',
                value: data.distanceFareDisplay,
                w: w,
                h: h),
          if (data.bookingFeePesewas > 0)
            _FareRow(
                label: 'Booking fee',
                value: data.bookingFeeDisplay,
                w: w,
                h: h),
          if ((data.toll?.amountPesewas ?? 0) > 0)
            _FareRow(
              label: data.toll!.label,
              value: data.tollDisplay,
              w: w,
              h: h,
            ),
          if (data.promoDiscountPesewas > 0)
            _FareRow(
              label: 'Promotional discount',
              value: data.promoDiscountDisplay,
              w: w,
              h: h,
            ),
          if (data.loyaltyDiscountPesewas > 0)
            _FareRow(
              label: 'Loyalty discount',
              value: data.loyaltyDiscountDisplay,
              w: w,
              h: h,
            ),
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
              Text(data.totalFareDisplay,
                  style: TextStyle(
                    color: MyShopColors.textPrimary,
                    fontSize: w * 0.044,
                    fontWeight: FontWeight.w800,
                  )),
            ],
          ),
          SizedBox(height: h * 0.010),
          Row(
            children: [
              const Icon(Icons.phone_android_rounded,
                  color: MyShopColors.textSecondary, size: 14),
              SizedBox(width: w * 0.016),
              Text('Paid via ${data.paymentMethod}',
                  style: TextStyle(
                      color: MyShopColors.textSecondary, fontSize: w * 0.030)),
            ],
          ),
        ],
      ),
    );
  }
}

class _FareRow extends StatelessWidget {
  final String label, value;
  final double w, h;
  const _FareRow({
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
  final String rideId;
  final RideDetailData data;
  final double w, h;
  const _ActionRow({
    required this.rideId,
    required this.data,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    if (!data.isCompleted) return const SizedBox.shrink();
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => context.push(AppRoutes.rideDisputePath(rideId)),
            icon: const Icon(Icons.flag_outlined, size: 18),
            label: const Text('Dispute Fare'),
            style: OutlinedButton.styleFrom(
              foregroundColor: MyShopColors.error,
              side: const BorderSide(color: MyShopColors.error),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              padding: EdgeInsets.symmetric(vertical: h * 0.018),
            ),
          ),
        ),
        SizedBox(width: w * 0.030),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () => context.push(AppRoutes.rideReceiptPath(rideId)),
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

// ── Cancelled fare notice ─────────────────────────────────────────────────────

class _CancelledFareNotice extends StatelessWidget {
  final double w, h;
  const _CancelledFareNotice({required this.w, required this.h});

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
            padding: EdgeInsets.all(w * 0.025),
            decoration: const BoxDecoration(
              color: MyShopColors.warningLight,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.info_outline_rounded,
                color: MyShopColors.warning, size: 18),
          ),
          SizedBox(width: w * 0.030),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('No fare collected',
                    style: TextStyle(
                      color: MyShopColors.textPrimary,
                      fontSize: w * 0.036,
                      fontWeight: FontWeight.w700,
                    )),
                const SizedBox(height: 2),
                Text('This ride was cancelled before completion.',
                    style: TextStyle(
                      color: MyShopColors.textSecondary,
                      fontSize: w * 0.030,
                    )),
              ],
            ),
          ),
        ],
      ),
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
          _ShimmerBox(w: double.infinity, h: h * 0.14),
          SizedBox(height: h * 0.020),
          _ShimmerBox(w: double.infinity, h: h * 0.10),
          SizedBox(height: h * 0.020),
          _ShimmerBox(w: double.infinity, h: h * 0.16),
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
