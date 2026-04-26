import 'package:api_client/api_client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  );
});

final clientAuthControllerProvider =
    StateNotifierProvider<ClientAuthController, ClientAuthState>((ref) {
  final controller = ClientAuthController(
    ref.watch(clientAuthRepositoryProvider),
  );
  controller.bootstrap();
  return controller;
});

final hasSeenOnboardingProvider = StateProvider<bool>((_) => false);

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
      debugPrint('[Auth] submitPhone: normalized phone = "$phone"');
      // Attempt to send OTP directly. If a client account exists, OTP is sent.
      // If not, the backend returns a 404 and we redirect to sign-up.
      // (We don't rely on /auth/check-phone's role list because it may be
      // stale — it can omit 'client' even when a client account exists.)
      await _repo.loginClient(phone);
      state = AuthOtpSent(phone: phone, isNewUser: false);
    } on ApiException catch (e) {
      debugPrint(
          '[Auth] loginClient ApiException: '
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

  /// Resend OTP.
  Future<void> resendOtp() async {
    final current = state;
    if (current is! AuthOtpSent) return;
    try {
      await _repo.loginClient(current.phone);
    } catch (_) {
      // Silently fail — user can tap again
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

  Future<void> logout() async {
    await _repo.clear();
    state = const AuthUnauthenticated();
  }
}
