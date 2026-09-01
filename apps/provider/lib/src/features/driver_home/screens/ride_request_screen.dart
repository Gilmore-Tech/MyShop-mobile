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
import '../../../core/services/incoming_request_overlay_presenter.dart';
import '../../../core/services/local_notification_service.dart';
import '../../../core/utils/incoming_ride_fare_copy.dart';
import '../../../core/utils/payment_method_label.dart';
import '../../../core/widgets/incoming_request_map_preview.dart';
import '../providers/driver_location_provider.dart';
import '../providers/ride_request_provider.dart';

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
  bool _isDeclining = false;
  bool _expired = false;
  bool _expiryHandled = false;
  late final StateController<String?> _visibleRequestController;
  late final StateController<VisibleRideRequestOwner?>
      _visibleRequestOwnerController;
  final Object _visibleRequestOwnerToken = Object();

  @override
  void initState() {
    super.initState();
    // Riverpod deliberately disallows `ref.read` once unmount has begun.
    // Cache this controller while mounted so dispose can conditionally release
    // only this ride's marker without overwriting a newer request screen.
    _visibleRequestController = ref.read(visibleRideRequestIdProvider.notifier);
    _visibleRequestOwnerController =
        ref.read(visibleRideRequestOwnerProvider.notifier);
    _mountRequest(widget.ride);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final dismissal = ref.read(rideOfferDismissalProvider);
      if (dismissal?.rideId == widget.ride.id) {
        _handleRemoteDismissal(dismissal!);
      }
    });
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
    _expiresAt = _deadlineFor(ride);
    _secondsRemaining = _secondsUntil(_expiresAt);
    _expired = _secondsRemaining <= 0;
    _markVisibleAfterBuild(ride.id);
    if (_expired) {
      _handleExpiryAfterBuild();
      return;
    }
    // Start the looping ringtone the moment this screen mounts. The
    // service is a singleton — both ride and job request flows share
    // it, and we never have both open simultaneously, so a stale
    // timer from a previous session is impossible.
    LocalNotificationService.instance.startIncomingRingtone();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _syncRemaining();
    });
  }

  void _markVisibleAfterBuild(String rideId) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.ride.id != rideId) return;
      _visibleRequestOwnerController.state = VisibleRideRequestOwner(
        rideId: rideId,
        token: _visibleRequestOwnerToken,
      );
      _visibleRequestController.state = rideId;
    });
  }

  void _handleExpiryAfterBuild() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_expired) return;
      _handleExpiry();
    });
  }

  DateTime _deadlineFor(Ride ride) {
    final explicit = ref.read(rideRequestDeadlineByIdProvider)[ride.id];
    if (explicit != null) return explicit.toLocal();
    return ride.createdAt.toLocal().add(_acceptanceWindow);
  }

  void _adoptLaterAuthoritativeDeadline(DateTime candidate) {
    if (!mounted ||
        _isAccepting ||
        _isDeclining ||
        _expired ||
        _expiryHandled) {
      return;
    }
    final nextDeadline = candidate.toLocal();
    // Delivery receipt and socket hydration may update the same mounted ride.
    // Only move the clock forward: a delayed delivery payload carrying the
    // earlier 10-second transport deadline must never shorten an already
    // authoritative 30-second decision window.
    if (!nextDeadline.toUtc().isAfter(_expiresAt.toUtc())) return;
    final remaining = _secondsUntil(nextDeadline);
    if (remaining <= 0) return;

    _timer?.cancel();
    setState(() {
      _expiresAt = nextDeadline;
      _secondsRemaining = remaining;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _syncRemaining();
    });
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
    _clearVisibleMarker();
    ref.read(incomingRideRequestProvider.notifier).state = null;
    ref.read(surfacedRideIdsProvider.notifier).update(
          (s) => {...s, widget.ride.id},
        );
    // Best-effort only. The backend may already have timed this provider out;
    // the UI should close cleanly either way.
    unawaited(
      ref.read(activeRideProvider.notifier).declineRideFromNotification(
            widget.ride.id,
            reason: 'request_expired',
          ),
    );
    unawaited(
      clearIncomingRequestAlert(
        type: NotificationPayload.typeRideRequest,
        requestId: widget.ride.id,
      ),
    );
    Future<void>.delayed(const Duration(milliseconds: 900), () {
      if (!mounted || !_expired) return;
      _closeRequest('expired');
    });
  }

  void _handleRemoteDismissal(RideOfferDismissal dismissal) {
    if (!mounted || dismissal.rideId != widget.ride.id || _expiryHandled) {
      return;
    }
    _expiryHandled = true;
    _timer?.cancel();
    LocalNotificationService.instance.stopIncomingRingtone();
    ref.read(incomingRideRequestProvider.notifier).state = null;
    _clearVisibleMarker();
    ref.read(rideOfferDismissalProvider.notifier).state = null;
    // Route state is the provider-facing source of truth. Close it before
    // best-effort native notification cleanup so a plugin/platform failure
    // can never leave a cancelled request visible until its timer expires.
    _closeRequest('dismissed');
    unawaited(
      clearIncomingRequestAlert(
        type: NotificationPayload.typeRideRequest,
        requestId: widget.ride.id,
        reason: dismissal.reason,
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    // Both exit paths — accept (pushReplacement) and decline (pop) —
    // tear this screen down, so dispose is the single place we
    // silence the ring. Without this, accepting a ride would leave
    // the alert chiming on top of the active-ride map.
    LocalNotificationService.instance.stopIncomingRingtone();
    // Riverpod rejects provider mutations while Flutter is finalizing the
    // widget tree. Defer the safety-net cleanup until after that frame, and use
    // an instance token so an outgoing same-ride screen cannot clear the marker
    // already claimed by its hydrated replacement.
    final rideId = widget.ride.id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        final owner = _visibleRequestOwnerController.state;
        if (owner?.rideId != rideId ||
            !identical(owner?.token, _visibleRequestOwnerToken)) {
          return;
        }
        _visibleRequestOwnerController.state = null;
        if (_visibleRequestController.state == rideId) {
          _visibleRequestController.state = null;
        }
      } on StateError {
        // The ProviderScope can be torn down before this post-frame safety
        // cleanup runs (notably during account teardown/test disposal).
      }
    });
    super.dispose();
  }

  void _clearVisibleMarker() {
    final owner = _visibleRequestOwnerController.state;
    if (owner?.rideId != widget.ride.id ||
        !identical(owner?.token, _visibleRequestOwnerToken)) {
      return;
    }
    _visibleRequestOwnerController.state = null;
    if (_visibleRequestController.state == widget.ride.id) {
      _visibleRequestController.state = null;
    }
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
      await clearIncomingRequestAlert(
        type: NotificationPayload.typeRideRequest,
        requestId: widget.ride.id,
      );
      if (!mounted) return;
      _clearVisibleMarker();
      // Keep the active ride inside GoRouter's route table. A raw
      // MaterialPageRoute sits above the router and cannot be removed by
      // context.go('/home') when the rider cancels remotely.
      context.pushReplacement('/active-ride');
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

  Future<void> _decline({String reason = 'driver_declined'}) async {
    if (_isDeclining) return;
    _timer?.cancel();
    setState(() => _isDeclining = true);
    // Tell the matcher to move on immediately — without this, the next
    // driver in the queue doesn't get the request until the 30 s window
    // expires and the matcher times us out.
    final notifier = ref.read(activeRideProvider.notifier);
    final acknowledged = await notifier.declineRideFromNotification(
      widget.ride.id,
      reason: reason,
    );
    if (!acknowledged) {
      // Socket fallback keeps older backends/builds functional. The backend
      // matcher timeout remains the final safety net if both paths are down.
      notifier.declineRide(widget.ride.id, reason: reason);
    }
    await clearIncomingRequestAlert(
      type: NotificationPayload.typeRideRequest,
      requestId: widget.ride.id,
    );
    if (mounted) _closeRequest('declined');
  }

  void _closeRequest(String result) {
    if (!mounted) return;
    _clearVisibleMarker();
    final router = GoRouter.maybeOf(context);
    final navigator = Navigator.of(context);
    unawaited(
      navigator.maybePop(result).then((didPop) {
        if (!mounted) return;
        final revealedPath =
            router?.routerDelegate.currentConfiguration.uri.path;
        // A duplicate callback may have left an older loader/details page
        // beneath this request. Never reveal another `/ride-request` after a
        // terminal decision; active-trip offers still return to
        // `/active-ride`, while ordinary offers return home.
        if (router != null && (!didPop || revealedPath == '/ride-request')) {
          router.go('/home');
        }
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<RideOfferDismissal?>(rideOfferDismissalProvider,
        (previous, next) {
      if (next != null && next.rideId == widget.ride.id) {
        _handleRemoteDismissal(next);
      }
    });
    ref.listen<Map<String, DateTime>>(rideRequestDeadlineByIdProvider,
        (previous, next) {
      final deadline = next[widget.ride.id];
      if (deadline != null) {
        _adoptLaterAuthoritativeDeadline(deadline);
      }
    });
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

            // Main request surface
            Expanded(
              child: Container(
                margin: const EdgeInsets.only(top: MyShopSpacing.lg),
                decoration: const BoxDecoration(
                  color: MyShopColors.surfaceWhite,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.all(MyShopSpacing.md),
                        children: [
                          const SizedBox(height: MyShopSpacing.sm),
                          // Request label + authoritative countdown.
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
                                          fontSize: 20,
                                          fontWeight: FontWeight.w800,
                                          color: MyShopColors.textPrimary)),
                                ],
                              ),
                              _CountdownTimer(
                                progress: progress,
                                seconds: _secondsRemaining,
                              ),
                            ],
                          ),
                          const SizedBox(height: MyShopSpacing.md),

                          // A non-interactive route snapshot lets the driver
                          // understand direction and span before accepting.
                          IncomingRequestMapPreview.route(
                            pickupLatitude: ride.pickupLat,
                            pickupLongitude: ride.pickupLng,
                            destinationLatitude: ride.dropoffLat,
                            destinationLongitude: ride.dropoffLng,
                          ),
                          const SizedBox(height: MyShopSpacing.md),

                          // Put the decision-driving amount before identity and
                          // the longer address details.
                          _PricingCard(ride: ride),
                          const SizedBox(height: MyShopSpacing.lg),

                          _PickupInfo(ride: ride),
                          const SizedBox(height: MyShopSpacing.lg),

                          _ClientCard(ride: ride),
                          const SizedBox(height: MyShopSpacing.md),

                          if (ride.hasSurge) ...[
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                  color: MyShopColors.errorLight,
                                  borderRadius:
                                      BorderRadius.circular(MyShopRadius.card),
                                  border: Border.all(
                                      color: MyShopColors.error
                                          .withValues(alpha: 0.35))),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.local_fire_department_outlined,
                                      size: 18, color: MyShopColors.error),
                                  SizedBox(width: 8),
                                  Text('HIGH DEMAND',
                                      style: TextStyle(
                                          fontFamily: 'Raleway',
                                          fontSize: 13,
                                          fontWeight: FontWeight.w900,
                                          color: MyShopColors.error,
                                          letterSpacing: 0.5)),
                                ],
                              ),
                            ),
                            const SizedBox(height: MyShopSpacing.md),
                          ],

                          Container(
                            padding: const EdgeInsets.all(MyShopSpacing.md),
                            decoration: BoxDecoration(
                                color: MyShopColors.surfaceGrey,
                                borderRadius:
                                    BorderRadius.circular(MyShopRadius.card)),
                            child: Row(
                              children: [
                                const Icon(Icons.shield_outlined,
                                    size: 20,
                                    color: MyShopColors.textSecondary),
                                const SizedBox(width: 12),
                                Expanded(
                                    child: Text(
                                        'Passenger phone numbers stay masked for your security.',
                                        style: MyShopTypography.body2
                                            .copyWith(fontSize: 12))),
                              ],
                            ),
                          ),
                          const SizedBox(height: MyShopSpacing.md),
                          Text(
                            _expired
                                ? 'This request has expired. Looking for another driver…'
                                : 'Repeated declines or missed requests may temporarily pause new requests. They do not change your customer rating.',
                            textAlign: TextAlign.center,
                            style:
                                MyShopTypography.caption.copyWith(fontSize: 11),
                          ),
                          const SizedBox(height: MyShopSpacing.sm),
                        ],
                      ),
                    ),
                    _RideRequestActionBar(
                      accepting: _isAccepting,
                      declining: _isDeclining,
                      expired: _expired,
                      onAccept: _accept,
                      onDecline: _decline,
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
    final color = seconds <= 10 ? MyShopColors.error : MyShopColors.primaryGold;
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
              valueColor: AlwaysStoppedAnimation(color)),
          Text('${seconds}s',
              style: TextStyle(
                  fontFamily: 'Raleway',
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: color)),
        ],
      ),
    );
  }
}

class _RideRequestActionBar extends StatelessWidget {
  const _RideRequestActionBar({
    required this.accepting,
    required this.declining,
    required this.expired,
    required this.onAccept,
    required this.onDecline,
  });

  final bool accepting;
  final bool declining;
  final bool expired;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final disabled = accepting || declining || expired;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        MyShopSpacing.md,
        MyShopSpacing.sm,
        MyShopSpacing.md,
        MyShopSpacing.md,
      ),
      decoration: const BoxDecoration(
        color: MyShopColors.surfaceWhite,
        border: Border(top: BorderSide(color: MyShopColors.divider)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: OutlinedButton.icon(
              onPressed: disabled ? null : onDecline,
              icon: const Icon(Icons.close, size: 18),
              label: const Text('Decline'),
              style: OutlinedButton.styleFrom(
                foregroundColor: MyShopColors.error,
                side: const BorderSide(color: MyShopColors.error),
                minimumSize: const Size(0, 52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(MyShopRadius.button),
                ),
                textStyle: const TextStyle(
                  fontFamily: 'Raleway',
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(width: MyShopSpacing.sm),
          Expanded(
            flex: 3,
            child: ElevatedButton(
              onPressed: disabled ? null : onAccept,
              style: ElevatedButton.styleFrom(
                backgroundColor: MyShopColors.buttonPrimary,
                foregroundColor: MyShopColors.textOnPrimary,
                disabledBackgroundColor:
                    MyShopColors.darkSlate.withValues(alpha: 0.6),
                disabledForegroundColor: MyShopColors.textOnPrimary,
                minimumSize: const Size(0, 52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(MyShopRadius.button),
                ),
                textStyle: const TextStyle(
                  fontFamily: 'Raleway',
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              child: accepting
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation(
                          MyShopColors.textOnPrimary,
                        ),
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(expired ? Icons.timer_off : Icons.check, size: 18),
                        const SizedBox(width: 8),
                        Text(expired ? 'Expired' : 'Accept ride'),
                      ],
                    ),
            ),
          ),
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

class _PricingCard extends StatelessWidget {
  const _PricingCard({required this.ride});
  final Ride ride;
  @override
  Widget build(BuildContext context) {
    final fare = IncomingRideFareCopy.fromSnapshot(
      IncomingRideFareSnapshot.fromRide(ride),
    );
    return Container(
      padding: const EdgeInsets.all(MyShopSpacing.md),
      decoration: BoxDecoration(
          color: MyShopColors.primaryGoldLight,
          borderRadius: BorderRadius.circular(MyShopRadius.card),
          border: Border.all(
            color: MyShopColors.primaryGold.withValues(alpha: 0.24),
          )),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                  color: MyShopColors.primaryGold.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(MyShopRadius.button)),
              child: const Icon(Icons.receipt_long,
                  size: 20, color: MyShopColors.primaryGold)),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(
                  fare.primaryLabel,
                  key: const ValueKey('incoming-fare-primary-label'),
                  style: MyShopTypography.overline.copyWith(
                    color: MyShopColors.primaryGoldDark,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 2),
                Text(fare.primaryAmount,
                    key: const ValueKey('incoming-fare-primary-amount'),
                    style: MyShopTypography.price.copyWith(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                    )),
              ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
                color: MyShopColors.surfaceWhite,
                borderRadius: BorderRadius.circular(MyShopRadius.pill),
                border: Border.all(color: MyShopColors.divider)),
            child: Text(paymentMethodLabel(ride.paymentMethod),
                style: MyShopTypography.body2.copyWith(
                    fontWeight: FontWeight.w600,
                    color: MyShopColors.textPrimary)),
          ),
        ]),
        if (fare.detailLines.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Divider(height: 1, color: MyShopColors.divider),
          const SizedBox(height: 6),
          for (final line in fare.detailLines)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(children: [
                Expanded(
                  child: Text(
                    line.label,
                    style: MyShopTypography.overline.copyWith(
                      color: MyShopColors.textSecondary,
                      fontSize: 10,
                      letterSpacing: 0.45,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  line.amount,
                  style: MyShopTypography.body2.copyWith(
                    fontWeight: FontWeight.w800,
                    color: line.label == IncomingRideFareCopy.discountLabel
                        ? MyShopColors.success
                        : MyShopColors.textPrimary,
                  ),
                ),
              ]),
            ),
        ],
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
