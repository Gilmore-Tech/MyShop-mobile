import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_client/src/features/safety/emergency_dialer.dart';

void main() {
  test('opens the exact tel URI only after the platform accepts it', () async {
    Uri? checked;
    Uri? launched;

    final result = await openEmergencyDialer(
      '191',
      canLaunch: (uri) async {
        checked = uri;
        return true;
      },
      launch: (uri) async {
        launched = uri;
        return true;
      },
    );

    expect(result, isTrue);
    expect(checked, Uri(scheme: 'tel', path: '191'));
    expect(launched, checked);
  });

  test('does not attempt launch when the dialer is unavailable', () async {
    var launchCalls = 0;

    final result = await openEmergencyDialer(
      '112',
      canLaunch: (_) async => false,
      launch: (_) async {
        launchCalls += 1;
        return true;
      },
    );

    expect(result, isFalse);
    expect(launchCalls, 0);
  });

  test('release source keeps every SOS entry on the approved hold flow', () {
    final tracking =
        File('lib/src/features/ride/screens/ride_tracking_screen.dart')
            .readAsStringSync();
    final emergency =
        File('lib/src/features/safety/screens/emergency_screen.dart')
            .readAsStringSync();
    final sheet = File('lib/src/features/ride/widgets/ride_tracking_sheet.dart')
        .readAsStringSync();

    expect(tracking, contains('context.push(AppRoutes.safetyEmergency)'));
    expect(tracking, isNot(contains('_showSosDialog')));
    expect(emergency, contains('duration: const Duration(seconds: 3)'));
    expect(emergency, contains("label: 'Ambulance\\n112'"));
    expect(emergency, contains("label: 'Fire\\n112'"));
    expect(emergency, isNot(contains('Auto-dials')));
    expect(emergency, isNot(contains('Ambulance\\n193')));
    expect(emergency, isNot(contains('Fire\\n192')));
    expect(sheet, isNot(contains('In-app recording is active')));
  });
}
