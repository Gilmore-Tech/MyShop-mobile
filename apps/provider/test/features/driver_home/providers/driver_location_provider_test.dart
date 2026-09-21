import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:myshop_provider/src/features/driver_home/providers/driver_location_provider.dart';

Position position(DateTime timestamp) => Position(
      latitude: 6.6885,
      longitude: -1.6244,
      timestamp: timestamp,
      accuracy: 8,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

void main() {
  test('Android online stream requests stationary periodic fixes', () {
    final settings = onlineStreamLocationSettings(TargetPlatform.android);

    expect(settings, isA<AndroidSettings>());
    expect(settings.distanceFilter, 0);
    final android = settings as AndroidSettings;
    expect(android.intervalDuration, const Duration(seconds: 4));
    expect(android.foregroundNotificationConfig, isNotNull);
    expect(android.foregroundNotificationConfig!.enableWakeLock, isTrue);
    expect(android.foregroundNotificationConfig!.enableWifiLock, isTrue);
    expect(android.foregroundNotificationConfig!.setOngoing, isTrue);
  });

  test('Apple online stream does not suppress stationary fixes', () {
    final settings = onlineStreamLocationSettings(TargetPlatform.iOS);

    expect(settings, isA<AppleSettings>());
    expect(settings.distanceFilter, 0);
    final apple = settings as AppleSettings;
    expect(apple.pauseLocationUpdatesAutomatically, isFalse);
    expect(apple.allowBackgroundLocationUpdates, isTrue);
  });

  test('Android Online acquisition uses a persistent fused foreground stream',
      () {
    final settings = onlineEntryLocationSettings(TargetPlatform.android);

    expect(settings, isA<AndroidSettings>());
    final android = settings as AndroidSettings;
    expect(android.forceLocationManager, isFalse);
    expect(android.distanceFilter, 0);
    expect(android.intervalDuration, const Duration(seconds: 2));
    expect(android.foregroundNotificationConfig, isNotNull);
    expect(android.foregroundNotificationConfig!.enableWakeLock, isTrue);
    expect(android.foregroundNotificationConfig!.enableWifiLock, isTrue);
  });

  test('Apple Online acquisition continues while the app is backgrounded', () {
    final settings = onlineEntryLocationSettings(TargetPlatform.iOS);

    expect(settings, isA<AppleSettings>());
    final apple = settings as AppleSettings;
    expect(apple.distanceFilter, 0);
    expect(apple.pauseLocationUpdatesAutomatically, isFalse);
    expect(apple.allowBackgroundLocationUpdates, isTrue);
  });

  test('periodic online resolver reuses only a genuinely recent fix', () async {
    final now = DateTime.utc(2026, 7, 20, 15);
    final recent = position(
      now.subtract(periodicOnlineFixMaxAge),
    );
    var loads = 0;

    final resolved = await resolvePeriodicOnlinePosition(
      recent,
      now: now,
      loader: () async {
        loads += 1;
        return position(now);
      },
    );

    expect(resolved, same(recent));
    expect(loads, 0);
  });

  test('periodic online resolver replaces stale and missing fixes', () async {
    final now = DateTime.utc(2026, 7, 20, 15);
    final fresh = position(now);
    var loads = 0;
    Future<Position> loader() async {
      loads += 1;
      return fresh;
    }

    expect(
      await resolvePeriodicOnlinePosition(
        position(
          now.subtract(
            periodicOnlineFixMaxAge + const Duration(milliseconds: 1),
          ),
        ),
        now: now,
        loader: loader,
      ),
      same(fresh),
    );
    expect(
      await resolvePeriodicOnlinePosition(
        null,
        now: now,
        loader: loader,
      ),
      same(fresh),
    );
    expect(loads, 2);
  });
}
