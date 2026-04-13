import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../providers/ride_provider.dart';
import '../widgets/driver_info_card.dart';
import '../widgets/driver_radar.dart';

// Design tokens
const _gold = Color(0xFFF5A623);
const _offWhite = Color(0xFFF6F7F8);
const _textPrimary = Color(0xFF161A1D);
const _textSecondary = Color(0xFF555E68);

/// PRD 4.3 — Driver Matching Screen
/// Radar animation while finding nearby drivers.
/// Transitions to driver-found state once a match is accepted.
class DriverMatchingScreen extends ConsumerStatefulWidget {
  const DriverMatchingScreen({super.key});

  @override
  ConsumerState<DriverMatchingScreen> createState() =>
      _DriverMatchingScreenState();
}

class _DriverMatchingScreenState extends ConsumerState<DriverMatchingScreen> {
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    // Defer provider mutations until after the first frame — modifying providers
    // synchronously inside initState triggers a "modified during build" error.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _startMatching();
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _startMatching() {
    ref.read(bookingPhaseProvider.notifier).startSearch();
    ref.read(searchCountdownProvider.notifier).reset();

    // Tick the countdown every second
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      ref.read(searchCountdownProvider.notifier).tick();
    });

    // Simulate driver found after 8 seconds
    Future.delayed(const Duration(seconds: 8), () {
      if (!mounted) return;
      _countdownTimer?.cancel();
      const driver = MatchedDriver(
        name: 'Kofi Mensah',
        vehicle: 'Midnight Black Toyota Camry Hybrid',
        plateNumber: 'GR-4557-23',
        rating: 4.92,
        minutesAway: 3,
        driversAvailable: 3,
        tripCount: 1450,
        isVerified: true,
        isPoliceChecked: true,
        maskedPhone: '+233 ••• ••• 42',
        vehicleTier: 'Premier Comfort',
        baseFarePesewas: 1200,
        distanceFarePesewas: 1550,
        distanceKm: 5.2,
        bookingFeePesewas: 250,
      );
      ref.read(matchedDriverProvider.notifier).state = driver;
      ref.read(bookingPhaseProvider.notifier).driverFound();
      // Brief pause to show "Accepted" card, then auto-navigate to detail screen
      Future.delayed(const Duration(milliseconds: 1200), () {
        if (!mounted) return;
        context.go(AppRoutes.rideDriverFound, extra: driver);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final phase = ref.watch(bookingPhaseProvider);
    final driver = ref.watch(matchedDriverProvider);
    final driversFound = phase == BookingPhase.driverFound;

    return Scaffold(
      backgroundColor: _offWhite,
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(
              driversFound: driversFound,
              driversAvailable: driver?.driversAvailable ?? 0,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: DriverRadar(
                  driversFound: driversFound,
                  driversAvailable: driver?.driversAvailable ?? 0,
                ),
              ),
            ),
            if (!driversFound) _SearchStatusBar(),
            if (driversFound && driver != null) DriverInfoCard(driver: driver),
          ],
        ),
      ),
    );
  }
}

// ── Top bar ───────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final bool driversFound;
  final int driversAvailable;

  const _TopBar({required this.driversFound, required this.driversAvailable});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: driversFound
            ? _DriversAvailablePill(count: driversAvailable)
            : _SearchingBar(),
      ),
    );
  }
}

class _SearchingBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      key:    const ValueKey('searching'),
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color:        Colors.white,
        borderRadius: BorderRadius.circular(23),
        boxShadow: [
          BoxShadow(
            color:      Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset:     const Offset(0, 3),
          ),
        ],
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_rounded, size: 17, color: _textSecondary),
          SizedBox(width: 8),
          Text(
            'Finding nearby drivers...',
            style: TextStyle(
              fontSize:   14,
              fontWeight: FontWeight.w500,
              color:      _textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _DriversAvailablePill extends StatelessWidget {
  final int count;
  const _DriversAvailablePill({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('found'),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: _gold,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: _gold.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Text(
        '$count Drivers available',
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }
}

// ── Search status bar ─────────────────────────────────────────────────────────

class _SearchStatusBar extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seconds = ref.watch(searchCountdownProvider);
    final mm = (seconds ~/ 60).toString().padLeft(2, '0');
    final ss = (seconds % 60).toString().padLeft(2, '0');

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          const Icon(Icons.access_time_rounded,
              size: 20, color: _textSecondary),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Search expires in',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _textPrimary,
                ),
              ),
              const Text(
                'Looking in 2km radius',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                  color: _textSecondary,
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            '$mm:$ss',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: _gold,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
