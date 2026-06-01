import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../trips/providers/driver_trips_provider.dart';

/// Last few trips the driver completed today, surfaced on the home sheet.
/// Reads from [driverTripsProvider] which auto-refreshes on `ride:state`
/// `completed` snapshots, so a finished trip appears here within a tick
/// of the End Trip tap.
class RecentActivitySection extends ConsumerWidget {
  const RecentActivitySection({super.key});

  static const _maxRows = 4;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tripsAsync = ref.watch(driverTripsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
              onTap: () => context.push('/trips'),
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
        tripsAsync.when(
          loading: () => const _ActivitySkeleton(),
          error: (_, __) => const _EmptyActivity(
            title: "Couldn't load recent trips",
            subtitle: 'Pull to refresh',
          ),
          data: (trips) {
            // Drop active rides — those live on the active-ride screen.
            // Sort newest first so the most recent completion bubbles up.
            final completed = trips
                .where((r) =>
                    r.status == RideStatus.completed ||
                    r.status == RideStatus.cancelled)
                .toList()
              ..sort((a, b) {
                final ai = a.completedAt ?? a.cancelledAt ?? a.createdAt;
                final bi = b.completedAt ?? b.cancelledAt ?? b.createdAt;
                return bi.compareTo(ai);
              });
            if (completed.isEmpty) {
              return const _EmptyActivity(
                title: 'No trips yet',
                subtitle: 'Your completed trips will appear here',
              );
            }
            return Column(
              children: [
                for (final trip in completed.take(_maxRows))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _ActivityRow(trip: trip),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.trip});

  final Ride trip;

  @override
  Widget build(BuildContext context) {
    final isCompleted = trip.status == RideStatus.completed;
    final dateLabel = _formatTime(
      trip.completedAt ?? trip.cancelledAt ?? trip.createdAt,
    );
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: MyShopSpacing.md, vertical: 12),
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: MyShopColors.divider.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isCompleted
                  ? MyShopColors.successLight
                  : MyShopColors.surfaceGrey,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isCompleted ? Icons.check_circle_outline : Icons.cancel_outlined,
              size: 18,
              color: isCompleted
                  ? MyShopColors.success
                  : MyShopColors.textSecondary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  trip.dropoffAddress.isEmpty ? 'Trip' : trip.dropoffAddress,
                  style: const TextStyle(
                    fontFamily: 'Raleway',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: MyShopColors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  dateLabel,
                  style: MyShopTypography.body2.copyWith(fontSize: 11),
                ),
              ],
            ),
          ),
          Text(
            trip.finalFareDisplay,
            style: const TextStyle(
              fontFamily: 'Raleway',
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: MyShopColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  static String _formatTime(DateTime at) {
    final local = at.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tripDay = DateTime(local.year, local.month, local.day);
    final diff = today.difference(tripDay).inDays;
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    if (diff == 0) return 'Today · $hh:$mm';
    if (diff == 1) return 'Yesterday · $hh:$mm';
    if (diff < 7) return '$diff days ago · $hh:$mm';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${local.day} ${months[local.month - 1]} · $hh:$mm';
  }
}

class _EmptyActivity extends StatelessWidget {
  const _EmptyActivity({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: MyShopColors.divider.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: MyShopColors.surfaceGrey,
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Icon(
              Icons.directions_car_outlined,
              size: 24,
              color: MyShopColors.textSecondary,
            ),
          ),
          const SizedBox(height: MyShopSpacing.md),
          Text(
            title,
            style: MyShopTypography.body1.copyWith(
              color: MyShopColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: MyShopSpacing.xs),
          Text(
            subtitle,
            style: MyShopTypography.body2.copyWith(
              color: MyShopColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivitySkeleton extends StatelessWidget {
  const _ActivitySkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(3, (_) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Container(
            height: 64,
            decoration: BoxDecoration(
              color: MyShopColors.shimmerBase,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }),
    );
  }
}
