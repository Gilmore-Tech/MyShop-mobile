import 'package:shared_utils/shared_utils.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime.utc(2026, 11, 14);
  const start = (latitude: 6.7, longitude: -1.6);
  const east = (latitude: 6.7, longitude: -1.599);
  const north = (latitude: 6.701, longitude: -1.599);

  test('interpolates between fixes and stops at the last real fix', () {
    final motion = VehicleMotion();
    motion.update(point: start, now: now, heading: 90);
    final at = now.add(const Duration(seconds: 4));
    motion.update(point: east, now: at, heading: 90);
    final middle = motion.sample(at.add(const Duration(seconds: 2)))!;
    expect(middle.point.longitude, closeTo(-1.5995, 0.000001));
    expect(motion.sample(at.add(const Duration(minutes: 1)))!.point, east);
  });

  test('follows an L-shaped road and rotates through its turn', () {
    final motion = VehicleMotion();
    motion.update(point: start, now: now, heading: 90);
    final at = now.add(const Duration(seconds: 4));
    motion
        .update(point: north, now: at, heading: 0, route: [start, east, north]);
    final before = motion.sample(at.add(const Duration(seconds: 1)))!;
    final turn = motion.sample(at.add(const Duration(seconds: 2)))!;
    final after = motion.sample(at.add(const Duration(seconds: 3)))!;
    expect(before.point.latitude, closeTo(start.latitude, 0.00001));
    expect(turn.point.longitude, closeTo(east.longitude, 0.00001));
    expect(after.point.longitude, closeTo(north.longitude, 0.00001));
    expect(before.heading, closeTo(90, 1));
    expect(turn.heading, inInclusiveRange(25, 65));
    expect(after.heading, closeTo(0, 1));
  });

  test('mid-animation retargeting starts at the displayed point and heading',
      () {
    final motion = VehicleMotion();
    motion.update(point: start, now: now, heading: 90);
    motion.update(
      point: east,
      now: now.add(const Duration(seconds: 4)),
      heading: 90,
    );
    final at = now.add(const Duration(seconds: 5));
    final before = motion.sample(at)!;
    motion.update(point: north, now: at, heading: 0);
    final after = motion.sample(at)!;
    expect(after.point, before.point);
    expect(after.heading, before.heading);
  });

  test('crossing north uses the short rotation rather than a full spin', () {
    final motion = VehicleMotion();
    motion.update(point: start, now: now, heading: 350);
    final at = now.add(const Duration(seconds: 4));
    motion.update(point: east, now: at, heading: 10);
    expect(
      motion.sample(at.add(const Duration(seconds: 2)))!.heading,
      closeTo(0, 0.01),
    );
  });

  test('a genuine deviation does not follow the stale road or cut a U-turn',
      () {
    final motion = VehicleMotion();
    motion.update(point: start, now: now, heading: 90);
    final at = now.add(const Duration(seconds: 4));
    const offRoad = (latitude: 6.699, longitude: -1.6);
    motion.update(point: offRoad, now: at, route: [start, east, north]);
    expect(
      motion.sample(at.add(const Duration(seconds: 2)))!.point.longitude,
      closeTo(start.longitude, 0.000001),
    );
  });

  test('rejects stale/invalid fixes and recovers immediately after a long gap',
      () {
    final motion = VehicleMotion();
    motion.update(point: start, now: now, fixAt: now);
    expect(motion.update(point: east, now: now, fixAt: now), isFalse);
    expect(
      motion.update(
        point: (latitude: double.nan, longitude: 0),
        now: now.add(const Duration(seconds: 1)),
      ),
      isFalse,
    );
    final at = now.add(const Duration(minutes: 1));
    motion.update(point: north, now: at);
    expect(motion.sample(at)!.point, north);
    motion.reset();
    expect(motion.sample(at), isNull);
  });
}
