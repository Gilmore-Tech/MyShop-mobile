import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:myshop_provider/src/core/providers/location_guard.dart';
import 'package:myshop_provider/src/core/providers/provider_status_provider.dart';

void main() {
  test('permission polling never overlaps a slow platform check', () async {
    final permissions = <Completer<LocationPermission>>[];
    var permissionCalls = 0;
    final container = ProviderContainer(
      overrides: [
        locationGuardPollIntervalProvider.overrideWithValue(
          const Duration(milliseconds: 5),
        ),
        locationServiceStatusStreamProvider.overrideWithValue(
          const Stream<ServiceStatus>.empty(),
        ),
        locationPermissionReaderProvider.overrideWithValue(() {
          final response = Completer<LocationPermission>();
          permissions.add(response);
          permissionCalls += 1;
          return response.future;
        }),
        locationUnavailableReporterProvider.overrideWithValue((_) async {}),
      ],
    );
    addTearDown(container.dispose);

    container.read(locationGuardProvider);
    container.read(providerStatusProvider.notifier).goOnline();
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(permissionCalls, 1);

    permissions[0].complete(LocationPermission.always);
    await Future<void>.delayed(const Duration(milliseconds: 15));
    expect(permissionCalls, 2);
  });

  test('an old permission result cannot report after going Offline', () async {
    final permission = Completer<LocationPermission>();
    final reported = <Object>[];
    final container = ProviderContainer(
      overrides: [
        locationGuardPollIntervalProvider.overrideWithValue(
          const Duration(milliseconds: 5),
        ),
        locationServiceStatusStreamProvider.overrideWithValue(
          const Stream<ServiceStatus>.empty(),
        ),
        locationPermissionReaderProvider.overrideWithValue(
          () => permission.future,
        ),
        locationUnavailableReporterProvider.overrideWithValue((reason) async {
          reported.add(reason);
        }),
      ],
    );
    addTearDown(container.dispose);

    container.read(locationGuardProvider);
    container.read(providerStatusProvider.notifier).goOnline();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    container.read(providerStatusProvider.notifier).goOffline();
    permission.complete(LocationPermission.deniedForever);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(reported, isEmpty);
  });
}
