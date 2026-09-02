import 'dart:async';
import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myshop_client/src/app/router.dart';
import 'package:myshop_client/src/core/di/providers.dart';
import 'package:myshop_client/src/core/providers/current_location_label_provider.dart';
import 'package:myshop_client/src/core/providers/current_location_provider.dart';
import 'package:myshop_client/src/core/services/google_places_service.dart';
import 'package:myshop_client/src/features/home/providers/home_provider.dart';
import 'package:myshop_client/src/features/home/providers/promo_campaigns_provider.dart';
import 'package:myshop_client/src/features/home/screens/home_screen.dart';
import 'package:myshop_client/src/features/notifications/providers/notifications_provider.dart';
import 'package:myshop_client/src/features/profile/providers/profile_provider.dart';
import 'package:myshop_client/src/features/ride/providers/ride_search_provider.dart';

import '../../../support/png_http_overrides.dart';

class _MockCurrentLocationService extends Mock
    implements CurrentLocationService {}

class _MockGooglePlacesService extends Mock implements GooglePlacesService {}

class _FakeAccountNotifier extends AccountScreenNotifier {
  @override
  Future<AccountScreenData> build() async => const AccountScreenData(
        profile: AccountProfile(
          userId: 'client-1',
          displayName: 'Ama Mensah',
          maskedEmail: '',
          maskedPhone: '+233 ••• ••• 227',
          isKycVerified: false,
        ),
        unreadNotificationCount: 0,
      );
}

class _EmptyOffersNotifier extends SpecialOffersNotifier {
  @override
  Future<List<SpecialOffer>> build() async => const [];
}

class _RecentActivityNotifier extends HomeRecentActivityNotifier {
  _RecentActivityNotifier(this.items);

  final List<HomeRecentActivityItem> items;

  @override
  Future<List<HomeRecentActivityItem>> build() async => items;
}

Position _position({
  required double latitude,
  required double longitude,
  required DateTime timestamp,
}) {
  return Position(
    latitude: latitude,
    longitude: longitude,
    timestamp: timestamp,
    accuracy: 8,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );
}

void main() {
  Future<ProviderContainer> pumpHome(
    WidgetTester tester, {
    List<HomeRecentActivityItem> activity = const [],
    List<ActivePromoCampaign> campaigns = const [],
    Position? currentPosition,
    CurrentLocationService? locationService,
    GooglePlacesService? placesService,
    bool useRealCurrentLocationLabel = false,
    int unreadNotificationCount = 0,
  }) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = GoRouter(
      initialLocation: AppRoutes.home,
      routes: [
        GoRoute(
          path: AppRoutes.home,
          builder: (_, __) => const HomeScreen(),
        ),
        GoRoute(
          path: AppRoutes.rideEstimate,
          builder: (_, __) => const Scaffold(body: Text('Ride estimate')),
        ),
        GoRoute(
          path: AppRoutes.notifications,
          builder: (_, __) => const Scaffold(body: Text('Notification inbox')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountScreenProvider.overrideWith(_FakeAccountNotifier.new),
          clientUnreadNotificationCountProvider.overrideWithValue(
            unreadNotificationCount,
          ),
          if (!useRealCurrentLocationLabel)
            currentLocationLabelProvider.overrideWith(
              (_) async => 'Prempeh II Street, Adum, Kumasi, Ghana',
            ),
          specialOffersProvider.overrideWith(_EmptyOffersNotifier.new),
          activePromoCampaignsProvider.overrideWith((_) async => campaigns),
          homeRecentActivityProvider.overrideWith(
            () => _RecentActivityNotifier(activity),
          ),
          if (currentPosition != null)
            currentDevicePositionProvider.overrideWith(
              (_) => currentPosition,
            ),
          if (locationService != null)
            currentLocationServiceProvider.overrideWithValue(locationService),
          if (placesService != null)
            googlePlacesServiceProvider.overrideWithValue(placesService),
          if (placesService != null)
            reverseGeocodingServiceProvider.overrideWithValue(placesService),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(tester.element(find.byType(HomeScreen)));
  }

  testWidgets('shows resolved location and no empty offers placeholder',
      (tester) async {
    await pumpHome(tester);

    expect(
      find.text('Current: Prempeh II Street, Adum, Kumasi, Ghana'),
      findsOneWidget,
    );
    expect(find.text('SPECIAL OFFERS'), findsNothing);
    expect(find.text('RECENT ACTIVITY'), findsOneWidget);
    expect(find.text('Your activity will appear here'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows the shared exact notification badge on Home',
      (tester) async {
    await pumpHome(tester, unreadNotificationCount: 3);

    expect(find.byKey(const Key('client-notification-bell')), findsOneWidget);
    expect(
      find.byKey(const Key('client-notification-unread-dot')),
      findsOneWidget,
    );
    expect(find.byTooltip('Notifications, 3 unread'), findsOneWidget);

    await tester.tap(find.byKey(const Key('client-notification-bell')));
    await tester.pumpAndSettle();
    expect(find.text('Notification inbox'), findsOneWidget);
  });

  testWidgets('renders the approved combined recent activity cards',
      (tester) async {
    await pumpHome(
      tester,
      activity: [
        HomeRecentActivityItem(
          id: 'ride-1',
          type: HomeActivityType.ride,
          title: 'Ride to Ahodwo',
          subtitle: 'Adum → Ahodwo',
          status: HomeActivityStatus.completed,
          createdAt: DateTime.now(),
        ),
        HomeRecentActivityItem(
          id: 'job-1',
          type: HomeActivityType.job,
          title: 'Plumbing',
          subtitle: 'Daban, Kumasi',
          status: HomeActivityStatus.inProgress,
          createdAt: DateTime.now().subtract(const Duration(hours: 1)),
        ),
      ],
    );

    expect(find.text('Ride to Ahodwo'), findsOneWidget);
    expect(find.text('Plumbing'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('In progress'), findsOneWidget);
    expect(find.text('Your activity will appear here'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hides the Promos section when no campaign carries a banner',
      (tester) async {
    await pumpHome(tester);
    expect(find.text('PROMOS'), findsNothing);
  });

  testWidgets(
      'shows the Promos header between the booking cards and recent activity',
      (tester) async {
    HttpOverrides.global = PngHttpOverrides();
    addTearDown(() => HttpOverrides.global = null);
    await pumpHome(
      tester,
      campaigns: [
        ActivePromoCampaign(
          id: 'camp-1',
          name: 'Weekend 15% Off',
          campaignType: 'percentage_discount',
          discountValue: 15,
          maxDiscountPesewas: 1000,
          minBookingPesewas: 0,
          promoScope: 'ride',
          newClientsOnly: false,
          startsAt: DateTime.now().subtract(const Duration(hours: 1)),
          endsAt: DateTime.now().add(const Duration(days: 7)),
          bannerUrl: 'https://cdn.example/banner.png',
          bannerPriority: 1,
        ),
      ],
    );

    expect(find.text('PROMOS'), findsOneWidget);
    final promosY = tester.getTopLeft(find.text('PROMOS')).dy;
    final activityY = tester.getTopLeft(find.text('RECENT ACTIVITY')).dy;
    expect(promosY, lessThan(activityY));
  });

  testWidgets('new ride refreshes stale office pickup before seeding',
      (tester) async {
    final location = _MockCurrentLocationService();
    final places = _MockGooglePlacesService();
    final staleOffice = _position(
      latitude: 6.6900,
      longitude: -1.6200,
      timestamp: DateTime.now().subtract(const Duration(hours: 1)),
    );
    final freshMall = _position(
      latitude: 6.7042,
      longitude: -1.6349,
      timestamp: DateTime.now().subtract(const Duration(seconds: 5)),
    );
    when(() => location.ensure(forceRefresh: true, retryOnFailure: false))
        .thenAnswer((_) async => freshMall);
    when(() => places.reverseGeocodePlace(6.7042, -1.6349)).thenAnswer(
      (_) async => const ReverseGeocodePlace(
        name: 'Kumasi City Mall',
        address: 'Kumasi City Mall, Asokwa, Kumasi',
      ),
    );

    final container = await pumpHome(
      tester,
      currentPosition: staleOffice,
      locationService: location,
      placesService: places,
    );

    await tester.tap(find.text('Book Akwaaba Ride'));
    await tester.pumpAndSettle();

    final pickup = container.read(rideSearchProvider).pickup;
    expect(pickup?.name, 'Kumasi City Mall');
    expect(pickup?.address, 'Kumasi City Mall, Asokwa, Kumasi');
    expect(pickup?.lat, 6.7042);
    expect(pickup?.lng, -1.6349);
    verify(
      () => location.ensure(forceRefresh: true, retryOnFailure: false),
    ).called(1);
    verify(() => places.reverseGeocodePlace(6.7042, -1.6349)).called(1);
    verifyNever(() => places.reverseGeocodePlace(6.6900, -1.6200));
  });

  testWidgets('failed refresh does not reuse an hours-old pickup',
      (tester) async {
    final location = _MockCurrentLocationService();
    final places = _MockGooglePlacesService();
    final staleOffice = _position(
      latitude: 6.6900,
      longitude: -1.6200,
      timestamp: DateTime.now().subtract(const Duration(hours: 1)),
    );
    when(() => location.ensure(forceRefresh: true, retryOnFailure: false))
        .thenAnswer((_) async => staleOffice);

    final container = await pumpHome(
      tester,
      currentPosition: staleOffice,
      locationService: location,
      placesService: places,
    );

    await tester.tap(find.text('Book Akwaaba Ride'));
    await tester.pumpAndSettle();

    expect(container.read(rideSearchProvider).pickup, isNull);
    verify(
      () => location.ensure(forceRefresh: true, retryOnFailure: false),
    ).called(1);
    verifyNever(() => places.reverseGeocodePlace(6.6900, -1.6200));
  });

  testWidgets('unavailable refresh does not reuse a recent process cache',
      (tester) async {
    final location = _MockCurrentLocationService();
    final places = _MockGooglePlacesService();
    final recentCache = _position(
      latitude: 6.7011,
      longitude: -1.6292,
      timestamp: DateTime.now().subtract(const Duration(seconds: 30)),
    );
    when(() => location.ensure(forceRefresh: true, retryOnFailure: false))
        .thenAnswer((_) async => null);

    final container = await pumpHome(
      tester,
      currentPosition: recentCache,
      locationService: location,
      placesService: places,
    );

    await tester.tap(find.text('Book Akwaaba Ride'));
    await tester.pumpAndSettle();

    expect(container.read(rideSearchProvider).pickup, isNull);
    verify(
      () => location.ensure(forceRefresh: true, retryOnFailure: false),
    ).called(1);
    verifyNever(() => places.reverseGeocodePlace(6.7011, -1.6292));
  });

  testWidgets('home label and automatic pickup share one reverse geocode',
      (tester) async {
    final location = _MockCurrentLocationService();
    final places = _MockGooglePlacesService();
    final staleOffice = _position(
      latitude: 6.6900,
      longitude: -1.6200,
      timestamp: DateTime.now().subtract(const Duration(hours: 1)),
    );
    final freshMall = _position(
      latitude: 6.7042,
      longitude: -1.6349,
      timestamp: DateTime.now().subtract(const Duration(seconds: 5)),
    );
    when(() => places.reverseGeocodePlace(6.6900, -1.6200)).thenAnswer(
      (_) async => const ReverseGeocodePlace(
        name: 'Old office',
        address: 'Old office, Kumasi',
      ),
    );
    when(() => places.reverseGeocodePlace(6.7042, -1.6349)).thenAnswer(
      (_) async => const ReverseGeocodePlace(
        name: 'Kumasi City Mall',
        address: 'Kumasi City Mall, Asokwa, Kumasi',
      ),
    );

    late ProviderContainer container;
    when(
      () => location.ensure(forceRefresh: true, retryOnFailure: false),
    ).thenAnswer((_) async {
      container.read(currentDevicePositionProvider.notifier).state = freshMall;
      return freshMall;
    });
    container = await pumpHome(
      tester,
      currentPosition: staleOffice,
      locationService: location,
      placesService: places,
      useRealCurrentLocationLabel: true,
    );
    clearInteractions(places);

    await tester.tap(find.text('Book Akwaaba Ride'));
    await tester.pumpAndSettle();

    expect(container.read(rideSearchProvider).pickup?.name, 'Kumasi City Mall');
    verify(
      () => location.ensure(forceRefresh: true, retryOnFailure: false),
    ).called(1);
    verify(() => places.reverseGeocodePlace(6.7042, -1.6349)).called(1);
  });

  testWidgets('double tap starts one GPS and reverse-geocode request',
      (tester) async {
    final location = _MockCurrentLocationService();
    final places = _MockGooglePlacesService();
    final refresh = Completer<Position?>();
    final freshMall = _position(
      latitude: 6.7042,
      longitude: -1.6349,
      timestamp: DateTime.now().subtract(const Duration(seconds: 5)),
    );
    when(() => location.ensure(forceRefresh: true, retryOnFailure: false))
        .thenAnswer((_) => refresh.future);
    when(() => places.reverseGeocodePlace(6.7042, -1.6349)).thenAnswer(
      (_) async => const ReverseGeocodePlace(
        name: 'Kumasi City Mall',
        address: 'Kumasi City Mall, Asokwa, Kumasi',
      ),
    );
    final container = await pumpHome(
      tester,
      locationService: location,
      placesService: places,
    );

    await tester.tap(find.text('Book Akwaaba Ride'));
    await tester.tap(find.text('Book Akwaaba Ride'));
    await tester.pump();
    verify(
      () => location.ensure(forceRefresh: true, retryOnFailure: false),
    ).called(1);

    refresh.complete(freshMall);
    await tester.pumpAndSettle();

    expect(container.read(rideSearchProvider).pickup?.name, 'Kumasi City Mall');
    verify(() => places.reverseGeocodePlace(6.7042, -1.6349)).called(1);
    expect(find.text('Ride estimate'), findsOneWidget);
  });

  testWidgets(
      'late address reuses one request and cannot replace manual pickup',
      (tester) async {
    final location = _MockCurrentLocationService();
    final places = _MockGooglePlacesService();
    final place = Completer<ReverseGeocodePlace?>();
    final freshMall = _position(
      latitude: 6.7042,
      longitude: -1.6349,
      timestamp: DateTime.now().subtract(const Duration(seconds: 5)),
    );
    when(() => location.ensure(forceRefresh: true, retryOnFailure: false))
        .thenAnswer((_) async => freshMall);
    when(() => places.reverseGeocodePlace(6.7042, -1.6349))
        .thenAnswer((_) => place.future);
    final container = await pumpHome(
      tester,
      locationService: location,
      placesService: places,
    );

    await tester.tap(find.text('Book Akwaaba Ride'));
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(
      container.read(rideSearchProvider).pickup?.name,
      'Pickup selected from GPS',
    );

    container.read(rideSearchProvider.notifier).setLocation(
          RideSearchField.pickup,
          const RideLocation(
            name: 'Chosen pickup',
            address: 'Chosen pickup address',
            lat: 6.7042,
            lng: -1.6349,
          ),
        );
    place.complete(
      const ReverseGeocodePlace(
        name: 'Kumasi City Mall',
        address: 'Kumasi City Mall, Asokwa, Kumasi',
      ),
    );
    await tester.pumpAndSettle();

    expect(container.read(rideSearchProvider).pickup?.name, 'Chosen pickup');
    verify(() => places.reverseGeocodePlace(6.7042, -1.6349)).called(1);
  });

  testWidgets('late address cannot unmark a pickup after ride creation',
      (tester) async {
    final location = _MockCurrentLocationService();
    final places = _MockGooglePlacesService();
    final place = Completer<ReverseGeocodePlace?>();
    final freshMall = _position(
      latitude: 6.7042,
      longitude: -1.6349,
      timestamp: DateTime.now().subtract(const Duration(seconds: 5)),
    );
    when(() => location.ensure(forceRefresh: true, retryOnFailure: false))
        .thenAnswer((_) async => freshMall);
    when(() => places.reverseGeocodePlace(6.7042, -1.6349))
        .thenAnswer((_) => place.future);
    final container = await pumpHome(
      tester,
      locationService: location,
      placesService: places,
    );

    await tester.tap(find.text('Book Akwaaba Ride'));
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(
      container.read(rideSearchProvider).pickup?.name,
      'Pickup selected from GPS',
    );
    container.read(rideSearchProvider.notifier).markSubmitted();

    place.complete(
      const ReverseGeocodePlace(
        name: 'Kumasi City Mall',
        address: 'Kumasi City Mall, Asokwa, Kumasi',
      ),
    );
    await tester.pumpAndSettle();

    final search = container.read(rideSearchProvider);
    expect(search.pickup?.name, 'Pickup selected from GPS');
    expect(search.wasSubmitted, isTrue);
    verify(() => places.reverseGeocodePlace(6.7042, -1.6349)).called(1);
  });

  testWidgets('submitted pickup is refreshed even if completion was missed',
      (tester) async {
    final location = _MockCurrentLocationService();
    final places = _MockGooglePlacesService();
    final freshMall = _position(
      latitude: 6.7042,
      longitude: -1.6349,
      timestamp: DateTime.now().subtract(const Duration(seconds: 5)),
    );
    when(() => location.ensure(forceRefresh: true, retryOnFailure: false))
        .thenAnswer((_) async => freshMall);
    when(() => places.reverseGeocodePlace(6.7042, -1.6349)).thenAnswer(
      (_) async => const ReverseGeocodePlace(
        name: 'Kumasi City Mall',
        address: 'Kumasi City Mall, Asokwa, Kumasi',
      ),
    );
    final container = await pumpHome(
      tester,
      locationService: location,
      placesService: places,
    );
    container.read(rideSearchProvider.notifier)
      ..setLocation(
        RideSearchField.pickup,
        const RideLocation(
          name: 'Previous office',
          address: 'Previous office pickup',
          lat: 6.6900,
          lng: -1.6200,
        ),
      )
      ..setLocation(
        RideSearchField.destination,
        const RideLocation(
          name: 'Previous destination',
          address: 'Previous destination address',
          lat: 6.7100,
          lng: -1.6000,
        ),
      )
      ..markSubmitted();
    await tester.pump();

    await tester.tap(find.text('Book Akwaaba Ride'));
    await tester.pumpAndSettle();

    final search = container.read(rideSearchProvider);
    expect(search.pickup?.name, 'Kumasi City Mall');
    expect(search.destination, isNull);
    expect(search.wasSubmitted, isFalse);
    verify(
      () => location.ensure(forceRefresh: true, retryOnFailure: false),
    ).called(1);
    verify(() => places.reverseGeocodePlace(6.7042, -1.6349)).called(1);
  });

  testWidgets('explicit pickup is preserved without refreshing GPS',
      (tester) async {
    final location = _MockCurrentLocationService();
    final places = _MockGooglePlacesService();
    final container = await pumpHome(
      tester,
      currentPosition: _position(
        latitude: 6.6900,
        longitude: -1.6200,
        timestamp: DateTime.now(),
      ),
      locationService: location,
      placesService: places,
    );
    container.read(rideSearchProvider.notifier).setLocation(
          RideSearchField.pickup,
          const RideLocation(
            name: 'Chosen pickup',
            address: 'Chosen pickup address',
            lat: 6.7123,
            lng: -1.6012,
          ),
        );
    await tester.pump();

    await tester.tap(find.text('Book Akwaaba Ride'));
    await tester.pumpAndSettle();

    final pickup = container.read(rideSearchProvider).pickup;
    expect(pickup?.name, 'Chosen pickup');
    expect(pickup?.lat, 6.7123);
    expect(pickup?.lng, -1.6012);
    verifyNever(
      () => location.ensure(forceRefresh: true, retryOnFailure: false),
    );
    verifyNever(() => places.reverseGeocodePlace(6.6900, -1.6200));
  });
}
