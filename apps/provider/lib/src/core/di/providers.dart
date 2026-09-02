import 'package:api_client/api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/providers/auth_controller.dart';
import '../providers/app_update_provider.dart';
import '../providers/service_notice_provider.dart';

/// API configuration (base URL).
final apiConfigProvider = Provider<ApiConfig>((ref) {
  return ApiConfig.fromEnvironment();
});

/// Token storage backed by Flutter Secure Storage.
final appTokenStorageProvider = Provider<TokenStorage>((ref) {
  return SecureTokenStorage();
});

final deviceIdProvider = Provider<DeviceIdProvider>((ref) {
  return DeviceIdProvider(ref.watch(appTokenStorageProvider));
});

final systemTelemetryProvider = Provider<SystemTelemetryService>((ref) {
  final tokenStorage = ref.watch(appTokenStorageProvider);
  final service = SystemTelemetryService(
    dio: ref.watch(dioProvider),
    deviceIdProvider: ref.watch(deviceIdProvider),
    app: 'provider',
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
/// has been invalidated by another device (SESSION_TAKEN_OVER). Tokens
/// are already cleared by the time this fires; the controller's job is
/// just to flip state to unauthenticated.
///
/// The [TokenRefresher] is exposed separately so the WS [SocketService]
/// can reuse the same single-flight as the REST auth interceptor —
/// without that, the two layers race the same rotating refresh token
/// and the loser gets REFRESH_TOKEN_REUSED → forced logout.
final dioClientProvider = Provider<DioClient>((ref) {
  final config = ref.watch(apiConfigProvider);
  final tokenStorage = ref.watch(appTokenStorageProvider);
  return createDioClient(
    config: config,
    tokenStorage: tokenStorage,
    appKind: MobileAppKind.provider,
    onAppUpdateRequired:
        ref.read(appUpdateRequirementProvider.notifier).requireUpdate,
    onServiceIssue: ref.read(serviceNoticeProvider.notifier).report,
    onServiceRecovered: ref.read(serviceNoticeProvider.notifier).recovered,
    onForceLogout: (event) {
      ref
          .read(authControllerProvider.notifier)
          .onForceLogoutFromInterceptor(event);
    },
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

/// Region service — public `GET /v1/regions`. Used by provider signup to
/// let the driver/artisan pick their home region. No auth header needed.
final regionServiceProvider = Provider<RegionService>((ref) {
  return RegionService(ref.watch(dioProvider));
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

/// Provider-targeted pending ride/job request recovery. Used when an FCM tap,
/// app resume, or socket reconnect needs to re-surface an actionable request
/// that arrived while the app process was sleeping.
final providerRequestServiceProvider = Provider<ProviderRequestService>((ref) {
  return ProviderRequestService(ref.watch(dioProvider));
});

/// Server-authored acceptance/response metrics. Null is a valid compatibility
/// result while the summary endpoint is rolling out.
final providerRequestResponseSummaryProvider =
    FutureProvider.autoDispose<ProviderRequestResponseSummary?>((ref) {
  return ref.watch(providerRequestServiceProvider).getRequestResponseSummary();
});

/// Server-authoritative online/offline snapshot used during lifecycle/socket
/// reconciliation.
final providerAvailabilityServiceProvider =
    Provider<ProviderAvailabilityService>((ref) {
  return ProviderAvailabilityService(ref.watch(dioProvider));
});

/// Chat REST — history fetch + send/markRead fallback paths used by the
/// orchestrator when the `/chat` socket can't deliver in time.
final chatServiceProvider = Provider<ChatService>((ref) {
  return ChatService(ref.watch(dioProvider));
});

/// App-to-app voice call session service.
final appCallServiceProvider = Provider<AppCallService>((ref) {
  return AppCallService(ref.watch(dioProvider));
});

/// Live `/calls` socket used by the in-app call screen.
final appCallSocketServiceProvider = Provider<AppCallSocketService>((ref) {
  ref.watch(currentAuthSessionIdentityProvider);
  final service = AppCallSocketService(
    config: ref.watch(apiConfigProvider),
    tokenStorage: ref.watch(appTokenStorageProvider),
    tokenRefresher: ref.watch(tokenRefresherProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});

/// Media upload — presigned URL flow for ticket attachments.
final mediaServiceProvider = Provider<MediaService>((ref) {
  return MediaService(ref.watch(dioProvider));
});

/// Payment service — payout-method OTP bind, payout request, retry
/// payment. Driver + artisan earnings dashboards consume this to let
/// providers cash out their available balance to MoMo without leaving
/// the app.
final paymentServiceProvider = Provider<PaymentService>((ref) {
  return PaymentService(ref.watch(dioProvider));
});

/// Promo campaigns — `GET /promos/active`. The backend filters by the
/// caller's token role, so a signed-in driver/artisan only ever receives
/// provider-audience commission-relief campaigns (empty list when the
/// promo feature flag is off).
final promoServiceProvider = Provider<PromoService>((ref) {
  return PromoService(ref.watch(dioProvider));
});

/// Safety service — POST /emergency for the SOS screen. Used by both
/// driver and artisan emergency surfaces with `bookingType: 'ride' | 'job'`
/// derived from the active role + active booking id.
final safetyServiceProvider = Provider<SafetyService>((ref) {
  return SafetyService(ref.watch(dioProvider));
});

/// User service — read + update + DELETE `/v1/users/me`. Used by the
/// deactivate-account flow for Apple Guideline 5.1.1(v) compliance:
/// every sign-up app must offer in-app deletion.
final userServiceProvider = Provider<UserService>((ref) {
  return UserService(ref.watch(dioProvider));
});

/// Platform config — public `GET /config/:key` reader. Admins flip
/// commission rate, payout windows, surge ceilings via the dashboard;
/// mobile reads them on demand so changes don't require a release.
final platformConfigServiceProvider = Provider<PlatformConfigService>((ref) {
  return PlatformConfigService(ref.watch(dioProvider));
});

/// Cached commission rate for estimate-only UI. Financial finalization remains
/// server-authoritative and fail-closed. An unavailable or invalid value is an
/// error state; silently substituting a percentage would misquote providers.
final commissionRatePercentProvider = FutureProvider<num>((ref) async {
  final value = await ref
      .watch(platformConfigServiceProvider)
      .getNumber('commission_rate_percent');
  if (value == null || !value.isFinite || value < 0 || value > 100) {
    throw StateError('Commission configuration is unavailable or invalid.');
  }
  return value;
});
