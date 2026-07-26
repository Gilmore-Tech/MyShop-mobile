import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_client/src/features/ride/providers/ride_provider.dart';
import 'package:myshop_client/src/features/ride/screens/driver_matching_screen.dart';

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
    const countdown = RideOfferDecisionCountdown(
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
    const countdown = RideOfferDecisionCountdown(
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
      serverNow: serverNow,
      decisionExpiresAt: serverNow.add(const Duration(seconds: 30)),
      totalSeconds: 30,
    );

    expect(notifier.state?.secondsRemaining, 30);
    expect(notifier.state?.totalSeconds, 30);
    notifier.clear();
    expect(notifier.state, isNull);
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
}
