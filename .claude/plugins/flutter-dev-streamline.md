# Flutter Dev Streamline Plugin
## MyShop Mobile — Implementation Patterns & Templates

> **Read this plugin before implementing any feature.** Follow these patterns for consistency across both apps and all packages.

---

## 1. Feature Implementation Checklist

When implementing a new feature (e.g., ride booking, artisan bidding):

```
□ 1. Check PRD for the feature requirements and user flow
□ 2. Check EDD for the API endpoints this feature calls
□ 3. Read flutter-design-system.md plugin for UI patterns
□ 4. Create Freezed models in myshop_core (if new data types needed)
□ 5. Add API endpoint methods in myshop_api
□ 6. Create repository interface in feature's domain/ or myshop_domain
□ 7. Create repository implementation in feature's data/
□ 8. Create Riverpod providers in feature's presentation/providers/
□ 9. Build screen + widgets in feature's presentation/screens/ and widgets/
□ 10. Add route to GoRouter config
□ 11. Add localisation strings to ARB files
□ 12. Write tests (provider test + widget test minimum)
□ 13. Run: melos run generate && melos run analyze && melos run test
```

---

## 2. Freezed Model Template

Every data model in `myshop_core` uses Freezed:

```dart
// packages/myshop_core/lib/src/models/ride.dart

import 'package:freezed_annotation/freezed_annotation.dart';

part 'ride.freezed.dart';
part 'ride.g.dart';

@freezed
class Ride with _$Ride {
  const factory Ride({
    required String id,
    required String clientId,
    required String driverId,
    required RideStatus status,
    required LatLng pickupLocation,
    required LatLng dropoffLocation,
    required int fareAmountPesewas,         // Always store money as int pesewas
    required DateTime createdAt,
    DateTime? completedAt,
    String? cancellationReason,
    @Default([]) List<LatLng> stops,
  }) = _Ride;

  factory Ride.fromJson(Map<String, dynamic> json) => _$RideFromJson(json);
}

// Helper extension for display
extension RideX on Ride {
  /// Display fare in GHS: ₵47, ₵1,250
  String get fareDisplay {
    final ghs = (fareAmountPesewas / 100).ceil();
    return '₵${_formatNumber(ghs)}';
  }
}
```

**Rules:**
- All fields are `required` unless truly optional (nullable with `?`)
- Money is always `int` in pesewas (100 pesewas = ₵1)
- Use enums from `myshop_core` for status fields
- Add `.fromJson` factory for JSON deserialization
- Add display extensions for formatted output (currency, dates, etc.)

---

## 3. Riverpod Provider Patterns

### 3.1 Simple Data Provider (fetch and cache)

```dart
// features/rides/presentation/providers/ride_history_provider.dart

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:myshop_core/myshop_core.dart';

part 'ride_history_provider.g.dart';

@riverpod
class RideHistory extends _$RideHistory {
  @override
  Future<List<Ride>> build() async {
    final repository = ref.watch(rideRepositoryProvider);
    return repository.getRideHistory();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(rideRepositoryProvider).getRideHistory(),
    );
  }
}
```

### 3.2 Action Provider (mutations)

```dart
// features/rides/presentation/providers/ride_booking_provider.dart

@riverpod
class RideBooking extends _$RideBooking {
  @override
  AsyncValue<Ride?> build() => const AsyncData(null);

  Future<void> requestRide({
    required LatLng pickup,
    required LatLng dropoff,
    List<LatLng> stops = const [],
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final repository = ref.read(rideRepositoryProvider);
      return repository.requestRide(
        pickup: pickup,
        dropoff: dropoff,
        stops: stops,
      );
    });
  }

  Future<void> cancelRide(String rideId, String reason) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref.read(rideRepositoryProvider).cancelRide(rideId, reason);
      return null; // Reset to no active ride
    });
  }
}
```

### 3.3 Stream Provider (real-time data)

```dart
// features/rides/presentation/providers/ride_tracking_provider.dart

@riverpod
Stream<RideUpdate> rideTracking(Ref ref, String rideId) {
  final wsClient = ref.watch(webSocketClientProvider);
  return wsClient.subscribeToRide(rideId);
}
```

### 3.4 Repository Provider

```dart
// features/rides/presentation/providers/ride_repository_provider.dart

@riverpod
RideRepository rideRepository(Ref ref) {
  final apiClient = ref.watch(apiClientProvider);
  return RideRepositoryImpl(apiClient: apiClient);
}
```

### 3.5 Consuming Providers in UI

```dart
// ALWAYS use AsyncValue pattern matching — never .value! or unchecked access

class RideHistoryScreen extends ConsumerWidget {
  const RideHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rideHistory = ref.watch(rideHistoryProvider);

    return rideHistory.when(
      loading: () => const RideHistorySkeletonLoader(),
      error: (error, stack) => ErrorStateWidget(
        message: 'Could not load ride history',
        onRetry: () => ref.invalidate(rideHistoryProvider),
      ),
      data: (rides) => rides.isEmpty
          ? const EmptyStateWidget(
              title: 'No rides yet',
              description: 'Book your first ride to get started',
              ctaLabel: 'Book a Ride',
            )
          : ListView.builder(
              itemCount: rides.length,
              itemBuilder: (context, index) => RideHistoryCard(ride: rides[index]),
            ),
    );
  }
}
```

---

## 4. API Client Patterns (Dio)

### 4.1 Base API Client

```dart
// packages/myshop_api/lib/src/api_client.dart

class MyShopApiClient {
  final Dio _dio;

  MyShopApiClient({required String baseUrl, required TokenStorage tokenStorage})
      : _dio = Dio(BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 15),
          headers: {'Content-Type': 'application/json'},
        )) {
    _dio.interceptors.addAll([
      AuthInterceptor(tokenStorage: tokenStorage, dio: _dio),
      LogInterceptor(requestBody: true, responseBody: true),
    ]);
  }
}
```

### 4.2 API Method Template

```dart
// packages/myshop_api/lib/src/services/ride_api_service.dart

class RideApiService {
  final Dio _dio;

  RideApiService(this._dio);

  Future<Ride> requestRide(RequestRideDto dto) async {
    try {
      final response = await _dio.post(
        Endpoints.rides,
        data: dto.toJson(),
      );
      return Ride.fromJson(response.data['data']);
    } on DioException catch (e) {
      throw _mapDioError(e);
    }
  }

  Future<List<Ride>> getRideHistory({int page = 1, int limit = 20}) async {
    try {
      final response = await _dio.get(
        Endpoints.rideHistory,
        queryParameters: {'page': page, 'limit': limit},
      );
      final items = response.data['data'] as List;
      return items.map((json) => Ride.fromJson(json)).toList();
    } on DioException catch (e) {
      throw _mapDioError(e);
    }
  }
}
```

### 4.3 Error Mapping

```dart
// packages/myshop_api/lib/src/errors/api_error.dart

sealed class ApiError implements Exception {
  final String message;
  final int? statusCode;
  const ApiError(this.message, {this.statusCode});
}

class NetworkError extends ApiError {
  const NetworkError() : super('No internet connection');
}

class ServerError extends ApiError {
  const ServerError(super.message, {super.statusCode});
}

class UnauthorizedError extends ApiError {
  const UnauthorizedError() : super('Session expired. Please login again.');
}

class ValidationError extends ApiError {
  final Map<String, List<String>> fieldErrors;
  const ValidationError(super.message, {required this.fieldErrors});
}

class NotFoundError extends ApiError {
  const NotFoundError(super.message);
}

// Mapper
ApiError mapDioError(DioException e) {
  return switch (e.type) {
    DioExceptionType.connectionTimeout ||
    DioExceptionType.receiveTimeout => const NetworkError(),
    DioExceptionType.connectionError => const NetworkError(),
    DioExceptionType.badResponse => _mapStatusCode(e.response),
    _ => ServerError(e.message ?? 'Unknown error'),
  };
}

ApiError _mapStatusCode(Response? response) {
  final statusCode = response?.statusCode;
  final body = response?.data;
  final message = body?['message'] ?? 'Something went wrong';

  return switch (statusCode) {
    401 => const UnauthorizedError(),
    403 => ServerError('Access denied', statusCode: 403),
    404 => NotFoundError(message),
    422 => ValidationError(message, fieldErrors: _parseFieldErrors(body)),
    _ => ServerError(message, statusCode: statusCode),
  };
}
```

---

## 5. GoRouter Navigation Patterns

### 5.1 Router Configuration

```dart
// apps/client_app/lib/app/router.dart

final goRouterProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);

  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final isLoggedIn = authState.valueOrNull != null;
      final isAuthRoute = state.matchedLocation.startsWith('/auth');

      if (!isLoggedIn && !isAuthRoute) return '/auth/login';
      if (isLoggedIn && isAuthRoute) return '/';
      return null;
    },
    routes: [
      // Auth routes (no bottom nav)
      GoRoute(
        path: '/auth/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/auth/otp',
        builder: (context, state) => OtpScreen(
          phoneNumber: state.extra as String,
        ),
      ),

      // Main shell with bottom navigation
      ShellRoute(
        builder: (context, state, child) => MainShell(child: child),
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => const HomeScreen(),
          ),
          GoRoute(
            path: '/services',
            builder: (context, state) => const ServicesScreen(),
            routes: [
              GoRoute(
                path: 'request/:categoryId',
                builder: (context, state) => ServiceRequestScreen(
                  categoryId: state.pathParameters['categoryId']!,
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/activity',
            builder: (context, state) => const ActivityScreen(),
          ),
          GoRoute(
            path: '/profile',
            builder: (context, state) => const ProfileScreen(),
          ),
        ],
      ),

      // Full-screen overlays (no bottom nav)
      GoRoute(
        path: '/ride/:rideId',
        builder: (context, state) => RideTrackingScreen(
          rideId: state.pathParameters['rideId']!,
        ),
      ),
    ],
  );
});
```

### 5.2 Navigation Calls

```dart
// Push to new screen
context.push('/services/request/$categoryId');

// Replace current screen
context.go('/');

// Go back
context.pop();

// Pass complex data via extra
context.push('/ride/confirm', extra: rideRequest);
```

---

## 6. Repository Pattern

### 6.1 Interface (Domain Layer)

```dart
// features/rides/domain/ride_repository.dart

abstract class RideRepository {
  Future<Ride> requestRide({
    required LatLng pickup,
    required LatLng dropoff,
    List<LatLng> stops,
  });
  Future<List<Ride>> getRideHistory({int page, int limit});
  Future<void> cancelRide(String rideId, String reason);
  Future<void> rateRide(String rideId, int rating, String? comment);
  Stream<RideUpdate> trackRide(String rideId);
}
```

### 6.2 Implementation (Data Layer)

```dart
// features/rides/data/ride_repository_impl.dart

class RideRepositoryImpl implements RideRepository {
  final RideApiService _apiService;
  final WebSocketClient _wsClient;

  RideRepositoryImpl({
    required RideApiService apiService,
    required WebSocketClient wsClient,
  })  : _apiService = apiService,
        _wsClient = wsClient;

  @override
  Future<Ride> requestRide({
    required LatLng pickup,
    required LatLng dropoff,
    List<LatLng> stops = const [],
  }) async {
    final dto = RequestRideDto(
      pickupLat: pickup.latitude,
      pickupLng: pickup.longitude,
      dropoffLat: dropoff.latitude,
      dropoffLng: dropoff.longitude,
      stops: stops.map((s) => StopDto(lat: s.latitude, lng: s.longitude)).toList(),
    );
    return _apiService.requestRide(dto);
  }

  @override
  Stream<RideUpdate> trackRide(String rideId) {
    return _wsClient.subscribeToRide(rideId);
  }
}
```

---

## 7. Localisation Pattern

### 7.1 ARB File Structure

```json
// lib/l10n/app_en.arb
{
  "@@locale": "en",
  "homeTitle": "Where to?",
  "servicesTitle": "Services",
  "bookRide": "Book Ride",
  "fareEstimate": "Estimated fare: {amount}",
  "@fareEstimate": {
    "placeholders": {
      "amount": { "type": "String", "example": "₵47" }
    }
  },
  "noDriversAvailable": "No drivers available in your area. Please try again.",
  "cancelRide": "Cancel Ride",
  "cancelConfirmation": "Are you sure you want to cancel this ride?",
  "emergencyConfirm": "Confirm Emergency"
}
```

```json
// lib/l10n/app_tw.arb (Twi)
{
  "@@locale": "tw",
  "homeTitle": "Wo kɔ he?",
  "servicesTitle": "Nkwadoɔ",
  "bookRide": "Hyɛ Ride",
  "fareEstimate": "Aboɔden a yɛhyɛ da: {amount}",
  "noDriversAvailable": "Driver biara nni wo nkyɛn ha. Yɛsrɛ bɔ mmɔden bio.",
  "cancelRide": "Twa Ride no mu",
  "cancelConfirmation": "Wo pɛ sɛ wo twa ride yi mu anaa?",
  "emergencyConfirm": "Siesie Emergency"
}
```

### 7.2 Usage in Widgets

```dart
// Import
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

// Access (prefer extension method for brevity)
Text(AppLocalizations.of(context)!.homeTitle)

// With parameters
Text(AppLocalizations.of(context)!.fareEstimate(ride.fareDisplay))
```

**Rule:** Every user-facing string must be in both ARB files. Never hardcode strings.

---

## 8. Error Handling in UI

### Pattern: Show User-Friendly Errors

```dart
// In a provider or screen, map ApiError to user-friendly messages

String userMessage(ApiError error) {
  return switch (error) {
    NetworkError() => 'No internet connection. Check your network and try again.',
    UnauthorizedError() => 'Your session has expired. Please login again.',
    ValidationError(:final fieldErrors) => fieldErrors.values.first.first,
    NotFoundError(:final message) => message,
    ServerError() => 'Something went wrong. Please try again.',
  };
}
```

### Pattern: Snackbar for Action Errors

```dart
// After a failed action (e.g., cancel ride, submit bid)
void _handleError(BuildContext context, Object error) {
  final message = error is ApiError
      ? userMessage(error)
      : 'Something went wrong. Please try again.';

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: MyShopColors.error,
      action: SnackBarAction(label: 'Retry', onPressed: _retry),
    ),
  );
}
```

---

## 9. Testing Patterns

### 9.1 Provider Test

```dart
// test/features/rides/presentation/providers/ride_booking_provider_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:riverpod/riverpod.dart';

class MockRideRepository extends Mock implements RideRepository {}

void main() {
  late MockRideRepository mockRepo;
  late ProviderContainer container;

  setUp(() {
    mockRepo = MockRideRepository();
    container = ProviderContainer(
      overrides: [
        rideRepositoryProvider.overrideWithValue(mockRepo),
      ],
    );
  });

  tearDown(() => container.dispose());

  test('requestRide returns ride on success', () async {
    final expectedRide = Ride(id: '1', ...);
    when(() => mockRepo.requestRide(
      pickup: any(named: 'pickup'),
      dropoff: any(named: 'dropoff'),
    )).thenAnswer((_) async => expectedRide);

    final notifier = container.read(rideBookingProvider.notifier);
    await notifier.requestRide(pickup: testPickup, dropoff: testDropoff);

    final state = container.read(rideBookingProvider);
    expect(state.value, expectedRide);
  });

  test('requestRide sets error state on failure', () async {
    when(() => mockRepo.requestRide(
      pickup: any(named: 'pickup'),
      dropoff: any(named: 'dropoff'),
    )).thenThrow(const NetworkError());

    final notifier = container.read(rideBookingProvider.notifier);
    await notifier.requestRide(pickup: testPickup, dropoff: testDropoff);

    final state = container.read(rideBookingProvider);
    expect(state.hasError, isTrue);
  });
}
```

### 9.2 Widget Test

```dart
// test/features/rides/presentation/screens/ride_booking_screen_test.dart

import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows fare estimate after entering destination', (tester) async {
    await tester.pumpApp(
      overrides: [
        fareEstimateProvider.overrideWith((_) => AsyncData(FareEstimate(amountPesewas: 4700))),
      ],
      child: const RideBookingScreen(),
    );

    expect(find.text('₵47'), findsOneWidget);
  });

  testWidgets('shows skeleton loader while loading', (tester) async {
    await tester.pumpApp(
      overrides: [
        rideHistoryProvider.overrideWith((_) => const AsyncLoading()),
      ],
      child: const RideHistoryScreen(),
    );

    expect(find.byType(RideHistorySkeletonLoader), findsOneWidget);
  });
}
```

### 9.3 Test Helper: pumpApp

```dart
// test/helpers/pump_app.dart

extension PumpApp on WidgetTester {
  Future<void> pumpApp({
    required Widget child,
    List<Override> overrides = const [],
  }) {
    return pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          theme: MyShopTheme.light,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: child,
        ),
      ),
    );
  }
}
```

---

## 10. Performance Rules

- **Images:** Always use `cached_network_image` — never raw `Image.network`
- **Lists:** Use `ListView.builder` for any list > 10 items — never `Column(children: items.map(...))`
- **Providers:** Use `autoDispose` for screen-specific data, keep alive for app-wide data (auth, user profile)
- **Maps:** Limit marker count to 50 visible at once — cluster beyond that
- **WebSockets:** Single connection per app, multiplex channels — never open multiple WS connections
- **Build method:** Keep build methods lean — extract complex logic to providers or helper methods
- **const:** Use `const` constructors for all static widgets — Flutter skips rebuild for const widgets

---

## 11. Security Rules

- **Never log:** Tokens, passwords, phone numbers, payment details, OTPs
- **Never store in SharedPreferences:** Tokens, sensitive user data — use Flutter Secure Storage
- **Always validate:** Client-side validation is for UX — never trust it for security (backend validates too)
- **Certificate pinning:** Configure in API client for production builds
- **Obfuscate:** Enable Dart obfuscation for release builds (`--obfuscate --split-debug-info`)
- **Deep links:** Validate all deep link parameters before navigation — never trust URL params
