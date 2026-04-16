import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

// ── App shell ──────────────────────────────────────────────────────────────────
import 'main_shell.dart';

// ── Dev ────────────────────────────────────────────────────────────────────────
import '../dev/dev_menu_screen.dart';

// ── Onboarding ─────────────────────────────────────────────────────────────────
import '../features/onboarding/screens/splash_screen.dart';

// ── Auth ───────────────────────────────────────────────────────────────────────
import '../features/auth/screens/phone_input_screen.dart';
import '../features/auth/screens/otp_verification_screen.dart';

// ── Home ───────────────────────────────────────────────────────────────────────
import '../features/home/screens/home_screen.dart';

// ── Ride ───────────────────────────────────────────────────────────────────────
import '../features/ride/screens/destination_search_screen.dart';
import '../features/ride/screens/map_pin_picker_screen.dart';
import '../features/ride/screens/fare_estimate_screen.dart';
import '../features/ride/providers/ride_search_provider.dart'
    show parseRideSearchField;
import '../features/ride/screens/add_stop_screen.dart';
import '../features/ride/screens/driver_matching_screen.dart';
import '../features/ride/screens/driver_found_screen.dart';
import '../features/ride/screens/ride_tracking_screen.dart';
import '../features/ride/screens/ride_complete_screen.dart';
import '../features/ride/screens/ride_dispute_screen.dart';
import '../features/ride/screens/ride_receipt_screen.dart';
import '../features/ride/providers/ride_provider.dart' show MatchedDriver;

// ── Services ───────────────────────────────────────────────────────────────────
import '../features/services/screens/categories_screen.dart';
import '../features/services/screens/job_form_screen.dart';
import '../features/services/screens/job_detail_screen.dart';
import '../features/services/screens/bid_detail_screen.dart';
import '../features/services/screens/bid_review_screen.dart';
import '../features/services/screens/supplement_review_screen.dart';
import '../features/services/screens/active_job_screen.dart';
import '../features/services/screens/job_tracking_screen.dart';
import '../features/services/screens/job_summary_screen.dart';
import '../features/services/screens/job_complete_screen.dart';
import '../features/services/screens/job_dispute_screen.dart';
import '../features/services/screens/service_receipt_screen.dart';
import '../features/services/screens/payment_screen.dart';

// ── Activity ───────────────────────────────────────────────────────────────────
import '../features/activity/screens/activity_list_screen.dart';
import '../features/activity/screens/ride_detail_screen.dart';
import '../features/activity/screens/job_detail_screen.dart'
    as activity_job_detail;

// ── Profile ────────────────────────────────────────────────────────────────────
import '../features/profile/screens/profile_screen.dart';
import '../features/profile/screens/edit_profile_screen.dart';
import '../features/profile/screens/saved_locations_screen.dart';
import '../features/profile/screens/notification_settings_screen.dart';
import '../features/profile/screens/privacy_security_screen.dart';
import '../features/profile/screens/app_preferences_screen.dart';
import '../features/profile/screens/support_legal_screen.dart';
import '../features/profile/screens/referral_screen.dart';
import '../features/profile/screens/payment_methods_screen.dart';
import '../features/profile/screens/emergency_contacts_screen.dart';
import '../features/profile/screens/language_settings_screen.dart';
import '../features/profile/screens/loyalty_points_screen.dart';

// ── Chat / Safety / Notifications ─────────────────────────────────────────────
import '../features/chat/screens/chat_screen.dart';
import '../features/safety/screens/emergency_screen.dart';
import '../features/safety/screens/share_tracking_screen.dart';
import '../features/notifications/screens/notifications_list_screen.dart';

// ── Route Path Constants ───────────────────────────────────────────────────────

abstract final class AppRoutes {
  // Onboarding
  static const splash          = '/';
  // Auth
  static const authPhone       = '/auth/phone';
  static const authOtp         = '/auth/otp';

  // Main tabs
  static const home            = '/home';
  static const services        = '/services';
  static const activity        = '/activity';
  static const profile         = '/profile';

  // Ride sub-flow
  static const rideSearch      = '/ride/search/:field';
  static const ridePinPicker   = '/ride/pin-picker/:field';
  static const rideEstimate    = '/ride/estimate';
  static const rideStops       = '/ride/stops';
  static const rideMatching    = '/ride/matching';
  static const rideDriverFound = '/ride/driver-found';
  static const rideTracking    = '/ride/tracking';
  static const rideComplete    = '/ride/complete';
  static const rideReceipt     = '/ride/:rideId/receipt';
  static const rideDispute     = '/ride/:rideId/dispute';

  static String rideSearchPath(String field)      => '/ride/search/$field';
  static String ridePinPickerPath(String field)   => '/ride/pin-picker/$field';
  static String rideReceiptPath(String rideId)    => '/ride/$rideId/receipt';
  static String rideDisputePath(String rideId)    => '/ride/$rideId/dispute';

  // Services sub-flow
  static const jobNew           = '/services/job/new';
  static const jobDetail        = '/services/job/:jobId';
  static const jobBids          = '/services/job/:jobId/bids/:bidId';
  static const jobBidReview     = '/services/job/:jobId/bid-review';
  static const jobSupplement    = '/services/job/:jobId/supplement';
  static const jobActive        = '/services/job/:jobId/active';
  static const jobTracking      = '/services/job/:jobId/tracking';
  static const jobSummary       = '/services/job/:jobId/summary';
  static const jobComplete      = '/services/job/:jobId/complete';
  static const jobReceipt       = '/services/job/:jobId/receipt';
  static const jobDispute       = '/services/job/:jobId/dispute';
  static const jobPayment       = '/services/job/:jobId/payment';

  static String jobDetailPath(String jobId)     => '/services/job/$jobId';
  static String jobBidsPath(String j, String b) => '/services/job/$j/bids/$b';
  static String jobBidReviewPath(String jobId)  => '/services/job/$jobId/bid-review';
  static String jobSupplementPath(String jobId) => '/services/job/$jobId/supplement';
  static String jobActivePath(String jobId)     => '/services/job/$jobId/active';
  static String jobTrackingPath(String jobId)   => '/services/job/$jobId/tracking';
  static String jobSummaryPath(String jobId)    => '/services/job/$jobId/summary';
  static String jobCompletePath(String jobId)   => '/services/job/$jobId/complete';
  static String jobReceiptPath(String jobId)    => '/services/job/$jobId/receipt';
  static String jobDisputePath(String jobId)    => '/services/job/$jobId/dispute';
  static String jobPaymentPath(String jobId)    => '/services/job/$jobId/payment';

  // Activity history
  static const activityRide    = '/activity/ride/:rideId';
  static const activityJob     = '/activity/job/:jobId';

  static String activityRidePath(String rideId) => '/activity/ride/$rideId';
  static String activityJobPath(String jobId)   => '/activity/job/$jobId';

  // Profile sub-screens
  static const profileEdit         = '/profile/edit';
  static const profileSavedPlaces  = '/profile/saved-places';
  static const profileNotifications = '/profile/notifications';
  static const profilePrivacy      = '/profile/privacy';
  static const profilePreferences  = '/profile/preferences';
  static const profileLanguage     = '/profile/language';
  static const profileSupport      = '/profile/support';
  static const profileReferral     = '/profile/referral';
  static const profilePayments     = '/profile/payments';
  static const profileEmergency    = '/profile/emergency-contacts';
  static const profileLoyalty      = '/profile/loyalty';

  // Overlays
  static const chat                = '/chat';
  static const safetyEmergency     = '/safety/emergency';
  static const safetyShare         = '/safety/share';
  static const notifications       = '/notifications';

  // Dev
  static const dev                 = '/dev';
}

// ── Navigator keys ─────────────────────────────────────────────────────────────

final _rootNavigatorKey     = GlobalKey<NavigatorState>();
final _homeNavKey           = GlobalKey<NavigatorState>(debugLabel: 'home');
final _servicesNavKey       = GlobalKey<NavigatorState>(debugLabel: 'services');
final _activityNavKey       = GlobalKey<NavigatorState>(debugLabel: 'activity');
final _profileNavKey        = GlobalKey<NavigatorState>(debugLabel: 'profile');

// ── Router Provider ────────────────────────────────────────────────────────────
// NOT autoDispose — the router must live for the full app lifetime.

final routerProvider = Provider<GoRouter>((ref) => _buildRouter());

GoRouter _buildRouter() {
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    // TEMP: land directly on home for UI testing of the redesigned homepage.
    // Revert to AppRoutes.splash when wiring auth/onboarding gate.
    initialLocation: AppRoutes.home,
    debugLogDiagnostics: false,
    routes: [

      // ── Dev menu ─────────────────────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.dev,
        builder: (_, __) => const DevMenuScreen(),
      ),

      // ── Onboarding ────────────────────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.splash,
        builder: (_, __) => const SplashScreen(),
      ),

      // ── Auth ──────────────────────────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.authPhone,
        builder: (_, __) => const PhoneInputScreen(),
      ),
      GoRoute(
        path: AppRoutes.authOtp,
        builder: (_, __) => const OtpVerificationScreen(),
      ),

      // ── Main tabs shell ───────────────────────────────────────────────────────
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            MainShell(navigationShell: navigationShell),
        branches: [
          // Tab 0 — Home
          StatefulShellBranch(
            navigatorKey: _homeNavKey,
            routes: [
              GoRoute(
                path: AppRoutes.home,
                builder: (_, __) => const HomeScreen(),
              ),
              // Ride completion lives inside the shell so the shared
              // bottom nav wraps it and users can jump to any tab.
              GoRoute(
                path: AppRoutes.rideComplete,
                builder: (_, __) => const RideCompleteScreen(),
              ),
            ],
          ),

          // Tab 1 — Services
          StatefulShellBranch(
            navigatorKey: _servicesNavKey,
            routes: [
              GoRoute(
                path: AppRoutes.services,
                builder: (_, __) => const CategoriesScreen(),
              ),
            ],
          ),

          // Tab 2 — Activity
          StatefulShellBranch(
            navigatorKey: _activityNavKey,
            routes: [
              GoRoute(
                path: AppRoutes.activity,
                builder: (_, __) => const ActivityListScreen(),
              ),
            ],
          ),

          // Tab 3 — Profile
          StatefulShellBranch(
            navigatorKey: _profileNavKey,
            routes: [
              GoRoute(
                path: AppRoutes.profile,
                builder: (_, __) => const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),

      // ── Ride sub-flow (full-screen, above shell) ──────────────────────────────
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: AppRoutes.rideSearch,
        builder: (_, state) => DestinationSearchScreen(
          field: parseRideSearchField(state.pathParameters['field']),
          stopId: state.extra is String ? state.extra as String : null,
        ),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: AppRoutes.ridePinPicker,
        builder: (_, state) => MapPinPickerScreen(
          field: parseRideSearchField(state.pathParameters['field']),
          stopId: state.extra is String ? state.extra as String : null,
        ),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: AppRoutes.rideEstimate,
        builder: (_, __) => const FareEstimateScreen(),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: AppRoutes.rideStops,
        builder: (_, __) => const AddStopScreen(),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: AppRoutes.rideMatching,
        builder: (_, __) => const DriverMatchingScreen(),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: AppRoutes.rideDriverFound,
        builder: (context, state) {
          final driver = state.extra as MatchedDriver?;
          if (driver == null) return const DriverMatchingScreen();
          return DriverFoundScreen(driver: driver);
        },
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: AppRoutes.rideTracking,
        builder: (context, state) {
          final driver = state.extra as MatchedDriver?;
          if (driver == null) return const DriverMatchingScreen();
          return RideTrackingScreen(driver: driver);
        },
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: AppRoutes.rideReceipt,
        builder: (_, state) {
          final rideId = state.pathParameters['rideId']!;
          final fromCompletion = state.extra == true;
          return RideReceiptScreen(
            rideId: rideId,
            fromCompletion: fromCompletion,
          );
        },
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: AppRoutes.rideDispute,
        builder: (_, __) => const RideDisputeScreen(),
      ),

      // ── Services sub-flow (full-screen, above shell) ──────────────────────────
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: AppRoutes.jobNew,
        builder: (_, state) {
          final extra = state.extra as Map<String, String?>?;
          return JobFormScreen(
            initialCategoryId:   extra?['categoryId'],
            initialCategoryName: extra?['categoryName'],
          );
        },
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: AppRoutes.jobBids,
        builder: (_, state) {
          final bidId = state.pathParameters['bidId']!;
          return BidDetailScreen(bidId: bidId);
        },
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: AppRoutes.jobBidReview,
        builder: (_, state) {
          final jobId = state.pathParameters['jobId']!;
          final bidId = state.extra as String? ?? '';
          return BidReviewScreen(jobId: jobId, bidId: bidId);
        },
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: AppRoutes.jobSupplement,
        builder: (_, __) => const SupplementReviewScreen(),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: AppRoutes.jobActive,
        builder: (_, state) {
          final jobId = state.pathParameters['jobId']!;
          return ActiveJobScreen(jobId: jobId);
        },
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: AppRoutes.jobTracking,
        builder: (_, __) => const JobTrackingScreen(),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: AppRoutes.jobSummary,
        builder: (_, state) {
          final jobId = state.pathParameters['jobId']!;
          return JobSummaryScreen(jobId: jobId);
        },
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: AppRoutes.jobComplete,
        builder: (_, __) => const JobCompleteScreen(),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: AppRoutes.jobReceipt,
        builder: (_, state) {
          final jobId = state.pathParameters['jobId']!;
          return ServiceReceiptScreen(jobId: jobId);
        },
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: AppRoutes.jobDispute,
        builder: (_, __) => const JobDisputeScreen(),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: AppRoutes.jobPayment,
        builder: (_, state) {
          final jobId = state.pathParameters['jobId']!;
          return PaymentScreen(jobId: jobId);
        },
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: AppRoutes.jobDetail,
        builder: (_, state) {
          final jobId = state.pathParameters['jobId']!;
          return JobDetailScreen(jobId: jobId);
        },
      ),

      // ── Activity history (full-screen, above shell) ────────────────────────────
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: AppRoutes.activityRide,
        builder: (_, __) => const RideDetailScreen(),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: AppRoutes.activityJob,
        builder: (_, __) => const activity_job_detail.JobDetailScreen(),
      ),

      // ── Profile sub-screens (full-screen, above shell) ─────────────────────────
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: AppRoutes.profileEdit,
        builder: (_, __) => const EditProfileScreen(),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: AppRoutes.profileSavedPlaces,
        builder: (_, __) => const SavedLocationsScreen(),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: AppRoutes.profileNotifications,
        builder: (_, __) => const NotificationSettingsScreen(),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: AppRoutes.profilePrivacy,
        builder: (_, __) => const PrivacySecurityScreen(),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: AppRoutes.profilePreferences,
        builder: (_, __) => const AppPreferencesScreen(),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: AppRoutes.profileLanguage,
        builder: (_, __) => const LanguageSettingsScreen(),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: AppRoutes.profileSupport,
        builder: (_, __) => const SupportLegalScreen(),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: AppRoutes.profileReferral,
        builder: (_, __) => const ReferralScreen(),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: AppRoutes.profilePayments,
        builder: (_, __) => const PaymentMethodsScreen(),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: AppRoutes.profileEmergency,
        builder: (_, __) => const EmergencyContactsScreen(),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: AppRoutes.profileLoyalty,
        builder: (_, __) => const LoyaltyPointsScreen(),
      ),

      // ── Overlays (full-screen, above shell) ────────────────────────────────────
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: AppRoutes.chat,
        builder: (_, __) => const ChatScreen(),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: AppRoutes.safetyEmergency,
        builder: (_, __) => const EmergencyScreen(),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: AppRoutes.safetyShare,
        builder: (_, __) => const ShareTrackingScreen(),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: AppRoutes.notifications,
        builder: (_, __) => const NotificationsListScreen(),
      ),
    ],

    // ── Error page ─────────────────────────────────────────────────────────────
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Text(
          'Page not found: ${state.uri}',
          style: const TextStyle(color: MyShopColors.textSecondary),
        ),
      ),
    ),
  );
}
