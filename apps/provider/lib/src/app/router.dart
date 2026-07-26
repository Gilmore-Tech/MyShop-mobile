import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

import '../core/providers/background_location_sync_provider.dart';
import '../core/di/providers.dart';
import '../core/providers/pending_request_recovery_provider.dart';
import '../core/providers/socket_provider.dart';
import '../core/widgets/incoming_request_listener.dart';
import '../features/artisan_home/providers/job_poller_provider.dart';
import '../features/artisan_home/providers/active_job_provider.dart';
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
import '../features/artisan_home/screens/supplement_request_screen.dart';
import '../features/calls/screens/in_app_call_screen.dart';
import '../features/chat/screens/chat_screen.dart';
import '../features/chat/screens/messages_list_screen.dart';
import '../features/notifications/screens/notifications_list_screen.dart';
import '../features/safety/screens/emergency_screen.dart';
import '../features/artisan_home/screens/artisan_home_screen.dart';
import '../features/artisan_home/screens/job_request_screen.dart';
import '../features/artisan_jobs/screens/artisan_jobs_screen.dart';
import '../features/artisan_home/widgets/bid_status_banner.dart';
import '../features/driver_home/providers/online_session_provider.dart';
import '../features/driver_home/providers/ride_request_provider.dart';
import '../features/driver_home/screens/active_ride_screen.dart';
import '../features/driver_home/screens/driver_home_screen.dart';
import '../core/providers/nav_badge_provider.dart';
import '../features/profile/providers/provider_type_provider.dart';
import '../features/profile/providers/verification_provider.dart';
import '../features/driver_home/screens/driver_ride_complete_screen.dart';
import '../features/driver_home/screens/ride_request_screen.dart';
import '../features/earnings/screens/artisan_earnings_screen.dart';
import '../features/earnings/screens/earnings_dashboard_screen.dart';
import '../features/earnings/screens/earnings_reports_screen.dart';
import '../features/profile/screens/account_settings_screen.dart';
import '../features/profile/screens/availability_schedule_screen.dart';
import '../features/profile/screens/business_information_screen.dart';
import '../features/profile/screens/deactivate_account_screen.dart';
import '../features/profile/screens/documents_verification_screen.dart';
import '../features/profile/screens/emergency_contacts_screen.dart';
import '../features/profile/screens/notification_settings_screen.dart';
import '../features/profile/screens/payout_methods_screen.dart';
import '../features/profile/screens/privacy_security_screen.dart';
import '../features/profile/screens/referral_screen.dart';
import '../features/support/screens/help_article_route_screen.dart';
import '../features/support/screens/help_category_route_screen.dart';
import '../features/support/screens/help_search_route_screen.dart';
import '../features/support/screens/legal_document_route_screen.dart';
import '../features/support/screens/legal_consent_route_screen.dart';
import '../features/support/providers/support_providers.dart'
    show legalConsentStatusProvider;
import '../features/support/screens/new_ticket_route_screen.dart';
import '../features/support/screens/support_legal_route_screen.dart';
import '../features/support/screens/ticket_detail_route_screen.dart';
import '../features/support/screens/tickets_list_route_screen.dart';
import '../features/profile/screens/vehicle_information_screen.dart';
import '../features/trips/screens/trips_history_screen.dart';

/// GoRouter configuration for the Provider (Driver) app.
///
/// Shell route provides the bottom navigation bar for the 4 main tabs.
/// Full-screen routes (ride request, active ride, trip complete) are outside the shell.
final goRouterProvider = Provider<GoRouter>((ref) {
  final refresh = _AuthRouterRefresh(ref);
  final telemetry = ref.read(systemTelemetryProvider);
  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final legalConsent = auth is AuthAuthenticated
          ? ref.read(legalConsentStatusProvider)
          : null;
      final hasActiveWork = auth is AuthAuthenticated &&
          (ref.read(activeRideProvider).hasRide ||
              ref.read(activeJobProvider).hasJob);
      final onboardingFlagLoaded = ref.read(onboardingFlagLoadedProvider);
      final loc = state.matchedLocation;
      telemetry.trackScreen(state.fullPath ?? state.matchedLocation);

      // Still bootstrapping — keep the Flutter splash visible. Both waits
      // have deadlines, so this route can no longer strand the user.
      if (auth is AuthUnknown || !onboardingFlagLoaded) {
        return loc == '/splash' ? null : '/splash';
      }

      const unauthAllowed = {
        '/onboarding',
        '/signin/phone',
        '/signin/role',
        '/signup/role',
        '/signup/driver',
        '/signup/artisan',
        '/signup/phone',
      };

      if (auth is AuthAuthenticated) {
        final consentRequiresReview =
            legalConsent?.valueOrNull?.requiresConsent == true ||
                legalConsent?.hasError == true;
        final consentExemptRoute = loc == '/legal-consent' ||
            loc.startsWith('/legal/') ||
            loc.startsWith('/active-ride') ||
            loc.startsWith('/active-job') ||
            loc.startsWith('/safety/') ||
            loc.startsWith('/account/support');
        if (consentRequiresReview &&
            !hasActiveWork &&
            legalConsent?.valueOrNull?.hasActiveWork != true &&
            !consentExemptRoute) {
          return '/legal-consent';
        }
        if (!consentRequiresReview && loc == '/legal-consent') return '/home';
        if (!loc.startsWith('/home') &&
            !loc.startsWith('/account') &&
            !loc.startsWith('/earnings') &&
            !loc.startsWith('/trips') &&
            !loc.startsWith('/active') &&
            !loc.startsWith('/ride') &&
            !loc.startsWith('/job') &&
            !loc.startsWith('/legal') &&
            !loc.startsWith('/calls') &&
            !loc.startsWith('/chat') &&
            !loc.startsWith('/messages') &&
            !loc.startsWith('/notifications') &&
            !loc.startsWith('/supplement-request') &&
            !loc.startsWith('/safety')) {
          return '/home';
        }
        return null;
      }
      if (loc.startsWith('/legal/')) return null;
      // Both roles found — force user to the role selection screen.
      if (auth is AuthRoleSelection) {
        return loc == '/signin/role' ? null : '/signin/role';
      }
      // OTP sent — force user to the OTP screen.
      if (auth is AuthOtpSent) {
        final otpRoute = auth.isNewUser ? '/signup/otp' : '/signin/otp';
        return loc == otpRoute ? null : otpRoute;
      }
      // Login was blocked because this account has an active session on
      // another device. Keep the current auth host route mounted so the
      // blocking dialog can stay visible until the user chooses takeover,
      // support, or cancel. Without this, the generic unauthenticated redirect
      // sends /signin/otp and /signin/role back to /signin/phone, destroying
      // the dialog as soon as it appears.
      if (auth is AuthBlockedByOtherDevice) {
        const blockedAllowed = {'/signin/phone', '/signin/otp', '/signin/role'};
        return blockedAllowed.contains(loc) ? null : '/signin/phone';
      }
      // AuthUnauthenticated — decide between onboarding and sign-in.
      //
      // Backing out of the OTP screen calls reset() → AuthUnauthenticated. The
      // OTP routes are deliberately NOT in unauthAllowed, so an unauthenticated
      // user is never left stranded on them; send them back to the phone step
      // that started the flow (sign-up vs sign-in) instead of a dead no-op.
      if (loc == '/signup/otp') return '/signup/phone';
      if (loc == '/signin/otp') return '/signin/phone';
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
        builder: (context, state) =>
            const ProviderPhoneInputScreen(mode: PhoneInputMode.signIn),
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
        path: '/legal-consent',
        builder: (context, state) => const LegalConsentRouteScreen(),
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
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: _ProviderHomeSwitcher()),
          ),
          GoRoute(
            path: '/earnings',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: _ProviderEarningsSwitcher()),
          ),
          GoRoute(
            path: '/trips',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: _ProviderTripsSwitcher()),
          ),
          GoRoute(
            path: '/account',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: AccountSettingsScreen()),
          ),
        ],
      ),

      // Earnings sub-pages (full-screen, no bottom nav)
      GoRoute(
        path: '/earnings/reports',
        builder: (context, state) => const EarningsReportsScreen(),
      ),

      // Account sub-pages (full-screen, no bottom nav)
      //
      // Provider profile is read-only: the former edit screens
      // (/account/edit, /account/vehicle/edit, /account/business/edit) now
      // redirect back to their view screens so deep links can't reach an
      // edit form. Profile changes are made by an admin on request.
      GoRoute(path: '/account/edit', redirect: (context, state) => '/account'),
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
          return '/account/vehicle';
        },
      ),
      GoRoute(
        path: '/account/business',
        builder: (context, state) => const BusinessInformationScreen(),
      ),
      GoRoute(
        path: '/account/business/edit',
        redirect: (context, state) => '/account/business',
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
        path: '/account/emergency-contacts',
        builder: (context, state) => const ProviderEmergencyContactsScreen(),
      ),
      GoRoute(
        path: '/account/privacy',
        builder: (context, state) => const PrivacySecurityScreen(),
      ),
      GoRoute(
        path: '/account/referrals',
        builder: (context, state) => const ProviderReferralScreen(),
      ),
      GoRoute(
        path: '/account/support',
        builder: (context, state) => const SupportLegalRouteScreen(),
        routes: [
          GoRoute(
            path: 'tickets',
            builder: (context, state) => const TicketsListRouteScreen(),
            routes: [
              GoRoute(
                path: 'new',
                builder: (context, state) {
                  final extra = state.extra is Map<String, Object?>
                      ? state.extra! as Map<String, Object?>
                      : const <String, Object?>{};
                  return NewTicketRouteScreen(
                    preselectedCategory:
                        extra['preselectedCategory'] as TicketCategory?,
                    referenceType: extra['referenceType'] as String?,
                    referenceId: extra['referenceId'] as String?,
                  );
                },
              ),
              GoRoute(
                path: ':ticketId',
                builder: (context, state) => TicketDetailRouteScreen(
                  ticketId: state.pathParameters['ticketId']!,
                ),
              ),
            ],
          ),
          GoRoute(
            path: 'search',
            builder: (context, state) => HelpSearchRouteScreen(
              initialQuery: state.uri.queryParameters['q'],
            ),
          ),
          GoRoute(
            path: 'help/:categorySlug',
            builder: (context, state) => HelpCategoryRouteScreen(
              categorySlug: state.pathParameters['categorySlug']!,
            ),
          ),
          GoRoute(
            path: 'help/article/:slug',
            builder: (context, state) =>
                HelpArticleRouteScreen(slug: state.pathParameters['slug']!),
          ),
        ],
      ),
      GoRoute(
        path: '/legal/:slug',
        builder: (context, state) =>
            LegalDocumentRouteScreen(slug: state.pathParameters['slug']!),
      ),
      GoRoute(
        path: '/account/deactivate',
        builder: (context, state) => const DeactivateAccountScreen(),
      ),

      // Artisan flow routes (full-screen, no bottom nav)
      GoRoute(
        path: '/active-job',
        builder: (context, state) => ActiveJobScreen(
          recoveryJobId: state.uri.queryParameters['jobId'],
        ),
      ),
      GoRoute(
        path: '/supplement-request',
        builder: (context, state) => const SupplementRequestScreen(),
      ),
      GoRoute(
        path: '/calls/:callId',
        builder: (context, state) => ProviderInAppCallScreen(
          callId: state.pathParameters['callId']!,
          initialSession: state.extra is AppCallSession
              ? state.extra! as AppCallSession
              : null,
        ),
      ),
      GoRoute(
        path: '/chat',
        builder: (context, state) {
          // `extra` carries the booking + peer hints. Accept the enum
          // directly OR a wire string (e.g. from a deep-link payload),
          // and tolerate omission so legacy `context.push('/chat')`
          // calls still build (they fall back to the messages-list
          // empty state).
          final extra = state.extra is Map<String, Object?>
              ? state.extra! as Map<String, Object?>
              : const <String, Object?>{};
          final raw = extra['bookingType'];
          final bookingType = raw is ChatBookingType
              ? raw
              : ChatBookingType.fromWire(raw as String?);
          return ProviderChatScreen(
            bookingType: bookingType,
            bookingId: extra['bookingId'] as String?,
            clientName: extra['peerName'] as String?,
            clientStatus: extra['peerStatus'] as String?,
            jobTitle: extra['jobTitle'] as String?,
          );
        },
      ),
      GoRoute(
        path: '/messages',
        builder: (context, state) => const MessagesListScreen(),
      ),
      GoRoute(
        path: '/notifications',
        builder: (context, state) => const ProviderNotificationsScreen(),
      ),
      GoRoute(
        path: '/safety/emergency',
        builder: (context, state) => const ProviderEmergencyScreen(),
      ),
      GoRoute(
        path: '/job-request',
        builder: (context, state) {
          final extra = state.extra;
          if (extra is Job) {
            return JobRequestScreen(job: extra);
          }
          if (extra is JobRequestRouteExtra) {
            return JobRequestScreen(
              job: extra.job,
              bidStatus: extra.bidStatus,
              submittedBidAmount: extra.submittedBidAmount,
              openBidSheet: extra.openBidSheet,
            );
          }
          // No valid payload — bounce back to home rather than render a blank.
          return const _InvalidJobRequestScreen();
        },
      ),

      // Ride flow routes (full-screen, no bottom nav)
      GoRoute(
        path: '/ride-request',
        pageBuilder: (context, state) {
          final extra = state.extra;
          if (extra is Ride) {
            return MaterialPage<void>(
              key: state.pageKey,
              child: RideRequestScreen(ride: extra),
            );
          }
          final Widget child;
          if (extra is RideRequestRouteExtra) {
            child = _RideRequestLoaderScreen(extra: extra);
          } else {
            child = const _InvalidRideRequestScreen();
          }
          return CustomTransitionPage<void>(
            key: state.pageKey,
            opaque: false,
            barrierColor: const Color(0x2E000000),
            transitionDuration: const Duration(milliseconds: 100),
            reverseTransitionDuration: const Duration(milliseconds: 80),
            transitionsBuilder: (_, animation, __, child) {
              return FadeTransition(opacity: animation, child: child);
            },
            child: child,
          );
        },
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
    _authSub = _ref.listen<AuthState>(
      authControllerProvider,
      (_, next) {
        _syncAuthenticatedDependencies(next);
        notifyListeners();
      },
    );
    _onboardingSub = _ref.listen<bool>(
      onboardingFlagLoadedProvider,
      (_, __) => notifyListeners(),
    );
    _hasSeenSub = _ref.listen<bool>(
      hasSeenOnboardingProvider,
      (_, __) => notifyListeners(),
    );
    _syncAuthenticatedDependencies(_ref.read(authControllerProvider));
  }

  final Ref _ref;
  late final ProviderSubscription<AuthState> _authSub;
  late final ProviderSubscription<bool> _onboardingSub;
  late final ProviderSubscription<bool> _hasSeenSub;
  ProviderSubscription<AsyncValue<LegalConsentStatus>>? _legalConsentSub;
  ProviderSubscription<bool>? _activeRideSub;
  ProviderSubscription<bool>? _activeJobSub;

  void _syncAuthenticatedDependencies(AuthState auth) {
    if (auth is AuthAuthenticated) {
      _legalConsentSub ??= _ref.listen<AsyncValue<LegalConsentStatus>>(
        legalConsentStatusProvider,
        (_, __) => notifyListeners(),
      );
      _activeRideSub ??= _ref.listen<bool>(
        activeRideProvider.select((state) => state.hasRide),
        (_, __) => notifyListeners(),
      );
      _activeJobSub ??= _ref.listen<bool>(
        activeJobProvider.select((state) => state.hasJob),
        (_, __) => notifyListeners(),
      );
      return;
    }

    _legalConsentSub?.close();
    _legalConsentSub = null;
    _activeRideSub?.close();
    _activeRideSub = null;
    _activeJobSub?.close();
    _activeJobSub = null;
  }

  @override
  void dispose() {
    _authSub.close();
    _onboardingSub.close();
    _hasSeenSub.close();
    _legalConsentSub?.close();
    _activeRideSub?.close();
    _activeJobSub?.close();
    super.dispose();
  }
}

/// Route payload for notification/deep-link taps where we know the ride id
/// immediately but still need to hydrate the full request details from REST.
class RideRequestRouteExtra {
  const RideRequestRouteExtra({
    required this.rideId,
    required this.navigationLatchToken,
    required this.releaseNavigationLatch,
    this.expiresAt,
  });

  final String rideId;
  final Object navigationLatchToken;
  final VoidCallback releaseNavigationLatch;
  final DateTime? expiresAt;
}

class _RideRequestLoaderScreen extends ConsumerStatefulWidget {
  const _RideRequestLoaderScreen({required this.extra});

  final RideRequestRouteExtra extra;

  @override
  ConsumerState<_RideRequestLoaderScreen> createState() =>
      _RideRequestLoaderScreenState();
}

class _RideRequestLoaderScreenState
    extends ConsumerState<_RideRequestLoaderScreen> {
  bool _showUnavailable = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _hydrate();
    });
  }

  @override
  void didUpdateWidget(covariant _RideRequestLoaderScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.extra.rideId != widget.extra.rideId ||
        oldWidget.extra.expiresAt != widget.extra.expiresAt ||
        !identical(
          oldWidget.extra.navigationLatchToken,
          widget.extra.navigationLatchToken,
        )) {
      // The callback is ownership checked by the tap bridge. If this widget is
      // being reused for a same-ride retry, releasing the old token cannot
      // clear the newer navigation claim.
      oldWidget.extra.releaseNavigationLatch();
      _hydrate();
    }
  }

  void _openRideRequest(Ride ride) {
    // Mark the request visible before replacing the loader. The loader's
    // dispose releases the navigation latch, so this ordering leaves no frame
    // where a duplicate iOS notification tap can stack the same route.
    ref.read(visibleRideRequestIdProvider.notifier).state = ride.id;
    context.pushReplacement('/ride-request', extra: ride);
  }

  Future<void> _hydrate() async {
    final generation = ++_generation;
    final startedAt = DateTime.now();
    final rideId = widget.extra.rideId;
    final deadline = widget.extra.expiresAt;

    setState(() => _showUnavailable = false);

    if (deadline != null) {
      ref.read(rideRequestDeadlineByIdProvider.notifier).update(
            (m) => {...m, rideId: deadline},
          );
      if (!_isBeforeDeadline(deadline)) {
        debugPrint('[RideRequestLoader] $rideId expired before hydrate');
        await _recoverOrShowUnavailable(startedAt, generation);
        return;
      }
    }

    final ride = await _loadFastestActionableRide(rideId);
    if (!mounted || generation != _generation) return;

    if (ride != null) {
      _openRideRequest(ride);
      return;
    }

    await _showUnavailableAfterMinimumLoading(startedAt, generation);
  }

  bool _isBeforeDeadline(DateTime deadline) {
    return DateTime.now().toUtc().isBefore(deadline.toUtc());
  }

  Future<Ride?> _loadFastestActionableRide(String rideId) {
    final completer = Completer<Ride?>();
    var remaining = 2;

    void completeIfDone() {
      remaining -= 1;
      if (remaining <= 0 && !completer.isCompleted) {
        completer.complete(null);
      }
    }

    void track(String source, Future<Ride?> future) {
      unawaited(
        future.then((ride) {
          if (ride != null && !completer.isCompleted) {
            debugPrint('[RideRequestLoader] $rideId hydrated from $source');
            completer.complete(ride);
          }
        }).catchError((Object e) {
          debugPrint(
              '[RideRequestLoader] $source hydrate failed for $rideId: $e');
        }).whenComplete(completeIfDone),
      );
    }

    track('ride snapshot', _fetchRideSnapshot(rideId));
    track('pending request', recoverPendingRideRequestById(ref, rideId));

    return completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        debugPrint('[RideRequestLoader] hydrate timed out for $rideId');
        return null;
      },
    );
  }

  Future<Ride?> _fetchRideSnapshot(String rideId) async {
    final data = await ref
        .read(rideServiceProvider)
        .getRide(rideId)
        .timeout(const Duration(seconds: 8));
    final ride = Ride.fromJson(data);
    if (ride.status == RideStatus.requested) return ride;
    debugPrint(
      '[RideRequestLoader] $rideId no longer actionable '
      '(status=${ride.status.toJson()})',
    );
    return null;
  }

  Future<void> _recoverOrShowUnavailable(
    DateTime startedAt,
    int generation,
  ) async {
    final ride = await recoverPendingRideRequest(ref);
    if (!mounted || generation != _generation) return;

    if (ride != null) {
      _openRideRequest(ride);
      return;
    }

    await _showUnavailableAfterMinimumLoading(startedAt, generation);
  }

  Future<void> _showUnavailableAfterMinimumLoading(
    DateTime startedAt,
    int generation,
  ) async {
    final elapsed = DateTime.now().difference(startedAt);
    const minimumLoading = Duration(milliseconds: 700);
    if (elapsed < minimumLoading) {
      await Future<void>.delayed(minimumLoading - elapsed);
    }
    if (mounted && generation == _generation) {
      // A failed/terminal hydrate must not block a deliberate retry for the
      // remainder of the 30-second offer. The timeout fallback in the tap
      // bridge is only for cases where this loader never mounts.
      widget.extra.releaseNavigationLatch();
      setState(() => _showUnavailable = true);
    }
  }

  @override
  void dispose() {
    widget.extra.releaseNavigationLatch();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _RideRequestOpeningScaffold(showUnavailable: _showUnavailable);
  }
}

class _InvalidRideRequestScreen extends ConsumerStatefulWidget {
  const _InvalidRideRequestScreen();

  @override
  ConsumerState<_InvalidRideRequestScreen> createState() =>
      _InvalidRideRequestScreenState();
}

class _InvalidRideRequestScreenState
    extends ConsumerState<_InvalidRideRequestScreen> {
  bool _showUnavailable = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _recover();
    });
  }

  Future<void> _recover() async {
    final startedAt = DateTime.now();
    final ride = await recoverPendingRideRequest(ref);
    if (!mounted) return;

    if (ride != null) {
      context.pushReplacement('/ride-request', extra: ride);
      return;
    }

    // Avoid a jarring flash of "unavailable" during notification cold-start
    // handoff. FCM tap hydration often wins within a few hundred milliseconds;
    // keep this screen in a neutral loading state until that race settles.
    final elapsed = DateTime.now().difference(startedAt);
    const minimumLoading = Duration(milliseconds: 700);
    if (elapsed < minimumLoading) {
      await Future<void>.delayed(minimumLoading - elapsed);
    }
    if (mounted) setState(() => _showUnavailable = true);
  }

  @override
  Widget build(BuildContext context) {
    return _RideRequestOpeningScaffold(showUnavailable: _showUnavailable);
  }
}

class _RideRequestOpeningScaffold extends StatelessWidget {
  const _RideRequestOpeningScaffold({required this.showUnavailable});

  final bool showUnavailable;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xF0FFFFFF),
                borderRadius: BorderRadius.circular(24),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x22000000),
                    blurRadius: 24,
                    offset: Offset(0, 12),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 22,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (showUnavailable)
                      const Icon(
                        Icons.local_taxi_outlined,
                        color: MyShopColors.warning,
                        size: 44,
                      )
                    else
                      const SizedBox(
                        width: 36,
                        height: 36,
                        child: CircularProgressIndicator(strokeWidth: 3),
                      ),
                    const SizedBox(height: 14),
                    Text(
                      showUnavailable ? 'Request expired' : 'Please wait…',
                      style: MyShopTypography.h3,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      showUnavailable
                          ? 'This request has expired or was assigned already.'
                          : 'Fetching the latest request details.',
                      style: MyShopTypography.body2.copyWith(
                        color: MyShopColors.textSecondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if (showUnavailable) ...[
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: () => context.go('/home'),
                        child: const Text('Back to home'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
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

/// Renders the artisan "My Jobs" list under the third tab slot, while
/// drivers keep their trips history. Lets us share one shell route for
/// both roles. (Artisans can still open chat via /messages.)
class _ProviderTripsSwitcher extends ConsumerWidget {
  const _ProviderTripsSwitcher();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final type = ref.watch(providerTypeProvider);
    return type.isArtisan
        ? const ArtisanJobsScreen()
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
class _DriverShell extends ConsumerStatefulWidget {
  const _DriverShell({required this.child});

  final Widget child;

  @override
  ConsumerState<_DriverShell> createState() => _DriverShellState();
}

class _DriverShellState extends ConsumerState<_DriverShell>
    with WidgetsBindingObserver {
  static const _tabs = ['/home', '/earnings', '/trips', '/account'];

  String? _lastVerificationRefreshLocation;
  bool _verificationRefreshQueued = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scheduleVerificationRefresh(force: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _scheduleVerificationRefresh(force: true);
    }
  }

  int _currentIndex(String location) {
    final index = _tabs.indexWhere((t) => location.startsWith(t));
    return index >= 0 ? index : 0;
  }

  void _onTabTap(BuildContext context, String path) {
    ref.read(navBadgeProvider.notifier).clear(path);
    final location = GoRouterState.of(context).uri.path;
    if (location == path) {
      _scheduleVerificationRefresh(force: true);
    }
    context.go(path);
  }

  void _scheduleVerificationRefresh({String? location, bool force = false}) {
    if (!force &&
        location != null &&
        _lastVerificationRefreshLocation == location) {
      return;
    }
    if (location != null) {
      _lastVerificationRefreshLocation = location;
    }
    if (_verificationRefreshQueued) return;

    _verificationRefreshQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _verificationRefreshQueued = false;
      if (!mounted) return;

      // Admin-side document/photo decisions happen out-of-band from the
      // provider app. Refresh the shared verification snapshot whenever a
      // provider enters a main tab or resumes the app, so approved profile
      // photos and document statuses appear without visiting Documents first.
      ref.invalidate(verificationStatusProvider);
      unawaited(
        ref
            .read(verificationStatusProvider.future)
            .then<void>((_) {})
            .catchError((_) {}),
      );

      // Keep role verification chips/profile fields fresh as well. This call
      // is intentionally fire-and-forget; auth_controller swallows profile
      // refresh failures and keeps the current session intact.
      unawaited(
        ref
            .read(authControllerProvider.notifier)
            .refreshProfile()
            .then<void>((_) {})
            .catchError((_) {}),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    // Activate the Socket.IO connection manager — connects/disconnects
    // automatically when the provider toggles online/offline.
    ref.watch(socketConnectionProvider);

    // Pipe GPS updates into the socket so the backend can match this
    // provider against incoming jobs/rides within their service radius.
    ref.watch(locationSocketBridgeProvider);

    // Durable REST location sync — keeps online heartbeats and active-trip
    // trails alive when the app is backgrounded and the socket is disconnected.
    ref.watch(backgroundLocationSyncProvider);

    // REST-polling fallback for incoming jobs — covers zombie sockets
    // and missed `job:new` emits. Deduped against the socket path.
    ref.watch(jobPollerProvider);

    // Online-session accumulator — every offline transition writes the
    // session length into a per-day SharedPreferences bucket so the
    // home-screen "HOURS" stat reflects today's real total.
    ref.watch(onlineSessionRecorderProvider);

    final location = GoRouterState.of(context).uri.path;
    _scheduleVerificationRefresh(location: location);

    final currentIndex = _currentIndex(location);
    final isArtisan = ref.watch(providerTypeProvider).isArtisan;
    final badges = ref.watch(navBadgeProvider);

    return Scaffold(
      body: IncomingRequestListener(child: widget.child),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Color(0xF2FFFFFF),
          border: Border(
            top: BorderSide(color: MyShopColors.divider, width: 0.5),
          ),
          boxShadow: [
            BoxShadow(
              color: Color(0x0D000000),
              blurRadius: 10,
              offset: Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 64,
            child: Row(
              children: isArtisan
                  ? [
                      _NavTab(
                        icon: Icons.work_outline,
                        label: 'Jobs',
                        isActive: currentIndex == 0,
                        badgeCount: badges['/home'],
                        onTap: () => _onTabTap(context, '/home'),
                      ),
                      _NavTab(
                        icon: Icons.account_balance_wallet_outlined,
                        label: 'Earnings',
                        isActive: currentIndex == 1,
                        badgeCount: badges['/earnings'],
                        onTap: () => _onTabTap(context, '/earnings'),
                      ),
                      _NavTab(
                        icon: Icons.assignment_outlined,
                        label: 'My Jobs',
                        isActive: currentIndex == 2,
                        badgeCount: badges['/trips'],
                        onTap: () => _onTabTap(context, '/trips'),
                      ),
                      _NavTab(
                        icon: Icons.account_circle_outlined,
                        label: 'Account',
                        isActive: currentIndex == 3,
                        badgeCount: badges['/account'],
                        onTap: () => _onTabTap(context, '/account'),
                      ),
                    ]
                  : [
                      _NavTab(
                        icon: Icons.dashboard_outlined,
                        label: 'Home',
                        isActive: currentIndex == 0,
                        badgeCount: badges['/home'],
                        onTap: () => _onTabTap(context, '/home'),
                      ),
                      _NavTab(
                        icon: Icons.account_balance_wallet_outlined,
                        label: 'Earnings',
                        isActive: currentIndex == 1,
                        badgeCount: badges['/earnings'],
                        onTap: () => _onTabTap(context, '/earnings'),
                      ),
                      _NavTab(
                        icon: Icons.history,
                        label: 'Trips',
                        isActive: currentIndex == 2,
                        badgeCount: badges['/trips'],
                        onTap: () => _onTabTap(context, '/trips'),
                      ),
                      _NavTab(
                        icon: Icons.account_circle_outlined,
                        label: 'Account',
                        isActive: currentIndex == 3,
                        badgeCount: badges['/account'],
                        onTap: () => _onTabTap(context, '/account'),
                      ),
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
    final color =
        isActive ? MyShopColors.primaryGold : MyShopColors.textSecondary;

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (badgeCount != null && badgeCount! > 0)
              Badge(
                label: Text(
                  '$badgeCount',
                  style: const TextStyle(fontSize: 8, color: Colors.white),
                ),
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

/// Route payload for the `/job-request` screen when we need to carry a job
/// alongside post-submission bid state (e.g. after the bid sheet closes).
class JobRequestRouteExtra {
  const JobRequestRouteExtra({
    required this.job,
    required this.bidStatus,
    this.submittedBidAmount = 0,
    this.openBidSheet = false,
  });

  final Job job;
  final BidStatus bidStatus;
  final num submittedBidAmount;
  final bool openBidSheet;
}

/// Fallback rendered when `/job-request` is navigated to without a valid
/// payload. Offers a way back rather than showing a blank screen.
class _InvalidJobRequestScreen extends StatelessWidget {
  const _InvalidJobRequestScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Request Details'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/home'),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 12),
              const Text(
                'No request data.',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
              const SizedBox(height: 8),
              const Text(
                'This request is no longer available or was opened without '
                'a valid link.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => context.go('/home'),
                child: const Text('Go home'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
