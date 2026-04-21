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
/// `onForceLogout` fires when the auth interceptor determines the refresh
/// token itself is dead (real backend revocation). The auth controller
/// flips to unauthenticated and the router redirects to the sign-in flow.
final dioProvider = Provider<Dio>((ref) {
  final config = ref.watch(apiConfigProvider);
  final tokenStorage = ref.watch(appTokenStorageProvider);
  return createDioClient(
    config: config,
    tokenStorage: tokenStorage,
    onForceLogout: () {
      ref.read(authControllerProvider.notifier).logout();
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

/// Backend notification service — exposes `/notifications` endpoints
/// (list, mark-as-read, register FCM device token).
final apiNotificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService(ref.watch(dioProvider));
});
