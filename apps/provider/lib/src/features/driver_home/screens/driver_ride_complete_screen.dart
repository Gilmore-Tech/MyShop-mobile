import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../core/utils/payment_method_label.dart';
import '../providers/ride_request_provider.dart';
import '../widgets/rate_passenger_sheet.dart';

/// Trip summary screen shown after ride completion.
///
/// Figma: node 208:11964
/// PRD Reference: PRD 5.2
///
/// Shows: completion banner, passenger info, pickup/dropoff, distance/duration,
/// full fare breakdown, commission, payment method, MoMo payout status,
/// dispute link, "GO TO WALLET" CTA.
///
/// Reads the completed ride from `activeRideProvider` (still populated until
/// the user dismisses the screen). The provider was set by the PATCH-status
/// response, so `finalFarePesewas`, `actualDistanceKm` etc. reflect the real
/// trip. Backend doesn't yet break down the fare into base/distance/time
/// rows — we show what's authoritative (total + commission split) and skip
/// the fabricated line items rather than display made-up numbers.
class DriverRideCompleteScreen extends ConsumerStatefulWidget {
  const DriverRideCompleteScreen({super.key});

  @override
  ConsumerState<DriverRideCompleteScreen> createState() =>
      _DriverRideCompleteScreenState();
}

class _DriverRideCompleteScreenState
    extends ConsumerState<DriverRideCompleteScreen> {
  /// One-shot guard so we only auto-show the rate-passenger sheet once
  /// per landing on the screen — without it a rebuild during the sheet's
  /// open animation would queue another sheet underneath.
  bool _rateSheetShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowRateSheet());
  }

  Future<void> _maybeShowRateSheet() async {
    if (_rateSheetShown || !mounted) return;
    final ride = ref.read(activeRideProvider).ride;
    if (ride == null || ride.id.isEmpty) return;
    _rateSheetShown = true;
    final firstName = (ride.clientName ?? 'Passenger').split(' ').first;
    await showRatePassengerSheet(
      context,
      rideId: ride.id,
      passengerFirstName: firstName,
    );
  }

  TripSummary _summaryFromRide(Ride ride) {
    final total = ride.totalPaidPesewas ??
        ride.finalFarePesewas ??
        ride.estimatedFarePesewas;
    // Backend overwrites the estimated distance/duration columns with the
    // ACTUAL values (computed from the GPS trail + start→complete time)
    // when the ride flips to `completed`, so reading them directly here
    // surfaces the real numbers. The dual `actualDistanceKm` /
    // `actualDurationMins` model fields are unused — kept as null on the
    // wire until the schema gets dedicated columns.
    final distanceKm = ride.actualDistanceKm ?? ride.estimatedDistanceKm;
    final durationMins = ride.actualDurationMins ?? ride.estimatedDurationMins;
    return TripSummary(
      rideId: ride.id,
      clientName: ride.clientName ?? 'Passenger',
      clientPhotoUrl: ride.clientPhotoUrl,
      clientRating: ride.clientRating ?? 0,
      paymentMethod: _formatPaymentMethod(ride.paymentMethod),
      pickupAddress: ride.pickupAddress,
      dropoffAddress: ride.dropoffAddress,
      distanceKm: distanceKm,
      durationMins: durationMins,
      // Backend does not yet break the fare into components — show 0 for
      // the per-line items so the breakdown collapses to just the total.
      baseFarePesewas: 0,
      distanceFarePesewas: 0,
      timeFarePesewas: 0,
      surgeFarePesewas: 0,
      taxesPesewas: 0,
      promoPesewas: 0,
      totalFarePesewas: total,
      commissionPesewas: ride.commissionPesewas,
      commissionRatePercent: ride.commissionRatePercent,
      netEarningsPesewas: ride.netPayoutPesewas,
      payoutMethod: 'MoMo Payout',
      payoutStatus: 'PROCESSING',
    );
  }

  // Shared label map (handles momo_mtn / momo_telecel / momo_airteltigo / cash
  // / card) so the completion summary matches the rider's choice exactly.
  String _formatPaymentMethod(String raw) => paymentMethodLabel(raw);

  @override
  Widget build(BuildContext context) {
    final ride = ref.watch(activeRideProvider).ride;
    if (ride == null) {
      // Recovery / hot-reload edge case — fall back to a benign empty state
      // rather than the previous Figma-mock summary so we never display
      // numbers that don't correspond to a real ride.
      return Scaffold(
        backgroundColor: MyShopColors.surfaceGrey,
        appBar: AppBar(
          backgroundColor: MyShopColors.surfaceWhite,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: MyShopColors.textPrimary),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: const Text('Trip Summary'),
        ),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'No completed ride to summarise.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    final s = _summaryFromRide(ride);

    return Scaffold(
      backgroundColor: MyShopColors.surfaceGrey,
      appBar: AppBar(
        backgroundColor: MyShopColors.surfaceWhite,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: MyShopColors.textPrimary),
          onPressed: () {
            ref.read(activeRideProvider.notifier).clearRide();
            // GoRouter — Navigator.pop here would pop off the entire
            // GoRoute and leave a black screen.
            context.go('/home');
          },
        ),
        title: const Text('Trip Summary',
            style: TextStyle(
                fontFamily: 'Raleway',
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: MyShopColors.textPrimary)),
        centerTitle: false,
      ),
      body: ListView(
        padding: const EdgeInsets.all(MyShopSpacing.md),
        children: [
          // Completion banner
          Container(
            padding: const EdgeInsets.all(MyShopSpacing.md),
            decoration: BoxDecoration(
                color: MyShopColors.primaryGoldLight,
                borderRadius: BorderRadius.circular(16)),
            child: Row(children: [
              const Icon(Icons.check_circle,
                  size: 24, color: MyShopColors.primaryGold),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    const Text('Trip Completed!',
                        style: TextStyle(
                            fontFamily: 'Raleway',
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: MyShopColors.textPrimary)),
                    Text('Earnings have been calculated and processed.',
                        style: MyShopTypography.body2),
                  ])),
            ]),
          ),
          const SizedBox(height: MyShopSpacing.md),

          // Passenger + fare card
          Container(
            padding: const EdgeInsets.all(MyShopSpacing.md),
            decoration: BoxDecoration(
                color: MyShopColors.surfaceWhite,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: MyShopColors.divider.withValues(alpha: 0.5))),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                _ClientAvatar(photoUrl: s.clientPhotoUrl),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(s.clientName,
                          style: const TextStyle(
                              fontFamily: 'Raleway',
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: MyShopColors.textPrimary)),
                      Row(children: [
                        const Icon(Icons.star,
                            size: 12, color: MyShopColors.ratingStar),
                        Text(
                          // Backend can return null for a brand-new rider
                          // with no revealed ratings yet — show "—" rather
                          // than "0.0" so they don't look one-starred.
                          s.clientRating > 0
                              ? ' ${s.clientRating.toStringAsFixed(1)}'
                              : ' —',
                          style: MyShopTypography.body2
                              .copyWith(fontWeight: FontWeight.w600),
                        ),
                        Text(' · ${s.paymentMethod}',
                            style: MyShopTypography.body2),
                      ]),
                    ])),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('TOTAL FARE',
                      style: MyShopTypography.overline.copyWith(
                          fontSize: 9, color: MyShopColors.primaryGold)),
                  Text(s.totalFareDisplay,
                      style: const TextStyle(
                          fontFamily: 'Raleway',
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: MyShopColors.textPrimary)),
                ]),
              ]),
              const SizedBox(height: MyShopSpacing.md),

              // Pickup/dropoff
              _RouteRow(
                  icon: Icons.circle,
                  iconColor: MyShopColors.textSecondary,
                  label: 'PICKUP',
                  address: s.pickupAddress),
              const SizedBox(height: 8),
              _RouteRow(
                  icon: Icons.radio_button_checked,
                  iconColor: MyShopColors.primaryGold,
                  label: 'DROP-OFF',
                  address: s.dropoffAddress),
              const SizedBox(height: MyShopSpacing.md),

              // Distance + Duration
              Row(children: [
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text('DISTANCE',
                          style:
                              MyShopTypography.overline.copyWith(fontSize: 10)),
                      Row(children: [
                        const Icon(Icons.straighten,
                            size: 14, color: MyShopColors.textSecondary),
                        const SizedBox(width: 4),
                        Text('${s.distanceKm} km',
                            style: const TextStyle(
                                fontFamily: 'Raleway',
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: MyShopColors.textPrimary)),
                      ]),
                    ])),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text('DURATION',
                          style:
                              MyShopTypography.overline.copyWith(fontSize: 10)),
                      Row(children: [
                        const Icon(Icons.access_time,
                            size: 14, color: MyShopColors.textSecondary),
                        const SizedBox(width: 4),
                        Text('${s.durationMins} mins',
                            style: const TextStyle(
                                fontFamily: 'Raleway',
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: MyShopColors.textPrimary)),
                      ]),
                    ])),
              ]),
            ]),
          ),
          const SizedBox(height: MyShopSpacing.md),

          // Fare summary. Per-line breakdown only renders if the backend
          // supplied non-zero components — otherwise we just show the total
          // rather than fabricate base/distance/time amounts that don't
          // tie out to the real fare.
          Container(
            padding: const EdgeInsets.all(MyShopSpacing.md),
            decoration: BoxDecoration(
                color: MyShopColors.surfaceWhite,
                borderRadius: BorderRadius.circular(16)),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('Fare Breakdown',
                    style: TextStyle(
                        fontFamily: 'Raleway',
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: MyShopColors.textPrimary)),
                Text(
                    'ID: #${s.rideId.substring(0, s.rideId.length.clamp(0, 8))}',
                    style: MyShopTypography.body2.copyWith(
                        color: MyShopColors.primaryGold, fontSize: 11)),
              ]),
              const SizedBox(height: MyShopSpacing.md),
              if (s.baseFarePesewas > 0)
                _FareRow(label: 'Base Fare', amount: s.baseFarePesewas),
              if (s.distanceFarePesewas > 0)
                _FareRow(
                    label: 'Distance (${s.distanceKm.toStringAsFixed(1)} km)',
                    amount: s.distanceFarePesewas),
              if (s.timeFarePesewas > 0)
                _FareRow(
                    label: 'Time (${s.durationMins} mins)',
                    amount: s.timeFarePesewas),
              if (s.surgeFarePesewas > 0)
                _FareRow(
                    label: 'Surge Pricing',
                    amount: s.surgeFarePesewas,
                    icon: Icons.bolt),
              if (s.taxesPesewas > 0)
                _FareRow(label: 'Taxes & Levies', amount: s.taxesPesewas),
              if (s.promoPesewas > 0)
                _FareRow(
                    label: 'Promotional Discount', amount: -s.promoPesewas),
              if (s.baseFarePesewas +
                      s.distanceFarePesewas +
                      s.timeFarePesewas +
                      s.surgeFarePesewas +
                      s.taxesPesewas +
                      s.promoPesewas >
                  0)
                const Divider(height: 24),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('Total Paid',
                    style: TextStyle(
                        fontFamily: 'Raleway',
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: MyShopColors.textPrimary)),
                Text(s.totalFareDisplay,
                    style: const TextStyle(
                        fontFamily: 'Raleway',
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: MyShopColors.primaryGold)),
              ]),
            ]),
          ),
          const SizedBox(height: MyShopSpacing.md),

          // Commission card
          Container(
            padding: const EdgeInsets.all(MyShopSpacing.md),
            decoration: BoxDecoration(
                color: MyShopColors.primaryGoldLight,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: MyShopColors.primaryGold.withValues(alpha: 0.3))),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.info_outline,
                    size: 16, color: MyShopColors.primaryGold),
                const SizedBox(width: 8),
                Text(s.commissionLabel,
                    style: MyShopTypography.body1.copyWith(fontSize: 13)),
                const Spacer(),
                Text(s.commissionDisplay,
                    style: const TextStyle(
                        fontFamily: 'Raleway',
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: MyShopColors.textPrimary)),
              ]),
              const SizedBox(height: 4),
              Text(
                  s.commissionPesewas == null
                      ? 'The authoritative commission is still being recorded. Check your earnings shortly.'
                      : 'This is the rate and amount recorded for this trip.',
                  style: MyShopTypography.caption.copyWith(fontSize: 10)),
            ]),
          ),
          const SizedBox(height: MyShopSpacing.md),

          // Payment method row
          Row(children: [
            const Icon(Icons.credit_card,
                size: 18, color: MyShopColors.textSecondary),
            const SizedBox(width: 8),
            Text(s.paymentMethod, style: MyShopTypography.body1),
          ]),
          const SizedBox(height: MyShopSpacing.md),

          // // Payout status
          // Container(
          //   padding: const EdgeInsets.all(MyShopSpacing.md),
          //   decoration: BoxDecoration(
          //       color: MyShopColors.surfaceWhite,
          //       borderRadius: BorderRadius.circular(16),
          //       border: Border.all(
          //           color: MyShopColors.divider.withValues(alpha: 0.5))),
          //   child: Row(children: [
          //     Container(
          //       width: 36,
          //       height: 36,
          //       decoration: BoxDecoration(
          //           color: MyShopColors.surfaceGrey,
          //           borderRadius: BorderRadius.circular(10)),
          //       child: const Icon(Icons.smartphone,
          //           size: 18, color: MyShopColors.textSecondary),
          //     ),
          //     const SizedBox(width: 12),
          //     Expanded(
          //         child: Column(
          //             crossAxisAlignment: CrossAxisAlignment.start,
          //             children: [
          //           Row(children: [
          //             Text(s.payoutMethod,
          //                 style: MyShopTypography.body1.copyWith(fontSize: 13)),
          //             const SizedBox(width: 8),
          //             Text(s.payoutStatus,
          //                 style: MyShopTypography.overline.copyWith(
          //                     fontSize: 9, color: MyShopColors.primaryGold)),
          //           ]),
          //           Text(
          //               'Funds are being sent to your registered MoMo wallet (+233 •••• 567). Usually arrives in 2-5 minutes.',
          //               style: MyShopTypography.caption.copyWith(fontSize: 10)),
          //         ])),
          //   ]),
          // ),
          const SizedBox(height: MyShopSpacing.md),

          // Go to wallet CTA → the earnings tab is the driver's wallet
          // surface (today's earnings, summary, payout requests). Tapping
          // here clears the active-ride slot so the driver doesn't bounce
          // back to this screen on the next state read.
          OutlinedButton.icon(
            onPressed: () {
              ref.read(activeRideProvider.notifier).clearRide();
              context.go('/earnings');
            },
            icon: const Icon(Icons.account_balance_wallet_outlined, size: 18),
            label: const Text('GO TO WALLET'),
            style: OutlinedButton.styleFrom(
              foregroundColor: MyShopColors.textPrimary,
              side: const BorderSide(color: MyShopColors.divider),
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              textStyle: const TextStyle(
                  fontFamily: 'Raleway',
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5),
            ),
          ),
          const SizedBox(height: MyShopSpacing.xxl),
        ],
      ),
    );
  }
}

class _RouteRow extends StatelessWidget {
  const _RouteRow(
      {required this.icon,
      required this.iconColor,
      required this.label,
      required this.address});
  final IconData icon;
  final Color iconColor;
  final String label;
  final String address;
  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, size: 12, color: iconColor),
      const SizedBox(width: 8),
      Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: MyShopTypography.overline.copyWith(fontSize: 9)),
        Text(address,
            style: const TextStyle(
                fontFamily: 'Raleway',
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: MyShopColors.textPrimary)),
      ])),
    ]);
  }
}

class _FareRow extends StatelessWidget {
  const _FareRow({required this.label, required this.amount, this.icon});
  final String label;
  final int amount;
  final IconData? icon;
  @override
  Widget build(BuildContext context) {
    final isNegative = amount < 0;
    final display =
        '${isNegative ? '- ' : ''}GHS ${(amount.abs() / 100).toStringAsFixed(2)}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        if (icon != null) ...[
          Icon(icon!, size: 14, color: MyShopColors.textSecondary),
          const SizedBox(width: 4)
        ],
        Expanded(
            child: Text(label,
                style: MyShopTypography.body2
                    .copyWith(color: MyShopColors.textPrimary))),
        Text(display,
            style: TextStyle(
                fontFamily: 'Raleway',
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isNegative
                    ? MyShopColors.success
                    : MyShopColors.textPrimary)),
      ]),
    );
  }
}

class _ClientAvatar extends StatelessWidget {
  const _ClientAvatar({this.photoUrl});

  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    final url = photoUrl;
    if (url == null || url.isEmpty) {
      return const CircleAvatar(
        radius: 20,
        backgroundColor: MyShopColors.avatarPlaceholder,
        child: Icon(Icons.person, size: 20, color: MyShopColors.textSecondary),
      );
    }
    return CircleAvatar(
      radius: 20,
      backgroundColor: MyShopColors.avatarPlaceholder,
      child: ClipOval(
        child: CachedNetworkImage(
          imageUrl: url,
          width: 40,
          height: 40,
          fit: BoxFit.cover,
          placeholder: (_, __) => const Icon(Icons.person,
              size: 20, color: MyShopColors.textSecondary),
          errorWidget: (_, __, ___) => const Icon(Icons.person,
              size: 20, color: MyShopColors.textSecondary),
        ),
      ),
    );
  }
}
