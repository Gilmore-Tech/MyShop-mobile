import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_client/src/features/ride/providers/ride_provider.dart';

void main() {
  late ProviderContainer container;
  final now = DateTime.utc(2026, 11, 8, 12);
  LiveDriverPosition fix(double lat, {bool live = true, int seconds = 0}) =>
      LiveDriverPosition(
          latitude: lat,
          longitude: -1.62,
          heading: 90,
          updatedAt: now.add(Duration(seconds: seconds)),
          isLiveFix: live);
  setUp(() => container = ProviderContainer());
  tearDown(() => container.dispose());
  for (final phase in [
    RideTrackingPhase.enRoute,
    RideTrackingPhase.inProgress
  ]) {
    test('live fixes move during $phase without snapshot rollback', () {
      container.read(rideTrackingPhaseProvider.notifier).state = phase;
      applyLiveDriverPosition(container.read, fix(6.68, live: false), now: now);
      applyLiveDriverPosition(container.read, fix(6.69), now: now);
      applyLiveDriverPosition(container.read, fix(6.70, seconds: 4), now: now);
      applyLiveDriverPosition(container.read, fix(6.68, live: false), now: now);
      expect(container.read(liveDriverPositionProvider)?.latitude, 6.70);
      expect(container.read(liveDriverPositionProvider)?.heading, 90);
    });
  }
  test('ignores delayed and duplicate live fixes', () {
    applyLiveDriverPosition(container.read, fix(6.70, seconds: 4), now: now);
    applyLiveDriverPosition(container.read, fix(6.69), now: now);
    applyLiveDriverPosition(container.read, fix(6.68, seconds: 4), now: now);
    expect(container.read(liveDriverPositionProvider)?.latitude, 6.70);
  });
  test('snapshots recover when live events stop', () {
    applyLiveDriverPosition(container.read, fix(6.69), now: now);
    applyLiveDriverPosition(container.read, fix(6.70, live: false),
        now: now.add(const Duration(seconds: 16)));
    expect(container.read(liveDriverPositionProvider)?.latitude, 6.70);
  });
  test('rejects invalid coordinates and keeps last good fix', () {
    applyLiveDriverPosition(container.read, fix(6.69), now: now);
    for (final invalid in [double.nan, double.infinity, 91.0]) {
      applyLiveDriverPosition(container.read, fix(invalid, seconds: 4),
          now: now);
    }
    expect(container.read(liveDriverPositionProvider)?.latitude, 6.69);
  });
}
