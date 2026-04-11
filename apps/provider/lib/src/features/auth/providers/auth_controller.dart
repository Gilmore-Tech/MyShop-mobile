import 'package:api_client/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../profile/providers/provider_type_provider.dart';
import '../data/auth_repository.dart';

/// Discriminated auth state. The router redirects on these.
sealed class AuthState {
  const AuthState();
}

class AuthUnknown extends AuthState {
  const AuthUnknown();
}

class AuthUnauthenticated extends AuthState {
  const AuthUnauthenticated({this.error});
  final String? error;
}

/// OTP requested as part of returning-user sign-in.
class AuthSignInOtp extends AuthState {
  const AuthSignInOtp({
    required this.phone,
    required this.otpId,
    this.error,
    this.isVerifying = false,
  });
  final String phone;
  final String otpId;
  final String? error;
  final bool isVerifying;
}

/// OTP requested as the final step of new-account sign-up. The role and the
/// in-progress draft live in the registration providers — auth only carries
/// the bare phone + otpId here.
class AuthSignUpOtp extends AuthState {
  const AuthSignUpOtp({
    required this.phone,
    required this.otpId,
    required this.role,
    this.error,
    this.isVerifying = false,
  });
  final String phone;
  final String otpId;
  final ProviderType role;
  final String? error;
  final bool isVerifying;
}

/// Sign-up OTP succeeded; we now hold a token but the user record does not
/// exist yet. The registration controller listens for this and submits.
class AuthSignUpReady extends AuthState {
  const AuthSignUpReady({
    required this.phone,
    required this.role,
  });
  final String phone;
  final ProviderType role;
}

class AuthAuthenticated extends AuthState {
  const AuthAuthenticated(this.user);
  final AuthUser user;
}

final authServiceProvider = Provider<AuthService>((ref) => MockAuthService());

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(service: ref.watch(authServiceProvider)),
);

final authControllerProvider =
    StateNotifierProvider<AuthController, AuthState>((ref) {
  final controller = AuthController(ref.watch(authRepositoryProvider));
  controller.bootstrap();
  return controller;
});

class AuthController extends StateNotifier<AuthState> {
  AuthController(this._repo) : super(const AuthUnauthenticated());

  final AuthRepository _repo;
  bool _requesting = false;

  Future<void> bootstrap() async {
    try {
      final user = await _repo
          .bootstrap()
          .timeout(const Duration(seconds: 3), onTimeout: () => null);
      if (user != null) {
        state = AuthAuthenticated(user);
      }
    } catch (_) {
      // Stay unauthenticated.
    }
  }

  Future<void> requestSignInOtp(String phone) async {
    if (_requesting) return;
    _requesting = true;
    try {
      final result = await _repo.requestOtp(phone);
      state = AuthSignInOtp(phone: phone, otpId: result.otpId);
    } on AuthException catch (e) {
      state = AuthUnauthenticated(error: e.message);
    } catch (_) {
      state = const AuthUnauthenticated(
        error: 'Could not send OTP. Try again.',
      );
    } finally {
      _requesting = false;
    }
  }

  Future<void> requestSignUpOtp({
    required String phone,
    required ProviderType role,
  }) async {
    if (_requesting) return;
    _requesting = true;
    try {
      final result = await _repo.requestOtp(phone);
      state = AuthSignUpOtp(
        phone: phone,
        otpId: result.otpId,
        role: role,
      );
    } on AuthException catch (e) {
      state = AuthUnauthenticated(error: e.message);
    } catch (_) {
      state = const AuthUnauthenticated(
        error: 'Could not send OTP. Try again.',
      );
    } finally {
      _requesting = false;
    }
  }

  Future<void> verifyOtp(String code) async {
    final current = state;
    if (current is AuthSignInOtp) {
      state = AuthSignInOtp(
        phone: current.phone,
        otpId: current.otpId,
        isVerifying: true,
      );
      try {
        final result = await _repo.verifyOtp(
          otpId: current.otpId,
          code: code,
          phone: current.phone,
        );
        if (result.user != null) {
          state = AuthAuthenticated(result.user!);
        } else {
          // Returning-user code path but no profile — surface as error.
          state = AuthSignInOtp(
            phone: current.phone,
            otpId: current.otpId,
            error:
                'No account found for that number. Try Get Started instead.',
          );
        }
      } on AuthException catch (e) {
        state = AuthSignInOtp(
          phone: current.phone,
          otpId: current.otpId,
          error: e.message,
        );
      } catch (_) {
        state = AuthSignInOtp(
          phone: current.phone,
          otpId: current.otpId,
          error: 'Verification failed. Try again.',
        );
      }
      return;
    }
    if (current is AuthSignUpOtp) {
      state = AuthSignUpOtp(
        phone: current.phone,
        otpId: current.otpId,
        role: current.role,
        isVerifying: true,
      );
      try {
        await _repo.verifyOtp(
          otpId: current.otpId,
          code: code,
          phone: current.phone,
        );
        state = AuthSignUpReady(phone: current.phone, role: current.role);
      } on AuthException catch (e) {
        state = AuthSignUpOtp(
          phone: current.phone,
          otpId: current.otpId,
          role: current.role,
          error: e.message,
        );
      } catch (_) {
        state = AuthSignUpOtp(
          phone: current.phone,
          otpId: current.otpId,
          role: current.role,
          error: 'Verification failed. Try again.',
        );
      }
    }
  }

  /// Called by registration controllers after their submit() succeeds.
  void completeSignUp(AuthUser user) {
    state = AuthAuthenticated(user);
  }

  /// Drop back to the unauthenticated landing.
  void reset() {
    state = const AuthUnauthenticated();
  }

  Future<void> logout() async {
    await _repo.clear();
    state = const AuthUnauthenticated();
  }
}
