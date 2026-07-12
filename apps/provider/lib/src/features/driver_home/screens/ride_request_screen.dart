import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:shared_utils/shared_utils.dart';

import '../../../core/providers/availability_controller.dart';
import '../../../core/providers/socket_provider.dart';
import '../../../core/services/local_notification_service.dart';
import '../../../core/utils/payment_method_label.dart';
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
  // Aligned with backend `ride_driver_acceptance_window_secs` (30 s).
  // Keep these in lockstep — if the UI counts past the backend window,
  // an Accept tap will fail with ACCEPTANCE_TIMEOUT.
  static const _acceptanceWindow = Duration(seconds: 30);
  late int _secondsRemaining;
  late DateTime _expiresAt;
  Timer? _timer;
  bool _isAccepting = false;
  bool _expired = false;
  bool _expiryHandled = false;

  @override
  void initState() {
    super.initState();
    _mountRequest(widget.ride);
  }

  @override
  void didUpdateWidget(covariant RideRequestScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ride.id != widget.ride.id) {
      _mountRequest(widget.ride);
    }
  }

  void _mountRequest(Ride ride) {
    _timer?.cancel();
    _expired = false;
    _expiryHandled = false;
    _isAccepting = false;
    ref.read(visibleRideRequestIdProvider.notifier).state = ride.id;
    _expiresAt = _deadlineFor(ride);
    _syncRemaining();
    // Start the looping ringtone the moment this screen mounts. The
    // service is a singleton — both ride and job request flows share
    // it, and we never have both open simultaneously, so a stale
    // timer from a previous session is impossible.
    LocalNotificationService.instance.startIncomingRingtone();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _syncRemaining();
    });
  }

  DateTime _deadlineFor(Ride ride) {
    final explicit = ref.read(rideRequestDeadlineByIdProvider)[ride.id];
    if (explicit != null) return explicit.toLocal();
    return ride.createdAt.toLocal().add(_acceptanceWindow);
  }

  int _secondsUntil(DateTime deadline) {
    final remainingMs = deadline.difference(DateTime.now()).inMilliseconds;
    if (remainingMs <= 0) return 0;
    return (remainingMs / 1000).ceil();
  }

  void _syncRemaining() {
    final remaining = _secondsUntil(_expiresAt);
    if (!mounted) return;
    setState(() {
      _secondsRemaining = remaining;
      _expired = remaining <= 0;
    });
    if (remaining <= 0) _handleExpiry();
  }

  void _handleExpiry() {
    if (_expiryHandled) return;
    _expiryHandled = true;
    _timer?.cancel();
    LocalNotificationService.instance.stopIncomingRingtone();
    ref.read(incomingRideRequestProvider.notifier).state = null;
    ref.read(surfacedRideIdsProvider.notifier).update(
          (s) => {...s, widget.ride.id},
        );
    // Best-effort only. The backend may already have timed this provider out;
    // the UI should close cleanly either way.
    ref
        .read(activeRideProvider.notifier)
        .declineRide(widget.ride.id, reason: 'request_expired');
    Future<void>.delayed(const Duration(milliseconds: 900), () {
      if (!mounted || !_expired) return;
      _closeRequest('expired');
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    // Both exit paths — accept (pushReplacement) and decline (pop) —
    // tear this screen down, so dispose is the single place we
    // silence the ring. Without this, accepting a ride would leave
    // the alert chiming on top of the active-ride map.
    LocalNotificationService.instance.stopIncomingRingtone();
    final visibleId = ref.read(visibleRideRequestIdProvider);
    if (visibleId == widget.ride.id) {
      ref.read(visibleRideRequestIdProvider.notifier).state = null;
    }
    super.dispose();
  }

  Future<void> _accept() async {
    if (_isAccepting) return;
    _syncRemaining();
    if (_expired) {
      _handleExpiry();
      return;
    }
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
    if (_secondsUntil(_expiresAt) <= 0) {
      _handleExpiry();
      return;
    }
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _syncRemaining();
    });
  }

  void _decline({String reason = 'driver_declined'}) {
    _timer?.cancel();
    // Tell the matcher to move on immediately — without this, the next
    // driver in the queue doesn't get the request until the 30 s window
    // expires and the matcher times us out.
    ref
        .read(activeRideProvider.notifier)
        .declineRide(widget.ride.id, reason: reason);
    if (mounted) _closeRequest('declined');
  }

  void _closeRequest(String result) {
    if (!mounted) return;
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop(result);
    } else {
      context.go('/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    final ride = widget.ride;
    final progress = (_secondsRemaining / _acceptanceWindow.inSeconds)
        .clamp(0.0, 1.0)
        .toDouble();

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
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => context.push('/notifications'),
                    child: const Icon(Icons.notifications_outlined,
                        color: MyShopColors.textSecondary),
                  ),
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
                            onPressed:
                                _isAccepting || _expired ? null : _decline,
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
                            onPressed:
                                _isAccepting || _expired ? null : _accept,
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
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        _expired
                                            ? Icons.timer_off
                                            : Icons.check,
                                        size: 18,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(_expired ? 'Expired' : 'Accept'),
                                    ],
                                  ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: MyShopSpacing.md),

                    Text(
                      _expired
                          ? 'This request has expired. Looking for another driver…'
                          : 'Accepting this trip implies agreement with the service terms.\nCancellations may affect your driver rating.',
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
                Text((ride.clientRating ?? 0).toStringAsFixed(1),
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
    // Live driver→pickup ETA derived from the most recent GPS fix. The
    // location stream can be a few seconds late after launch/reconnect, so
    // fall back to the cached fix populated by the availability/socket bridge
    // instead of hiding the km chip.
    final position = ref.watch(driverLocationStreamProvider).valueOrNull ??
        ref.watch(lastKnownPositionProvider);
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

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // ── Pickup row ────────────────────────────────────────────────────
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
                color: MyShopColors.surfaceGrey,
                borderRadius: BorderRadius.circular(16)),
            child: const Icon(Icons.trip_origin,
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
          if (minutesAway != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
      ]),

      // ── Connector + trip metrics (pickup → dropoff) ──────────────────
      // The dashed vertical line visually links the two stops so the
      // driver reads it as one journey. Trip-level metrics (total distance,
      // total duration) sit alongside the line because they describe the
      // whole pickup→dropoff leg, not the pickup alone.
      Padding(
        padding: const EdgeInsets.only(left: 15, top: 4, bottom: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          SizedBox(
            width: 2,
            height: 24,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: MyShopColors.divider,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
          const SizedBox(width: 18),
          const Icon(Icons.straighten,
              size: 14, color: MyShopColors.textSecondary),
          const SizedBox(width: 4),
          Text(ride.distanceDisplay, style: MyShopTypography.body2),
          const SizedBox(width: 12),
          const Icon(Icons.access_time, size: 14, color: MyShopColors.online),
          const SizedBox(width: 4),
          Text('${ride.estimatedDurationMins} min trip',
              style:
                  MyShopTypography.body2.copyWith(color: MyShopColors.online)),
        ]),
      ),

      // ── Intermediate stops ──────────────────────────────────────────────
      // When booking-time stops land on the backend, or when a canonical
      // request snapshot includes them, show drivers the full route before
      // they accept. This is display-only; the backend remains authoritative
      // for pricing, ordering, and whether stops exist.
      for (final stop in ride.stops) ...[
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                  color: MyShopColors.surfaceGrey,
                  borderRadius: BorderRadius.circular(16)),
              child: const Icon(Icons.add_location_alt_outlined,
                  size: 18, color: MyShopColors.warning)),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('STOP',
                    style: MyShopTypography.overline
                        .copyWith(fontSize: 11, letterSpacing: 0.5)),
                const SizedBox(height: 4),
                Text(stop.address,
                    style: const TextStyle(
                        fontFamily: 'Raleway',
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: MyShopColors.textPrimary)),
              ])),
        ]),
        Padding(
          padding: const EdgeInsets.only(left: 15, top: 4, bottom: 4),
          child: Container(
            width: 2,
            height: 16,
            decoration: BoxDecoration(
              color: MyShopColors.divider,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        ),
      ],

      // ── Destination row ──────────────────────────────────────────────
      // The destination was previously not surfaced on the request screen;
      // drivers were accepting blind to where the rider wanted to go.
      // Backend has emitted dropoffAddress on `ride:new` since launch — we
      // just weren't rendering it here.
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
                color: MyShopColors.surfaceGrey,
                borderRadius: BorderRadius.circular(16)),
            child: const Icon(Icons.location_on,
                size: 18, color: MyShopColors.error)),
        const SizedBox(width: 12),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('DESTINATION',
              style: MyShopTypography.overline
                  .copyWith(fontSize: 11, letterSpacing: 0.5)),
          const SizedBox(height: 4),
          Text(
              ride.dropoffAddress.isEmpty
                  ? 'Destination not provided'
                  : ride.dropoffAddress,
              style: TextStyle(
                  fontFamily: 'Raleway',
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: ride.dropoffAddress.isEmpty
                      ? MyShopColors.textSecondary
                      : MyShopColors.textPrimary)),
        ])),
      ]),
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
          child: Text(paymentMethodLabel(ride.paymentMethod),
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
