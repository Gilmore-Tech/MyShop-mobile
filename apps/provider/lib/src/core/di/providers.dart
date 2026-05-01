import 'package:api_client/api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/providers/auth_controller.dart';

/// API configuration (base URL).
final apiConfigProvider = Provider<ApiConfig>((ref) {
  return ApiConfig.fromEnvironment();
});

/// Token storage backed by Flutter Secure Storage.
final appTokenStorageProvider = Provider<TokenStorage>((ref) {
  return SecureTokenStorage();
});

/// Configured Dio HTTP client with auth + logging interceptors.
///
/// `onForceLogout` fires when the auth interceptor decides the session is
/// terminal (TOKEN_EXPIRED / INVALID_TOKEN / REFRESH_TOKEN_REUSED) or has
/// been invalidated by another device (SESSION_TAKEN_OVER). The interceptor
/// has already cleared the appropriate tokens by the time this fires;
/// the controller's job is just to flip state to unauthenticated.
final dioProvider = Provider<Dio>((ref) {
  final config = ref.watch(apiConfigProvider);
  final tokenStorage = ref.watch(appTokenStorageProvider);
  return createDioClient(
    config: config,
    tokenStorage: tokenStorage,
    onForceLogout: () {
      ref.read(authControllerProvider.notifier).onForceLogoutFromInterceptor();
    },
  );
});

/// Real auth service backed by Dio.
final realAuthServiceProvider = Provider<AuthService>((ref) {
  return RealAuthService(ref.watch(dioProvider));
});

/// REST location updates — keeps `current_location` + `online_status`
/// in the DB in sync with the socket `location:update` emits.
final locationServiceProvider = Provider<LocationService>((ref) {
  return LocationService(ref.watch(dioProvider));
});

/// Job service — marketplace endpoints for listing jobs, submitting bids,
/// and managing job lifecycle actions.
final jobServiceProvider = Provider<JobService>((ref) {
  return JobService(ref.watch(dioProvider));
});

/// Ride service — ride-hailing endpoints for accepting and advancing rides
/// through the driver lifecycle (accepted → driver_en_route → arrived →
/// in_progress → completed) plus driver-initiated cancellation.
final rideServiceProvider = Provider<RideService>((ref) {
  return RideService(ref.watch(dioProvider));
});

/// Ratings — `POST /ratings` (blind 24h window). Used by the driver-side
/// rate-passenger sheet on the trip-complete screen; same endpoint the
/// rider hits to rate the driver, just with `bookingType: 'ride'` and a
/// rateeId pulled from the ride payload server-side.
final ratingServiceProvider = Provider<RatingService>((ref) {
  return RatingService(ref.watch(dioProvider));
});

/// Backend notification service — exposes `/notifications` endpoints
/// (list, mark-as-read, register FCM device token).
final apiNotificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService(ref.watch(dioProvider));
});

/// Chat REST — history fetch + send/markRead fallback paths used by the
/// orchestrator when the `/chat` socket can't deliver in time.
final chatServiceProvider = Provider<ChatService>((ref) {
  return ChatService(ref.watch(dioProvider));
});
