import 'package:api_client/api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/google_places_service.dart';

/// API configuration (base URL).
final apiConfigProvider = Provider<ApiConfig>((ref) {
  return ApiConfig.fromEnvironment();
});

/// Token storage backed by Flutter Secure Storage.
final appTokenStorageProvider = Provider<TokenStorage>((ref) {
  return SecureTokenStorage();
});

/// Configured Dio HTTP client with auth + logging interceptors.
final dioProvider = Provider<Dio>((ref) {
  final config = ref.watch(apiConfigProvider);
  final tokenStorage = ref.watch(appTokenStorageProvider);
  return createDioClient(
    config: config,
    tokenStorage: tokenStorage,
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

/// Payment service for Flutterwave integration.
final paymentServiceProvider = Provider<PaymentService>((ref) {
  return PaymentService(ref.watch(dioProvider));
});

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

/// Verification service for document + profile photo uploads.
final verificationServiceProvider = Provider<VerificationService>((ref) {
  return VerificationService(ref.watch(dioProvider));
});

/// Google Places service for location autocomplete & reverse geocoding.
final googlePlacesServiceProvider = Provider<GooglePlacesService>((ref) {
  return GooglePlacesService();
});
