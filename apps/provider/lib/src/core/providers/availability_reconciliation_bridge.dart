import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/providers/auth_controller.dart';
import '../services/fcm_service.dart';
import 'app_lifecycle_provider.dart';
import 'availability_reconciliation_controller.dart';
import 'provider_online_intent.dart';
import 'socket_provider.dart';

/// Keeps authoritative availability reconciliation active for the authenticated
/// app lifetime. Network failures are best-effort and never change local state.
final availabilityReconciliationBridgeProvider = Provider<void>((ref) {
  var disposed = false;
  ref.onDispose(() => disposed = true);

  void reconcile(String trigger) {
    if (ref.read(authControllerProvider) is! AuthAuthenticated) return;
    unawaited(
      ref
          .read(availabilityReconciliationControllerProvider)
          .reconcile(trigger: trigger),
    );
  }

  void installIdentity(AuthState next, {required bool reconcileAfterInstall}) {
    // A fireImmediately listener runs while this bridge provider is itself
    // being constructed. Riverpod forbids synchronously changing another
    // provider in that phase and throws an unhandled assertion. Defer only the
    // state write to the next microtask, then reconcile against that installed
    // exact-role identity.
    Future<void>.microtask(() {
      if (disposed) return;
      if (next is AuthAuthenticated) {
        try {
          ref.read(currentProviderOnlineIntentIdentityProvider.notifier).state =
              ProviderOnlineIntentIdentity.fromUser(next.user);
        } catch (error) {
          ref.read(currentProviderOnlineIntentIdentityProvider.notifier).state =
              null;
        }
        if (reconcileAfterInstall) reconcile('authentication');
        return;
      }
      ref.read(currentProviderOnlineIntentIdentityProvider.notifier).state =
          null;
    });
  }

  ref.listen<AuthState>(
    authControllerProvider,
    (previous, next) {
      installIdentity(
        next,
        reconcileAfterInstall:
            next is AuthAuthenticated && previous is! AuthAuthenticated,
      );
    },
    fireImmediately: true,
  );

  ref.listen<bool>(appForegroundedProvider, (previous, next) {
    if (next && previous == false) reconcile('app_resume');
  });

  ref.listen<bool>(socketConnectedProvider, (previous, next) {
    if (next && previous != true) reconcile('socket_reconnect');
  });

  ref.listen<bool>(firebaseReadyProvider, (previous, next) {
    if (next && previous != true) reconcile('notification_startup');
  });
});
