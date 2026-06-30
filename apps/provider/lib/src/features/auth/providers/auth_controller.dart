import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../artisan_home/providers/bid_drafts_provider.dart';
import '../../artisan_jobs/providers/pending_incoming_jobs_provider.dart';
import '../../artisan_jobs/providers/submitted_bids_provider.dart';
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

/// Phone has both roles — user must pick which to sign in as. Reached AFTER
/// OTP verification (post-OTP role resolution): [selectionToken] is the
/// short-lived token from `provider/verify-otp` that `provider/select-role`
/// exchanges for a session.
class AuthRoleSelection extends AuthState {
  const AuthRoleSelection({
    required this.phone,
    required this.roles,
    required this.selectionToken,
    this.isLoading = false,
    this.error,
  });

  final String phone;
  final List<String> roles;
  final String selectionToken;
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
    this.regionRejected = false,
  });

  final String phone;
  final bool isNewUser;
  final ProviderType? role;
  final String? error;
  final bool isVerifying;

  /// True when [error] came from an INVALID_REGION verify failure during
  /// provider signup. The OTP screen reacts by dropping the cached region
  /// list so the region step re-fetches when the user backs out to re-select.
  final bool regionRejected;
}

/// Backend rejected the login because the same account has an active
/// session on another device. The block dialog gives the user three
/// options: take over the session via OTP (proves phone ownership and
/// signs the other device out), contact support, or cancel.
class AuthBlockedByOtherDevice extends AuthState {
  const AuthBlockedByOtherDevice({
    required this.phone,
    this.role,
    this.otpCode,
    this.selectionToken,
    this.recoveryRequestStatus = RecoveryRequestStatus.idle,
    this.isTakingOver = false,
    this.takeoverError,
  });

  final String phone;

  /// The role being taken over. Null in the post-OTP single-role flow where
  /// the backend resolves the role itself on the forceLogin retry.
  final ProviderType? role;

  /// The OTP code to replay on a forceLogin takeover (single-role verify
  /// conflict — the backend preserves the unconsumed code). Null for the
  /// role-selection conflict path, which retries with [selectionToken].
  final String? otpCode;

  /// The role-selection token to replay on a forceLogin takeover (dual-role
  /// select-role conflict). Null for the single-role verify path.
  final String? selectionToken;

  /// Tracks the in-flight state of the "request session recovery" call so
  /// the dialog can show a spinner / success / failure.
  final RecoveryRequestStatus recoveryRequestStatus;

  /// True while the takeover-via-OTP retry of the login call is in flight,
  /// so the dialog button can show a spinner.
  final bool isTakingOver;

  /// Surface for a takeover failure (network error, etc). Cleared when
  /// the user retries.
  final String? takeoverError;
}

/// State of the support-recovery request fired from the block dialog.
enum RecoveryRequestStatus { idle, sending, sent, failed }

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

/// Persistent per-install device ID + device info collector.
final deviceIdProviderRef = Provider<DeviceIdProvider>((ref) {
  return DeviceIdProvider(ref.watch(tokenStorageProvider));
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    service: ref.watch(authServiceProvider),
    tokenStorage: ref.watch(tokenStorageProvider),
    deviceIdProvider: ref.watch(deviceIdProviderRef),
  );
});

final otpChannelsProvider = FutureProvider.autoDispose<List<String>>((ref) {
  return ref.watch(authRepositoryProvider).getOtpChannels();
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
    onLocalStateClear: () async {
      // Wipe per-account artisan caches that live outside TokenStorage.
      // Without this, "BID SENT" entries (artisan_submitted_bids) and
      // in-progress drafts (artisan_bid_drafts_v1) leak across logouts and
      // across backend DB resets. Awaited so SharedPreferences writes
      // flush before the router redirects away from the screen.
      await Future.wait([
        ref.read(submittedBidsProvider.notifier).clear(),
        ref.read(bidDraftsProvider.notifier).clear(),
      ]);
      ref.read(pendingIncomingJobsProvider.notifier).clear();
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
    this.onLocalStateClear,
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

  /// Called when the session ends (explicit logout or force-logout from the
  /// 401 interceptor). Wires per-account local caches that live outside
  /// [TokenStorage] — submitted bids, bid drafts, in-memory job queues —
  /// so they don't leak across accounts or across a backend DB reset.
  ///
  /// Awaited by [logout] before flipping state so the SharedPreferences
  /// writes flush before the user navigates away. The interceptor path is
  /// sync and fires-and-forgets — safe because the next app start re-runs
  /// the same wipe via [bootstrap]'s 401 path.
  final Future<void> Function()? onLocalStateClear;
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
    List<String>? rideCategories,
    String? regionId,
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
        rideCategories: rideCategories,
        regionId: regionId,
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

  /// Sign-in step 1: request a provider login OTP WITHOUT revealing the role.
  /// The backend returns a uniform response whether or not the number is
  /// registered (no enumeration oracle), so we always advance to the OTP
  /// screen. The role is resolved after the code is verified (one role → in;
  /// both roles → role picker). Method name kept for the phone screen.
  Future<void> checkPhoneAndLogin({required String phone}) async {
    if (_requesting) return;
    _requesting = true;
    state = const AuthUnauthenticated(isLoading: true);
    try {
      await _repo.providerLogin(phone);
      // role unknown until post-OTP resolution.
      state = AuthOtpSent(phone: phone, isNewUser: false);
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

  /// Sign-in step 3 (dual-role accounts only): the user picked a role on the
  /// post-OTP picker. Exchanges the selection token + role for a session.
  Future<void> selectRoleAndLogin({required String role}) async {
    final current = state;
    if (current is! AuthRoleSelection) return;
    if (_requesting) return;
    _requesting = true;
    state = AuthRoleSelection(
      phone: current.phone,
      roles: current.roles,
      selectionToken: current.selectionToken,
      isLoading: true,
    );
    try {
      final session = await _repo.providerSelectRole(
        selectionToken: current.selectionToken,
        role: role,
      );
      await _completeProviderSession(session);
    } on ApiException catch (e) {
      if (e.errorCode == AuthErrorCodes.alreadyLoggedInElsewhere) {
        state = AuthBlockedByOtherDevice(
          phone: current.phone,
          role: role == 'artisan' ? ProviderType.artisan : ProviderType.driver,
          selectionToken: current.selectionToken,
        );
      } else {
        state = AuthRoleSelection(
          phone: current.phone,
          roles: current.roles,
          selectionToken: current.selectionToken,
          error: AuthErrorMapper.message(e),
        );
      }
    } on AuthException catch (e) {
      state = AuthRoleSelection(
        phone: current.phone,
        roles: current.roles,
        selectionToken: current.selectionToken,
        error: e.message,
      );
    } catch (_) {
      state = AuthRoleSelection(
        phone: current.phone,
        roles: current.roles,
        selectionToken: current.selectionToken,
        error: 'Could not sign you in. Please try again.',
      );
    } finally {
      _requesting = false;
    }
  }

  /// Fetch the profile for a freshly-issued provider session and flip to
  /// authenticated. Shared by single-role verify and role selection.
  Future<void> _completeProviderSession(ProviderSession session) async {
    final providerType =
        session.role == 'artisan' ? ProviderType.artisan : ProviderType.driver;
    // Pass the freshly-selected role into fetchProfile. Storage still holds
    // the previous session's role at this point (onAuthenticated writes the
    // new one below), so without this the AuthUser would resolve its
    // name/email/photo from the wrong role — e.g. the artisan business name
    // showing up on a driver login.
    final user =
        await _repo.fetchProfile(activeRole: _authRoleFor(providerType));
    onAuthenticated?.call(user, providerType);
    state = AuthAuthenticated(user);
  }

  /// Map the app's [ProviderType] to the api_client [AuthRole] used to
  /// resolve per-role identity on [AuthUser]. Returns null when the role is
  /// unknown, letting [AuthRepository.fetchProfile] fall back to storage.
  AuthRole? _authRoleFor(ProviderType? type) => type == null
      ? null
      : (type.isArtisan ? AuthRole.artisan : AuthRole.driver);

  /// Verify OTP code.
  ///
  /// Sign-up (isNewUser) keeps the legacy `verify-otp` path — registration
  /// already committed the role. Sign-in uses the post-OTP provider flow:
  /// one provider role → straight in; both roles → the role picker.
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
      if (current.isNewUser) {
        // Registration: role already chosen at sign-up; legacy verify.
        await _repo.verifyOtp(phone: current.phone, code: code);
        // Same stale-role guard as _completeProviderSession: pass the role
        // chosen at sign-up so identity resolves from the right profile
        // before onAuthenticated persists it.
        final user =
            await _repo.fetchProfile(activeRole: _authRoleFor(current.role));
        onAuthenticated?.call(user, current.role);
        state = AuthAuthenticated(user);
        return;
      }

      final result =
          await _repo.providerVerifyOtp(phone: current.phone, code: code);
      switch (result) {
        case ProviderSession session:
          await _completeProviderSession(session);
        case ProviderRoleChoice choice:
          state = AuthRoleSelection(
            phone: current.phone,
            roles: choice.roles,
            selectionToken: choice.selectionToken,
          );
      }
    } on ApiException catch (e) {
      if (e.errorCode == AuthErrorCodes.alreadyLoggedInElsewhere) {
        // Conflict surfaced after OTP — the backend preserved the code, so
        // the takeover retry replays it with forceLogin.
        state = AuthBlockedByOtherDevice(phone: current.phone, otpCode: code);
      } else {
        // INVALID_REGION is a stale-cache edge case: the region step re-fetches
        // GET /v1/regions when the user backs out to re-select (the OTP screen
        // drops the cache on this flag). The draft still holds the rejected
        // regionId — the register payload is re-sent on the next attempt.
        state = AuthOtpSent(
          phone: current.phone,
          isNewUser: current.isNewUser,
          role: current.role,
          error: AuthErrorMapper.message(e),
          regionRejected: e.errorCode == AuthErrorCodes.invalidRegion,
        );
      }
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

  /// Re-deliver the active OTP without issuing a new code.
  Future<void> resendOtp({String channel = 'sms'}) async {
    final current = state;
    if (current is! AuthOtpSent) return;
    if (_requesting) return;
    _requesting = true;
    try {
      await _repo.resendOtp(phone: current.phone, channel: channel);
      state = AuthOtpSent(
        phone: current.phone,
        isNewUser: current.isNewUser,
        role: current.role,
      );
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
    } catch (_) {
      state = AuthOtpSent(
        phone: current.phone,
        isNewUser: current.isNewUser,
        role: current.role,
        error: 'Could not resend code. Please try again.',
      );
    } finally {
      _requesting = false;
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
        selectionToken: current.selectionToken,
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

  /// User-initiated logout: revokes the refresh token server-side, then
  /// wipes local state.
  Future<void> logout() async {
    debugPrint('[AuthController] logout() called from ${state.runtimeType}');
    try {
      await _repo.logout().timeout(const Duration(seconds: 8));
      debugPrint('[AuthController] _repo.logout() returned');
    } on TimeoutException {
      debugPrint('[AuthController] _repo.logout() timed out — wiping locally');
      try {
        await _repo.clear();
      } catch (_) {}
    } catch (e) {
      debugPrint('[AuthController] _repo.logout() threw: $e — wiping locally');
      try {
        await _repo.clear();
      } catch (_) {}
    }
    try {
      await onLocalStateClear?.call();
    } catch (_) {
      // Cache wipe is best-effort — never block logout on storage errors.
    }
    state = const AuthUnauthenticated();
    debugPrint('[AuthController] state → AuthUnauthenticated');
  }

  /// User dismisses the "already signed in elsewhere" block dialog.
  /// Returns to phone input so they can try a different number or come
  /// back later (e.g. after signing out on the other device).
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
      role: current.role,
      otpCode: current.otpCode,
      selectionToken: current.selectionToken,
      recoveryRequestStatus: RecoveryRequestStatus.sending,
    );
    try {
      await _repo.requestSessionRecovery(current.phone);
      state = AuthBlockedByOtherDevice(
        phone: current.phone,
        role: current.role,
        otpCode: current.otpCode,
        selectionToken: current.selectionToken,
        recoveryRequestStatus: RecoveryRequestStatus.sent,
      );
    } catch (_) {
      state = AuthBlockedByOtherDevice(
        phone: current.phone,
        role: current.role,
        otpCode: current.otpCode,
        selectionToken: current.selectionToken,
        recoveryRequestStatus: RecoveryRequestStatus.failed,
      );
    }
  }

  /// User tapped "Sign me in here, sign out the other device" on the block
  /// dialog. Re-fires the role-specific login with `forceLogin: true` so
  /// the backend skips the single-device check; the verifyOtp step then
  /// revokes the prior session as part of the takeover.
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
      role: current.role,
      otpCode: current.otpCode,
      selectionToken: current.selectionToken,
      recoveryRequestStatus: current.recoveryRequestStatus,
      isTakingOver: true,
    );
    try {
      // The backend preserved the OTP / selection token on the conflict, so
      // the takeover replays it with forceLogin and completes the session
      // directly — no re-entering the OTP.
      if (current.selectionToken != null && current.role != null) {
        final session = await _repo.providerSelectRole(
          selectionToken: current.selectionToken!,
          role: current.role!.name,
          forceLogin: true,
        );
        await _completeProviderSession(session);
      } else if (current.otpCode != null) {
        final result = await _repo.providerVerifyOtp(
          phone: current.phone,
          code: current.otpCode!,
          forceLogin: true,
        );
        switch (result) {
          case ProviderSession session:
            await _completeProviderSession(session);
          case ProviderRoleChoice choice:
            state = AuthRoleSelection(
              phone: current.phone,
              roles: choice.roles,
              selectionToken: choice.selectionToken,
            );
        }
      } else {
        state = const AuthUnauthenticated(
          error: 'Please sign in again.',
        );
      }
    } on ApiException catch (e) {
      state = AuthBlockedByOtherDevice(
        phone: current.phone,
        role: current.role,
        otpCode: current.otpCode,
        selectionToken: current.selectionToken,
        recoveryRequestStatus: current.recoveryRequestStatus,
        takeoverError: AuthErrorMapper.message(e),
      );
    } on AuthException catch (e) {
      state = AuthBlockedByOtherDevice(
        phone: current.phone,
        role: current.role,
        otpCode: current.otpCode,
        selectionToken: current.selectionToken,
        recoveryRequestStatus: current.recoveryRequestStatus,
        takeoverError: e.message,
      );
    } catch (_) {
      state = AuthBlockedByOtherDevice(
        phone: current.phone,
        role: current.role,
        otpCode: current.otpCode,
        selectionToken: current.selectionToken,
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
    final clear = onLocalStateClear?.call();
    if (clear != null) unawaited(clear);
    state = const AuthUnauthenticated(
      error: 'Your session ended. Please sign in again.',
    );
  }

  /// Re-validate the session against [kSessionTtl]. Called on app resume
  /// so a session that crossed the TTL while the app was backgrounded
  /// gets invalidated immediately rather than on the next 401.
  ///
  /// Noop if the user isn't authenticated.
  Future<void> recheckSessionOnResume() async {
    if (state is! AuthAuthenticated) return;
    final startedAt = await _tokenStorage.readSessionStartedAt();
    if (startedAt == null) return;
    if (DateTime.now().difference(startedAt) > kSessionTtl) {
      await logout();
    }
  }
}
