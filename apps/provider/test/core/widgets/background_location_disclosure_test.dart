import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:myshop_provider/src/core/widgets/background_location_disclosure.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('flutter.baseflow.com/geolocator');
  var permission = LocationPermission.whileInUse;
  var serviceEnabled = true;
  var appSettingsOpened = false;

  setUp(() {
    permission = LocationPermission.whileInUse;
    serviceEnabled = true;
    appSettingsOpened = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'checkPermission':
          return permission.index;
        case 'isLocationServiceEnabled':
          return serviceEnabled;
        case 'openAppSettings':
          appSettingsOpened = true;
          return true;
        case 'openLocationSettings':
          return true;
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('discloses background collection before permission request', (
    tester,
  ) async {
    Future<bool>? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () {
              result = confirmBackgroundLocationDisclosure(context);
            },
            child: const Text('Go Online'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Go Online'));
    await tester.pumpAndSettle();

    expect(find.text('Allow background location'), findsOneWidget);
    expect(find.textContaining('precise location'), findsOneWidget);
    expect(find.textContaining('closed or not in use'), findsOneWidget);
    expect(find.textContaining('stops when you go offline'), findsOneWidget);

    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(await result, isFalse);
  });

  testWidgets('does not show disclosure after Always permission is granted', (
    tester,
  ) async {
    permission = LocationPermission.always;
    bool? accepted;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              accepted = await confirmBackgroundLocationDisclosure(context);
            },
            child: const Text('Go Online'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Go Online'));
    await tester.pumpAndSettle();

    expect(accepted, isTrue);
    expect(find.text('Allow background location'), findsNothing);
  });

  testWidgets('offers app Settings when background access is still missing', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showLocationRecoveryIfNeeded(context),
            child: const Text('Recover'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Recover'));
    await tester.pumpAndSettle();

    expect(find.text('Background location is off'), findsOneWidget);
    expect(find.textContaining('Allow all the time'), findsOneWidget);
    await tester.tap(find.text('Open Settings'));
    await tester.pumpAndSettle();

    expect(appSettingsOpened, isTrue);
  });
}
