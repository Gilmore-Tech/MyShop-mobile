import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

import '../core/providers/socket_provider.dart';
import '../core/widgets/incoming_request_listener.dart';
import '../features/auth/providers/auth_controller.dart';
import '../features/auth/screens/otp_verification_screen.dart';
import '../features/auth/screens/phone_input_screen.dart';
import '../features/auth/screens/role_selection_screen.dart';
import '../features/onboarding/screens/onboarding_screen.dart';
import '../features/onboarding/screens/role_picker_screen.dart';
import '../features/onboarding/screens/splash_screen.dart';
import '../features/registration/screens/artisan_registration_screen.dart';
import '../features/registration/screens/driver_registration_screen.dart';
import '../features/artisan_home/screens/active_job_screen.dart';
import '../features/chat/screens/chat_screen.dart';
import '../features/chat/screens/messages_list_screen.dart';
import '../features/artisan_home/screens/artisan_home_screen.dart';
import '../features/artisan_home/screens/job_request_screen.dart';
import '../features/artisan_home/widgets/bid_status_banner.dart';
import '../features/driver_home/screens/active_ride_screen.dart';
import '../features/driver_home/screens/driver_home_screen.dart';
import '../core/providers/nav_badge_provider.dart';
import '../features/profile/providers/provider_type_provider.dart';
import '../features/driver_home/screens/driver_ride_complete_screen.dart';
import '../features/driver_home/screens/ride_request_screen.dart';
import '../features/earnings/screens/artisan_earnings_screen.dart';
import '../features/earnings/screens/earnings_dashboard_screen.dart';
import '../features/earnings/screens/earnings_reports_screen.dart';
import '../features/profile/screens/account_settings_screen.dart';
import '../features/profile/screens/availability_schedule_screen.dart';
import '../features/profile/screens/business_information_screen.dart';
import '../features/profile/screens/edit_business_information_screen.dart';
import '../features/profile/screens/edit_vehicle_information_screen.dart';
import '../features/profile/screens/deactivate_account_screen.dart';
import '../features/profile/screens/documents_verification_screen.dart';
import '../features/profile/screens/edit_provider_profile_screen.dart';
import '../features/profile/screens/notification_settings_screen.dart';
import '../features/profile/screens/payout_methods_screen.dart';
import '../features/profile/screens/privacy_security_screen.dart';
import '../features/profile/screens/support_legal_screen.dart';
import '../features/profile/screens/vehicle_information_screen.dart';
import '../features/trips/screens/trips_history_screen.dart';

/// GoRouter configuration for the Provider (Driver) app.
///
/// Shell route provides the bottom navigation bar for the 4 main tabs.
/// Full-screen routes (ride request, active ride, trip complete) are outside the shell.
final goRouterProvider = Provider<GoRouter>((ref) {
  final refresh = _AuthRouterRefresh(ref);
  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final loc = state.matchedLocation;

      // Still bootstrapping — keep the splash visible.
      if (auth is AuthUnknown) {
        return loc == '/splash' ? null : '/splash';
      }

      const unauthAllowed = {
        '/onboarding',
        '/signin/phone',
        '/signin/role',
        '/signin/otp',
        '/signup/role',
        '/signup/driver',
        '/signup/artisan',
        '/signup/phone',
        '/signup/otp',
      };

      if (auth is AuthAuthenticated) {
        if (!loc.startsWith('/home') &&
            !loc.startsWith('/account') &&
            !loc.startsWith('/earnings') &&
            !loc.startsWith('/trips') &&
            !loc.startsWith('/active') &&
            !loc.startsWith('/ride') &&
            !loc.startsWith('/job') &&
            !loc.startsWith('/chat')) {
          return '/home';
        }
        return null;
      }
      // Both roles found — force user to the role selection screen.
      if (auth is AuthRoleSelection) {
        return loc == '/signin/role' ? null : '/signin/role';
      }
      // OTP sent — force user to the OTP screen.
      if (auth is AuthOtpSent) {
        final otpRoute = auth.isNewUser ? '/signup/otp' : '/signin/otp';
        return loc == otpRoute ? null : otpRoute;
      }
      // AuthUnauthenticated — decide between onboarding and sign-in.
      if (!unauthAllowed.contains(loc)) {
        // Returning user (has seen onboarding before) → go to sign-in.
        // First-time user → show onboarding welcome.
        final hasSeen = ref.read(hasSeenOnboardingProvider);
        return hasSeen ? '/signin/phone' : '/onboarding';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const ProviderSplashScreen(),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/signin/phone',
        builder: (context, state) => const ProviderPhoneInputScreen(
          mode: PhoneInputMode.signIn,
        ),
      ),
      GoRoute(
        path: '/signin/role',
        builder: (context, state) => const SignInRoleSelectionScreen(),
      ),
      GoRoute(
        path: '/signin/otp',
        builder: (context, state) => const ProviderOtpVerificationScreen(),
      ),
      GoRoute(
        path: '/signup/role',
        builder: (context, state) => const RolePickerScreen(),
      ),
      GoRoute(
        path: '/signup/driver',
        builder: (context, state) => const DriverRegistrationScreen(),
      ),
      GoRoute(
        path: '/signup/artisan',
        builder: (context, state) => const ArtisanRegistrationScreen(),
      ),
      GoRoute(
        path: '/signup/phone',
        builder: (context, state) {
          final role = ref.read(providerTypeProvider);
          return ProviderPhoneInputScreen(
            mode: PhoneInputMode.signUp,
            signUpRole: role,
          );
        },
      ),
      GoRoute(
        path: '/signup/otp',
        builder: (context, state) => const ProviderOtpVerificationScreen(),
      ),
      // Main shell with bottom navigation
      ShellRoute(
        builder: (context, state, child) => _DriverShell(child: child),
        routes: [
          GoRoute(
            path: '/home',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: _ProviderHomeSwitcher(),
            ),
          ),
          GoRoute(
            path: '/earnings',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: _ProviderEarningsSwitcher(),
            ),
          ),
          GoRoute(
            path: '/trips',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: _ProviderTripsSwitcher(),
            ),
          ),
          GoRoute(
            path: '/account',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: AccountSettingsScreen(),
            ),
          ),
        ],
      ),

      // Earnings sub-pages (full-screen, no bottom nav)
      GoRoute(
        path: '/earnings/reports',
        builder: (context, state) => const EarningsReportsScreen(),
      ),

      // Account sub-pages (full-screen, no bottom nav)
      GoRoute(
        path: '/account/edit',
        builder: (context, state) => const EditProviderProfileScreen(),
      ),
      GoRoute(
        path: '/account/documents',
        builder: (context, state) => const DocumentsVerificationScreen(),
      ),
      GoRoute(
        path: '/account/vehicle',
        redirect: (context, state) {
          final role = ref.read(providerTypeProvider);
          if (role.isArtisan) return '/account';
          return null;
        },
        builder: (context, state) => const VehicleInformationScreen(),
      ),
      GoRoute(
        path: '/account/vehicle/edit',
        redirect: (context, state) {
          final role = ref.read(providerTypeProvider);
          if (role.isArtisan) return '/account';
          return null;
        },
        builder: (context, state) => const EditVehicleInformationScreen(),
      ),
      GoRoute(
        path: '/account/business',
        builder: (context, state) => const BusinessInformationScreen(),
      ),
      GoRoute(
        path: '/account/business/edit',
        builder: (context, state) => const EditBusinessInformationScreen(),
      ),
      GoRoute(
        path: '/account/payouts',
        builder: (context, state) => const PayoutMethodsScreen(),
      ),
      GoRoute(
        path: '/account/availability',
        builder: (context, state) => const AvailabilityScheduleScreen(),
      ),
      GoRoute(
        path: '/account/notifications',
        builder: (context, state) => const NotificationSettingsScreen(),
      ),
      GoRoute(
        path: '/account/privacy',
        builder: (context, state) => const PrivacySecurityScreen(),
      ),
      GoRoute(
        path: '/account/support',
        builder: (context, state) => const SupportLegalScreen(),
      ),
      GoRoute(
        path: '/account/deactivate',
        builder: (context, state) => const DeactivateAccountScreen(),
      ),

      // Artisan flow routes (full-screen, no bottom nav)
      GoRoute(
        path: '/active-job',
        builder: (context, state) => const ActiveJobScreen(),
      ),
      GoRoute(
        path: '/chat',
        builder: (context, state) => const ProviderChatScreen(),
      ),
      GoRoute(
        path: '/job-request',
        builder: (context, state) {
          final extra = state.extra;
          if (extra is Job) {
            return JobRequestScreen(job: extra);
          }
          final status = extra is BidStatus ? extra : BidStatus.none;
          return JobRequestScreen(bidStatus: status);
        },
      ),

      // Ride flow routes (full-screen, no bottom nav)
      GoRoute(
        path: '/ride-request',
        builder: (context, state) => RideRequestScreen(
          ride: state.extra! as Ride,
        ),
      ),
      GoRoute(
        path: '/active-ride',
        builder: (context, state) => const ActiveRideScreen(),
      ),
      GoRoute(
        path: '/ride-complete',
        builder: (context, state) => const DriverRideCompleteScreen(),
      ),
    ],
  );
});

/// Bridges Riverpod's [authControllerProvider] to a [Listenable] so GoRouter
/// re-evaluates its [redirect] when auth state changes.
class _AuthRouterRefresh extends ChangeNotifier {
  _AuthRouterRefresh(this._ref) {
    _sub = _ref.listen<AuthState>(
      authControllerProvider,
      (_, __) => notifyListeners(),
    );
  }

  final Ref _ref;
  late final ProviderSubscription<AuthState> _sub;

  @override
  void dispose() {
    _sub.close();
    super.dispose();
  }
}

/// Switches between Driver and Artisan home based on the active provider role.
class _ProviderHomeSwitcher extends ConsumerWidget {
  const _ProviderHomeSwitcher();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final type = ref.watch(providerTypeProvider);
    return type.isArtisan
        ? const ArtisanHomeScreen()
        : const DriverHomeScreen();
  }
}

/// Renders the artisan messages list under the third tab slot, while drivers
/// keep their trips history. Lets us share one shell route for both roles.
class _ProviderTripsSwitcher extends ConsumerWidget {
  const _ProviderTripsSwitcher();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final type = ref.watch(providerTypeProvider);
    return type.isArtisan
        ? const MessagesListScreen()
        : const TripsHistoryScreen();
  }
}

/// Switches between Driver and Artisan earnings based on the active role.
class _ProviderEarningsSwitcher extends ConsumerWidget {
  const _ProviderEarningsSwitcher();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final type = ref.watch(providerTypeProvider);
    return type.isArtisan
        ? const ArtisanEarningsScreen()
        : const EarningsDashboardScreen();
  }
}

/// Shell widget providing the provider bottom navigation bar.
///
/// The tab set adapts to the active provider role:
///   - Driver:  Home, Earnings, Trips, Account
///   - Artisan: Jobs, Earnings, Messages, Account
///
/// Badge counts are driven by [navBadgeProvider]. When a tab is tapped its
/// badge is cleared automatically — just like any normal notification badge.
class _DriverShell extends ConsumerWidget {
  const _DriverShell({required this.child});

  final Widget child;

  static const _tabs = ['/home', '/earnings', '/trips', '/account'];

  int _currentIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    final index = _tabs.indexWhere((t) => location.startsWith(t));
    return index >= 0 ? index : 0;
  }

  void _onTabTap(BuildContext context, WidgetRef ref, String path) {
    ref.read(navBadgeProvider.notifier).clear(path);
    context.go(path);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Activate the Socket.IO connection manager — connects/disconnects
    // automatically when the provider toggles online/offline.
    ref.watch(socketConnectionProvider);

    // Pipe GPS updates into the socket so the backend can match this
    // provider against incoming jobs/rides within their service radius.
    ref.watch(locationSocketBridgeProvider);

    final currentIndex = _currentIndex(context);
    final isArtisan = ref.watch(providerTypeProvider).isArtisan;
    final badges = ref.watch(navBadgeProvider);

    return Scaffold(
      body: IncomingRequestListener(child: child),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Color(0xF2FFFFFF),
          border: Border(top: BorderSide(color: MyShopColors.divider, width: 0.5)),
          boxShadow: [BoxShadow(color: Color(0x0D000000), blurRadius: 10, offset: Offset(0, -2))],
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 64,
            child: Row(
              children: isArtisan
                  ? [
                      _NavTab(icon: Icons.work_outline, label: 'Jobs', isActive: currentIndex == 0, badgeCount: badges['/home'], onTap: () => _onTabTap(context, ref, '/home')),
                      _NavTab(icon: Icons.account_balance_wallet_outlined, label: 'Earnings', isActive: currentIndex == 1, badgeCount: badges['/earnings'], onTap: () => _onTabTap(context, ref, '/earnings')),
                      _NavTab(icon: Icons.chat_bubble_outline, label: 'Messages', isActive: currentIndex == 2, badgeCount: badges['/trips'], onTap: () => _onTabTap(context, ref, '/trips')),
                      _NavTab(icon: Icons.account_circle_outlined, label: 'Account', isActive: currentIndex == 3, badgeCount: badges['/account'], onTap: () => _onTabTap(context, ref, '/account')),
                    ]
                  : [
                      _NavTab(icon: Icons.dashboard_outlined, label: 'Home', isActive: currentIndex == 0, badgeCount: badges['/home'], onTap: () => _onTabTap(context, ref, '/home')),
                      _NavTab(icon: Icons.account_balance_wallet_outlined, label: 'Earnings', isActive: currentIndex == 1, badgeCount: badges['/earnings'], onTap: () => _onTabTap(context, ref, '/earnings')),
                      _NavTab(icon: Icons.history, label: 'Trips', isActive: currentIndex == 2, badgeCount: badges['/trips'], onTap: () => _onTabTap(context, ref, '/trips')),
                      _NavTab(icon: Icons.account_circle_outlined, label: 'Account', isActive: currentIndex == 3, badgeCount: badges['/account'], onTap: () => _onTabTap(context, ref, '/account')),
                    ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavTab extends StatelessWidget {
  const _NavTab({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
    this.badgeCount,
  });

  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;
  final int? badgeCount;

  @override
  Widget build(BuildContext context) {
    final color = isActive ? MyShopColors.primaryGold : MyShopColors.textSecondary;

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (badgeCount != null && badgeCount! > 0)
              Badge(
                label: Text('$badgeCount', style: const TextStyle(fontSize: 8, color: Colors.white)),
                backgroundColor: MyShopColors.error,
                child: Icon(icon, size: 24, color: color),
              )
            else
              Icon(icon, size: 24, color: color),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Raleway',
                fontSize: 10,
                fontWeight: isActive ? FontWeight.w800 : FontWeight.w400,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
