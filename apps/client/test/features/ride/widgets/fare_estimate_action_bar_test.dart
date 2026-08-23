import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:myshop_client/src/core/providers/recent_locations_provider.dart';
import 'package:myshop_client/src/features/ride/providers/fare_estimate_provider.dart';
import 'package:myshop_client/src/features/ride/providers/ride_provider.dart';
import 'package:myshop_client/src/features/ride/providers/ride_search_provider.dart';
import 'package:myshop_client/src/features/ride/screens/destination_search_screen.dart';
import 'package:myshop_client/src/features/ride/screens/fare_estimate_screen.dart';
import 'package:myshop_client/src/features/ride/widgets/fare_estimate_action_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_models/shared_models.dart' show RideToll;

const _pickup = RideLocation(
  name: 'Adum',
  address: 'Adum, Kumasi',
  lat: 6.6885,
  lng: -1.6244,
);
const _destination = RideLocation(
  name: 'Bantama',
  address: 'Bantama, Kumasi',
  lat: 6.7094,
  lng: -1.5917,
);
const _availableOption = VehicleOption(
  id: 'regular',
  name: 'Regular',
  description: 'Everyday ride',
  capacityPersons: 4,
  farePesewas: 2500,
  estimatedTime: '4 min',
  isMotorcycle: false,
);
const _unavailableOption = VehicleOption(
  id: 'regular',
  name: 'Regular',
  description: 'Everyday ride',
  capacityPersons: 4,
  farePesewas: 2500,
  estimatedTime: '4 min',
  isMotorcycle: false,
  driversAvailable: false,
);

RideSearchNotifier _searchNotifier(RideSearchState search) {
  final notifier = RideSearchNotifier();
  final pickup = search.pickup;
  final destination = search.destination;
  if (pickup != null) {
    notifier.setLocation(RideSearchField.pickup, pickup);
  }
  if (destination != null) {
    notifier.setLocation(RideSearchField.destination, destination);
  }
  return notifier;
}

class _FareWidgetCase {
  const _FareWidgetCase({
    required this.name,
    required this.primaryLabel,
    this.options,
    this.error,
    this.loading = false,
    this.enabled = true,
  });

  final String name;
  final String primaryLabel;
  final List<VehicleOption>? options;
  final Object? error;
  final bool loading;
  final bool enabled;

  Future<List<VehicleOption>> load() {
    if (loading) return Completer<List<VehicleOption>>().future;
    final failure = error;
    if (failure != null) {
      return Future<List<VehicleOption>>.error(failure, StackTrace.empty);
    }
    return Future<List<VehicleOption>>.value(
      options ?? const <VehicleOption>[],
    );
  }
}

class _SeededRecentLocationsNotifier extends RecentLocationsNotifier {
  _SeededRecentLocationsNotifier(List<RecentLocation> entries) : super() {
    state = entries;
  }
}

void main() {
  testWidgets('selected estimate omits all toll copy when absent or zero',
      (tester) async {
    for (final toll in <RideToll?>[
      null,
      const RideToll(label: 'Airport toll', amountPesewas: 0),
    ]) {
      final option = VehicleOption(
        id: 'regular',
        name: 'Regular',
        description: 'Everyday ride',
        capacityPersons: 4,
        farePesewas: 4000,
        transportFarePesewas: 4000,
        toll: toll,
        estimatedTime: '4 min',
        isMotorcycle: false,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            rideSearchProvider.overrideWith(
              (_) => _searchNotifier(
                const RideSearchState(
                  pickup: _pickup,
                  destination: _destination,
                ),
              ),
            ),
            pretripMultistopEnabledProvider.overrideWith((_) async => false),
            fareEstimateProvider.overrideWith((_) async => [option]),
          ],
          child: const MaterialApp(home: FareEstimateScreen()),
        ),
      );
      await tester.pumpAndSettle();

      final visibleCopy = tester
          .widgetList<Text>(find.byType(Text))
          .map((widget) => widget.data ?? '')
          .join(' ')
          .toLowerCase();
      expect(visibleCopy, isNot(contains('toll')));
      expect(find.byKey(const Key('selected-fare-breakdown')), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('selected estimate reconciles transport, toll, and total once',
      (tester) async {
    const option = VehicleOption(
      id: 'regular',
      name: 'Regular',
      description: 'Everyday ride',
      capacityPersons: 4,
      farePesewas: 4500,
      transportFarePesewas: 4000,
      toll: RideToll(label: 'Airport toll', amountPesewas: 500),
      estimatedTime: '4 min',
      isMotorcycle: false,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          rideSearchProvider.overrideWith(
            (_) => _searchNotifier(
              const RideSearchState(
                pickup: _pickup,
                destination: _destination,
              ),
            ),
          ),
          pretripMultistopEnabledProvider.overrideWith((_) async => false),
          fareEstimateProvider.overrideWith((_) async => [option]),
        ],
        child: const MaterialApp(home: FareEstimateScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('selected-fare-breakdown')), findsOneWidget);
    expect(find.byKey(const Key('selected-toll-line')), findsOneWidget);
    expect(find.text('Ride fare'), findsOneWidget);
    expect(find.text('GH₵ 40.00'), findsOneWidget);
    expect(find.text('Airport toll'), findsOneWidget);
    expect(find.text('GH₵ 5.00'), findsOneWidget);
    expect(find.text('Estimated total'), findsOneWidget);
    expect(find.text('GH₵ 45.00'), findsWidgets);
    expect(option.effectiveTransportFarePesewas + option.toll!.amountPesewas,
        option.farePesewas);
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('resolveFareEstimateAction', () {
    test('provides an action for every pre-booking and estimate state', () {
      FareEstimateActionState resolve({
        RideSearchState search = const RideSearchState(
          pickup: _pickup,
          destination: _destination,
        ),
        AsyncValue<List<VehicleOption>> estimate =
            const AsyncData([_availableOption]),
      }) =>
          resolveFareEstimateAction(
            search: search,
            estimate: estimate,
            selectedVehicleId: 'regular',
          );

      expect(
        resolve(search: const RideSearchState()).action,
        FareEstimateAction.choosePickup,
      );
      expect(
        resolve(search: const RideSearchState(pickup: _pickup)).action,
        FareEstimateAction.chooseDestination,
      );
      expect(
        resolve(
          search: const RideSearchState(
            pickup: RideLocation(name: 'Area', address: 'Kumasi'),
            destination: _destination,
          ),
        ).action,
        FareEstimateAction.chooseExactPickup,
      );
      expect(
        resolve(
          search: const RideSearchState(
            pickup: _pickup,
            destination: RideLocation(name: 'Area', address: 'Kumasi'),
          ),
        ).action,
        FareEstimateAction.chooseExactDestination,
      );
      expect(
        resolve(estimate: const AsyncLoading()).action,
        FareEstimateAction.calculating,
      );
      expect(
        resolve(
          estimate: const AsyncError(
            NetworkException(message: 'Socket timed out'),
            StackTrace.empty,
          ),
        ).action,
        FareEstimateAction.retryFare,
      );
      expect(
        resolve(
          estimate: const AsyncError(
            ApiException(
              message: 'Outside internal polygon',
              statusCode: 400,
              errorCode: 'OUTSIDE_PILOT_REGION',
            ),
            StackTrace.empty,
          ),
        ).action,
        FareEstimateAction.changeLocations,
      );
      final serverFailure = resolve(
        estimate: const AsyncError(
          ServerException(
            message: 'Database trace that must not reach the rider',
            statusCode: 503,
          ),
          StackTrace.empty,
        ),
      );
      expect(serverFailure.action, FareEstimateAction.serviceUnavailable);
      expect(serverFailure.message, isNot(contains('Database trace')));
      expect(
        resolve(estimate: const AsyncData([])).action,
        FareEstimateAction.serviceUnavailable,
      );
      expect(
        resolve(estimate: const AsyncData([_unavailableOption])).action,
        FareEstimateAction.noDrivers,
      );
      final ready = resolve();
      expect(ready.action, FareEstimateAction.confirm);
      expect(ready.option?.id, 'regular');
    });

    test('falls back to the first available category, never an unavailable one',
        () {
      const comfort = VehicleOption(
        id: 'comfort',
        name: 'Comfort',
        description: 'Comfort ride',
        capacityPersons: 4,
        farePesewas: 4000,
        estimatedTime: '6 min',
        isMotorcycle: false,
      );
      final state = resolveFareEstimateAction(
        search: const RideSearchState(
          pickup: _pickup,
          destination: _destination,
        ),
        estimate: const AsyncData([_unavailableOption, comfort]),
        selectedVehicleId: 'regular',
      );

      expect(state.action, FareEstimateAction.confirm);
      expect(state.option?.id, 'comfort');
    });
  });

  testWidgets(
      'action bar remains usable at iPhone and iPad sizes with large text',
      (tester) async {
    final sizes = <Size>[
      const Size(440, 956), // iPhone 17 Pro Max logical viewport
      const Size(956, 440), // iPhone 17 Pro Max landscape
      const Size(834, 1194), // iPad Air 11-inch portrait
      const Size(1194, 834), // iPad Air 11-inch landscape
    ];
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final size in sizes) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;

      var primaryTaps = 0;
      var cancelTaps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: size,
              textScaler: const TextScaler.linear(2),
            ),
            child: Scaffold(
              bottomNavigationBar: FareEstimateActionBar(
                state: const FareEstimateActionState(
                  action: FareEstimateAction.confirm,
                  title: 'Ready to request',
                  message:
                      'Review your trip and fare before requesting a driver.',
                  primaryLabel: 'Confirm Ride',
                  option: _availableOption,
                ),
                onPrimary: () => primaryTaps++,
                onCancel: () => cancelTaps++,
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Confirm Ride'), findsOneWidget);
      expect(find.text('GH₵ 25.00'), findsOneWidget);
      await tester.tap(find.byKey(
        const Key('fare-estimate-primary-action'),
      ));
      await tester.tap(find.byKey(
        const Key('fare-estimate-cancel-action'),
      ));
      expect(primaryTaps, 1);
      expect(cancelTaps, 1);
    }
  });

  testWidgets(
      'production fare screen keeps every release state usable on iPhone and iPad',
      (tester) async {
    final sizes = <Size>[
      const Size(440, 956), // iPhone portrait
      const Size(956, 440), // iPhone landscape
      const Size(834, 1194), // iPad portrait
      const Size(1194, 834), // iPad landscape
    ];
    final cases = <_FareWidgetCase>[
      const _FareWidgetCase(
        name: 'loading',
        primaryLabel: 'Calculating Fare…',
        loading: true,
        enabled: false,
      ),
      const _FareWidgetCase(
        name: 'offline',
        primaryLabel: 'Retry Fare Estimate',
        error: NetworkException(message: 'No internet connection'),
      ),
      const _FareWidgetCase(
        name: 'timeout',
        primaryLabel: 'Retry Fare Estimate',
        error: NetworkException(message: 'The request timed out'),
      ),
      const _FareWidgetCase(
        name: '5xx',
        primaryLabel: 'Retry Fare Estimate',
        error: ServerException(
          message: 'Internal implementation detail',
          statusCode: 503,
        ),
      ),
      const _FareWidgetCase(
        name: 'outside service area',
        primaryLabel: 'Change Locations',
        error: ApiException(
          message: 'Outside internal polygon',
          statusCode: 400,
          errorCode: 'OUTSIDE_PILOT_REGION',
        ),
      ),
      const _FareWidgetCase(
        name: 'empty categories',
        primaryLabel: 'Retry Fare Estimate',
        options: [],
      ),
      const _FareWidgetCase(
        name: 'no drivers',
        primaryLabel: 'Try Again',
        options: [_unavailableOption],
      ),
      const _FareWidgetCase(
        name: 'confirm',
        primaryLabel: 'Confirm Ride',
        options: [_availableOption],
      ),
    ];
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final size in sizes) {
      for (final widgetCase in cases) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              rideSearchProvider.overrideWith(
                (_) => _searchNotifier(
                  const RideSearchState(
                    pickup: _pickup,
                    destination: _destination,
                  ),
                ),
              ),
              pretripMultistopEnabledProvider.overrideWith((_) async => false),
              fareEstimateProvider.overrideWith((_) => widgetCase.load()),
            ],
            child: MaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(2)),
                child: child!,
              ),
              home: const FareEstimateScreen(),
            ),
          ),
        );
        if (widgetCase.loading) {
          await tester.pump();
          await tester.pump();
        } else {
          await tester.pumpAndSettle();
        }

        expect(
          find.byKey(const Key('fare-estimate-bottom-action')),
          findsOneWidget,
          reason: '${widgetCase.name} at $size',
        );
        expect(
          find.text(widgetCase.primaryLabel),
          findsOneWidget,
          reason: '${widgetCase.name} at $size',
        );
        expect(find.text('Cancel Request'), findsOneWidget);
        final button = tester.widget<ElevatedButton>(
          find.byKey(const Key('fare-estimate-primary-action')),
        );
        expect(
          button.onPressed != null,
          widgetCase.enabled,
          reason: '${widgetCase.name} at $size',
        );
        if (widgetCase.enabled) {
          expect(
            find.byKey(const Key('fare-estimate-primary-action')).hitTestable(),
            findsOneWidget,
            reason: '${widgetCase.name} at $size',
          );
        }
        if (widgetCase.name == 'confirm') {
          expect(find.text('GH₵ 25.00'), findsWidgets);
        }
        expect(
          tester.takeException(),
          isNull,
          reason: '${widgetCase.name} at $size',
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    }
  });

  testWidgets(
      'retry action invalidates and requests the production fare provider again',
      (tester) async {
    var attempts = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          rideSearchProvider.overrideWith(
            (_) => _searchNotifier(
              const RideSearchState(
                pickup: _pickup,
                destination: _destination,
              ),
            ),
          ),
          pretripMultistopEnabledProvider.overrideWith((_) async => false),
          fareEstimateProvider.overrideWith((_) {
            attempts++;
            return Future<List<VehicleOption>>.error(
              const NetworkException(message: 'Offline'),
              StackTrace.empty,
            );
          }),
        ],
        child: const MaterialApp(home: FareEstimateScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final attemptsBeforeRetry = attempts;
    expect(attemptsBeforeRetry, greaterThanOrEqualTo(1));
    expect(find.text('Retry Fare Estimate'), findsOneWidget);
    await tester.tap(
      find.byKey(const Key('fare-estimate-primary-action')),
    );
    await tester.pumpAndSettle();

    expect(attempts, greaterThan(attemptsBeforeRetry));
    expect(find.text('Retry Fare Estimate'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'outside-area chooser routes pickup and destination independently',
      (tester) async {
    for (final field in RideSearchField.values) {
      final router = GoRouter(
        initialLocation: '/fare',
        routes: [
          GoRoute(
            path: '/fare',
            builder: (_, __) => const FareEstimateScreen(),
          ),
          GoRoute(
            path: '/ride/search/:field',
            builder: (_, state) => Scaffold(
              body: Text('search:${state.pathParameters['field']}'),
            ),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            rideSearchProvider.overrideWith(
              (_) => _searchNotifier(
                const RideSearchState(
                  pickup: _pickup,
                  destination: _destination,
                ),
              ),
            ),
            pretripMultistopEnabledProvider.overrideWith((_) async => false),
            fareEstimateProvider.overrideWith(
              (_) => Future<List<VehicleOption>>.error(
                const ApiException(
                  message: 'Outside internal polygon',
                  statusCode: 400,
                  errorCode: 'OUTSIDE_PILOT_REGION',
                ),
                StackTrace.empty,
              ),
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('fare-estimate-primary-action')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('change-pickup-location')), findsOneWidget);
      expect(
        find.byKey(const Key('change-destination-location')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(Key('change-${field.name}-location')),
      );
      await tester.pumpAndSettle();

      expect(find.text('search:${field.name}'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      router.dispose();
    }
  });

  testWidgets('exact-point actions open the matching production pin route',
      (tester) async {
    final cases = <(RideSearchField, RideSearchState, String)>[
      (
        RideSearchField.pickup,
        const RideSearchState(
          pickup: RideLocation(name: 'Adum area', address: 'Kumasi'),
          destination: _destination,
        ),
        'Choose Exact Pickup',
      ),
      (
        RideSearchField.destination,
        const RideSearchState(
          pickup: _pickup,
          destination: RideLocation(name: 'Bantama area', address: 'Kumasi'),
        ),
        'Choose Exact Destination',
      ),
    ];

    for (final (field, search, label) in cases) {
      final router = GoRouter(
        initialLocation: '/fare',
        routes: [
          GoRoute(
            path: '/fare',
            builder: (_, __) => const FareEstimateScreen(),
          ),
          GoRoute(
            path: '/ride/pin-picker/:field',
            builder: (_, state) => Scaffold(
              body: Text('pin:${state.pathParameters['field']}'),
            ),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            rideSearchProvider.overrideWith(
              (_) => _searchNotifier(search),
            ),
            pretripMultistopEnabledProvider.overrideWith((_) async => false),
            fareEstimateProvider.overrideWith(
              (_) async => const <VehicleOption>[],
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(label), findsOneWidget);
      await tester.tap(
        find.byKey(const Key('fare-estimate-primary-action')),
      );
      await tester.pumpAndSettle();

      expect(find.text('pin:${field.name}'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      router.dispose();
    }
  });

  testWidgets(
      'destination search only offers coordinate-backed recents and applies one',
      (tester) async {
    final container = ProviderContainer(
      overrides: [
        recentLocationsProvider.overrideWith(
          (_) => _SeededRecentLocationsNotifier(
            const [
              RecentLocation(
                name: 'Kejetia',
                address: 'Kejetia Market, Kumasi',
                lat: 6.6970,
                lng: -1.6287,
                lastUsedAt: 1,
              ),
            ],
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    final router = GoRouter(
      initialLocation: '/search',
      routes: [
        GoRoute(
          path: '/search',
          builder: (_, __) => const DestinationSearchScreen(),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('RECENT'), findsOneWidget);
    expect(find.text('Kejetia'), findsOneWidget);
    expect(find.text('SAVED PLACES'), findsNothing);
    await tester.tap(find.text('Kejetia'));
    await tester.pump();

    final destination = container.read(rideSearchProvider).destination;
    expect(destination?.name, 'Kejetia');
    expect(destination?.lat, 6.6970);
    expect(destination?.lng, -1.6287);
    expect(destination?.isPrecise, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'pickup and destination search remain actionable with keyboard and large text',
      (tester) async {
    final viewports = <(Size, double)>[
      (const Size(956, 440), 180), // iPhone landscape
      (const Size(440, 956), 360), // iPhone portrait
      (const Size(834, 1194), 360), // iPad portrait
      (const Size(1194, 834), 300), // iPad landscape
    ];
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final (size, keyboardHeight) in viewports) {
      for (final field in RideSearchField.values) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              recentLocationsProvider.overrideWith(
                (_) => _SeededRecentLocationsNotifier(const []),
              ),
            ],
            child: MaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: const TextScaler.linear(2),
                  viewInsets: EdgeInsets.only(bottom: keyboardHeight),
                ),
                child: child!,
              ),
              home: DestinationSearchScreen(field: field),
            ),
          ),
        );
        await tester.pump();
        await tester.pump();

        final textFieldFinder = find.byType(TextField);
        final mapActionFinder = find.text('Set location on map');
        final expectedTitle =
            field == RideSearchField.pickup ? 'Pickup location' : 'Where to?';
        final expectedHint = field == RideSearchField.pickup
            ? 'Search pickup'
            : 'Search destination';

        expect(find.text(expectedTitle), findsOneWidget);
        expect(textFieldFinder, findsOneWidget);
        expect(textFieldFinder.hitTestable(), findsOneWidget);
        expect(mapActionFinder, findsOneWidget);
        expect(mapActionFinder.hitTestable(), findsOneWidget);

        final textField = tester.widget<TextField>(textFieldFinder);
        expect(textField.decoration?.hintText, expectedHint);

        final visibleBottom = size.height - keyboardHeight;
        for (final finder in [textFieldFinder, mapActionFinder]) {
          final rect = tester.getRect(finder);
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.top, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(size.width));
          expect(
            rect.bottom,
            lessThanOrEqualTo(visibleBottom),
            reason: '${field.name} control clipped at $size',
          );
        }

        await tester.tap(textFieldFinder);
        await tester.enterText(textFieldFinder, 'Adum');
        await tester.pump();
        final editable = tester.widget<EditableText>(find.byType(EditableText));
        expect(editable.controller.text, 'Adum');
        expect(
          tester.takeException(),
          isNull,
          reason: '${field.name} keyboard layout at $size',
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    }
  });
}
