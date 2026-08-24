import 'package:api_client/api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/services/data/pending_payment_store.dart';
import '../../features/ride/data/ride_booking_attempt_store.dart';
import '../../features/ride/data/ride_booking_coordinator.dart';
import '../providers/current_location_provider.dart';
import '../providers/app_update_provider.dart';
import '../providers/auth_session_identity_provider.dart';
import '../providers/service_notice_provider.dart';
import '../services/google_places_service.dart';
import 'force_logout_handler.dart';

/// API configuration (base URL).
final apiConfigProvider = Provider<ApiConfig>((ref) {
  return ApiConfig.fromEnvironment();
});

/// Token storage backed by Flutter Secure Storage.
final appTokenStorageProvider = Provider<TokenStorage>((ref) {
  return SecureTokenStorage();
});

/// Persistent per-install device ID + device info collector.
final deviceIdProvider = Provider<DeviceIdProvider>((ref) {
  return DeviceIdProvider(ref.watch(appTokenStorageProvider));
});

final systemTelemetryProvider = Provider<SystemTelemetryService>((ref) {
  final tokenStorage = ref.watch(appTokenStorageProvider);
  final service = SystemTelemetryService(
    dio: ref.watch(dioProvider),
    deviceIdProvider: ref.watch(deviceIdProvider),
    app: 'client',
    deliveryAuthority: () async {
      final token = await tokenStorage.readAccessToken();
      return token?.isNotEmpty ?? false;
    },
  );
  ref.onDispose(service.dispose);
  return service;
});

/// Configured Dio HTTP client + the shared [TokenRefresher].
///
/// `onForceLogout` fires when the refresher decides the session is
/// terminal (TOKEN_EXPIRED / INVALID_TOKEN / REFRESH_TOKEN_REUSED) or
/// has been invalidated by another device (SESSION_TAKEN_OVER). It
/// dispatches through [forceLogoutHandlerProvider] so the auth
/// controller can register itself without creating a Dart import cycle.
///
/// The [TokenRefresher] is exposed separately so the WS [SocketService]
/// can reuse the same single-flight as the REST auth interceptor —
/// without that, the two layers race the same rotating refresh token
/// and the loser gets REFRESH_TOKEN_REUSED → forced logout.
final dioClientProvider = Provider<DioClient>((ref) {
  final config = ref.watch(apiConfigProvider);
  final tokenStorage = ref.watch(appTokenStorageProvider);
  final handler = ref.watch(forceLogoutHandlerProvider);
  return createDioClient(
    config: config,
    tokenStorage: tokenStorage,
    appKind: MobileAppKind.client,
    onAppUpdateRequired:
        ref.read(appUpdateRequirementProvider.notifier).requireUpdate,
    onServiceIssue: ref.read(serviceNoticeProvider.notifier).report,
    onServiceRecovered: ref.read(serviceNoticeProvider.notifier).recovered,
    onForceLogout: handler.call,
  );
});

final dioProvider = Provider<Dio>((ref) {
  return ref.watch(dioClientProvider).dio;
});

final tokenRefresherProvider = Provider<TokenRefresher>((ref) {
  return ref.watch(dioClientProvider).refresher;
});

/// Real auth service backed by Dio.
final realAuthServiceProvider = Provider<AuthService>((ref) {
  return RealAuthService(ref.watch(dioProvider));
});

// ── Domain services ──────────────────────────────────────────────────────────

/// Category service for fetching service categories.
final categoryServiceProvider = Provider<CategoryService>((ref) {
  return CategoryService(ref.watch(dioProvider));
});

/// Ride service for ride-hailing endpoints.
final rideServiceProvider = Provider<RideService>((ref) {
  return RideService(ref.watch(dioProvider));
});

/// Privacy-minimal durable handle for an ambiguous ride-create response.
final rideBookingAttemptStoreProvider = Provider<RideBookingAttemptStore>(
  (_) => RideBookingAttemptStore(),
);

/// Single-flight coordinator that must resolve a prior key before POST /rides.
final rideBookingCoordinatorProvider = Provider<RideBookingCoordinator>((ref) {
  final rideService = ref.watch(rideServiceProvider);
  return RideBookingCoordinator(
    store: ref.watch(rideBookingAttemptStoreProvider),
    lookup: rideService.lookupBookingAttempt,
  );
});

/// Runtime platform configuration service for feature flags and business rules.
final platformConfigServiceProvider = Provider<PlatformConfigService>((ref) {
  return PlatformConfigService(ref.watch(dioProvider));
});

/// Job service for artisan marketplace endpoints.
final jobServiceProvider = Provider<JobService>((ref) {
  return JobService(ref.watch(dioProvider));
});

/// Media upload service for presigned URL file uploads.
final mediaServiceProvider = Provider<MediaService>((ref) {
  return MediaService(ref.watch(dioProvider));
});

/// Payment service for Paystack integration.
final paymentServiceProvider = Provider<PaymentService>((ref) {
  return PaymentService(ref.watch(dioProvider));
});

/// Promo service for active promotional campaigns.
final promoServiceProvider = Provider<PromoService>((ref) {
  return PromoService(ref.watch(dioProvider));
});

/// SharedPreferences-backed store of in-flight Paystack charges, keyed
/// on bookingId. Persisted so the OTP/USSD flow can resume across app
/// restarts and Retry can clear stale rows even when the in-memory
/// paymentId was lost.
final pendingPaymentStoreProvider = Provider<PendingPaymentStore>(
  (_) => PendingPaymentStore(),
);

/// Notification service.
final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService(ref.watch(dioProvider));
});

/// Rating service for blind 24h rating window.
final ratingServiceProvider = Provider<RatingService>((ref) {
  return RatingService(ref.watch(dioProvider));
});

/// Chat service for in-app messaging.
final chatServiceProvider = Provider<ChatService>((ref) {
  return ChatService(ref.watch(dioProvider));
});

/// App-to-app voice call session service.
final appCallServiceProvider = Provider<AppCallService>((ref) {
  return AppCallService(ref.watch(dioProvider));
});

/// Live `/calls` socket used by the in-app call screen.
final appCallSocketServiceProvider = Provider<AppCallSocketService>((ref) {
  ref.watch(currentClientAuthSessionIdentityProvider);
  final service = AppCallSocketService(
    config: ref.watch(apiConfigProvider),
    tokenStorage: ref.watch(appTokenStorageProvider),
    tokenRefresher: ref.watch(tokenRefresherProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});

/// Safety/emergency service.
final safetyServiceProvider = Provider<SafetyService>((ref) {
  return SafetyService(ref.watch(dioProvider));
});

/// User service for saved locations, emergency contacts.
final userServiceProvider = Provider<UserService>((ref) {
  return UserService(ref.watch(dioProvider));
});

/// Loyalty service — transaction history + in-booking redemption.
/// The points balance itself lives on the user profile, not this service.
final loyaltyServiceProvider = Provider<LoyaltyService>((ref) {
  return LoyaltyService(ref.watch(dioProvider));
});

/// Verification service for document + profile photo uploads.
final verificationServiceProvider = Provider<VerificationService>((ref) {
  return VerificationService(ref.watch(dioProvider));
});

/// Google Places service for location autocomplete & reverse geocoding.
/// Bias is re-derived from the latest cached device fix so suggestions
/// stay relevant once the user moves out of the pilot city.
final googlePlacesServiceProvider = Provider<GooglePlacesService>((ref) {
  final position = ref.watch(currentDevicePositionProvider);
  return GooglePlacesService(
    dio: ref.watch(dioProvider),
    biasLatitude: position?.latitude,
    biasLongitude: position?.longitude,
  );
});

/// Stable Google proxy client for coordinate-bound reverse geocoding.
///
/// Autocomplete needs a location-biased service that rebuilds as the rider
/// moves. Reverse geocoding already carries its exact coordinate in each call,
/// so coupling it to that bias can invalidate an in-flight request and send the
/// same backend/Google lookup twice when only Position metadata changes.
final reverseGeocodingServiceProvider = Provider<GooglePlacesService>((ref) {
  return GooglePlacesService(dio: ref.watch(dioProvider));
});
