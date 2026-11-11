import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_provider/src/features/driver_home/data/surge_areas_service.dart';
import 'package:myshop_provider/src/features/driver_home/providers/surge_provider.dart';

void main() {
  final started = DateTime.utc(2026, 11, 10);
  SurgeMapArea area(DateTime expiry) => SurgeMapArea(
      id: 'area',
      name: 'Area',
      multiplier: 1.5,
      source: 'manual',
      expiresAt: expiry,
      polygons: []);

  testWidgets(
      'authoritative empty response immediately removes active coverage',
      (tester) async {
    var response = [area(started.add(const Duration(seconds: 25)))];
    final notifier =
        SurgeAreasNotifier(load: () async => response, now: () => started);
    await tester.pump(const Duration(milliseconds: 1));
    expect(notifier.state, hasLength(1));
    response = [];
    await notifier.refresh();
    expect(notifier.state, isEmpty);
    notifier.dispose();
  });
  testWidgets('coverage expires during outage and cannot remain stuck on map',
      (tester) async {
    var now = started;
    var calls = 0;
    final notifier = SurgeAreasNotifier(
        load: () async {
          if (calls++ == 0) {
            return [area(started.add(const Duration(seconds: 25)))];
          }
          throw Exception('offline');
        },
        now: () => now);
    await tester.pump(const Duration(milliseconds: 1));
    expect(notifier.state, hasLength(1));
    now = started.add(const Duration(seconds: 26));
    await tester.pump(const Duration(seconds: 1));
    expect(notifier.state, isEmpty);
    notifier.dispose();
  });
  testWidgets(
      'invalidation during an in-flight response fetches newer authority',
      (tester) async {
    final first = Completer<List<SurgeMapArea>>();
    var calls = 0;
    final notifier = SurgeAreasNotifier(
        load: () {
          calls++;
          return calls == 1 ? first.future : Future.value([]);
        },
        now: () => started);
    await tester.pump(const Duration(milliseconds: 1));
    await notifier.refresh(); // Surge disabled while the first GET is running.
    first.complete([area(started.add(const Duration(seconds: 25)))]);
    await tester.pump(const Duration(milliseconds: 1));
    expect(calls, 2);
    expect(notifier.state, isEmpty);
    notifier.dispose();
  });
  testWidgets('background/unauthenticated state does not fetch or retain areas',
      (tester) async {
    var calls = 0;
    final notifier = SurgeAreasNotifier(
        load: () async {
          calls++;
          return [];
        },
        enabled: false);
    await tester.pump(const Duration(seconds: 30));
    await notifier.refresh();
    expect(calls, 0);
    expect(notifier.state, isEmpty);
    notifier.dispose();
  });
  testWidgets('disposing stops refreshes and ignores an old response',
      (tester) async {
    final response = Completer<List<SurgeMapArea>>();
    var calls = 0;
    final notifier = SurgeAreasNotifier(
        load: () {
          calls++;
          return response.future;
        },
        now: () => started);
    await tester.pump(const Duration(milliseconds: 1));
    notifier.dispose();
    response.complete([area(started.add(const Duration(seconds: 25)))]);
    await tester.pump(const Duration(seconds: 30));
    expect(calls, 1);
  });
}
