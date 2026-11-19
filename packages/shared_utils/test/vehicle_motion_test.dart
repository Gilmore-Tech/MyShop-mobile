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
    motion.update(
      point: (latitude: 6.701, longitude: -1.5998225),
      now: at,
      heading: 10,
    );
    expect(
      motion.sample(at.add(const Duration(seconds: 2)))!.heading,
      anyOf(closeTo(0, 0.01), closeTo(360, 0.01)),
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

  test('a noisy compass cannot turn a moving car sideways on a straight road',
      () {
    final motion = VehicleMotion();
    motion.update(point: start, now: now, heading: 90);
    final at = now.add(const Duration(seconds: 5));
    motion.update(point: east, now: at, heading: 0, route: [start, east]);
    for (var ms = 0; ms <= 5000; ms += 100) {
      expect(
        motion.sample(at.add(Duration(milliseconds: ms)))!.heading,
        closeTo(90, 1),
      );
    }
  });

  test('GPS offset does not create sideways connector legs on a road', () {
    final motion = VehicleMotion();
    const a = (latitude: 6.70008, longitude: -1.5999);
    const b = (latitude: 6.70009, longitude: -1.5991);
    motion.update(point: a, now: now, heading: 90);
    final at = now.add(const Duration(seconds: 5));
    motion.update(point: b, now: at, heading: 0, route: [start, east]);
    var last = a;
    for (var ms = 100; ms <= 5000; ms += 100) {
      final pose = motion.sample(at.add(Duration(milliseconds: ms)))!;
      expect(pose.point.longitude, greaterThan(last.longitude));
      expect(pose.heading, inInclusiveRange(85, 95));
      expect(pose.point.latitude, inInclusiveRange(a.latitude, b.latitude));
      last = pose.point;
    }
    expect(last, b);
  });

  test('ten-second GPS cadence keeps moving beyond the old five-second cap',
      () {
    final motion = VehicleMotion();
    motion.update(point: start, now: now, fixAt: now, heading: 90);
    final at = now.add(const Duration(seconds: 10));
    motion.update(point: east, now: at, fixAt: at, heading: 90);
    final halfway = motion.sample(at.add(const Duration(seconds: 5)))!;
    final later = motion.sample(at.add(const Duration(seconds: 8)))!;
    expect(halfway.point.longitude, closeTo(-1.5995, 0.000001));
    expect(later.point.longitude, greaterThan(halfway.point.longitude));
    expect(later.point.longitude, lessThan(east.longitude));
    expect(motion.sample(at.add(const Duration(seconds: 10)))!.point, east);
  });

  test('repeat coordinates preserve the planned arrival time', () {
    final motion = VehicleMotion();
    motion.update(point: start, now: now);
    final moving = now.add(const Duration(seconds: 5));
    motion.update(point: east, now: moving);
    final repeated = moving.add(const Duration(seconds: 4));
    final before = motion.sample(repeated)!;
    motion.update(point: east, now: repeated);
    expect(motion.sample(repeated)!.point, before.point);
    expect(motion.duration, const Duration(seconds: 1));
    expect(motion.sample(repeated.add(motion.duration))!.point, east);
    motion.update(point: east, now: repeated.add(const Duration(seconds: 5)));
    expect(motion.duration, Duration.zero);
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
