import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../app/router.dart';
import '../../../core/providers/socket_provider.dart';
import '../providers/edit_trip_provider.dart';
import '../providers/ride_provider.dart';
import '../widgets/driver_radar.dart';

/// Live, server-driven rider matching screen.
///
/// The status copy comes from `ride:matcher_progress`. A visible countdown is
/// started only by `ride:offer_received`, after the provider device has sent
/// its authenticated receipt and the database has created the 30-second
/// decision deadline.
class DriverMatchingScreen extends ConsumerStatefulWidget {
  const DriverMatchingScreen({super.key});

  @override
  ConsumerState<DriverMatchingScreen> createState() =>
      _DriverMatchingScreenState();
}

class _DriverMatchingScreenState extends ConsumerState<DriverMatchingScreen> {
  bool _navigatedToTracking = false;
  bool _cancelling = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ref.read(bookingPhaseProvider) == BookingPhase.accepted) {
        _goToTracking();
      }
    });
  }

  void _goToTracking() {
    if (_navigatedToTracking || !mounted) return;
    final driver = ref.read(matchedDriverProvider);
    if (driver == null) return;
    _navigatedToTracking = true;
    ref.read(rideOfferDecisionCountdownProvider.notifier).clear();
    context.go(AppRoutes.rideTracking, extra: driver);
  }

  Future<void> _requestMatcherProgressReplay() async {
    final rideId = ref.read(activeRideIdProvider);
    if (rideId == null || rideId.isEmpty) return;
    final socket = ref.read(socketServiceProvider);
    if (!socket.isConnected) return;
    socket.emit('client:track:ride', {
      'rideId': rideId,
      'replayProgress': true,
    });
    // The backend expiry worker runs once per second. One bounded follow-up
    // covers the race where the local countdown reaches zero just before the
    // durable offer ledger is advanced.
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    if (!mounted || !socket.isConnected) return;
    socket.emit('client:track:ride', {
      'rideId': rideId,
      'replayProgress': true,
    });
  }

  Future<void> _confirmAndCancel() async {
    if (_cancelling) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel ride request?'),
        content: const Text(
          'No driver has accepted yet. Cancelling now is free and will not '
          'affect you or the driver.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep searching'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: MyShopColors.error),
            child: const Text('Cancel request'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _cancelling = true);
    final container = ProviderScope.containerOf(context, listen: false);
    final cancelled = await cancelInFlightRideRequest(container);
    if (!mounted) return;
    if (!cancelled) {
      setState(() => _cancelling = false);
      final message = container.read(bookingFailureMessageProvider) ??
          "We couldn't confirm that the ride request was cancelled.";
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
      return;
    }

    resetRideRequestDraft(container.read);
    context.go(AppRoutes.home);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<BookingPhase>(bookingPhaseProvider, (previous, next) {
      if (next == BookingPhase.accepted) _goToTracking();
    });
    ref.listen<RideOfferDecisionCountdown?>(
      rideOfferDecisionCountdownProvider,
      (previous, next) {
        if ((previous?.secondsRemaining ?? 0) > 0 &&
            next?.secondsRemaining == 0) {
          unawaited(_requestMatcherProgressReplay());
        }
      },
    );

    final phase = ref.watch(bookingPhaseProvider);
    final failed = phase == BookingPhase.failed;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !failed) unawaited(_confirmAndCancel());
      },
      child: Scaffold(
        backgroundColor: MyShopColors.offWhite,
        body: SafeArea(
          child: failed
              ? const _FailureView()
              : Column(
                  children: [
                    const _MatchingHeader(),
                    const Expanded(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(24, 8, 24, 20),
                        child: DriverRadar(
                          driversFound: false,
                          driversAvailable: 0,
                        ),
                      ),
                    ),
                    _RideSearchStatusCard(
                      isCancelling: _cancelling,
                      onCancel: _confirmAndCancel,
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _MatchingHeader extends StatelessWidget {
  const _MatchingHeader();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.local_taxi_rounded,
              color: MyShopColors.textPrimary,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Finding your driver',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: MyShopColors.textPrimary,
                  ),
                ),
                Text(
                  'We will update you at every step',
                  style: TextStyle(
                    fontSize: 13,
                    color: MyShopColors.textSecondary,
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

class MatcherStatusPresentation {
  const MatcherStatusPresentation({
    required this.headline,
    required this.subtitle,
    required this.icon,
  });

  final String headline;
  final String subtitle;
  final IconData icon;
}

@visibleForTesting
MatcherStatusPresentation matcherStatusPresentation({
  required BookingPhase phase,
  required MatcherProgress? progress,
  required RideOfferDecisionCountdown? countdown,
}) {
  if (countdown != null) {
    if (countdown.secondsRemaining <= 0) {
      return const MatcherStatusPresentation(
        headline: "Driver didn't respond",
        subtitle: 'Looking for another driver',
        icon: Icons.sync_rounded,
      );
    }
    return MatcherStatusPresentation(
      headline: 'Driver found',
      subtitle:
          'Waiting for driver confirmation · ${countdown.secondsRemaining}s',
      icon: Icons.person_pin_circle_rounded,
    );
  }

  if (progress == null) {
    if (phase == BookingPhase.driverFound) {
      return const MatcherStatusPresentation(
        headline: 'Driver found',
        subtitle: 'Waiting for the driver to receive your request',
        icon: Icons.person_pin_circle_rounded,
      );
    }
    return const MatcherStatusPresentation(
      headline: 'Searching for a driver',
      subtitle: 'Checking nearby available drivers',
      icon: Icons.search_rounded,
    );
  }

  final radius = progress.radiusKm;
  final radiusText = radius > 0
      ? radius.toStringAsFixed(radius == radius.roundToDouble() ? 0 : 1)
      : null;

  switch (progress.reason) {
    case MatcherReason.initial:
      return const MatcherStatusPresentation(
        headline: 'Searching for a driver',
        subtitle: 'Notifying a nearby available driver',
        icon: Icons.search_rounded,
      );
    case MatcherReason.decline:
    case MatcherReason.timeout:
      if (progress.expanded) {
        return MatcherStatusPresentation(
          headline: 'Expanding search',
          subtitle: radiusText == null
              ? 'Searching a wider area for available drivers'
              : 'Searching within $radiusText km',
          icon: Icons.radar_rounded,
        );
      }
      if (progress.driversRemaining > 0) {
        return const MatcherStatusPresentation(
          headline: 'Driver unavailable',
          subtitle: 'Looking for another driver',
          icon: Icons.sync_rounded,
        );
      }
      return MatcherStatusPresentation(
        headline: 'Still searching',
        subtitle: radiusText == null
            ? 'Checking for another available driver'
            : 'Checking again within $radiusText km',
        icon: Icons.sync_rounded,
      );
  }
}

class _RideSearchStatusCard extends ConsumerWidget {
  const _RideSearchStatusCard({
    required this.isCancelling,
    required this.onCancel,
  });

  final bool isCancelling;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final phase = ref.watch(bookingPhaseProvider);
    final progress = ref.watch(matcherProgressProvider);
    final countdown = ref.watch(rideOfferDecisionCountdownProvider);
    final status = matcherStatusPresentation(
      phase: phase,
      progress: progress,
      countdown: countdown,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              width: 54,
              height: 5,
              decoration: BoxDecoration(
                color: MyShopColors.divider,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          const SizedBox(height: 22),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: Column(
              key: ValueKey('${status.headline}-${status.subtitle}'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  status.headline,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: MyShopColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  status.subtitle,
                  style: const TextStyle(
                    fontSize: 15,
                    height: 1.35,
                    color: MyShopColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              minHeight: 6,
              value: countdown?.progress,
              backgroundColor: MyShopColors.successLight,
              valueColor:
                  const AlwaysStoppedAnimation<Color>(MyShopColors.success),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: _StatusAction(
                  icon: status.icon,
                  label: countdown == null ? 'Matching' : '30-sec window',
                  onTap: null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatusAction(
                  icon: Icons.cancel_outlined,
                  label: isCancelling ? 'Cancelling…' : 'Cancel ride',
                  destructive: true,
                  loading: isCancelling,
                  onTap: isCancelling ? null : onCancel,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusAction extends StatelessWidget {
  const _StatusAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
    this.loading = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool destructive;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? MyShopColors.error : MyShopColors.textPrimary;
    return Semantics(
      button: onTap != null,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(36),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: destructive
                      ? MyShopColors.error.withValues(alpha: 0.10)
                      : MyShopColors.offWhite,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: loading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      )
                    : Icon(icon, color: color, size: 28),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FailureView extends ConsumerWidget {
  const _FailureView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final message = ref.watch(bookingFailureMessageProvider) ??
        "We couldn't request your ride.";

    Future<void> dismiss() async {
      final container = ProviderScope.containerOf(context, listen: false);
      final cancelled = await cancelInFlightRideRequest(container);
      if (!context.mounted) return;
      if (!cancelled) {
        final failure = container.read(bookingFailureMessageProvider) ??
            "We couldn't confirm whether the ride was cancelled.";
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(failure)),
        );
        return;
      }
      resetRideRequestDraft(container.read);
      context.go(AppRoutes.home);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              icon: const Icon(
                Icons.close_rounded,
                color: MyShopColors.textPrimary,
              ),
              onPressed: dismiss,
            ),
          ),
          const Spacer(),
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: MyShopColors.error.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.error_outline_rounded,
              size: 44,
              color: MyShopColors.error,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'No available drivers found',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: MyShopColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              color: MyShopColors.textSecondary,
              height: 1.4,
            ),
          ),
          const Spacer(),
          ElevatedButton(
            onPressed: dismiss,
            style: ElevatedButton.styleFrom(
              backgroundColor: MyShopColors.primaryGold,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 56),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
            ),
            child: const Text('Back to home'),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
