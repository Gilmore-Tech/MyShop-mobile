import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_provider/src/features/driver_home/providers/ride_request_provider.dart';
import 'package:myshop_provider/src/features/driver_home/screens/ride_request_screen.dart';
import 'package:shared_models/shared_models.dart';

Ride _pendingRide() => Ride(
      id: 'ride-cancelled-by-rider',
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
}
