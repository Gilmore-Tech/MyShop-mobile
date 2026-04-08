import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

import '../providers/ride_request_provider.dart';

/// Trip summary screen shown after ride completion.
///
/// Figma: node 208:11964
/// PRD Reference: PRD 5.2
///
/// Shows: completion banner, passenger info, pickup/dropoff, distance/duration,
/// full fare breakdown, commission, payment method, MoMo payout status,
/// dispute link, "GO TO WALLET" CTA.
class DriverRideCompleteScreen extends ConsumerWidget {
  const DriverRideCompleteScreen({super.key});

  // Mock trip summary matching Figma design
  static const _summary = TripSummary(
    rideId: 'RID-92834',
    clientName: 'Kofi Mensah',
    clientRating: 4.9,
    paymentMethod: 'Cash Payment',
    pickupAddress: 'Makola Market, Accra Central',
    dropoffAddress: 'Legon Botanical Gardens',
    distanceKm: 12.4,
    durationMins: 24,
    baseFarePesewas: 1200,
    distanceFarePesewas: 3250,
    timeFarePesewas: 600,
    surgeFarePesewas: 920,
    taxesPesewas: 180,
    promoPesewas: 500,
    totalFarePesewas: 5650,
    commissionPesewas: 1130,
    netEarningsPesewas: 4250,
    payoutMethod: 'Instant MoMo Payout',
    payoutStatus: 'PROCESSING',
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const s = _summary;

    return Scaffold(
      backgroundColor: MyShopColors.surfaceGrey,
      appBar: AppBar(
        backgroundColor: MyShopColors.surfaceWhite,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: MyShopColors.textPrimary),
          onPressed: () {
            ref.read(activeRideProvider.notifier).clearRide();
            Navigator.of(context).pop();
          },
        ),
        title: const Text('Trip Summary', style: TextStyle(fontFamily: 'Raleway', fontSize: 18, fontWeight: FontWeight.w700, color: MyShopColors.textPrimary)),
        centerTitle: false,
      ),
      body: ListView(
        padding: const EdgeInsets.all(MyShopSpacing.md),
        children: [
          // Completion banner
          Container(
            padding: const EdgeInsets.all(MyShopSpacing.md),
            decoration: BoxDecoration(color: MyShopColors.primaryGoldLight, borderRadius: BorderRadius.circular(16)),
            child: Row(children: [
              const Icon(Icons.check_circle, size: 24, color: MyShopColors.primaryGold),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Trip Completed!', style: TextStyle(fontFamily: 'Raleway', fontSize: 16, fontWeight: FontWeight.w700, color: MyShopColors.textPrimary)),
                Text('Earnings have been calculated and processed.', style: MyShopTypography.body2),
              ])),
            ]),
          ),
          const SizedBox(height: MyShopSpacing.md),

          // Passenger + fare card
          Container(
            padding: const EdgeInsets.all(MyShopSpacing.md),
            decoration: BoxDecoration(color: MyShopColors.surfaceWhite, borderRadius: BorderRadius.circular(16), border: Border.all(color: MyShopColors.divider.withValues(alpha: 0.5))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const CircleAvatar(radius: 20, backgroundColor: MyShopColors.avatarPlaceholder, child: Icon(Icons.person, size: 20, color: MyShopColors.textSecondary)),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s.clientName, style: const TextStyle(fontFamily: 'Raleway', fontSize: 14, fontWeight: FontWeight.w700, color: MyShopColors.textPrimary)),
                  Row(children: [
                    const Icon(Icons.star, size: 12, color: MyShopColors.ratingStar),
                    Text(' ${s.clientRating}', style: MyShopTypography.body2.copyWith(fontWeight: FontWeight.w600)),
                    Text(' · ${s.paymentMethod}', style: MyShopTypography.body2),
                  ]),
                ])),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('TOTAL FARE', style: MyShopTypography.overline.copyWith(fontSize: 9, color: MyShopColors.primaryGold)),
                  Text(s.totalFareDisplay, style: const TextStyle(fontFamily: 'Raleway', fontSize: 18, fontWeight: FontWeight.w900, color: MyShopColors.textPrimary)),
                ]),
              ]),
              const SizedBox(height: MyShopSpacing.md),

              // Pickup/dropoff
              _RouteRow(icon: Icons.circle, iconColor: MyShopColors.textSecondary, label: 'PICKUP', address: s.pickupAddress),
              const SizedBox(height: 8),
              _RouteRow(icon: Icons.radio_button_checked, iconColor: MyShopColors.primaryGold, label: 'DROP-OFF', address: s.dropoffAddress),
              const SizedBox(height: MyShopSpacing.md),

              // Distance + Duration
              Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('DISTANCE', style: MyShopTypography.overline.copyWith(fontSize: 10)),
                  Row(children: [
                    const Icon(Icons.straighten, size: 14, color: MyShopColors.textSecondary),
                    const SizedBox(width: 4),
                    Text('${s.distanceKm} km', style: const TextStyle(fontFamily: 'Raleway', fontSize: 14, fontWeight: FontWeight.w700, color: MyShopColors.textPrimary)),
                  ]),
                ])),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('DURATION', style: MyShopTypography.overline.copyWith(fontSize: 10)),
                  Row(children: [
                    const Icon(Icons.access_time, size: 14, color: MyShopColors.textSecondary),
                    const SizedBox(width: 4),
                    Text('${s.durationMins} mins', style: const TextStyle(fontFamily: 'Raleway', fontSize: 14, fontWeight: FontWeight.w700, color: MyShopColors.textPrimary)),
                  ]),
                ])),
              ]),
            ]),
          ),
          const SizedBox(height: MyShopSpacing.md),

          // Fare breakdown
          Container(
            padding: const EdgeInsets.all(MyShopSpacing.md),
            decoration: BoxDecoration(color: MyShopColors.surfaceWhite, borderRadius: BorderRadius.circular(16)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('Fare Breakdown', style: TextStyle(fontFamily: 'Raleway', fontSize: 16, fontWeight: FontWeight.w700, color: MyShopColors.textPrimary)),
                Text('ID: #${s.rideId}', style: MyShopTypography.body2.copyWith(color: MyShopColors.primaryGold, fontSize: 11)),
              ]),
              const SizedBox(height: MyShopSpacing.md),
              _FareRow(label: 'Base Fare', amount: s.baseFarePesewas),
              _FareRow(label: 'Distance (${s.distanceKm} km)', amount: s.distanceFarePesewas),
              _FareRow(label: 'Time (${s.durationMins} mins)', amount: s.timeFarePesewas),
              if (s.surgeFarePesewas > 0) _FareRow(label: 'Surge Pricing (1.2x)', amount: s.surgeFarePesewas, icon: Icons.bolt),
              const Divider(height: 24),
              _FareRow(label: 'Subtotal', amount: s.baseFarePesewas + s.distanceFarePesewas + s.timeFarePesewas + s.surgeFarePesewas),
              _FareRow(label: 'Taxes & Levies', amount: s.taxesPesewas),
              if (s.promoPesewas > 0) _FareRow(label: 'Promotional Discount', amount: -s.promoPesewas),
              const Divider(height: 24),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('Total Paid', style: TextStyle(fontFamily: 'Raleway', fontSize: 16, fontWeight: FontWeight.w700, color: MyShopColors.textPrimary)),
                Text(s.totalFareDisplay, style: const TextStyle(fontFamily: 'Raleway', fontSize: 20, fontWeight: FontWeight.w900, color: MyShopColors.primaryGold)),
              ]),
            ]),
          ),
          const SizedBox(height: MyShopSpacing.md),

          // Commission card
          Container(
            padding: const EdgeInsets.all(MyShopSpacing.md),
            decoration: BoxDecoration(color: MyShopColors.primaryGoldLight, borderRadius: BorderRadius.circular(16), border: Border.all(color: MyShopColors.primaryGold.withValues(alpha: 0.3))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.info_outline, size: 16, color: MyShopColors.primaryGold),
                const SizedBox(width: 8),
                Text('Platform Commission (20%)', style: MyShopTypography.body1.copyWith(fontSize: 13)),
                const Spacer(),
                Text(s.commissionDisplay, style: const TextStyle(fontFamily: 'Raleway', fontSize: 14, fontWeight: FontWeight.w700, color: MyShopColors.textPrimary)),
              ]),
              const SizedBox(height: 4),
              Text('Commission supports local artisan verification and 24/7 police-check monitoring.', style: MyShopTypography.caption.copyWith(fontSize: 10)),
            ]),
          ),
          const SizedBox(height: MyShopSpacing.md),

          // Payment method row
          Row(children: [
            const Icon(Icons.credit_card, size: 18, color: MyShopColors.textSecondary),
            const SizedBox(width: 8),
            Text('Cash', style: MyShopTypography.body1),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: MyShopColors.successLight, borderRadius: BorderRadius.circular(6)),
              child: Text('SUCCESS', style: MyShopTypography.overline.copyWith(fontSize: 9, color: MyShopColors.success)),
            ),
          ]),
          const SizedBox(height: MyShopSpacing.md),

          // Payout status
          Container(
            padding: const EdgeInsets.all(MyShopSpacing.md),
            decoration: BoxDecoration(color: MyShopColors.surfaceWhite, borderRadius: BorderRadius.circular(16), border: Border.all(color: MyShopColors.divider.withValues(alpha: 0.5))),
            child: Row(children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(color: MyShopColors.surfaceGrey, borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.smartphone, size: 18, color: MyShopColors.textSecondary),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text(s.payoutMethod, style: MyShopTypography.body1.copyWith(fontSize: 13)),
                  const SizedBox(width: 8),
                  Text(s.payoutStatus, style: MyShopTypography.overline.copyWith(fontSize: 9, color: MyShopColors.primaryGold)),
                ]),
                Text('Funds are being sent to your registered MoMo wallet (+233 •••• 567). Usually arrives in 2-5 minutes.', style: MyShopTypography.caption.copyWith(fontSize: 10)),
              ])),
            ]),
          ),
          const SizedBox(height: MyShopSpacing.md),

          // Dispute link
          Center(
            child: TextButton(
              onPressed: () {},
              child: Text('Dispute this trip or report an issue', style: MyShopTypography.body2.copyWith(color: MyShopColors.error, fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(height: MyShopSpacing.sm),

          // Go to wallet CTA
          OutlinedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.account_balance_wallet_outlined, size: 18),
            label: const Text('GO TO WALLET'),
            style: OutlinedButton.styleFrom(
              foregroundColor: MyShopColors.textPrimary,
              side: const BorderSide(color: MyShopColors.divider),
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              textStyle: const TextStyle(fontFamily: 'Raleway', fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 0.5),
            ),
          ),
          const SizedBox(height: MyShopSpacing.xxl),
        ],
      ),
    );
  }
}

class _RouteRow extends StatelessWidget {
  const _RouteRow({required this.icon, required this.iconColor, required this.label, required this.address});
  final IconData icon;
  final Color iconColor;
  final String label;
  final String address;
  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, size: 12, color: iconColor),
      const SizedBox(width: 8),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: MyShopTypography.overline.copyWith(fontSize: 9)),
        Text(address, style: const TextStyle(fontFamily: 'Raleway', fontSize: 13, fontWeight: FontWeight.w600, color: MyShopColors.textPrimary)),
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
    final display = '${isNegative ? '- ' : ''}GHS ${(amount.abs() / 100).toStringAsFixed(2)}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        if (icon != null) ...[Icon(icon!, size: 14, color: MyShopColors.textSecondary), const SizedBox(width: 4)],
        Expanded(child: Text(label, style: MyShopTypography.body2.copyWith(color: MyShopColors.textPrimary))),
        Text(display, style: TextStyle(fontFamily: 'Raleway', fontSize: 13, fontWeight: FontWeight.w600, color: isNegative ? MyShopColors.success : MyShopColors.textPrimary)),
      ]),
    );
  }
}
