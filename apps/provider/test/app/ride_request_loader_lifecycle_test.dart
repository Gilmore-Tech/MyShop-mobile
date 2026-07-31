import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:myshop_provider/src/app/router.dart';
import 'package:shared_models/shared_models.dart';

Ride _pendingRide(String id) => Ride(
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

class _LoaderHarness {
  _LoaderHarness({
    required this.deadline,
    required this.recover,
    required this.fetchRide,
  }) {
    router = GoRouter(
      initialLocation: '/home',
      routes: [
        GoRoute(
          path: '/home',
          builder: (_, __) => const Scaffold(body: Text('Provider home')),
        ),
        GoRoute(
          path: '/cover',
          builder: (_, __) => const Scaffold(body: Text('Cover route')),
        ),
        GoRoute(
          path: '/ride-request',
          builder: (_, state) => buildRideRequestLoaderForTesting(
            extra: state.extra! as RideRequestRouteExtra,
            recoverPendingRide: recover,
            fetchRideData: fetchRide,
          ),
        ),
      ],
    );
  }

  final DateTime? deadline;
  final Future<Ride?> Function(String? rideId) recover;
  final Future<Map<String, dynamic>> Function(String rideId) fetchRide;
  late final GoRouter router;
  int releaseCount = 0;

  RideRequestRouteExtra get extra => RideRequestRouteExtra(
        rideId: 'ride-loader-test',
        navigationLatchToken: Object(),
        releaseNavigationLatch: () => releaseCount += 1,
        allowNotificationRetry: () {},
        expiresAt: deadline,
      );

  Widget get app => ProviderScope(
        child: MaterialApp.router(routerConfig: router),
      );
}

class _InvalidFallbackHarness {
  _InvalidFallbackHarness({
    required this.recover,
    this.timeout = const Duration(seconds: 1),
  }) {
    router = GoRouter(
      initialLocation: '/ride-request',
      routes: [
        GoRoute(
          path: '/home',
          builder: (_, __) => const Scaffold(body: Text('Provider home')),
        ),
        GoRoute(
          path: '/ride-request',
          builder: (_, state) {
            final extra = state.extra;
            if (extra is Ride) {
              return Scaffold(body: Text('Ride ${extra.id}'));
            }
            return buildInvalidRideRequestFallbackForTesting(
              recoverPendingRide: recover,
              recoveryTimeout: timeout,
            );
          },
        ),
      ],
    );
  }

  final Future<Ride?> Function(String? rideId) recover;
  final Duration timeout;
  late final GoRouter router;

  Widget get app => ProviderScope(
        child: MaterialApp.router(routerConfig: router),
      );
}

void main() {
  test('ride request URI preserves identity and absolute deadline', () {
    final deadline = DateTime.utc(2026, 7, 30, 12, 0, 30);
    final uri = Uri.parse(
      rideRequestRouteLocation('ride/with spaces', expiresAt: deadline),
    );
    final identity = rideRequestIdentityFromUri(uri);

    expect(identity?.rideId, 'ride/with spaces');
    expect(identity?.expiresAt, deadline);
  });

  test('loader commit is rejected after its route is replaced', () {
    final deadline = DateTime.utc(2026, 7, 30, 12, 0, 30);

    expect(
      canCommitRideRequestLoaderResult(
        mounted: true,
        routeIsCurrent: false,
        generation: 3,
        activeGeneration: 3,
        deadline: deadline,
        now: DateTime.utc(2026, 7, 30, 12, 0, 10),
      ),
      isFalse,
    );
  });

  test('loader commit is rejected at and after the absolute deadline', () {
    final deadline = DateTime.utc(2026, 7, 30, 12, 0, 30);

    expect(
      canCommitRideRequestLoaderResult(
        mounted: true,
        routeIsCurrent: true,
        generation: 2,
        activeGeneration: 2,
        deadline: deadline,
        now: deadline,
      ),
      isFalse,
    );
    expect(
      canCommitRideRequestLoaderResult(
        mounted: true,
        routeIsCurrent: true,
        generation: 2,
        activeGeneration: 2,
        deadline: deadline,
        now: deadline.add(const Duration(milliseconds: 1)),
      ),
      isFalse,
    );
  });

  test('a hanging request terminates when the absolute deadline wins',
      () async {
    final fetch = Completer<String?>();
    final deadlineWait = Completer<void>();
    final deadline = DateTime.utc(2026, 7, 30, 12, 0, 30);

    final result = awaitRideRequestLoaderFetch<String>(
      fetch: fetch.future,
      deadline: deadline,
      now: () => DateTime.utc(2026, 7, 30, 12, 0),
      delay: (_) => deadlineWait.future,
    );
    deadlineWait.complete();

    final resolved = await result;
    expect(resolved.status, RideRequestLoaderFetchStatus.expired);
    expect(resolved.value, isNull);
  });

  test('a fetch failure becomes unavailable instead of spinning', () async {
    final deadline = DateTime.utc(2026, 7, 30, 12, 0, 30);
    final neverExpires = Completer<void>();

    final result = await awaitRideRequestLoaderFetch<String>(
      fetch: Future<String?>.error(StateError('network failed')),
      deadline: deadline,
      now: () => DateTime.utc(2026, 7, 30, 12, 0),
      delay: (_) => neverExpires.future,
    );

    expect(result.status, RideRequestLoaderFetchStatus.unavailable);
    expect(result.value, isNull);
  });

  test('a fetch completing after expiry cannot reopen the request', () async {
    final fetch = Completer<String?>();
    final deadlineWait = Completer<void>();
    final deadline = DateTime.utc(2026, 7, 30, 12, 0, 30);
    var now = DateTime.utc(2026, 7, 30, 12, 0);

    final result = awaitRideRequestLoaderFetch<String>(
      fetch: fetch.future,
      deadline: deadline,
      now: () => now,
      delay: (_) => deadlineWait.future,
    );

    now = deadline.add(const Duration(milliseconds: 1));
    fetch.complete('ride details');

    final resolved = await result;
    expect(resolved.status, RideRequestLoaderFetchStatus.expired);
    expect(resolved.value, isNull);
  });

  testWidgets('routed loader ignores fetch completion after replacement',
      (tester) async {
    final recover = Completer<Ride?>();
    final fetch = Completer<Map<String, dynamic>>();
    final harness = _LoaderHarness(
      deadline: DateTime.now().add(const Duration(seconds: 30)),
      recover: (_) => recover.future,
      fetchRide: (_) => fetch.future,
    );
    addTearDown(harness.router.dispose);

    await tester.pumpWidget(harness.app);
    harness.router.go('/ride-request', extra: harness.extra);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Fetching the latest request details.'), findsOneWidget);

    harness.router.go('/home');
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    recover.complete(_pendingRide('ride-loader-test'));
    fetch.complete(<String, dynamic>{});
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(tester.takeException(), isNull);
    expect(find.text('Provider home'), findsWidgets);
    expect(find.text('Fetching the latest request details.'), findsNothing);
  });

  testWidgets('same ride restored with a new token keeps one hydration owner',
      (tester) async {
    final recover = Completer<Ride?>();
    final fetch = Completer<Map<String, dynamic>>();
    var recoverCalls = 0;
    var fetchCalls = 0;
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    final harness = _LoaderHarness(
      deadline: deadline,
      recover: (_) {
        recoverCalls += 1;
        return recover.future;
      },
      fetchRide: (_) {
        fetchCalls += 1;
        return fetch.future;
      },
    );
    addTearDown(harness.router.dispose);

    await tester.pumpWidget(harness.app);
    harness.router.go('/ride-request', extra: harness.extra);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    harness.router.go(
      '/ride-request',
      extra: RideRequestRouteExtra(
        rideId: 'ride-loader-test',
        navigationLatchToken: Object(),
        releaseNavigationLatch: () {},
        allowNotificationRetry: () {},
        expiresAt: deadline,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
    expect(recoverCalls, 1);
    expect(fetchCalls, 1);
    expect(find.text('Fetching the latest request details.'), findsOneWidget);

    recover.complete(null);
    fetch.complete(<String, dynamic>{});
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('routed loader leaves automatically when hanging fetch expires',
      (tester) async {
    final recover = Completer<Ride?>();
    final fetch = Completer<Map<String, dynamic>>();
    final harness = _LoaderHarness(
      deadline: DateTime.now().add(const Duration(seconds: 1)),
      recover: (_) => recover.future,
      fetchRide: (_) => fetch.future,
    );
    addTearDown(harness.router.dispose);

    await tester.pumpWidget(harness.app);
    harness.router.go('/ride-request', extra: harness.extra);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Fetching the latest request details.'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 1));

    expect(tester.takeException(), isNull);
    expect(find.text('Provider home'), findsOneWidget);
    expect(find.text('Fetching the latest request details.'), findsNothing);
    expect(harness.releaseCount, greaterThanOrEqualTo(1));
    recover.complete(null);
    fetch.complete(<String, dynamic>{});
    await tester.pump();
  });

  testWidgets('covered routed loader still exits when its deadline elapses',
      (tester) async {
    final recover = Completer<Ride?>();
    final fetch = Completer<Map<String, dynamic>>();
    final harness = _LoaderHarness(
      deadline: DateTime.now().add(const Duration(seconds: 1)),
      recover: (_) => recover.future,
      fetchRide: (_) => fetch.future,
    );
    addTearDown(harness.router.dispose);

    await tester.pumpWidget(harness.app);
    harness.router.go('/ride-request', extra: harness.extra);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    unawaited(harness.router.push('/cover'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Cover route'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 1));

    expect(tester.takeException(), isNull);
    expect(find.text('Provider home'), findsOneWidget);
    expect(find.text('Cover route'), findsNothing);
    expect(find.text('Fetching the latest request details.'), findsNothing);
    recover.complete(null);
    fetch.complete(<String, dynamic>{});
    await tester.pump();
  });

  testWidgets('covered loader without remote expiry still cannot spin forever',
      (tester) async {
    final recover = Completer<Ride?>();
    final fetch = Completer<Map<String, dynamic>>();
    final harness = _LoaderHarness(
      deadline: null,
      recover: (_) => recover.future,
      fetchRide: (_) => fetch.future,
    );
    addTearDown(harness.router.dispose);

    await tester.pumpWidget(harness.app);
    harness.router.go('/ride-request', extra: harness.extra);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    unawaited(harness.router.push('/cover'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Cover route'), findsOneWidget);

    await tester.pump(const Duration(seconds: 13));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Provider home'), findsOneWidget);
    expect(find.text('Fetching the latest request details.'), findsNothing);
    recover.complete(null);
    fetch.complete(<String, dynamic>{});
    await tester.pump();
  });

  testWidgets('identityless fallback leaves home when recovery hangs',
      (tester) async {
    final recover = Completer<Ride?>();
    final harness = _InvalidFallbackHarness(
      recover: (_) => recover.future,
      timeout: const Duration(seconds: 1),
    );
    addTearDown(harness.router.dispose);

    await tester.pumpWidget(harness.app);
    await tester.pump();
    expect(find.text('Fetching the latest request details.'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 500));

    expect(tester.takeException(), isNull);
    expect(find.text('Provider home'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    recover.complete(_pendingRide('late-ride'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Provider home'), findsOneWidget);
    expect(find.text('Ride late-ride'), findsNothing);
  });

  testWidgets('identityless fallback opens one recovered request',
      (tester) async {
    final harness = _InvalidFallbackHarness(
      recover: (_) async => _pendingRide('recovered-ride'),
    );
    addTearDown(harness.router.dispose);

    await tester.pumpWidget(harness.app);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
    expect(find.text('Ride recovered-ride'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
