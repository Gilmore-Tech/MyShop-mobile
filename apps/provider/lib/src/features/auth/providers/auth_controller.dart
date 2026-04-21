import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../profile/providers/provider_type_provider.dart';
import '../data/auth_repository.dart';

// ---------------------------------------------------------------------------
// Auth states
// ---------------------------------------------------------------------------

/// Discriminated auth state. The router redirects on these.
sealed class AuthState {
  const AuthState();
}

/// Initial state while checking for stored tokens.
class AuthUnknown extends AuthState {
  const AuthUnknown();
}

/// No valid session — show login / onboarding.
class AuthUnauthenticated extends AuthState {
  const AuthUnauthenticated({
    this.error,
    this.fieldErrors = const {},
    this.isLoading = false,
  });

  final String? error;

  /// Per-field errors from backend validation (e.g. {"phone": "invalid"}).
  final Map<String, String> fieldErrors;

  /// True while an API call (register/login) is in flight.
  final bool isLoading;
}

/// Phone has both roles — user must pick which to sign in as.
class AuthRoleSelection extends AuthState {
  const AuthRoleSelection({
    required this.phone,
    required this.roles,
    this.isLoading = false,
    this.error,
  });

  final String phone;
  final List<String> roles;
  final bool isLoading;
  final String? error;
}

/// OTP has been sent (via register or login). Waiting for user input.
class AuthOtpSent extends AuthState {
  const AuthOtpSent({
    required this.phone,
    required this.isNewUser,
    this.role,
    this.error,
    this.isVerifying = false,
  });

  final String phone;
  final bool isNewUser;
  final ProviderType? role;
  final String? error;
  final bool isVerifying;
}

/// Fully authenticated with a loaded user profile.
class AuthAuthenticated extends AuthState {
  const AuthAuthenticated(this.user);
  final AuthUser user;
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

/// Provides the configured [AuthService] implementation.
/// Override this in main.dart or tests to swap between mock/real.
final authServiceProvider = Provider<AuthService>((ref) {
  // Default to mock — overridden at app startup for real backend
  return MockAuthService();
});

/// Provides the [TokenStorage] used for persisting auth tokens.
final tokenStorageProvider = Provider<TokenStorage>((ref) {
  return SecureTokenStorage();
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    service: ref.watch(authServiceProvider),
    tokenStorage: ref.watch(tokenStorageProvider),
  );
});

final authControllerProvider =
    StateNotifierProvider<AuthController, AuthState>((ref) {
  final controller = AuthController(
    ref.watch(authRepositoryProvider),
    tokenStorage: ref.watch(tokenStorageProvider),
    onAuthenticated: (AuthUser user, ProviderType? intendedRole) {
      // Mark onboarding as seen whenever a user successfully authenticates.
      final storage = ref.read(tokenStorageProvider);
      storage.markOnboardingSeen();
      ref.read(hasSeenOnboardingProvider.notifier).state = true;
      // Use the intended role if provided (sign-up/sign-in choice).
      // When intendedRole is null (e.g. refreshProfile, updateProfile),
      // preserve the current role — never override it from backend data,
      // as that causes artisan→driver leakage for dual-role accounts.
      if (intendedRole != null) {
        ref.read(providerTypeProvider.notifier).state = intendedRole;
        // Persist so bootstrap restores the correct role after restart
        storage.writeRole(intendedRole.name);
      }
    },
  );
  controller.bootstrap();
  return controller;
});

/// Whether this device has seen the onboarding/welcome screen before.
/// Survives logout — returning users skip onboarding and go straight to login.
///
/// Loaded eagerly at app startup via [loadOnboardingFlag]. Updated to `true`
/// whenever the user reaches [AuthAuthenticated] or interacts with the
/// onboarding screen.
final hasSeenOnboardingProvider = StateProvider<bool>((_) => false);

/// Call once at app startup (before runApp) to hydrate [hasSeenOnboardingProvider].
Future<void> loadOnboardingFlag(ProviderContainer container) async {
  final storage = container.read(tokenStorageProvider);
  final seen = await storage.hasSeenOnboarding();
  container.read(hasSeenOnboardingProvider.notifier).state = seen;
}

// ---------------------------------------------------------------------------
// Controller
// ---------------------------------------------------------------------------

class AuthController extends StateNotifier<AuthState> {
  AuthController(
    this._repo, {
    this.onAuthenticated,
    required TokenStorage tokenStorage,
  })  : _tokenStorage = tokenStorage,
        super(const AuthUnknown());

  final AuthRepository _repo;
  final TokenStorage _tokenStorage;

  /// Called when authentication succeeds. [intendedRole] is the role the user
  /// chose during sign-up or sign-in (from [AuthOtpSent.role]). When restoring
  /// a session via [bootstrap], it is null — derive from the profile instead.
  final void Function(AuthUser user, ProviderType? intendedRole)?
      onAuthenticated;
  bool _requesting = false;

  /// Try to restore session from stored tokens.
  ///
  /// Hydrates from the locally cached profile so the UI is unblocked even on
  /// a cold start with no network. Then kicks off a background `/users/me`
  /// refresh to pull the latest data — failures are intentionally swallowed
  /// (only the 401 interceptor may force a logout).
  Future<void> bootstrap() async {
    try {
      final user = await _repo.bootstrap();
      if (user != null) {
        final savedRole = await _tokenStorage.readRole();
        final restoredRole = savedRole != null
            ? ProviderType.values.where((e) => e.name == savedRole).firstOrNull
            : null;
        onAuthenticated?.call(user, restoredRole);
        state = AuthAuthenticated(user);
        unawaited(_refreshInBackground());
      } else {
        state = const AuthUnauthenticated();
      }
    } catch (_) {
      state = const AuthUnauthenticated();
    }
  }

  Future<void> _refreshInBackground() async {
    final fresh = await _repo.refreshProfileQuiet();
    if (fresh != null && state is AuthAuthenticated) {
      state = AuthAuthenticated(fresh);
    }
  }

  /// Sign-up flow: register a new account → OTP sent.
  Future<void> registerAndSendOtp({
    required String phone,
    required String fullName,
    required String type,
    required bool privacyPolicyAccepted,
    ProviderType? role,
    String? displayName,
    String? businessName,
    String? email,
    List<String>? categories,
    String? shopCapacity,
  }) async {
    if (_requesting) return;
    _requesting = true;
    state = const AuthUnauthenticated(isLoading: true);
    try {
      await _repo.register(RegisterRequest(
        phone: phone,
        fullName: fullName,
        type: type,
        privacyPolicyAccepted: privacyPolicyAccepted,
        displayName: displayName,
        businessName: businessName,
        email: email,
        categories: categories,
        shopCapacity: shopCapacity,
      ));
      state = AuthOtpSent(phone: phone, isNewUser: true, role: role);
    } on ApiException catch (e) {
      state = AuthUnauthenticated(
        error: AuthErrorMapper.message(e),
        fieldErrors: AuthErrorMapper.fieldErrors(e),
      );
    } on AuthException catch (e) {
      state = AuthUnauthenticated(error: e.message);
    } catch (_) {
      state = const AuthUnauthenticated(
        error: 'Could not create account. Please try again.',
      );
    } finally {
      _requesting = false;
    }
  }

  /// Sign-in step 1: check which roles this phone has.
  /// - Single role → auto-sends OTP via the role-specific login endpoint.
  /// - Both roles → transitions to [AuthRoleSelection] for user to pick.
  Future<void> checkPhoneAndLogin({required String phone}) async {
    if (_requesting) return;
    _requesting = true;
    state = const AuthUnauthenticated(isLoading: true);
    try {
      final roles = await _repo.checkPhone(phone);
      if (roles.isEmpty) {
        state = const AuthUnauthenticated(
          error: 'No account found for this phone number. Please register first.',
        );
        return;
      }
      if (roles.length == 1) {
        // Single role — send OTP immediately.
        await _loginWithRole(phone: phone, role: roles.first);
      } else {
        // Both roles — ask the user to choose.
        state = AuthRoleSelection(phone: phone, roles: roles);
      }
    } on ApiException catch (e) {
      state = AuthUnauthenticated(
        error: AuthErrorMapper.message(e),
        fieldErrors: AuthErrorMapper.fieldErrors(e),
      );
    } on AuthException catch (e) {
      state = AuthUnauthenticated(error: e.message);
    } catch (_) {
      state = const AuthUnauthenticated(
        error: 'Something went wrong. Please try again.',
      );
    } finally {
      _requesting = false;
    }
  }

  /// Sign-in step 2 (only when both roles exist): user picked a role.
  Future<void> selectRoleAndLogin({required String role}) async {
    final current = state;
    if (current is! AuthRoleSelection) return;
    if (_requesting) return;
    _requesting = true;
    state = AuthRoleSelection(
      phone: current.phone,
      roles: current.roles,
      isLoading: true,
    );
    try {
      await _loginWithRole(phone: current.phone, role: role);
    } on ApiException catch (e) {
      state = AuthRoleSelection(
        phone: current.phone,
        roles: current.roles,
        error: AuthErrorMapper.message(e),
      );
    } on AuthException catch (e) {
      state = AuthRoleSelection(
        phone: current.phone,
        roles: current.roles,
        error: e.message,
      );
    } catch (_) {
      state = AuthRoleSelection(
        phone: current.phone,
        roles: current.roles,
        error: 'Could not send verification code. Please try again.',
      );
    } finally {
      _requesting = false;
    }
  }

  /// Calls the role-specific login endpoint and transitions to OTP state.
  Future<void> _loginWithRole({
    required String phone,
    required String role,
  }) async {
    if (role == 'driver') {
      await _repo.loginDriver(phone);
    } else {
      await _repo.loginArtisan(phone);
    }
    final providerType =
        role == 'artisan' ? ProviderType.artisan : ProviderType.driver;
    state = AuthOtpSent(phone: phone, isNewUser: false, role: providerType);
  }

  /// Verify OTP code → fetch profile → authenticated.
  Future<void> verifyOtp(String code) async {
    final current = state;
    if (current is! AuthOtpSent) return;

    state = AuthOtpSent(
      phone: current.phone,
      isNewUser: current.isNewUser,
      role: current.role,
      isVerifying: true,
    );

    try {
      await _repo.verifyOtp(phone: current.phone, code: code);
      final user = await _repo.fetchProfile();
      onAuthenticated?.call(user, current.role);
      state = AuthAuthenticated(user);
    } on ApiException catch (e) {
      state = AuthOtpSent(
        phone: current.phone,
        isNewUser: current.isNewUser,
        role: current.role,
        error: AuthErrorMapper.message(e),
      );
    } on AuthException catch (e) {
      state = AuthOtpSent(
        phone: current.phone,
        isNewUser: current.isNewUser,
        role: current.role,
        error: e.message,
      );
    } catch (e) {
      state = AuthOtpSent(
        phone: current.phone,
        isNewUser: current.isNewUser,
        role: current.role,
        error: 'Verification failed: $e',
      );
    }
  }

  /// Resend OTP — re-calls register (sign-up) or login (sign-in).
  Future<void> resendOtp() async {
    final current = state;
    if (current is! AuthOtpSent) return;

    if (current.isNewUser) {
      // For sign-up resend, we re-call register.
      // Register is idempotent for OTP sending.
      await _repo.register(RegisterRequest(
        phone: current.phone,
        fullName: '', // Backend already has the data from initial register
        type: current.role == ProviderType.artisan ? 'artisan' : 'driver',
        privacyPolicyAccepted: true,
      ));
    } else {
      if (current.role == ProviderType.driver) {
        await _repo.loginDriver(current.phone);
      } else {
        await _repo.loginArtisan(current.phone);
      }
    }
  }

  /// Clear any error from the current state without changing the state type.
  void clearError() {
    final current = state;
    if (current is AuthUnauthenticated && current.error != null) {
      state = const AuthUnauthenticated();
    } else if (current is AuthRoleSelection && current.error != null) {
      state = AuthRoleSelection(
        phone: current.phone,
        roles: current.roles,
      );
    } else if (current is AuthOtpSent && current.error != null) {
      state = AuthOtpSent(
        phone: current.phone,
        isNewUser: current.isNewUser,
        role: current.role,
      );
    }
  }

  /// Re-fetch the user profile from GET /users/me and update auth state.
  /// Use after uploading a photo or document to get the latest data.
  /// Returns null on success, or an error message on failure.
  Future<String?> refreshProfile() async {
    if (state is! AuthAuthenticated) return 'Not authenticated';
    try {
      final user = await _repo.fetchProfile();
      onAuthenticated?.call(user, null);
      state = AuthAuthenticated(user);
      return null;
    } catch (_) {
      return 'Failed to refresh profile.';
    }
  }

  /// Update the user's profile (name, email, language).
  /// On success, refreshes the [AuthAuthenticated] state with the updated user.
  /// Returns null on success, or an error message on failure.
  Future<String?> updateProfile(UpdateProfileRequest request) async {
    if (state is! AuthAuthenticated) return 'Not authenticated';
    try {
      final updatedUser = await _repo.updateProfile(request);
      state = AuthAuthenticated(updatedUser);
      return null;
    } on ApiException catch (e) {
      return AuthErrorMapper.message(e);
    } catch (_) {
      return 'Failed to update profile. Please try again.';
    }
  }

  /// Update driver-specific fields (vehicle, licence, payout).
  /// On success, refreshes the [AuthAuthenticated] state with the updated user.
  /// Returns null on success, or an error message on failure.
  Future<String?> updateDriverProfile(
    UpdateDriverProfileRequest request,
  ) async {
    if (state is! AuthAuthenticated) return 'Not authenticated';
    try {
      final updatedUser = await _repo.updateDriverProfile(request);
      state = AuthAuthenticated(updatedUser);
      return null;
    } on ApiException catch (e) {
      return AuthErrorMapper.message(e);
    } catch (_) {
      return 'Failed to update driver profile. Please try again.';
    }
  }

  /// Update artisan-specific fields (display name, business name, payout, etc.).
  /// On success, refreshes the [AuthAuthenticated] state with the updated user.
  /// Returns null on success, or an error message on failure.
  Future<String?> updateArtisanProfile(
    UpdateArtisanProfileRequest request,
  ) async {
    if (state is! AuthAuthenticated) return 'Not authenticated';
    try {
      final updatedUser = await _repo.updateArtisanProfile(request);
      state = AuthAuthenticated(updatedUser);
      return null;
    } on ApiException catch (e) {
      return AuthErrorMapper.message(e);
    } catch (_) {
      return 'Failed to update business info. Please try again.';
    }
  }

  /// Drop back to unauthenticated landing.
  void reset() {
    state = const AuthUnauthenticated();
  }

  /// Log out — clear tokens and return to landing.
  Future<void> logout() async {
    await _repo.clear();
    state = const AuthUnauthenticated();
  }
}
