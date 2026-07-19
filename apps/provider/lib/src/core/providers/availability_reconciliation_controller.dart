import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart';

import '../../features/profile/providers/provider_type_provider.dart';
import '../di/providers.dart';
import '../services/fcm_service.dart';
import 'availability_controller.dart';
import 'provider_status_provider.dart';
import 'location_degradation_provider.dart';
import 'provider_location_session_provider.dart';
import 'provider_online_intent.dart';

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
/// * backend offline + local online -> local offline;
/// * no durable intent -> both sides converge Offline;
/// * durable intent -> restore only after notification, full server
///   eligibility, and a fresh BR-30 device-location revalidation;
/// * failed revalidation consumes the intent, leaves both sides Offline, and
///   presents stable actionable copy instead of retrying invisibly forever.
class AvailabilityReconciliationController {
  AvailabilityReconciliationController(this._ref);

  final Ref _ref;
  Future<void>? _inFlight;

  Future<void> reconcile({required String trigger}) {
    final inFlight = _inFlight;
    if (inFlight != null) return inFlight;

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
      return;
    } on FormatException catch (error) {
      debugPrint(
        '[AvailabilityReconcile] $trigger rejected invalid response '
        'type=${error.runtimeType}',
      );
      return;
    } catch (error) {
      debugPrint('[AvailabilityReconcile] $trigger error: $error');
      return;
    }

    if (statusNotifier.transitionRevision != transitionRevisionAtStart) {
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

    if (statusNotifier.transitionRevision != transitionRevisionAtStart) {
      debugPrint(
        '[AvailabilityReconcile] $trigger ignored intent after a newer '
        'local transition',
      );
      return;
    }

    if (!hasOnlineIntent) {
      if (snapshot.status == ProviderAvailabilityStatus.online) {
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

    if (localStatus != DriverStatus.offline) return;

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
        notice: 'We kept you offline because no approved vehicle was selected. '
            'Tap Go Online and choose the vehicle you are using.',
      );
      return;
    }

    final actions = _ref.read(availabilityReconciliationActionsProvider);
    final error = await actions.restoreOnline(snapshot.selectedVehicleId);
    if (error == null) {
      _ref.read(availabilityRestoreNoticeProvider.notifier).state = null;
      debugPrint(
        '[AvailabilityReconcile] $trigger restored prior Online intent',
      );
      return;
    }

    if (statusNotifier.transitionRevision != transitionRevisionAtStart) {
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
  return AvailabilityReconciliationController(ref);
});
