import 'dart:async';
import 'dart:math';

import 'package:api_client/api_client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart';

import '../../features/profile/providers/provider_type_provider.dart';
import '../../features/auth/providers/auth_controller.dart';
import '../di/providers.dart';
import '../services/fcm_service.dart';
import '../services/provider_request_policy.dart';
import '../services/provider_online_recovery.dart';
import 'availability_controller.dart';
import 'provider_status_provider.dart';
import 'location_degradation_provider.dart';
import 'provider_location_session_provider.dart';
import 'provider_online_intent.dart';
import 'provider_connection_recovery_provider.dart';

class AvailabilityReconciliationActions {
  const AvailabilityReconciliationActions({
    required this.restoreOnline,
    required this.forceOffline,
  });

  final Future<String?> Function(String? selectedVehicleId) restoreOnline;
  final Future<String?> Function() forceOffline;
}

final availabilityReconciliationActionsProvider =
    Provider<AvailabilityReconciliationActions>((ref) {
  final controller = ref.read(availabilityControllerProvider);
  return AvailabilityReconciliationActions(
    restoreOnline: (selectedVehicleId) => controller.restorePriorOnlineIntent(
      vehicleId: selectedVehicleId,
    ),
    forceOffline: controller.goOffline,
  );
});

/// Reconciles the in-memory availability switch against the backend without
/// restoring a provider Online unless an exact-role durable intent exists.
///
/// Active-work state is deliberately left alone: ride/job recovery owns it,
/// and changing `busy` here would encode unresolved product policy. For an
/// idle provider the safe convergence rules are:
///
/// * temporary dispatch unavailability preserves a live session and its writer;
/// * ended server session + local online -> local offline;
/// * no durable intent -> both sides converge Offline;
/// * durable intent -> restore only after notification, full server
///   eligibility, and a fresh BR-30 device-location revalidation;
/// * transient restore failures retain intent and retry silently; permanent
///   restrictions still leave both sides Offline with actionable copy.
class AvailabilityReconciliationController {
  AvailabilityReconciliationController(this._ref);

  final Ref _ref;
  Future<void>? _inFlight;
  Timer? _retryTimer;
  int _failures = 0;
  bool _disposed = false;

  void dispose() {
    _disposed = true;
    _retryTimer?.cancel();
  }

  void _recovered() {
    _retryTimer?.cancel();
    _failures = 0;
    _ref.read(providerConnectionRecoveryProvider.notifier).recovered();
  }

  Future<void> _retryIfIntended(bool Function() current) async {
    if (!current()) return;
    final identity = _ref.read(currentProviderOnlineIntentIdentityProvider);
    if (identity == null) return;
    bool intended;
    try {
      intended =
          await _ref.read(providerOnlineIntentStoreProvider).read(identity);
    } catch (_) {
      return;
    }
    if (!current() || !intended) return;
    _ref.read(providerConnectionRecoveryProvider.notifier).interrupted();
    _retryTimer?.cancel();
    final seconds = min(30, 2 * (1 << min(_failures++, 4)));
    _retryTimer = Timer(
      Duration(
          milliseconds:
              (seconds * 1000 * (0.8 + Random().nextDouble() * 0.4)).round()),
      () {
        if (current()) unawaited(reconcile(trigger: 'automatic_recovery'));
      },
    );
  }

  Future<void> reconcile({required String trigger}) {
    if (_disposed) return Future<void>.value();
    final inFlight = _inFlight;
    if (inFlight != null) return inFlight;
    _retryTimer?.cancel();

    final future = _reconcile(trigger: trigger).whenComplete(() {
      _inFlight = null;
    });
    _inFlight = future;
    return future;
  }

  Future<void> _reconcile({required String trigger}) async {
    final intentIdentity =
        _ref.read(currentProviderOnlineIntentIdentityProvider);
    if (intentIdentity == null) return;

    final statusNotifier = _ref.read(providerStatusProvider.notifier);
    final transitionRevisionAtStart = statusNotifier.transitionRevision;
    final authSession = _ref.read(currentAuthSessionIdentityProvider);
    bool current() =>
        !_disposed &&
        _ref.read(currentProviderOnlineIntentIdentityProvider) ==
            intentIdentity &&
        _ref.read(currentAuthSessionIdentityProvider) == authSession &&
        statusNotifier.transitionRevision == transitionRevisionAtStart;
    final ProviderAvailabilitySnapshot snapshot;
    try {
      snapshot = await _ref
          .read(providerAvailabilityServiceProvider)
          .getMyAvailability();
    } on ApiException catch (error) {
      debugPrint(
        '[AvailabilityReconcile] $trigger failed: '
        '${error.errorCode ?? error.message}',
      );
      if (isRetryableProviderRestoreError(error)) {
        await _retryIfIntended(current);
      }
      return;
    } on FormatException catch (error) {
      debugPrint(
        '[AvailabilityReconcile] $trigger rejected invalid response '
        'type=${error.runtimeType}',
      );
      return;
    } catch (error) {
      debugPrint('[AvailabilityReconcile] $trigger error: $error');
      await _retryIfIntended(current);
      return;
    }

    if (!current()) {
      debugPrint(
        '[AvailabilityReconcile] $trigger ignored stale snapshot after '
        'a newer local transition',
      );
      return;
    }

    final expectedRole = _ref.read(providerTypeProvider).isDriver
        ? ProviderAvailabilityRole.driver
        : ProviderAvailabilityRole.artisan;
    if (snapshot.role != expectedRole) {
      debugPrint(
        '[AvailabilityReconcile] $trigger role mismatch '
        '(expected=$expectedRole, actual=${snapshot.role}) — ignored',
      );
      return;
    }

    if (snapshot.providerId != intentIdentity.roleAccountId) {
      debugPrint(
        '[AvailabilityReconcile] $trigger role-account mismatch — ignored',
      );
      _ref.read(availabilityRestoreNoticeProvider.notifier).state =
          'We kept you offline because the server returned a different '
          'provider account. Sign out and back in, then contact support if '
          'this continues.';
      return;
    }

    _ref
        .read(providerLocationSessionProvider.notifier)
        .installSnapshot(snapshot);

    _ref.read(providerLocationDegradationProvider.notifier).state =
        ProviderLocationDegradationState.fromSnapshot(snapshot);

    final localStatus = _ref.read(providerStatusProvider);
    if (snapshot.hasActiveWork || localStatus == DriverStatus.busy) {
      debugPrint(
        '[AvailabilityReconcile] $trigger deferred to active-work recovery '
        '(serverActive=${snapshot.hasActiveWork}, local=$localStatus)',
      );
      return;
    }

    bool hasOnlineIntent;
    try {
      hasOnlineIntent = await _ref
          .read(providerOnlineIntentStoreProvider)
          .read(intentIdentity);
    } catch (error) {
      debugPrint(
        '[AvailabilityReconcile] $trigger intent read failed: $error',
      );
      hasOnlineIntent = false;
      _ref.read(availabilityRestoreNoticeProvider.notifier).state =
          'We kept you offline because your previous Online choice could not '
          'be verified on this device. Tap Go Online when you are ready.';
    }

    if (!current()) {
      debugPrint(
        '[AvailabilityReconcile] $trigger ignored intent after a newer '
        'local transition',
      );
      return;
    }

    // Enforcement and other server fences can close an idle Online epoch while
    // this device still has a durable Online preference. The server snapshot is
    // authoritative: never leave the toggle visually Online merely because the
    // preference is true. When the dedicated response summary confirms an
    // active restriction, consume that preference and preserve the exact safe
    // provider-facing reason instead of allowing a later GPS/rate-limit error
    // to replace it.
    if (snapshot.effectiveSessionStatus == ProviderAvailabilityStatus.offline &&
        localStatus != DriverStatus.offline &&
        hasOnlineIntent) {
      final restrictionMessage = await _activeRequestRestrictionMessage();
      if (!current()) {
        debugPrint(
          '[AvailabilityReconcile] $trigger ignored authoritative offline '
          'after a newer local transition',
        );
        return;
      }
      if (restrictionMessage != null) {
        await _consumeOnlineIntent(intentIdentity);
        if (!current()) {
          return;
        }
      }
      statusNotifier.goOffline();
      _ref.read(providerLocationSessionProvider.notifier).clear();
      clearOnlineLocationPostAt();
      _ref.read(availabilityRestoreNoticeProvider.notifier).state =
          restrictionMessage ??
              'MyShop ended the previous Online session. You are now offline. '
                  'Tap Go Online when you are ready to receive requests.';
      debugPrint(
        '[AvailabilityReconcile] $trigger applied authoritative offline '
        '(requestRestricted=${restrictionMessage != null})',
      );
      return;
    }

    if (!hasOnlineIntent) {
      if (snapshot.effectiveSessionStatus ==
          ProviderAvailabilityStatus.online) {
        await _forceOfflineAfterRecovery(
          trigger: trigger,
          notice:
              'We kept you offline because this device had no verified prior '
              'Online choice. Tap Go Online when you are ready.',
        );
      } else if (localStatus != DriverStatus.offline) {
        statusNotifier.goOffline();
        _ref.read(providerLocationSessionProvider.notifier).clear();
        clearOnlineLocationPostAt();
        debugPrint(
          '[AvailabilityReconcile] $trigger applied authoritative offline',
        );
      }
      return;
    }

    if (localStatus != DriverStatus.offline) {
      if (snapshot.status == ProviderAvailabilityStatus.offline) {
        // The same SID still owns an Online session. Keep the writer alive,
        // acquire a fresh fix and repair it without changing the toggle.
        _ref.read(providerConnectionRecoveryProvider.notifier).interrupted();
        _ref.read(providerLocationRecoveryKickProvider.notifier).state++;
      } else {
        _recovered();
      }
      return;
    }

    // A new API explicitly distinguishes a closed session from a temporary
    // dispatch pause. Do not resurrect logout, manual Offline or enforcement.
    if (snapshot.sessionStatus == ProviderAvailabilityStatus.offline) {
      await _consumeOnlineIntent(intentIdentity);
      if (!current()) return;
      _recovered();
      _ref.read(providerLocationSessionProvider.notifier).clear();
      _ref.read(availabilityRestoreNoticeProvider.notifier).state =
          'Your previous Online session ended. Tap Go Online when you are ready.';
      return;
    }

    // Firebase setup is asynchronous during process launch. Do not consume a
    // valid prior intent merely because notification authority is not ready;
    // the bridge triggers another reconciliation as soon as Firebase is ready.
    if (!_ref.read(firebaseReadyProvider)) {
      debugPrint(
        '[AvailabilityReconcile] $trigger waiting for notification startup',
      );
      return;
    }

    if (snapshot.role == ProviderAvailabilityRole.driver &&
        snapshot.selectedVehicleId == null) {
      await _consumeOnlineIntent(intentIdentity);
      await _forceOfflineAfterRecovery(
        trigger: trigger,
        notice: 'Your previous Online session ended. Tap Go Online and choose '
            'the vehicle you are using for this session.',
      );
      return;
    }

    final actions = _ref.read(availabilityReconciliationActionsProvider);
    final String? error;
    try {
      error = await actions.restoreOnline(snapshot.selectedVehicleId);
    } on ProviderOnlineRestorePending {
      await _retryIfIntended(current);
      return;
    } on StaleAuthSessionException {
      return;
    }
    if (_disposed ||
        _ref.read(currentProviderOnlineIntentIdentityProvider) !=
            intentIdentity ||
        _ref.read(currentAuthSessionIdentityProvider) != authSession) {
      return;
    }
    if (error == null) {
      _recovered();
      _ref.read(availabilityRestoreNoticeProvider.notifier).state = null;
      debugPrint(
        '[AvailabilityReconcile] $trigger restored prior Online intent',
      );
      return;
    }

    if (!current()) {
      debugPrint(
        '[AvailabilityReconcile] $trigger ignored failed restore after a '
        'newer local transition',
      );
      return;
    }

    await _consumeOnlineIntent(intentIdentity);
    await _forceOfflineAfterRecovery(
      trigger: trigger,
      notice: 'We kept you offline: $error',
    );
  }

  Future<void> _consumeOnlineIntent(
    ProviderOnlineIntentIdentity identity,
  ) async {
    try {
      await _ref.read(providerOnlineIntentStoreProvider).write(
            identity,
            shouldBeOnline: false,
          );
    } catch (error) {
      debugPrint('[AvailabilityReconcile] intent clear failed: $error');
    }
  }

  Future<String?> _activeRequestRestrictionMessage() async {
    try {
      final summary = await _ref
          .read(providerRequestServiceProvider)
          .getRequestResponseSummary();
      final restriction = summary?.activeRestriction;
      return restriction == null
          ? null
          : providerActiveRestrictionMessage(restriction);
    } on ApiException catch (error) {
      debugPrint(
        '[AvailabilityReconcile] restriction lookup failed: '
        '${error.errorCode ?? error.message}',
      );
      return null;
    } on FormatException catch (error) {
      debugPrint(
        '[AvailabilityReconcile] restriction lookup malformed: $error',
      );
      return null;
    }
  }

  Future<void> _forceOfflineAfterRecovery({
    required String trigger,
    required String notice,
  }) async {
    final offlineError = await _ref
        .read(availabilityReconciliationActionsProvider)
        .forceOffline();
    if (offlineError == null) {
      _ref.read(providerStatusProvider.notifier).goOffline();
      _ref.read(providerLocationSessionProvider.notifier).clear();
      clearOnlineLocationPostAt();
    }
    _ref.read(availabilityRestoreNoticeProvider.notifier).state =
        offlineError == null
            ? notice
            : 'We could not confirm that you are offline. Check your '
                'connection, then open the app again before accepting work.';
    debugPrint(
      '[AvailabilityReconcile] $trigger recovery failed; forced offline '
      '(confirmed=${offlineError == null})',
    );
  }
}

final availabilityReconciliationControllerProvider =
    Provider<AvailabilityReconciliationController>((ref) {
  ref.watch(currentAuthSessionIdentityProvider);
  final controller = AvailabilityReconciliationController(ref);
  ref.onDispose(controller.dispose);
  return controller;
});
