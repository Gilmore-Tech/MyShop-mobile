import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

/// Recent activity list with trip cards.
///
/// Figma: nodes 164:10493 → 164:10579
/// - "RECENT ACTIVITY" header + "See All" gold link
/// - Trip cards: map-pin icon circle, destination name, time + star rating, amount + "SETTLED"
class RecentActivitySection extends StatelessWidget {
  const RecentActivitySection({super.key});

  // Mock data matching the Figma design
  static const _trips = [
    _TripData(
      destination: 'Kotoka Int. Airport',
      timeAgo: '15 mins ago',
      rating: 5.0,
      amountGhs: '85.00',
    ),
    _TripData(
      destination: 'Accra Mall, Tetteh Quarshie',
      timeAgo: '1 hour ago',
      rating: 4.8,
      amountGhs: '42.50',
    ),
    _TripData(
      destination: 'Labadi Beach Resort',
      timeAgo: '3 hours ago',
      rating: 4.9,
      amountGhs: '60.00',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header row
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'RECENT ACTIVITY',
              style: TextStyle(
                fontFamily: 'Raleway',
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: MyShopColors.textPrimary,
                letterSpacing: 0.7,
                height: 1.43,
              ),
            ),
            GestureDetector(
              onTap: () {
                // TODO: Navigate to full activity list
              },
              child: Text(
                'See All',
                style: MyShopTypography.body2.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: MyShopColors.primaryGold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: MyShopSpacing.md),

        // Trip cards
        ...List.generate(_trips.length, (index) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: index < _trips.length - 1 ? MyShopSpacing.sm : 0,
            ),
            child: _TripCard(trip: _trips[index]),
          );
        }),
      ],
    );
  }
}

class _TripData {
  const _TripData({
    required this.destination,
    required this.timeAgo,
    required this.rating,
    required this.amountGhs,
  });

  final String destination;
  final String timeAgo;
  final double rating;
  final String amountGhs;
}

class _TripCard extends StatelessWidget {
  const _TripCard({required this.trip});

  final _TripData trip;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 74,
      padding: const EdgeInsets.symmetric(horizontal: MyShopSpacing.md),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: MyShopColors.divider.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        children: [
          // Map pin icon
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: MyShopColors.surfaceWhite,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: MyShopColors.divider),
            ),
            child: const Icon(
              Icons.location_on_outlined,
              size: 20,
              color: MyShopColors.textSecondary,
            ),
          ),
          const SizedBox(width: MyShopSpacing.sm + 4),

          // Destination + time + rating
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  trip.destination,
                  style: const TextStyle(
                    fontFamily: 'Raleway',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: MyShopColors.textPrimary,
                    height: 1.43,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(
                      Icons.access_time,
                      size: 12,
                      color: MyShopColors.textSecondary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      trip.timeAgo,
                      style: const TextStyle(
                        fontFamily: 'Raleway',
                        fontSize: 10,
                        fontWeight: FontWeight.w400,
                        color: MyShopColors.textSecondary,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(width: MyShopSpacing.sm),
                    // Rating badge
                    Container(
                      height: 16,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: MyShopColors.divider.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            trip.rating.toStringAsFixed(1),
                            style: const TextStyle(
                              fontFamily: 'Raleway',
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: MyShopColors.textPrimary,
                              height: 1.56,
                            ),
                          ),
                          const SizedBox(width: 2),
                          const Icon(
                            Icons.star,
                            size: 8,
                            color: MyShopColors.ratingStar,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Amount + status
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'GHS ${trip.amountGhs}',
                style: const TextStyle(
                  fontFamily: 'Raleway',
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: MyShopColors.textPrimary,
                  height: 1.43,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'SETTLED',
                style: TextStyle(
                  fontFamily: 'Raleway',
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: MyShopColors.textSecondary.withValues(alpha: 0.6),
                  height: 1.5,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
