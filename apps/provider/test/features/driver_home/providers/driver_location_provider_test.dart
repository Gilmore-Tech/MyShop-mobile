import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:myshop_provider/src/features/driver_home/providers/driver_location_provider.dart';

void main() {
  test('Android online stream requests stationary periodic fixes', () {
    final settings = onlineStreamLocationSettings(TargetPlatform.android);

    expect(settings, isA<AndroidSettings>());
    expect(settings.distanceFilter, 0);
    expect((settings as AndroidSettings).intervalDuration,
        const Duration(seconds: 4));
  });

  test('Apple online stream does not suppress stationary fixes', () {
    final settings = onlineStreamLocationSettings(TargetPlatform.iOS);

    expect(settings, isA<AppleSettings>());
    expect(settings.distanceFilter, 0);
    final apple = settings as AppleSettings;
    expect(apple.pauseLocationUpdatesAutomatically, isFalse);
    expect(apple.allowBackgroundLocationUpdates, isTrue);
  });
}
