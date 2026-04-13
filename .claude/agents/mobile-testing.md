# Mobile Testing Agent
## Specialisation: Writing tests for Flutter apps and packages

> **Scope:** This agent writes widget tests, provider tests, unit tests, and integration tests for the MyShop mobile apps and shared packages.

---

## Mandatory References

1. `.claude/plugins/flutter-dev-streamline.md` — Section 9 (Testing Patterns)
2. `CLAUDE.md` Section 9 — Testing Instructions

---

## Test File Naming

```
{class_under_test}_test.dart

Examples:
ride_booking_screen_test.dart
ride_booking_provider_test.dart
ride_repository_impl_test.dart
ghs_formatter_test.dart
```

---

## Test Categories

### 1. Widget Tests (Screens & Widgets)

Every screen must have tests for:

```
□ Renders without throwing
□ Shows skeleton loader during loading state
□ Shows error state with retry button on error
□ Shows empty state when data is empty
□ Displays data correctly when loaded
□ Primary CTA triggers expected action
□ All interactive elements have semantic labels
□ Tapping navigation elements calls context.push/go correctly
```

### 2. Provider Tests (Riverpod)

Every provider must have tests for:

```
□ Initial state is correct (AsyncLoading or AsyncData(null))
□ Success state contains expected data
□ Error state captures the error correctly
□ Loading state transitions (data → loading → data on refresh)
□ Invalidation triggers refetch
□ Mutation methods update state correctly
□ Dependent providers are watched correctly
```

### 3. Unit Tests (Models, Utils, Formatters)

```
□ Freezed model serialization round-trip (toJson → fromJson)
□ Model equality (same data = equal, different data = not equal)
□ Model copyWith produces correct copies
□ Currency formatter: pesewas to GHS display string
□ Phone formatter: raw digits to +233 XX XXX XXXX
□ Validators: phone, email, OTP, bid amounts
□ Enum mappings: string ↔ enum conversions
```

### 4. Repository Tests

```
□ Calls correct API endpoint
□ Maps API response to domain model correctly
□ Throws correct ApiError type on failure
□ Handles empty list responses
□ Handles pagination parameters
```

---

## Test Fixtures

### Common Test Data

```dart
// test/helpers/test_data.dart

abstract final class TestData {
  static final ride = Ride(
    id: 'ride-001',
    clientId: 'client-001',
    driverId: 'driver-001',
    status: RideStatus.inProgress,
    pickupLocation: const LatLng(6.6885, -1.6244),  // Kumasi center
    dropoffLocation: const LatLng(6.7000, -1.6300),
    fareAmountPesewas: 4700,
    createdAt: DateTime(2026, 3, 15, 14, 30),
  );

  static final artisanJob = Job(
    id: 'job-001',
    clientId: 'client-001',
    artisanId: 'artisan-001',
    categoryId: 'electrician',
    status: JobStatus.bidding,
    description: 'Living room rewiring — light switches not working',
    locationLat: 6.6900,
    locationLng: -1.6250,
    createdAt: DateTime(2026, 3, 15, 10, 0),
  );

  static final bid = Bid(
    id: 'bid-001',
    jobId: 'job-001',
    artisanId: 'artisan-001',
    amountPesewas: 18000,
    message: 'Includes inspection and standard materials.',
    createdAt: DateTime(2026, 3, 15, 10, 5),
  );

  static final user = User(
    id: 'user-001',
    phoneNumber: '+233241234567',
    email: 'ama@example.com',
    fullName: 'Ama Mensah',
    role: UserRole.client,
  );

  static final driver = Provider_(
    id: 'driver-001',
    userId: 'user-002',
    role: ProviderRole.driver,
    isOnline: true,
    rating: 4.5,
    completedRides: 150,
    vehicleMake: 'Toyota',
    vehicleModel: 'Corolla',
    vehicleYear: 2018,
    licensePlate: 'AS-1234-26',
  );
}
```

### Mock Providers

```dart
// test/helpers/mock_providers.dart

class MockRideRepository extends Mock implements RideRepository {}
class MockJobRepository extends Mock implements JobRepository {}
class MockAuthRepository extends Mock implements AuthRepository {}
class MockPaymentRepository extends Mock implements PaymentRepository {}

// Provider overrides for testing
List<Override> testOverrides({
  RideRepository? rideRepo,
  JobRepository? jobRepo,
  AuthRepository? authRepo,
}) {
  return [
    if (rideRepo != null) rideRepositoryProvider.overrideWithValue(rideRepo),
    if (jobRepo != null) jobRepositoryProvider.overrideWithValue(jobRepo),
    if (authRepo != null) authRepositoryProvider.overrideWithValue(authRepo),
  ];
}
```

---

## Hard Constraints

1. **Every test must be independent.** No shared mutable state between tests. Use `setUp` and `tearDown`.
2. **Never test implementation details.** Test observable behaviour (what the user sees, what state changes).
3. **Use `mocktail`, not `mockito`.** Mocktail supports null safety without codegen.
4. **Never skip error path tests.** Every happy path test must have a corresponding error path test.
5. **Widget tests must use `pumpApp` helper.** This wraps with ProviderScope, MaterialApp, theme, and localization.
6. **Name tests descriptively.** Format: `'shows fare estimate when destination is selected'` — not `'test1'`.
7. **Golden tests are optional.** Use for complex custom-painted widgets only, not for standard layouts.
