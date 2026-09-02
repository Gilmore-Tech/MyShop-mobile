import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:myshop_client/src/app/router.dart';
import 'package:myshop_client/src/core/di/providers.dart';
import 'package:myshop_client/src/features/ride/data/ride_booking_attempt_store.dart';
import 'package:myshop_client/src/features/ride/providers/ride_provider.dart';
import 'package:myshop_client/src/features/ride/screens/driver_matching_screen.dart';

class _RecordingRideBookingAttemptStore extends RideBookingAttemptStore {
  int clearCalls = 0;

  @override
  Future<void> clear({String? bookingKey}) async {
    clearCalls++;
  }
}

ProviderContainer _failedPreCreateContainer(
  _RecordingRideBookingAttemptStore store,
) {
  final container = ProviderContainer(
    overrides: [rideBookingAttemptStoreProvider.overrideWithValue(store)],
  );
  container.read(bookingPhaseProvider.notifier).fail();
  container.read(bookingFailureExitModeProvider.notifier).state =
      BookingFailureExitMode.noRideCreated;
  container.read(bookingFailureMessageProvider.notifier).state =
      'All nearby drivers are busy or offline. Please try again.';
  return container;
}

GoRouter _matchingRouter() => GoRouter(
      initialLocation: AppRoutes.rideMatching,
      routes: [
        GoRoute(
          path: AppRoutes.rideMatching,
          builder: (_, __) => const DriverMatchingScreen(),
        ),
        GoRoute(
          path: AppRoutes.home,
          builder: (_, __) => const Scaffold(body: Text('Client home')),
        ),
      ],
    );

void main() {
  test('shows searching before any driver is notified', () {
    final status = matcherStatusPresentation(
      phase: BookingPhase.searching,
      progress: null,
      countdown: null,
    );

    expect(status.headline, 'Searching for a driver');
    expect(status.subtitle, 'Checking nearby available drivers');
  });

  test('shows the real receipt countdown after a driver receives the offer',
      () {
    final countdown = RideOfferDecisionCountdown(
      attempt: 1,
      decisionExpiresAt: DateTime.utc(2026, 7, 26, 12, 0, 30),
      secondsRemaining: 27,
      totalSeconds: 30,
    );
    final status = matcherStatusPresentation(
      phase: BookingPhase.driverFound,
      progress: null,
      countdown: countdown,
    );

    expect(status.headline, 'Driver found');
    expect(status.subtitle, contains('27s'));
    expect(countdown.progress, closeTo(0.9, 0.001));
  });

  test('moves on immediately when the driver decision countdown reaches zero',
      () {
    final countdown = RideOfferDecisionCountdown(
      attempt: 1,
      decisionExpiresAt: DateTime.utc(2026, 7, 26, 12, 0, 30),
      secondsRemaining: 0,
      totalSeconds: 30,
    );

    final status = matcherStatusPresentation(
      phase: BookingPhase.driverFound,
      progress: null,
      countdown: countdown,
    );

    expect(status.headline, "Driver didn't respond");
    expect(status.subtitle, 'Looking for another driver');
  });

  test('shows another-driver and radius-expansion states', () {
    final another = matcherStatusPresentation(
      phase: BookingPhase.driverFound,
      progress: const MatcherProgress(
        attempt: 2,
        driversTried: 1,
        driversRemaining: 1,
        radiusKm: 5,
        expanded: false,
        reason: MatcherReason.decline,
      ),
      countdown: null,
    );
    final expanded = matcherStatusPresentation(
      phase: BookingPhase.driverFound,
      progress: const MatcherProgress(
        attempt: 3,
        driversTried: 2,
        driversRemaining: 0,
        radiusKm: 7,
        expanded: true,
        reason: MatcherReason.timeout,
      ),
      countdown: null,
    );

    expect(another.headline, 'Driver unavailable');
    expect(another.subtitle, 'Looking for another driver');
    expect(expanded.headline, 'Expanding search');
    expect(expanded.subtitle, 'Searching within 7 km');
  });

  test('countdown starts from the server clock delta', () {
    final notifier = RideOfferDecisionCountdownNotifier();
    addTearDown(notifier.dispose);
    final serverNow = DateTime.utc(2026, 7, 25, 12);

    notifier.start(
      attempt: 1,
      serverNow: serverNow,
      decisionExpiresAt: serverNow.add(const Duration(seconds: 30)),
      totalSeconds: 30,
    );

    expect(notifier.state?.secondsRemaining, 30);
    expect(notifier.state?.attempt, 1);
    expect(notifier.state?.totalSeconds, 30);
    notifier.clear();
    expect(notifier.state, isNull);
  });

  test('combined replay keeps attempt-two driver found after prior timeout',
      () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(bookingPhaseProvider.notifier).startSearch();

    final applied = applyRideMatchingState(container.read, {
      'rideId': 'ride-1',
      'matcherProgress': {
        'attempt': 2,
        'driversTried': 2,
        'driversRemaining': 1,
        'radiusKm': 5,
        'expanded': true,
        'reason': 'timeout',
      },
      'decisionWindow': {
        'attempt': 2,
        'serverNow': '2026-07-26T12:00:00.000Z',
        'decisionExpiresAt': '2026-07-26T12:00:30.000Z',
        'acceptanceWindowSeconds': 30,
      },
    });

    expect(applied, isTrue);
    expect(container.read(bookingPhaseProvider), BookingPhase.driverFound);
    expect(
      container.read(rideOfferDecisionCountdownProvider)?.attempt,
      2,
    );
    expect(
      container.read(rideOfferDecisionCountdownProvider)?.secondsRemaining,
      30,
    );
  });

  test('stale combined replay cannot erase a newer driver decision window', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(bookingPhaseProvider.notifier).driverFound();
    container.read(matcherProgressProvider.notifier).state =
        const MatcherProgress(
      attempt: 3,
      driversTried: 3,
      driversRemaining: 1,
      radiusKm: 7,
      expanded: true,
      reason: MatcherReason.timeout,
    );
    final serverNow = DateTime.utc(2026, 7, 26, 12);
    container.read(rideOfferDecisionCountdownProvider.notifier).start(
          attempt: 3,
          serverNow: serverNow,
          decisionExpiresAt: serverNow.add(const Duration(seconds: 30)),
          totalSeconds: 30,
        );

    final applied = applyRideMatchingState(container.read, {
      'rideId': 'ride-1',
      'matcherProgress': {
        'attempt': 2,
        'driversTried': 2,
        'driversRemaining': 0,
        'radiusKm': 5,
        'expanded': false,
        'reason': 'timeout',
      },
      'decisionWindow': null,
    });

    expect(applied, isFalse);
    expect(container.read(matcherProgressProvider)?.attempt, 3);
    expect(container.read(rideOfferDecisionCountdownProvider)?.attempt, 3);
    expect(container.read(bookingPhaseProvider), BookingPhase.driverFound);
  });

  test('same-attempt replay cannot undo a wider radius expansion', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(bookingPhaseProvider.notifier).startSearch();
    container.read(matcherProgressProvider.notifier).state =
        const MatcherProgress(
      attempt: 2,
      driversTried: 1,
      driversRemaining: 0,
      radiusKm: 5,
      expanded: true,
      reason: MatcherReason.timeout,
    );

    applyRideMatchingState(container.read, {
      'rideId': 'ride-1',
      'matcherProgress': {
        'attempt': 2,
        'driversTried': 1,
        'driversRemaining': 0,
        'radiusKm': 3,
        'expanded': false,
        'reason': 'timeout',
      },
      'decisionWindow': null,
    });

    final progress = container.read(matcherProgressProvider);
    expect(progress?.attempt, 2);
    expect(progress?.radiusKm, 5);
    expect(progress?.expanded, isTrue);
  });

  testWidgets('matching controls fit on a compact phone viewport',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: DriverMatchingScreen()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Searching for a driver'), findsOneWidget);
    expect(find.text('Cancel ride'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Back to home dismisses a definitive no-driver pre-create failure',
      (tester) async {
    final store = _RecordingRideBookingAttemptStore();
    final container = _failedPreCreateContainer(store);
    final router = _matchingRouter();
    addTearDown(container.dispose);
    addTearDown(router.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No available drivers found'), findsOneWidget);
    await tester.tap(find.text('Back to home'));
    await tester.pumpAndSettle();

    expect(find.text('Client home'), findsOneWidget);
    expect(store.clearCalls, 1);
    expect(container.read(bookingPhaseProvider), BookingPhase.idle);
    expect(tester.takeException(), isNull);
  });

  testWidgets('system back dismisses a definitive no-driver failure to home',
      (tester) async {
    final store = _RecordingRideBookingAttemptStore();
    final container = _failedPreCreateContainer(store);
    final router = _matchingRouter();
    addTearDown(container.dispose);
    addTearDown(router.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('Client home'), findsOneWidget);
    expect(store.clearCalls, 1);
    expect(container.read(bookingPhaseProvider), BookingPhase.idle);
    expect(tester.takeException(), isNull);
  });
}
