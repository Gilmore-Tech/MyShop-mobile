import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_provider/src/core/providers/socket_provider.dart';
import 'package:myshop_provider/src/core/widgets/incoming_request_listener.dart';
import 'package:myshop_provider/src/features/driver_home/providers/ride_request_provider.dart';
import 'package:myshop_provider/src/features/driver_home/screens/ride_request_screen.dart';
import 'package:shared_models/shared_models.dart';

Ride _pendingRide({
  String id = 'ride-cancelled-by-rider',
}) =>
    Ride(
      id: id,
      clientId: 'client-1',
      status: RideStatus.requested,
      pickupAddress: 'Pickup',
      dropoffAddress: 'Destination',
      pickupLat: 6.6885,
      pickupLng: -1.6244,
      dropoffLat: 6.7094,
      dropoffLng: -1.5917,
      estimatedFarePesewas: 1500,
      estimatedDistanceKm: 4.2,
      estimatedDurationMins: 12,
      paymentMethod: 'cash',
      createdAt: DateTime.now(),
    );

void main() {
  testWidgets('promo request renders the authoritative three-price breakdown',
      (tester) async {
    final ride = Ride(
      id: 'promo-request',
      clientId: 'client-1',
      status: RideStatus.requested,
      pickupAddress: 'Pickup',
      dropoffAddress: 'Destination',
      pickupLat: 6.6885,
      pickupLng: -1.6244,
      dropoffLat: 6.7094,
      dropoffLng: -1.5917,
      estimatedFarePesewas: 0,
      estimatedProviderEarningsPesewas: 1144,
      prePromoFarePesewas: 1430,
      clientPayableEstimatePesewas: 0,
      platformDiscountPesewas: 1430,
      promoApplied: true,
      estimatedDistanceKm: 4.2,
      estimatedDurationMins: 12,
      paymentMethod: 'momo_mtn',
      createdAt: DateTime.now(),
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: RideRequestScreen(ride: ride)),
      ),
    );
    await tester.pump();

    expect(find.text('EST. FULL FARE'), findsOneWidget);
    expect(find.text('GHS 14.30'), findsOneWidget);
    expect(find.text('PROMO / DISCOUNT'), findsOneWidget);
    expect(find.text('- GHS 14.30'), findsOneWidget);
    expect(find.text('CLIENT PRICE'), findsOneWidget);
    expect(find.text('GHS 0.00'), findsOneWidget);
    expect(find.text('ESTIMATED EARNINGS'), findsNothing);
    expect(find.text('GHS 11.44'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 11));
  });

  testWidgets(
      'notification route preclaim preserves socket ride without a second route',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    const rideId = 'ride-owned-by-notification-tap';
    final socketRide = _pendingRide(id: rideId);
    container.read(rideRequestNavigationInFlightProvider.notifier).state = {
      rideId,
    };

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: IncomingRequestListener(
            child: Scaffold(body: Text('Provider home')),
          ),
        ),
      ),
    );
    await tester.pump();

    container.read(incomingRideRequestProvider.notifier).state = socketRide;
    await tester.pump();

    expect(container.read(incomingRideRequestProvider), same(socketRide));
    expect(find.byType(RideRequestScreen), findsNothing);
    expect(find.text('Provider home'), findsOneWidget);
  });

  testWidgets('rider cancellation closes an already-open provider request',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final navigatorKey = GlobalKey<NavigatorState>();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          navigatorKey: navigatorKey,
          home: const Scaffold(body: Text('Provider home')),
        ),
      ),
    );

    unawaited(
      navigatorKey.currentState!.push<String>(
        MaterialPageRoute<String>(
          builder: (_) => RideRequestScreen(ride: _pendingRide()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(RideRequestScreen), findsOneWidget);
    expect(navigatorKey.currentState!.canPop(), isTrue);

    container.read(rideOfferDismissalProvider.notifier).state =
        const RideOfferDismissal(
      rideId: 'ride-cancelled-by-rider',
      reason: 'cancelled_by_rider',
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(RideRequestScreen), findsNothing);
    expect(find.text('Provider home'), findsOneWidget);
    // Flush the detached map preview's bounded route-request timeout.
    await tester.pump(const Duration(seconds: 11));
  });

  testWidgets(
      'mounted request adopts only a later authoritative same-ride deadline',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    const rideId = 'ride-deadline-extension';
    container.read(rideRequestDeadlineByIdProvider.notifier).state = {
      rideId: DateTime.now().add(const Duration(seconds: 5)),
    };

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: RideRequestScreen(ride: _pendingRide(id: rideId)),
        ),
      ),
    );
    await tester.pump();

    int displayedSeconds() {
      final countdown = tester.widgetList<Text>(find.byType(Text)).firstWhere(
            (text) => RegExp(r'^\d+s$').hasMatch(text.data ?? ''),
          );
      return int.parse(
          countdown.data!.substring(0, countdown.data!.length - 1));
    }

    expect(displayedSeconds(), lessThanOrEqualTo(5));

    container.read(rideRequestDeadlineByIdProvider.notifier).state = {
      rideId: DateTime.now().add(const Duration(seconds: 25)),
    };
    await tester.pump();
    final extendedSeconds = displayedSeconds();
    expect(extendedSeconds, greaterThanOrEqualTo(24));

    // A delayed copy of the earlier delivery deadline must not regress the
    // live 30-second decision deadline already displayed on the same screen.
    container.read(rideRequestDeadlineByIdProvider.notifier).state = {
      rideId: DateTime.now().add(const Duration(seconds: 2)),
    };
    await tester.pump();
    expect(displayedSeconds(), extendedSeconds);

    await tester.pumpWidget(const SizedBox.shrink());
    // Flush the detached map preview's bounded route-request timeout.
    await tester.pump(const Duration(seconds: 11));
  });

  testWidgets('dispose does not clear a newer request visible marker',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    const rideId = 'ride-being-disposed';

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: RideRequestScreen(ride: _pendingRide(id: rideId)),
        ),
      ),
    );
    await tester.pump();
    expect(container.read(visibleRideRequestIdProvider), rideId);

    container.read(visibleRideRequestIdProvider.notifier).state =
        'newer-ride-request';
    await tester.pumpWidget(const SizedBox.shrink());

    expect(
      container.read(visibleRideRequestIdProvider),
      'newer-ride-request',
    );
    // Flush the detached map preview's bounded route-request timeout.
    await tester.pump(const Duration(seconds: 11));
  });

  testWidgets(
      'disposing an owned request marker defers cleanup without Riverpod error',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    const rideId = 'ride-owned-during-dispose';

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: RideRequestScreen(ride: _pendingRide(id: rideId)),
        ),
      ),
    );
    await tester.pump();
    expect(container.read(visibleRideRequestIdProvider), rideId);
    expect(
      container.read(visibleRideRequestOwnerProvider)?.rideId,
      rideId,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(container.read(visibleRideRequestIdProvider), isNull);
    expect(container.read(visibleRideRequestOwnerProvider), isNull);
    // Flush the detached map preview's bounded route-request timeout.
    await tester.pump(const Duration(seconds: 11));
  });
}
