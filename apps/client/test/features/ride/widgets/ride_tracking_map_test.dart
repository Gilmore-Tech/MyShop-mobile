import 'package:flutter/material.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myshop_client/src/core/services/directions_service.dart';
import 'package:myshop_client/src/features/ride/widgets/ride_route_map.dart';
import 'package:myshop_client/src/features/ride/providers/ride_search_provider.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
// ignore: depend_on_referenced_packages
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'package:myshop_client/src/features/ride/providers/ride_provider.dart';
import 'package:myshop_client/src/core/providers/chat_controller_provider.dart';
import 'package:myshop_client/src/features/ride/screens/ride_tracking_screen.dart';

class _Directions extends Mock implements DirectionsService {}

class _MapController extends Mock implements GoogleMapController {}

class _FakeMapsPlatform extends GoogleMapsFlutterPlatform {
  @override
  Widget buildViewWithConfiguration(
    int creationId,
    PlatformViewCreatedCallback onPlatformViewCreated, {
    required MapWidgetConfiguration widgetConfiguration,
    MapConfiguration mapConfiguration = const MapConfiguration(),
    MapObjects mapObjects = const MapObjects(),
  }) =>
      const SizedBox.expand();
}

void main() {
  late GoogleMapsFlutterPlatform original;
  setUp(() {
    registerFallbackValue(const LatLng(0, 0));
    registerFallbackValue(CameraUpdate.newLatLng(const LatLng(0, 0)));
    original = GoogleMapsFlutterPlatform.instance;
    GoogleMapsFlutterPlatform.instance = _FakeMapsPlatform();
  });
  tearDown(() => GoogleMapsFlutterPlatform.instance = original);
  testWidgets('camera stays at a stable scale and follows the displayed car',
      (tester) async {
    final controller = _MapController();
    final updates = <Object>[];
    when(() =>
            controller.animateCamera(any(), duration: any(named: 'duration')))
        .thenAnswer((invocation) async {
      updates
          .add((invocation.positionalArguments.first as CameraUpdate).toJson());
    });
    when(() => controller.dispose()).thenAnswer((_) async {});
    var visible = LatLngBounds(
      southwest: const LatLng(6.695, -1.605),
      northeast: const LatLng(6.705, -1.595),
    );
    when(() => controller.getVisibleRegion()).thenAnswer((_) async => visible);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    var inset = 100.0;
    late StateSetter rebuild;
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: StatefulBuilder(builder: (context, setState) {
        rebuild = setState;
        return Scaffold(
            body: RideRouteMap(
          destination: 'Destination',
          etaMinutes: 10,
          bottomInset: inset,
        ));
      })),
    ));
    GoogleMap map() => tester.widget<GoogleMap>(find.byType(GoogleMap));
    map().onMapCreated!(controller);
    await tester.pump();
    final at = DateTime.utc(2026, 11, 16);
    container.read(liveDriverPositionProvider.notifier).state =
        LiveDriverPosition(
      latitude: 6.7,
      longitude: -1.6,
      heading: 90,
      updatedAt: at,
    );
    await tester.pump();
    expect(updates, hasLength(1));
    expect((updates.single as List).first, 'newCameraPosition');
    container.read(liveDriverPositionProvider.notifier).state =
        LiveDriverPosition(
      latitude: 6.7,
      longitude: -1.599,
      heading: 90,
      updatedAt: at.add(const Duration(seconds: 4)),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(updates, hasLength(1));
    // Moving the sheet must not refit/zoom the map on every drag frame.
    for (var i = 0; i < 10; i++) {
      rebuild(() => inset += 5);
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(updates, hasLength(1));
    visible = LatLngBounds(
      southwest: const LatLng(6.69, -1.62),
      northeast: const LatLng(6.695, -1.61),
    );
    final driver =
        map().markers.singleWhere((m) => m.markerId.value == 'driver');
    await tester.pump(const Duration(milliseconds: 500));
    expect(updates, hasLength(2));
    expect(updates.last, ['newLatLng', driver.position.toJson()]);
    // Pause automatic recentering while the rider explores the map.
    final gesture =
        await tester.startGesture(tester.getCenter(find.byType(GoogleMap)));
    await tester.pump(const Duration(seconds: 2));
    expect(updates, hasLength(2));
    await gesture.up();
    await tester.pump(const Duration(seconds: 5));
    expect(updates, hasLength(2));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'renders intermediate car positions instead of teleporting on GPS updates',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
          home: Scaffold(
              body: RideRouteMap(
        destination: 'Destination',
        etaMinutes: 10,
      ))),
    ));
    final at = DateTime.utc(2026, 11, 14);
    container.read(liveDriverPositionProvider.notifier).state =
        LiveDriverPosition(
      latitude: 6.7,
      longitude: -1.6,
      heading: 90,
      updatedAt: at,
      isLiveFix: true,
    );
    await tester.pump();
    container.read(liveDriverPositionProvider.notifier).state =
        LiveDriverPosition(
      latitude: 6.7,
      longitude: -1.599,
      heading: 90,
      updatedAt: at.add(const Duration(seconds: 4)),
      isLiveFix: true,
    );
    await tester.pump();
    Marker driver() => tester
        .widget<GoogleMap>(find.byType(GoogleMap))
        .markers
        .singleWhere((m) => m.markerId.value == 'driver');
    expect(driver().position.longitude, closeTo(-1.6, 0.000001));
    await tester.pump(const Duration(seconds: 2));
    expect(driver().position.longitude, closeTo(-1.5995, 0.00002));
    await tester.pump(const Duration(seconds: 2));
    expect(driver().position.longitude, closeTo(-1.599, 0.000001));
    await tester.pump(const Duration(seconds: 20));
    expect(driver().position.longitude, closeTo(-1.599, 0.000001));
    await tester.pumpWidget(const SizedBox());
  });

  for (final phase in [
    RideTrackingPhase.enRoute,
    RideTrackingPhase.inProgress
  ]) {
    testWidgets('GPS updates the car and road ETA together during $phase',
        (tester) async {
      final directions = _Directions();
      const start = LatLng(0, 0);
      const corner = LatLng(0, 0.01);
      const end = LatLng(0.01, 0.01);
      when(() => directions.fetchRoute(
              origin: any(named: 'origin'),
              destination: any(named: 'destination'),
              purpose: any(named: 'purpose')))
          .thenAnswer((_) async => const DirectionsRoute(
              polyline: [start, corner, end],
              distanceMeters: 2200,
              durationSeconds: 600));
      final container = ProviderContainer(overrides: [
        directionsServiceProvider.overrideWithValue(directions),
      ]);
      addTearDown(container.dispose);
      container.read(rideSearchProvider.notifier).setLocation(
          RideSearchField.pickup,
          const RideLocation(
              name: 'Pickup', address: 'Pickup', lat: 0.01, lng: 0.01));
      container.read(rideSearchProvider.notifier).setLocation(
          RideSearchField.destination,
          const RideLocation(
              name: 'Dropoff', address: 'Dropoff', lat: 0.02, lng: 0.02));
      await tester.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
              home: Scaffold(
                  body: RideRouteMap(
                      destination: 'Destination',
                      etaMinutes: 99,
                      phase: phase)))));
      container.read(liveDriverPositionProvider.notifier).state =
          const LiveDriverPosition(latitude: 0, longitude: 0);
      await tester.pump();
      await tester.pump();
      final eta = phase == RideTrackingPhase.inProgress
          ? tripEtaProvider
          : rideEtaProvider;
      expect(container.read(eta), 10);
      final call = verify(() => directions.fetchRoute(
          origin: start,
          destination: captureAny(named: 'destination'),
          purpose: 'client_ride_tracking'));
      expect(
          call.captured.single,
          phase == RideTrackingPhase.inProgress
              ? const LatLng(0.02, 0.02)
              : end);
      container.read(liveDriverPositionProvider.notifier).state =
          const LiveDriverPosition(latitude: 0, longitude: 0.01);
      await tester.pump();
      expect(container.read(eta), lessThan(10));
      final map = tester.widget<GoogleMap>(find.byType(GoogleMap));
      expect(
          map.markers.singleWhere((m) => m.markerId.value == 'driver').position,
          corner);
      await tester.pump(const Duration(seconds: 30));
      // No fake countdown while the driver is stationary.
      expect(container.read(eta), 5);
      container.read(liveDriverPositionProvider.notifier).state =
          LiveDriverPosition(
              latitude: 0,
              longitude: 0.01,
              updatedAt: DateTime.now().subtract(const Duration(seconds: 30)));
      await tester.pump();
      expect(
          find.text(phase == RideTrackingPhase.inProgress
              ? 'UPDATING DESTINATION ETA…'
              : 'UPDATING PICKUP ETA…'),
          findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  }
  for (final phase in [
    RideTrackingPhase.enRoute,
    RideTrackingPhase.inProgress,
    RideTrackingPhase.arrived
  ]) {
    testWidgets('preserves $phase and shows moving car above sheet',
        (tester) async {
      final container = ProviderContainer(overrides: [
        chatControllerProvider.overrideWith((_) async => null),
        activeRideTrackingMaintainerProvider
            .overrideWith((_) => const Stream.empty()),
      ]);
      addTearDown(container.dispose);
      container.read(rideTrackingPhaseProvider.notifier).state = phase;
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
            home: RideTrackingScreen(
                driver: MatchedDriver(
          name: 'Driver',
          vehicle: 'Toyota',
          plateNumber: 'GT 123',
          rating: 4.8,
          minutesAway: 3,
          driversAvailable: 1,
        ))),
      ));
      await tester.pump();
      expect(container.read(rideTrackingPhaseProvider), phase);
      final map = tester.widget<GoogleMap>(find.byType(GoogleMap));
      expect(map.padding.bottom, greaterThan(0));
      expect(
          map.padding.top + map.padding.bottom,
          lessThan(
              tester.view.physicalSize.height / tester.view.devicePixelRatio));
      container.read(liveDriverPositionProvider.notifier).state =
          const LiveDriverPosition(
              latitude: 6.69, longitude: -1.61, heading: 90);
      await tester.pump();
      final updatedMap = tester.widget<GoogleMap>(find.byType(GoogleMap));
      final driver =
          updatedMap.markers.singleWhere((m) => m.markerId.value == 'driver');
      expect(driver.position, const LatLng(6.69, -1.61));
      expect(driver.rotation, 90);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
