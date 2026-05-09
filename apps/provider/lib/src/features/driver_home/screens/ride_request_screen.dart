import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:shared_utils/shared_utils.dart';

import '../providers/driver_location_provider.dart';
import '../providers/ride_request_provider.dart';
import 'active_ride_screen.dart';

/// Full-screen incoming ride request notification.
///
/// Figma: node 189:10815
/// PRD Reference: PRD 5.2
class RideRequestScreen extends ConsumerStatefulWidget {
  const RideRequestScreen({super.key, required this.ride});

  final Ride ride;

  @override
  ConsumerState<RideRequestScreen> createState() => _RideRequestScreenState();
}

class _RideRequestScreenState extends ConsumerState<RideRequestScreen> {
  static const _acceptanceWindowSecs = 22;
  late int _secondsRemaining;
  Timer? _timer;
  bool _isAccepting = false;

  @override
  void initState() {
    super.initState();
    _secondsRemaining = _acceptanceWindowSecs;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_secondsRemaining > 0) {
        setState(() => _secondsRemaining--);
      } else {
        _decline();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _accept() async {
    if (_isAccepting) return;
    _timer?.cancel();
    setState(() => _isAccepting = true);
    final ok =
        await ref.read(activeRideProvider.notifier).acceptRide(widget.ride);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => const ActiveRideScreen(),
        ),
      );
      return;
    }
    // Acceptance failed — surface the error and let the driver dismiss the
    // request manually. We don't restart the countdown because the matcher
    // may already have moved on.
    final message =
        ref.read(activeRideProvider).errorMessage ?? "Couldn't accept the ride";
    setState(() => _isAccepting = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _decline() {
    _timer?.cancel();
    if (mounted) Navigator.of(context).pop('declined');
  }

  @override
  Widget build(BuildContext context) {
    final ride = widget.ride;
    final progress = _secondsRemaining / _acceptanceWindowSecs;

    return Scaffold(
      backgroundColor: MyShopColors.surfaceGrey,
      body: SafeArea(
        child: Column(
          children: [
            // Top bar
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: MyShopSpacing.md,
                vertical: MyShopSpacing.sm,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Icon(Icons.more_vert,
                      color: MyShopColors.textSecondary),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: MyShopColors.surfaceWhite,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _Dot(color: MyShopColors.online),
                        SizedBox(width: 6),
                        Text('Online',
                            style: TextStyle(
                                fontFamily: 'Raleway',
                                fontSize: 14,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  const Icon(Icons.notifications_outlined,
                      color: MyShopColors.textSecondary),
                ],
              ),
            ),

            // Main card
            Expanded(
              child: Container(
                margin: const EdgeInsets.only(top: MyShopSpacing.lg),
                decoration: const BoxDecoration(
                  color: MyShopColors.surfaceWhite,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
                ),
                child: ListView(
                  padding: const EdgeInsets.all(MyShopSpacing.md),
                  children: [
                    const SizedBox(height: MyShopSpacing.sm),
                    // Header + Timer
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('New Ride Request',
                                style: MyShopTypography.body2),
                            const SizedBox(height: 4),
                            const Text('Immediate Pickup',
                                style: TextStyle(
                                    fontFamily: 'Raleway',
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: MyShopColors.textPrimary)),
                          ],
                        ),
                        _CountdownTimer(
                            progress: progress, seconds: _secondsRemaining),
                      ],
                    ),
                    const SizedBox(height: MyShopSpacing.lg),

                    // Client card
                    _ClientCard(ride: ride),
                    const SizedBox(height: MyShopSpacing.lg),

                    // Pickup location
                    _PickupInfo(ride: ride),
                    const SizedBox(height: MyShopSpacing.lg),

                    // Estimated earnings
                    _EarningsCard(ride: ride),
                    const SizedBox(height: MyShopSpacing.xl),

                    // Action buttons
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: OutlinedButton.icon(
                            onPressed: _isAccepting ? null : _decline,
                            icon: const Icon(Icons.close, size: 18),
                            label: const Text('Decline'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: MyShopColors.error,
                              side: const BorderSide(color: MyShopColors.error),
                              minimumSize: const Size(0, 52),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              textStyle: const TextStyle(
                                  fontFamily: 'Raleway',
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                        const SizedBox(width: MyShopSpacing.md),
                        Expanded(
                          flex: 3,
                          child: ElevatedButton(
                            onPressed: _isAccepting ? null : _accept,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: MyShopColors.darkSlate,
                              foregroundColor: MyShopColors.textOnPrimary,
                              disabledBackgroundColor:
                                  MyShopColors.darkSlate.withValues(alpha: 0.6),
                              disabledForegroundColor:
                                  MyShopColors.textOnPrimary,
                              minimumSize: const Size(0, 52),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              textStyle: const TextStyle(
                                  fontFamily: 'Raleway',
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700),
                            ),
                            child: _isAccepting
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      valueColor: AlwaysStoppedAnimation(
                                          MyShopColors.textOnPrimary),
                                    ),
                                  )
                                : const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.check, size: 18),
                                      SizedBox(width: 8),
                                      Text('Accept'),
                                    ],
                                  ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: MyShopSpacing.md),

                    Text(
                      'Accepting this trip implies agreement with the service terms.\nCancellations may affect your driver rating.',
                      textAlign: TextAlign.center,
                      style: MyShopTypography.caption.copyWith(fontSize: 11),
                    ),
                    const SizedBox(height: MyShopSpacing.md),

                    // High demand banner
                    if (ride.hasSurge)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                            color: MyShopColors.error,
                            borderRadius: BorderRadius.circular(12)),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.warning_amber,
                                size: 18, color: MyShopColors.textOnPrimary),
                            SizedBox(width: 8),
                            Text('HIGH DEMAND',
                                style: TextStyle(
                                    fontFamily: 'Raleway',
                                    fontSize: 14,
                                    fontWeight: FontWeight.w900,
                                    color: MyShopColors.textOnPrimary,
                                    letterSpacing: 0.5)),
                          ],
                        ),
                      ),
                    const SizedBox(height: MyShopSpacing.md),

                    // Safety notice
                    Container(
                      padding: const EdgeInsets.all(MyShopSpacing.md),
                      decoration: BoxDecoration(
                          color: MyShopColors.surfaceGrey,
                          borderRadius: BorderRadius.circular(12)),
                      child: Row(
                        children: [
                          const Icon(Icons.shield_outlined,
                              size: 20, color: MyShopColors.textSecondary),
                          const SizedBox(width: 12),
                          Expanded(
                              child: Text(
                                  'For your security, passenger phone numbers are masked. All calls are recorded for safety.',
                                  style: MyShopTypography.body2
                                      .copyWith(fontSize: 12))),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle));
}

class _CountdownTimer extends StatelessWidget {
  const _CountdownTimer({required this.progress, required this.seconds});
  final double progress;
  final int seconds;
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 56,
      height: 56,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
              value: progress,
              strokeWidth: 3,
              backgroundColor: MyShopColors.divider,
              valueColor:
                  const AlwaysStoppedAnimation(MyShopColors.primaryGold)),
          Text('${seconds}s',
              style: const TextStyle(
                  fontFamily: 'Raleway',
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: MyShopColors.primaryGold)),
        ],
      ),
    );
  }
}

class _ClientCard extends StatelessWidget {
  const _ClientCard({required this.ride});
  final Ride ride;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(MyShopSpacing.md),
      decoration: BoxDecoration(
          color: MyShopColors.surfaceWhite,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: MyShopColors.divider)),
      child: Row(
        children: [
          _ClientAvatar(photoUrl: ride.clientPhotoUrl, size: 48),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(ride.clientName ?? 'Passenger',
                    style: const TextStyle(
                        fontFamily: 'Raleway',
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
                const SizedBox(width: 4),
                const Icon(Icons.verified, size: 16, color: MyShopColors.info),
              ]),
              const SizedBox(height: 4),
              Row(children: [
                const Icon(Icons.star,
                    size: 14, color: MyShopColors.ratingStar),
                const SizedBox(width: 2),
                Text('${ride.clientRating ?? 0}',
                    style: MyShopTypography.body2.copyWith(
                        fontWeight: FontWeight.w600,
                        color: MyShopColors.textPrimary)),
                Text(' (${ride.clientTripCount ?? 0}+ trips)',
                    style: MyShopTypography.body2),
              ]),
            ]),
          ),
        ],
      ),
    );
  }
}

class _PickupInfo extends ConsumerWidget {
  const _PickupInfo({required this.ride});
  final Ride ride;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Live driver→pickup ETA derived from the most recent GPS fix. Falls
    // back to null (chip hidden) when the location stream hasn't emitted
    // yet — the static trip distance/duration below is unaffected.
    final position = ref.watch(driverLocationStreamProvider).valueOrNull;
    int? minutesAway;
    double? metersAway;
    if (position != null) {
      metersAway = haversineMeters(
        position.latitude,
        position.longitude,
        ride.pickupLat,
        ride.pickupLng,
      );
      minutesAway = estimatedEtaMinutes(metersAway);
    }

    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
              color: MyShopColors.surfaceGrey,
              borderRadius: BorderRadius.circular(16)),
          child: const Icon(Icons.location_on,
              size: 18, color: MyShopColors.textSecondary)),
      const SizedBox(width: 12),
      Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('PICKUP LOCATION',
            style: MyShopTypography.overline
                .copyWith(fontSize: 11, letterSpacing: 0.5)),
        const SizedBox(height: 4),
        Text(ride.pickupAddress,
            style: const TextStyle(
                fontFamily: 'Raleway',
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: MyShopColors.textPrimary)),
        const SizedBox(height: 8),
        Row(children: [
          const Icon(Icons.straighten,
              size: 14, color: MyShopColors.textSecondary),
          const SizedBox(width: 4),
          Text(ride.distanceDisplay, style: MyShopTypography.body2),
          const SizedBox(width: 16),
          const Icon(Icons.access_time, size: 14, color: MyShopColors.online),
          const SizedBox(width: 4),
          Text('${ride.estimatedDurationMins} min drive',
              style:
                  MyShopTypography.body2.copyWith(color: MyShopColors.online)),
        ]),
        if (minutesAway != null) ...[
          const SizedBox(height: 8),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: MyShopColors.primaryGold.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.near_me,
                  size: 13, color: MyShopColors.primaryGold),
              const SizedBox(width: 6),
              Text(
                '${(metersAway! / 1000).toStringAsFixed(1)} km · '
                '~${formatEtaLabel(minutesAway)} away',
                style: MyShopTypography.body2.copyWith(
                  color: MyShopColors.primaryGold,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ]),
          ),
        ],
      ])),
    ]);
  }
}

class _EarningsCard extends StatelessWidget {
  const _EarningsCard({required this.ride});
  final Ride ride;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(MyShopSpacing.md),
      decoration: BoxDecoration(
          color: MyShopColors.primaryGoldLight,
          borderRadius: BorderRadius.circular(16)),
      child: Row(children: [
        Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
                color: MyShopColors.primaryGold.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.account_balance_wallet,
                size: 20, color: MyShopColors.primaryGold)),
        const SizedBox(width: 12),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Estimated Earnings', style: MyShopTypography.body2),
          Text(ride.estimatedFareDisplay,
              style: const TextStyle(
                  fontFamily: 'Raleway',
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: MyShopColors.textPrimary)),
        ])),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
              color: MyShopColors.surfaceWhite,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: MyShopColors.divider)),
          child: Text(ride.paymentMethod,
              style: MyShopTypography.body2.copyWith(
                  fontWeight: FontWeight.w600,
                  color: MyShopColors.textPrimary)),
        ),
      ]),
    );
  }
}

/// Round avatar that loads `photoUrl` over the network when available and
/// falls back to a generic person icon while loading or on error.
class _ClientAvatar extends StatelessWidget {
  const _ClientAvatar({required this.photoUrl, required this.size});

  final String? photoUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final url = photoUrl;
    if (url == null || url.isEmpty) return _placeholder();
    // Decode at ~3x retina so a high-res upload doesn't balloon RAM usage.
    final cacheDim = (size * 3).round();
    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        memCacheWidth: cacheDim,
        memCacheHeight: cacheDim,
        placeholder: (_, __) => _placeholder(),
        errorWidget: (_, __, ___) => _placeholder(),
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: MyShopColors.avatarPlaceholder,
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.person, color: MyShopColors.textSecondary),
    );
  }
}
