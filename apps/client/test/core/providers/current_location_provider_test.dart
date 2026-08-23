import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:myshop_client/src/core/providers/current_location_provider.dart';

Position _position({
  required double latitude,
  required double longitude,
  required DateTime timestamp,
  double accuracy = 8,
}) {
  return Position(
    latitude: latitude,
    longitude: longitude,
    timestamp: timestamp,
    accuracy: accuracy,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('flutter.baseflow.com/geolocator');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('forced refresh publishes only the fresh fix', () async {
    final positionCompleter = Completer<Map<String, dynamic>>();
    var currentPositionCalls = 0;
    final lastKnown = _position(
      latitude: 6.6885,
      longitude: -1.6244,
      timestamp: DateTime.utc(2026, 8, 21),
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'checkPermission':
          return LocationPermission.whileInUse.index;
        case 'isLocationServiceEnabled':
          return true;
        case 'getLastKnownPosition':
          return lastKnown.toJson();
        case 'getCurrentPosition':
          currentPositionCalls += 1;
          return positionCompleter.future;
      }
      return null;
    });

    final container = ProviderContainer();
    final emissions = <Position?>[];
    container.listen<Position?>(
      currentDevicePositionProvider,
      (_, next) => emissions.add(next),
    );
    final service = container.read(currentLocationServiceProvider);

    final forced = service.ensure(forceRefresh: true);
    await pumpEventQueue();

    expect(container.read(currentDevicePositionProvider), isNull);
    expect(emissions, isEmpty);
    expect(currentPositionCalls, 1);

    final fresh = _position(
      latitude: 6.7048,
      longitude: -1.6349,
      timestamp: DateTime.utc(2026, 8, 22),
    );
    positionCompleter.complete(fresh.toJson());

    expect(await forced, fresh);
    expect(container.read(currentDevicePositionProvider), fresh);
    expect(emissions, [fresh]);
    expect(currentPositionCalls, 1);
    container.dispose();
  });

  test('forced refresh upgrades a startup lookup before last-known resolves',
      () async {
    final lastKnownCompleter = Completer<Map<String, dynamic>>();
    final positionCompleter = Completer<Map<String, dynamic>>();
    var currentPositionCalls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'checkPermission':
          return LocationPermission.whileInUse.index;
        case 'isLocationServiceEnabled':
          return true;
        case 'getLastKnownPosition':
          return lastKnownCompleter.future;
        case 'getCurrentPosition':
          currentPositionCalls += 1;
          return positionCompleter.future;
      }
      return null;
    });

    final container = ProviderContainer();
    final emissions = <Position?>[];
    container.listen<Position?>(
      currentDevicePositionProvider,
      (_, next) => emissions.add(next),
    );
    final service = container.read(currentLocationServiceProvider);

    final startup = service.ensure();
    await pumpEventQueue();
    final forced = service.ensure(forceRefresh: true);
    var forcedCompleted = false;
    unawaited(forced.then((_) => forcedCompleted = true));

    final oldOffice = _position(
      latitude: 6.6900,
      longitude: -1.6200,
      timestamp: DateTime.utc(2026, 8, 21),
    );
    lastKnownCompleter.complete(oldOffice.toJson());
    await pumpEventQueue();

    expect(currentPositionCalls, 1);
    expect(forcedCompleted, isFalse);
    expect(container.read(currentDevicePositionProvider), isNull);
    expect(emissions, isEmpty);

    final freshMall = _position(
      latitude: 6.7042,
      longitude: -1.6349,
      timestamp: DateTime.utc(2026, 8, 22),
    );
    positionCompleter.complete(freshMall.toJson());

    expect(await startup, freshMall);
    expect(await forced, freshMall);
    expect(emissions, [freshMall]);
    expect(currentPositionCalls, 1);
    container.dispose();
  });

  test('booking join suppresses retries inherited from startup', () async {
    final lastKnownCompleter = Completer<Map<String, dynamic>>();
    var currentPositionCalls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'checkPermission':
          return LocationPermission.whileInUse.index;
        case 'isLocationServiceEnabled':
          return true;
        case 'getLastKnownPosition':
          return lastKnownCompleter.future;
        case 'getCurrentPosition':
          currentPositionCalls += 1;
          throw PlatformException(code: 'LOCATION_TIMEOUT');
      }
      return null;
    });

    final container = ProviderContainer();
    final service = container.read(currentLocationServiceProvider);
    final startup = service.ensure();
    await pumpEventQueue();
    final booking = service.ensure(
      forceRefresh: true,
      retryOnFailure: false,
    );
    final lastKnown = _position(
      latitude: 6.7042,
      longitude: -1.6349,
      timestamp: DateTime.utc(2026, 8, 22),
    );
    lastKnownCompleter.complete(lastKnown.toJson());

    expect(await startup, lastKnown);
    expect(await booking, lastKnown);
    expect(currentPositionCalls, 1);
    expect(service.hasScheduledRetry, isFalse);
    expect(container.read(currentDevicePositionProvider), isNull);
    container.dispose();
  });

  test('booking stops an already-running cold-start retry chain', () async {
    final activeRetryCompleter = Completer<Map<String, dynamic>>();
    var currentPositionCalls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'checkPermission':
          return LocationPermission.whileInUse.index;
        case 'isLocationServiceEnabled':
          return true;
        case 'getLastKnownPosition':
          return null;
        case 'getCurrentPosition':
          currentPositionCalls += 1;
          if (currentPositionCalls == 1) {
            throw PlatformException(code: 'LOCATION_TIMEOUT');
          }
          return activeRetryCompleter.future;
      }
      return null;
    });

    final container = ProviderContainer(
      overrides: [
        currentLocationRetryDelayProvider.overrideWithValue(Duration.zero),
      ],
    );
    final service = container.read(currentLocationServiceProvider);

    expect(await service.ensure(), isNull);
    await pumpEventQueue();
    expect(currentPositionCalls, 2);

    final booking = service.ensure(
      forceRefresh: true,
      retryOnFailure: false,
    );
    activeRetryCompleter.completeError(
      PlatformException(code: 'LOCATION_TIMEOUT'),
    );

    expect(await booking, isNull);
    await pumpEventQueue();
    expect(currentPositionCalls, 2);
    expect(service.hasScheduledRetry, isFalse);
    container.dispose();
  });

  test('forced refresh joins the fresh request behind a fast last-known fix',
      () async {
    final positionCompleter = Completer<Map<String, dynamic>>();
    var currentPositionCalls = 0;
    final lastKnown = _position(
      latitude: 6.6885,
      longitude: -1.6244,
      timestamp: DateTime.utc(2026, 8, 21),
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'checkPermission':
          return LocationPermission.whileInUse.index;
        case 'isLocationServiceEnabled':
          return true;
        case 'getLastKnownPosition':
          return lastKnown.toJson();
        case 'getCurrentPosition':
          currentPositionCalls += 1;
          return positionCompleter.future;
      }
      return null;
    });

    final container = ProviderContainer();
    final service = container.read(currentLocationServiceProvider);

    final initial = await service.ensure();
    expect(initial, lastKnown);
    expect(container.read(currentDevicePositionProvider), lastKnown);
    expect(currentPositionCalls, 1);

    final forced = service.ensure(forceRefresh: true);
    await pumpEventQueue();
    expect(currentPositionCalls, 1);

    final expected = _position(
      latitude: 6.7048,
      longitude: -1.6244,
      timestamp: DateTime.utc(2026, 8, 22),
    );
    positionCompleter.complete(expected.toJson());

    expect(await forced, expected);
    expect(container.read(currentDevicePositionProvider), expected);
    expect(currentPositionCalls, 1);
    container.dispose();
  });

  test('failed forced GPS returns last-known without publishing it', () async {
    var currentPositionCalls = 0;
    final lastKnown = _position(
      latitude: 6.6885,
      longitude: -1.6244,
      timestamp: DateTime.utc(2026, 8, 22),
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'checkPermission':
          return LocationPermission.whileInUse.index;
        case 'isLocationServiceEnabled':
          return true;
        case 'getLastKnownPosition':
          return lastKnown.toJson();
        case 'getCurrentPosition':
          currentPositionCalls += 1;
          throw PlatformException(code: 'LOCATION_TIMEOUT');
      }
      return null;
    });

    final container = ProviderContainer();
    final emissions = <Position?>[];
    container.listen<Position?>(
      currentDevicePositionProvider,
      (_, next) => emissions.add(next),
    );
    final result = await container
        .read(currentLocationServiceProvider)
        .ensure(forceRefresh: true, retryOnFailure: false);

    expect(result, lastKnown);
    expect(container.read(currentDevicePositionProvider), isNull);
    expect(emissions, isEmpty);
    expect(currentPositionCalls, 1);
    container.dispose();
  });

  test('forced refresh never reuses cache when location services are off',
      () async {
    var lastKnownCalls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'checkPermission':
          return LocationPermission.whileInUse.index;
        case 'isLocationServiceEnabled':
          return false;
        case 'getLastKnownPosition':
          lastKnownCalls += 1;
          return null;
      }
      return null;
    });

    final container = ProviderContainer();
    final staleCache = _position(
      latitude: 6.6900,
      longitude: -1.6200,
      timestamp: DateTime.utc(2026, 8, 20),
    );
    container.read(currentDevicePositionProvider.notifier).state = staleCache;

    final result = await container
        .read(currentLocationServiceProvider)
        .ensure(forceRefresh: true);

    expect(result, isNull);
    expect(container.read(currentDevicePositionProvider), staleCache);
    expect(lastKnownCalls, 0);
    container.dispose();
  });
}
