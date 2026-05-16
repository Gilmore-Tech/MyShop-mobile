import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

/// Full-screen trip summary modal shown when a trip card is tapped.
///
/// Figma: node 231:15139
///
/// Layout (top to bottom):
///   1. Map preview image with distance badge (8.2 km) + gradient fade
///   2. TRIP-ID tag + "Completed" status badge
///   3. "Trip Summary" heading
///   4. Date + Time row (calendar icon, clock icon, duration)
///   5. Pickup → Dropoff route with dot-line connector
///   6. Fare Breakdown table in a card with:
///      - Header: "Fare Breakdown" + ID: #RID-xxxxx
///      - Base Fare, Distance, Time, Surge Pricing
///      - Divider → Subtotal, Taxes & Levies, Promotional Discount
///      - Divider → Total Paid (bold)
///      - Platform Commission (20%) bordered card
///      - Footer: Payment method + SUCCESS tag
///   7. "Report an Incident or Item Lost" link
class TripDetailModal extends StatelessWidget {
  const TripDetailModal({super.key, required this.trip});

  final TripDetailData trip;

  /// Show this modal as a centered dialog overlay with dark scrim.
  static Future<void> show(BuildContext context, TripDetailData trip) {
    return showDialog(
      context: context,
      barrierColor: const Color(0x99000000),
      builder: (_) => TripDetailModal(trip: trip),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 358,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        margin: const EdgeInsets.symmetric(horizontal: MyShopSpacing.md),
        decoration: BoxDecoration(
          color: MyShopColors.surfaceWhite,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
              color: Color(0x40000000),
              blurRadius: 50,
              offset: Offset(0, 25),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Material(
            color: MyShopColors.surfaceWhite,
            child: ListView(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              children: [
                // ── 1. Map preview with distance badge ──
                _MapPreview(distanceKm: trip.distanceKm),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: MyShopSpacing.md),

                      // ── 2. Trip ID + Status badge ──
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _TripIdTag(tripId: trip.tripId),
                          _StatusBadge(status: trip.status),
                        ],
                      ),
                      const SizedBox(height: MyShopSpacing.sm),

                      // ── 3. Trip Summary heading ──
                      const Text(
                        'Trip Summary',
                        style: TextStyle(
                          fontFamily: 'Raleway',
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: MyShopColors.textPrimary,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: MyShopSpacing.sm),

                      // ── 4. Date + Time ──
                      Row(
                        children: [
                          const Icon(Icons.calendar_today,
                              size: 12, color: MyShopColors.textSecondary),
                          const SizedBox(width: 8),
                          Text(trip.date, style: _metaStyle),
                          const SizedBox(width: 12),
                          const Text('•',
                              style: TextStyle(
                                  color: MyShopColors.textSecondary,
                                  fontSize: 12)),
                          const SizedBox(width: 12),
                          const Icon(Icons.access_time,
                              size: 12, color: MyShopColors.textSecondary),
                          const SizedBox(width: 8),
                          Text(trip.timeRange, style: _metaStyle),
                        ],
                      ),
                      const SizedBox(height: MyShopSpacing.lg),

                      // ── 5. Route: Pickup → Dropoff ──
                      _RouteSection(
                        pickupTime: trip.pickupTime,
                        pickupAddress: trip.pickupAddress,
                        dropoffTime: trip.dropoffTime,
                        dropoffAddress: trip.dropoffAddress,
                      ),
                      const SizedBox(height: MyShopSpacing.lg),
                    ],
                  ),
                ),

                // ── 6. Fare Breakdown card ──
                const Divider(height: 1, color: MyShopColors.divider),
                _FareBreakdownCard(trip: trip),

              ],
            ),
          ),
        ),
      ),
    );
  }

  static const _metaStyle = TextStyle(
    fontFamily: 'Raleway',
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: MyShopColors.textSecondary,
  );
}

// ─── Map Preview ────────────────────────────────────────────────────────────

class _MapPreview extends StatelessWidget {
  const _MapPreview({required this.distanceKm});
  final String distanceKm;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 180,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Placeholder map background
          Container(
            decoration: const BoxDecoration(
              color: MyShopColors.surfaceGrey,
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: const Center(
              child: Icon(Icons.map_outlined,
                  size: 48, color: MyShopColors.disabled),
            ),
          ),
          // Bottom gradient fade
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 48,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x00000000), Color(0x33000000)],
                ),
              ),
            ),
          ),
          // Distance badge (top right)
          Positioned(
            top: MyShopSpacing.md,
            right: MyShopSpacing.md,
            child: Container(
              height: 22,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: MyShopColors.surfaceWhite.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(11),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x12171A1F),
                    blurRadius: 2.5,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.navigation,
                      size: 12, color: MyShopColors.primaryGold),
                  const SizedBox(width: 4),
                  Text(
                    distanceKm,
                    style: const TextStyle(
                      fontFamily: 'Raleway',
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: MyShopColors.primaryGold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Trip ID Tag ────────────────────────────────────────────────────────────

class _TripIdTag extends StatelessWidget {
  const _TripIdTag({required this.tripId});
  final String tripId;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 17,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: MyShopColors.surfaceGrey),
      ),
      child: Center(
        child: Text(
          'TRIP-ID: #$tripId',
          style: const TextStyle(
            fontFamily: 'Raleway',
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: MyShopColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

// ─── Status Badge ───────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final String status;

  bool get _isCompleted => status == 'Completed';

  @override
  Widget build(BuildContext context) {
    final bgColor =
        _isCompleted ? const Color(0xFFD1FAE5) : MyShopColors.errorLight;
    final textColor =
        _isCompleted ? const Color(0xFF047857) : MyShopColors.error;
    final icon = _isCompleted ? Icons.check_circle : Icons.cancel;

    return Container(
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: textColor),
          const SizedBox(width: 4),
          Text(
            status,
            style: TextStyle(
              fontFamily: 'Raleway',
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Route Section (Pickup → Dropoff) ───────────────────────────────────────

class _RouteSection extends StatelessWidget {
  const _RouteSection({
    required this.pickupTime,
    required this.pickupAddress,
    required this.dropoffTime,
    required this.dropoffAddress,
  });

  final String pickupTime;
  final String pickupAddress;
  final String dropoffTime;
  final String dropoffAddress;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Route dots + line
        Column(
          children: [
            _RouteDot(color: MyShopColors.darkSlate),
            Container(width: 1, height: 52, color: MyShopColors.divider),
            _RouteDot(color: MyShopColors.primaryGold),
          ],
        ),
        const SizedBox(width: 16),

        // Addresses
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'PICKUP · $pickupTime',
                style: const TextStyle(
                  fontFamily: 'Raleway',
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: MyShopColors.textSecondary,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                pickupAddress,
                style: const TextStyle(
                  fontFamily: 'Raleway',
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: MyShopColors.textPrimary,
                  height: 1.36,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'DROPOFF · $dropoffTime',
                style: const TextStyle(
                  fontFamily: 'Raleway',
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: MyShopColors.textSecondary,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                dropoffAddress,
                style: const TextStyle(
                  fontFamily: 'Raleway',
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: MyShopColors.textPrimary,
                  height: 1.36,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RouteDot extends StatelessWidget {
  const _RouteDot({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color, width: 2),
      ),
      child: Center(
        child: Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      ),
    );
  }
}

// ─── Fare Breakdown Card ────────────────────────────────────────────────────

class _FareBreakdownCard extends StatelessWidget {
  const _FareBreakdownCard({required this.trip});
  final TripDetailData trip;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(17, MyShopSpacing.md, 17, 0),
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFFF9FAFB),
              borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
              border: Border(
                bottom: BorderSide(color: MyShopColors.divider, width: 0.5),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Fare Breakdown',
                  style: TextStyle(
                    fontFamily: 'Raleway',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: MyShopColors.textPrimary,
                    letterSpacing: -0.35,
                  ),
                ),
                Text(
                  'ID: #${trip.rideId}',
                  style: const TextStyle(
                    fontFamily: 'Raleway',
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: MyShopColors.primaryGold,
                    letterSpacing: -0.35,
                  ),
                ),
              ],
            ),
          ),

          // Line items
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 16, 10, 0),
            child: Column(
              children: [
                _FareLine(label: 'Base Fare', amount: trip.baseFare),
                const SizedBox(height: 16),
                _FareLine(
                    label: 'Distance (${trip.distanceKm})',
                    amount: trip.distanceFare),
                const SizedBox(height: 16),
                _FareLine(
                    label: 'Time (${trip.durationMins} mins)',
                    amount: trip.timeFare),
                const SizedBox(height: 16),
                _FareLine(
                  label: 'Surge Pricing (${trip.surgeMultiplier})',
                  amount: trip.surgeFare,
                  icon: Icons.bolt,
                ),

                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Divider(height: 1, color: MyShopColors.divider),
                ),
                _FareLine(label: 'Subtotal', amount: trip.subtotal),
                const SizedBox(height: 16),
                _FareLine(label: 'Taxes & Levies', amount: trip.taxes),
                const SizedBox(height: 16),
                _FareLine(
                  label: 'Promotional Discount',
                  amount: trip.promoDiscount,
                  isNegative: true,
                ),

                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Divider(height: 1, color: MyShopColors.divider),
                ),

                // Total
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Total Paid',
                      style: TextStyle(
                        fontFamily: 'Raleway',
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: MyShopColors.textPrimary,
                      ),
                    ),
                    Text(
                      trip.totalPaid,
                      style: const TextStyle(
                        fontFamily: 'Raleway',
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: MyShopColors.darkSlate,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Commission box
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: MyShopColors.primaryGold),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.info_outline,
                              size: 12, color: MyShopColors.textPrimary),
                          const SizedBox(width: 6),
                          const Text(
                            'Platform Commission (20%)',
                            style: TextStyle(
                              fontFamily: 'Raleway',
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
                              color: MyShopColors.textPrimary,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            trip.commission,
                            style: const TextStyle(
                              fontFamily: 'Raleway',
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
                              color: MyShopColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.only(left: 22),
                        child: Text(
                          'Commission supports local artisan verification and 24/7 police-check monitoring.',
                          style: TextStyle(
                            fontFamily: 'Raleway',
                            fontSize: 10,
                            fontWeight: FontWeight.w400,
                            color: MyShopColors.textSecondary,
                            height: 1.6,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Payment method footer
          Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: const BoxDecoration(
              color: Color(0xFFF9FAFB),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(8)),
              border: Border(
                top: BorderSide(color: MyShopColors.divider, width: 0.5),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.credit_card,
                    size: 16, color: MyShopColors.textPrimary),
                const SizedBox(width: 8),
                Text(
                  trip.paymentMethod,
                  style: const TextStyle(
                    fontFamily: 'Raleway',
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: MyShopColors.textPrimary,
                  ),
                ),
                const Spacer(),
                Text(
                  'SUCCESS',
                  style: TextStyle(
                    fontFamily: 'Raleway',
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: MyShopColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FareLine extends StatelessWidget {
  const _FareLine({
    required this.label,
    required this.amount,
    this.icon,
    this.isNegative = false,
  });

  final String label;
  final String amount;
  final IconData? icon;
  final bool isNegative;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon!, size: 14, color: MyShopColors.textSecondary),
          const SizedBox(width: 6),
        ],
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontFamily: 'Raleway',
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: MyShopColors.textSecondary,
            ),
          ),
        ),
        Text(
          '${isNegative ? '- ' : ''}$amount',
          style: const TextStyle(
            fontFamily: 'Raleway',
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: MyShopColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

// ─── Data Model ─────────────────────────────────────────────────────────────

/// Data needed to display the trip detail modal.
class TripDetailData {
  const TripDetailData({
    required this.tripId,
    required this.rideId,
    required this.status,
    required this.date,
    required this.timeRange,
    required this.pickupTime,
    required this.pickupAddress,
    required this.dropoffTime,
    required this.dropoffAddress,
    required this.distanceKm,
    required this.durationMins,
    required this.surgeMultiplier,
    required this.baseFare,
    required this.distanceFare,
    required this.timeFare,
    required this.surgeFare,
    required this.subtotal,
    required this.taxes,
    required this.promoDiscount,
    required this.totalPaid,
    required this.commission,
    required this.paymentMethod,
  });

  final String tripId;
  final String rideId;
  final String status;
  final String date;
  final String timeRange;
  final String pickupTime;
  final String pickupAddress;
  final String dropoffTime;
  final String dropoffAddress;
  final String distanceKm;
  final int durationMins;
  final String surgeMultiplier;
  final String baseFare;
  final String distanceFare;
  final String timeFare;
  final String surgeFare;
  final String subtotal;
  final String taxes;
  final String promoDiscount;
  final String totalPaid;
  final String commission;
  final String paymentMethod;
}
