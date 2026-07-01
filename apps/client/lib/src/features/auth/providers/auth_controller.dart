import 'package:api_client/api_client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/di/force_logout_handler.dart';
import '../../../core/di/providers.dart';
import '../data/auth_repository.dart';

// ---------------------------------------------------------------------------
// Auth states
// ---------------------------------------------------------------------------

sealed class ClientAuthState {
  const ClientAuthState();
}

/// Initial state while checking for stored tokens.
class AuthUnknown extends ClientAuthState {
  const AuthUnknown();
}

/// No valid session — show login / onboarding.
class AuthUnauthenticated extends ClientAuthState {
  const AuthUnauthenticated({
    this.error,
    this.fieldErrors = const {},
    this.isLoading = false,
  });

  final String? error;
  final Map<String, String> fieldErrors;
  final bool isLoading;
}

/// Phone not found — user needs to register. Show sign-up screen.
class AuthNeedsRegistration extends ClientAuthState {
  const AuthNeedsRegistration({
    required this.phone,
    this.error,
    this.message,
    this.isLoading = false,
  });

  final String phone;
  final String? error;

  /// Non-error info message shown at the top (e.g. "No account found").
  final String? message;
  final bool isLoading;
}

/// OTP has been sent. Waiting for user input.
class AuthOtpSent extends ClientAuthState {
  const AuthOtpSent({
    required this.phone,
    required this.isNewUser,
    this.error,
    this.isVerifying = false,
  });

  final String phone;
  final bool isNewUser;
  final String? error;
  final bool isVerifying;
}

/// Backend rejected the login because the same account has an active
/// session on another device. The UI shows a hard-block dialog (no
/// "Continue here" / force-takeover option). The user must either sign
/// out on the other device or tap "Contact support" to request a
/// session recovery from an admin.
class AuthBlockedByOtherDevice extends ClientAuthState {
  const AuthBlockedByOtherDevice({
    required this.phone,
    this.recoveryRequestStatus = RecoveryRequestStatus.idle,
    this.isTakingOver = false,
    this.takeoverError,
  });

  final String phone;

  /// Tracks the in-flight state of the "request session recovery" call so
  /// the dialog can show a spinner / success / failure.
  final RecoveryRequestStatus recoveryRequestStatus;

  /// True while the takeover-via-OTP retry of the login call is in flight,
  /// so the dialog button can show a spinner.
  final bool isTakingOver;

  /// Surface for a takeover failure (network error, etc).
  final String? takeoverError;
}

/// State of the support-recovery request fired from the block dialog.
enum RecoveryRequestStatus { idle, sending, sent, failed }

/// Fully authenticated with a loaded user profile.
class AuthAuthenticated extends ClientAuthState {
  const AuthAuthenticated(this.profile);
  final UserProfile profile;
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

final authServiceProvider = Provider<AuthService>((ref) {
  return ref.watch(realAuthServiceProvider);
});

final tokenStorageProvider = Provider<TokenStorage>((ref) {
  return ref.watch(appTokenStorageProvider);
});

final clientAuthRepositoryProvider = Provider<ClientAuthRepository>((ref) {
  return ClientAuthRepository(
    service: ref.watch(authServiceProvider),
    tokenStorage: ref.watch(tokenStorageProvider),
    deviceIdProvider: ref.watch(deviceIdProvider),
  );
});

final clientOtpChannelsProvider =
    FutureProvider.autoDispose<List<String>>((ref) {
  return ref.watch(clientAuthRepositoryProvider).getOtpChannels();
});

final clientAuthControllerProvider =
    StateNotifierProvider<ClientAuthController, ClientAuthState>((ref) {
  final controller = ClientAuthController(
    ref.watch(clientAuthRepositoryProvider),
  );
  // Register with the Dio interceptor's force-logout dispatcher so that
  // SESSION_TAKEN_OVER / TOKEN_EXPIRED / etc. flip the controller to
  // unauthenticated and the router redirects to sign-in.
  ref
      .read(forceLogoutHandlerProvider)
      .register(controller.onForceLogoutFromInterceptor);
  controller.bootstrap();
  return controller;
});

final hasSeenOnboardingProvider = StateProvider<bool>((_) => false);

/// True once the persisted onboarding preference has either loaded or hit
/// its startup deadline. The router keeps the Flutter splash visible until
/// then, preventing a returning user from briefly flashing the onboarding
/// screen while secure storage is still opening.
final onboardingFlagLoadedProvider = StateProvider<bool>((_) => false);

/// Mirrors the SharedPreferences `app_pref_replay_onboarding` flag. The
/// AppPreferences screen sets it to true; the router redirects authenticated
/// users to /onboarding while it's true; the OnboardingScreen clears it
/// (and SharedPrefs) on completion so the next app open lands on home.
///
/// Top-level (not autoDispose) so the router redirect can read it on every
/// navigation without forcing the prefs notifier to stay mounted.
final pendingReplayOnboardingProvider = StateProvider<bool>((_) => false);

Future<void> loadOnboardingFlag(ProviderContainer container) async {
  final storage = container.read(tokenStorageProvider);
  final seen = await storage.hasSeenOnboarding();
  container.read(hasSeenOnboardingProvider.notifier).state = seen;

  // Also hydrate the one-shot replay flag from SharedPreferences.
  final prefs = await SharedPreferences.getInstance();
  final replay = prefs.getBool('app_pref_replay_onboarding') ?? false;
  container.read(pendingReplayOnboardingProvider.notifier).state = replay;
}

// ---------------------------------------------------------------------------
// Controller
// ---------------------------------------------------------------------------

class ClientAuthController extends StateNotifier<ClientAuthState> {
  ClientAuthController(this._repo) : super(const AuthUnknown());

  final ClientAuthRepository _repo;
  bool _requesting = false;

  /// Try to restore session from stored tokens.
  Future<void> bootstrap() async {
    try {
      final profile = await _repo
          .bootstrap()
          .timeout(const Duration(seconds: 8), onTimeout: () => null);
      if (profile != null) {
        state = AuthAuthenticated(profile);
      } else {
        state = const AuthUnauthenticated();
      }
    } catch (_) {
      state = const AuthUnauthenticated();
    }
  }

  /// Step 1: Phone input screen calls this.
  /// Checks if a client account exists for this phone, then routes accordingly.
  Future<void> submitPhone({required String phone}) async {
    if (_requesting) return;
    _requesting = true;
    state = const AuthUnauthenticated(isLoading: true);
    try {
      if (kDebugMode) {
        debugPrint('[Auth] submitPhone called with a normalized phone number');
      }
      // Attempt to send OTP directly. If a client account exists, OTP is sent.
      // If not, the backend returns a 404 and we redirect to sign-up.
      // (We don't rely on /auth/check-phone's role list because it may be
      // stale — it can omit 'client' even when a client account exists.)
      await _repo.loginClient(phone);
      state = AuthOtpSent(phone: phone, isNewUser: false);
    } on ApiException catch (e) {
      debugPrint('[Auth] loginClient ApiException: '
          'status=${e.statusCode} code=${e.errorCode} msg=${e.message}');
      // Backend returns 404 / USER_NOT_FOUND / CLIENT_PROFILE_NOT_FOUND when
      // the phone has no client account yet — redirect to registration.
      if (e.errorCode == 'ACCOUNT_NOT_FOUND' ||
          e.errorCode == 'USER_NOT_FOUND' ||
          e.errorCode == 'PHONE_NOT_FOUND' ||
          e.errorCode == 'CLIENT_PROFILE_NOT_FOUND' ||
          e.statusCode == 404) {
        await _showNotFoundThenRegister(
          phone: phone,
          message: 'No account found for this number. Sign up to get started.',
        );
      } else if (e.errorCode == AuthErrorCodes.alreadyLoggedInElsewhere) {
        state = AuthBlockedByOtherDevice(phone: phone);
      } else {
        state = AuthUnauthenticated(
          error: AuthErrorMapper.message(e),
          fieldErrors: AuthErrorMapper.fieldErrors(e),
        );
      }
    } on AuthException catch (e) {
      // AuthException from mock service also means not found
      if (e.code == 'USER_NOT_FOUND' || e.code == 'ACCOUNT_NOT_FOUND') {
        state = AuthNeedsRegistration(phone: phone);
      } else {
        state = AuthUnauthenticated(error: e.message);
      }
    } catch (_) {
      state = const AuthUnauthenticated(
        error: 'Something went wrong. Please try again.',
      );
    } finally {
      _requesting = false;
    }
  }

  /// Show error on the phone screen for 2 seconds, then navigate to sign-up.
  Future<void> _showNotFoundThenRegister({
    required String phone,
    required String message,
  }) async {
    // Brief error on the sign-in screen so the user sees feedback
    state = AuthUnauthenticated(error: message);
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    state = AuthNeedsRegistration(phone: phone, message: message);
  }

  /// Sign-up screen calls this.
  /// POST /auth/register with type: "client".
  Future<void> register({
    required String phone,
    required String fullName,
    String? email,
    String? referralCode,
  }) async {
    if (_requesting) return;
    _requesting = true;
    state = AuthNeedsRegistration(phone: phone, isLoading: true);
    try {
      await _repo.register(
        phone: phone,
        fullName: fullName,
        privacyPolicyAccepted: true,
        email: email,
        referralCode: referralCode,
      );
      state = AuthOtpSent(phone: phone, isNewUser: true);
    } on ApiException catch (e) {
      // If already registered, try login instead
      if (e.errorCode == 'PHONE_ALREADY_REGISTERED' ||
          e.errorCode == 'USER_ALREADY_EXISTS') {
        try {
          await _repo.loginClient(phone);
          state = AuthOtpSent(phone: phone, isNewUser: false);
        } on ApiException catch (loginError) {
          state = AuthNeedsRegistration(
            phone: phone,
            error: AuthErrorMapper.message(loginError),
          );
        }
      } else {
        state = AuthNeedsRegistration(
          phone: phone,
          error: AuthErrorMapper.message(e),
        );
      }
    } on AuthException catch (e) {
      state = AuthNeedsRegistration(phone: phone, error: e.message);
    } catch (_) {
      state = AuthNeedsRegistration(
        phone: phone,
        error: 'Could not create account. Please try again.',
      );
    } finally {
      _requesting = false;
    }
  }

  /// Verify OTP code → fetch profile → authenticated.
  Future<void> verifyOtp(String code) async {
    final current = state;
    if (current is! AuthOtpSent) return;

    state = AuthOtpSent(
      phone: current.phone,
      isNewUser: current.isNewUser,
      isVerifying: true,
    );

    try {
      await _repo.verifyOtp(phone: current.phone, code: code);
      final profile = await _repo.fetchProfile();
      // markOnboardingSeen() is fired from OnboardingScreen._finish, not
      // here — verifying OTP doesn't mean the user has been shown the
      // tutorial yet. Authenticated users without the seen flag get
      // routed to /onboarding by the router redirect.
      state = AuthAuthenticated(profile);
    } on ApiException catch (e) {
      state = AuthOtpSent(
        phone: current.phone,
        isNewUser: current.isNewUser,
        error: AuthErrorMapper.message(e),
      );
    } on AuthException catch (e) {
      state = AuthOtpSent(
        phone: current.phone,
        isNewUser: current.isNewUser,
        error: e.message,
      );
    } catch (e) {
      state = AuthOtpSent(
        phone: current.phone,
        isNewUser: current.isNewUser,
        error: 'Verification failed. Please try again.',
      );
    }
  }

  /// Re-deliver the active OTP without issuing a new code.
  Future<void> resendOtp({String channel = 'sms'}) async {
    final current = state;
    if (current is! AuthOtpSent) return;
    try {
      await _repo.resendOtp(phone: current.phone, channel: channel);
      // Success — clear any prior error so the screen reflects the new send.
      state = AuthOtpSent(phone: current.phone, isNewUser: current.isNewUser);
    } on ApiException catch (e) {
      // Surface cooldown / daily-cap / send failures. Previously swallowed, so
      // the user saw nothing and no code arrived (OTP_COOLDOWN, OTP_DAILY_LIMIT).
      state = AuthOtpSent(
        phone: current.phone,
        isNewUser: current.isNewUser,
        error: AuthErrorMapper.message(e),
      );
    } catch (_) {
      state = AuthOtpSent(
        phone: current.phone,
        isNewUser: current.isNewUser,
        error: 'Could not resend the code. Please try again.',
      );
    }
  }

  /// Clear any error from the current state.
  void clearError() {
    final current = state;
    if (current is AuthUnauthenticated && current.error != null) {
      state = const AuthUnauthenticated();
    } else if (current is AuthNeedsRegistration && current.error != null) {
      state = AuthNeedsRegistration(phone: current.phone);
    } else if (current is AuthOtpSent && current.error != null) {
      state = AuthOtpSent(
        phone: current.phone,
        isNewUser: current.isNewUser,
      );
    }
  }

  /// Re-fetch the user profile.
  Future<String?> refreshProfile() async {
    if (state is! AuthAuthenticated) return 'Not authenticated';
    try {
      final profile = await _repo.fetchProfile();
      state = AuthAuthenticated(profile);
      return null;
    } catch (_) {
      return 'Failed to refresh profile.';
    }
  }

  /// Update the user's profile.
  Future<String?> updateProfile(UpdateProfileRequest request) async {
    if (state is! AuthAuthenticated) return 'Not authenticated';
    try {
      final updated = await _repo.updateProfile(request);
      state = AuthAuthenticated(updated);
      return null;
    } on ApiException catch (e) {
      return AuthErrorMapper.message(e);
    } catch (_) {
      return 'Failed to update profile. Please try again.';
    }
  }

  /// Go back to phone input from sign-up screen.
  void backToPhoneInput() {
    state = const AuthUnauthenticated();
  }

  void reset() {
    state = const AuthUnauthenticated();
  }

  /// User-initiated logout: revokes the refresh token server-side, then
  /// wipes local state.
  Future<void> logout() async {
    await _repo.logout();
    state = const AuthUnauthenticated();
  }

  /// User dismisses the "already signed in elsewhere" block dialog.
  /// Returns to the phone-input screen so they can try a different number
  /// or come back later.
  void dismissBlockedLogin() {
    if (state is AuthBlockedByOtherDevice) {
      state = const AuthUnauthenticated();
    }
  }

  /// User tapped "Contact support" on the block dialog. Fires the
  /// admin-alert endpoint with the blocked phone + this device's deviceId.
  /// Updates [AuthBlockedByOtherDevice.recoveryRequestStatus] so the
  /// dialog can show progress + outcome.
  Future<void> requestSessionRecovery() async {
    final current = state;
    if (current is! AuthBlockedByOtherDevice) return;
    if (current.recoveryRequestStatus == RecoveryRequestStatus.sending) return;
    state = AuthBlockedByOtherDevice(
      phone: current.phone,
      recoveryRequestStatus: RecoveryRequestStatus.sending,
    );
    try {
      await _repo.requestSessionRecovery(current.phone);
      state = AuthBlockedByOtherDevice(
        phone: current.phone,
        recoveryRequestStatus: RecoveryRequestStatus.sent,
      );
    } catch (_) {
      state = AuthBlockedByOtherDevice(
        phone: current.phone,
        recoveryRequestStatus: RecoveryRequestStatus.failed,
      );
    }
  }

  /// User tapped "Sign me in here, sign out the other device" on the block
  /// dialog. Re-fires `loginClient` with `forceLogin: true` so the backend
  /// skips the single-device check; the verifyOtp step then revokes the
  /// prior session as part of the takeover.
  ///
  /// On success the state machine transitions to [AuthOtpSent] (the
  /// router/dialog listener pops the dialog and routes to the OTP screen
  /// automatically). On failure we stay in [AuthBlockedByOtherDevice]
  /// with [takeoverError] set so the dialog can surface the message.
  Future<void> forceTakeover() async {
    final current = state;
    if (current is! AuthBlockedByOtherDevice) return;
    if (current.isTakingOver) return;
    state = AuthBlockedByOtherDevice(
      phone: current.phone,
      recoveryRequestStatus: current.recoveryRequestStatus,
      isTakingOver: true,
    );
    try {
      await _repo.loginClient(current.phone, forceLogin: true);
      state = AuthOtpSent(phone: current.phone, isNewUser: false);
    } on ApiException catch (e) {
      state = AuthBlockedByOtherDevice(
        phone: current.phone,
        recoveryRequestStatus: current.recoveryRequestStatus,
        takeoverError: e.message,
      );
    } catch (_) {
      state = AuthBlockedByOtherDevice(
        phone: current.phone,
        recoveryRequestStatus: current.recoveryRequestStatus,
        takeoverError: 'Could not sign in. Please try again.',
      );
    }
  }

  /// Called by the Dio interceptor after it has decided the session is
  /// dead and already wiped tokens from secure storage. Just flips the
  /// state machine — no token clearing here.
  ///
  /// Transitions from any state EXCEPT [AuthUnauthenticated] (where we'd
  /// just clobber an existing field-level error). Critical that this also
  /// fires for [AuthUnknown] — without that, a session that died while
  /// the app was force-quit gets bounced from /users/me on bootstrap, the
  /// interceptor wipes tokens, but the UI stays stuck on splash.
  void onForceLogoutFromInterceptor() {
    if (state is AuthUnauthenticated) return;
    state = const AuthUnauthenticated(
      error: 'Your session ended. Please sign in again.',
    );
  }
}
