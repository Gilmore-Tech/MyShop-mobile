import 'package:api_client/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_controller.dart';

/// Convenience provider that extracts the [AuthUser] when authenticated.
/// Returns null when not in [AuthAuthenticated] state.
final currentUserProvider = Provider<AuthUser?>((ref) {
  final authState = ref.watch(authControllerProvider);
  if (authState is AuthAuthenticated) {
    return authState.user;
  }
  return null;
});
