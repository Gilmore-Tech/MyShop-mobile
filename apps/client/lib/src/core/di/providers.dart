import 'package:api_client/api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/services/data/pending_payment_store.dart';
import '../providers/current_location_provider.dart';
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

/// Configured Dio HTTP client with auth + logging interceptors.
///
/// `onForceLogout` fires when the auth interceptor decides the session is
/// terminal (TOKEN_EXPIRED / INVALID_TOKEN / REFRESH_TOKEN_REUSED) or has
/// been invalidated by another device (SESSION_TAKEN_OVER). It dispatches
/// through [forceLogoutHandlerProvider] so the auth controller can register
/// itself without creating a Dart import cycle.
final dioProvider = Provider<Dio>((ref) {
  final config = ref.watch(apiConfigProvider);
  final tokenStorage = ref.watch(appTokenStorageProvider);
  final handler = ref.watch(forceLogoutHandlerProvider);
  return createDioClient(
    config: config,
    tokenStorage: tokenStorage,
    onForceLogout: handler.call,
  );
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
    biasLatitude: position?.latitude,
    biasLongitude: position?.longitude,
  );
});
