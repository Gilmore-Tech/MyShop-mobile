import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_models/shared_models.dart';

import '../../features/auth/providers/current_user_provider.dart';
import '../../features/auth/providers/auth_controller.dart';
import '../../features/driver_home/providers/driver_location_provider.dart';
import '../../features/profile/providers/provider_type_provider.dart';
import '../di/providers.dart';
import 'availability_controller.dart';
import 'availability_reconciliation_controller.dart';
import 'provider_status_provider.dart';
import 'provider_location_session_provider.dart';
import 'provider_location_sync_recovery.dart';
import 'provider_online_intent.dart';

const int _maxDriverSamplesPerBatch = 120;
const int _maxQueuedDriverSamples = 360;
const Duration _driverBusyCadence = Duration(seconds: 5);
const Duration _artisanBusyCadence = Duration(seconds: 20);
// BR-30 requires a matching fix no older than 30 seconds. Fifteen seconds
// leaves one full missed cycle for ordinary scheduler/network jitter while
// the server still fails closed if the OS stops delivering real GPS fixes.
const Duration _idleCadence = Duration(seconds: 15);
const Duration _busySampleMinAge = Duration(seconds: 4);
const double _busySampleMinMeters = 10;
const double _idleHeartbeatMinMeters = 50;

class ProviderLocationRecoveryActions {
  const ProviderLocationRecoveryActions({
    required this.forceOffline,
    required this.reconcile,
  });

  final Future<ProviderRecoveryOfflineResult> Function(
    ProviderRecoveryOfflineAuthority authority,
  ) forceOffline;
  final Future<void> Function(String trigger) reconcile;
}

final providerLocationRecoveryActionsProvider =
    Provider<ProviderLocationRecoveryActions>((ref) {
  return ProviderLocationRecoveryActions(
    forceOffline: ref.read(availabilityControllerProvider).goOfflineIfCurrent,
    reconcile: (trigger) => ref
        .read(availabilityReconciliationControllerProvider)
        .reconcile(trigger: trigger),
  );
});

/// Durable REST location writer for foreground and background execution.
///
/// Socket.IO is still used for low-latency foreground driver updates, but this
/// provider is the single periodic REST heartbeat. That keeps providers online
/// after background/screen-off and preserves driver ride trails without keeping
/// unrelated pollers alive.
final backgroundLocationSyncProvider = Provider<void>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) {
    debugPrint('[LOC] background sync: unauthenticated — idle');
    return;
  }

  final status = ref.watch(providerStatusProvider);
  if (status.isOffline) {
    debugPrint('[LOC] background sync: offline — idle');
    return;
  }

  final isArtisan = ref.watch(providerTypeProvider).isArtisan;
  final authSession = ref.watch(currentAuthSessionIdentityProvider);
  final onlineIntentIdentity = ref.watch(
    currentProviderOnlineIntentIdentityProvider,
  );
  if (authSession == null || onlineIntentIdentity == null) {
    debugPrint('[LOC] background sync: session authority unavailable — idle');
    return;
  }
  final locationService = ref.read(locationServiceProvider);
  final positionLoader = ref.read(onlinePositionLoaderProvider);
  final cadence = _syncCadence(status, isArtisan: isArtisan);
  final movementThreshold =
      status.isBusy ? _busySampleMinMeters : _idleHeartbeatMinMeters;

  final driverQueue = <DriverLocationSample>[];
  Position? latestPosition;
  Position? lastQueuedDriverPosition;
  Position? lastSyncedPosition;
  DateTime? lastSyncAt;
  var flushInFlight = false;
  var disposed = false;
  String? queuedSessionId;
  var observedSessionId =
      ref.read(providerLocationSessionProvider)?.onlineSessionId;
  var recoveryInFlight = false;
  var terminalRecoveryInFlight = false;
  final retryGate = ProviderLocationRetryGate(
    ref.read(providerLocationRetryPolicyProvider),
  );
  final container = ref.container;
  final recoveryActions = ref.read(providerLocationRecoveryActionsProvider);

  bool authorityCurrent() =>
      !disposed &&
      container.read(currentUserProvider) == user &&
      container.read(currentAuthSessionIdentityProvider) == authSession &&
      container.read(currentProviderOnlineIntentIdentityProvider) ==
          onlineIntentIdentity;

  bool sessionCurrent(String attemptedSessionId) =>
      authorityCurrent() &&
      container.read(providerLocationSessionProvider)?.onlineSessionId ==
          attemptedSessionId;

  bool requestCurrent(
    String attemptedSessionId,
    int attemptedTransitionRevision,
  ) =>
      sessionCurrent(attemptedSessionId) &&
      container.read(providerStatusProvider.notifier).transitionRevision ==
          attemptedTransitionRevision;

  Future<void> reconcileOnce(String trigger) async {
    if (recoveryInFlight || !authorityCurrent()) return;
    recoveryInFlight = true;
    try {
      await recoveryActions.reconcile(trigger);
    } finally {
      recoveryInFlight = false;
    }
  }

  Future<void> recoverTerminalRejection(
    ProviderLocationRejection rejection, {
    required String attemptedSessionId,
  }) async {
    debugPrint(
      '[LOC] background sync paused: kind=${rejection.kind.name} '
      'reasonCodes=${rejection.reasonCodes.join(',')}',
    );
    retryGate.recordFailure(container.read(providerLocationSyncNowProvider)());

    final currentStatus = container.read(providerStatusProvider);
    if (currentStatus.isBusy) {
      // Active-work recovery owns the status. Preserve the queued trip trail.
      // Session failures are reconciled and retried with bounded backoff;
      // persistent/unknown eligibility failures pause this epoch without ever
      // pretending an active provider is Offline.
      if (rejection.kind == ProviderLocationRejectionKind.eligibility) {
        container.read(providerLocationSyncPauseProvider.notifier).state =
            ProviderLocationSyncPause(
          authSession: authSession,
          onlineSessionId: attemptedSessionId,
          rejection: rejection,
        );
      }
      await reconcileOnce('location_rejected_during_active_work');
      if (container.read(currentAuthSessionIdentityProvider) == authSession) {
        container.read(availabilityRestoreNoticeProvider.notifier).state =
            rejection.kind == ProviderLocationRejectionKind.locationSession
                ? 'Location reporting is recovering because the server ended '
                    'this Online session. Keep the app open during the active '
                    'trip or job.'
                : 'Location reporting was paused because this provider no '
                    'longer meets every server requirement. The active trip '
                    'or job remains open; review verification afterwards.';
      }
      return;
    }

    container.read(providerLocationSyncPauseProvider.notifier).state =
        ProviderLocationSyncPause(
      authSession: authSession,
      onlineSessionId: attemptedSessionId,
      rejection: rejection,
    );
    driverQueue.clear();
    lastQueuedDriverPosition = null;
    final transitionRevision =
        container.read(providerStatusProvider.notifier).transitionRevision;
    final offlineResult = await recoveryActions.forceOffline(
      ProviderRecoveryOfflineAuthority(
        authSession: authSession,
        onlineSessionId: attemptedSessionId,
        transitionRevision: transitionRevision,
      ),
    );
    if (offlineResult.disposition ==
        ProviderRecoveryOfflineDisposition.authorityChanged) {
      // A 409 proves that epoch A is no longer server authority. If A is still
      // the exact unchanged local authority, retire only that stale local
      // view. A newer SID, epoch, or status transition fails this guard and is
      // left completely untouched.
      if (requestCurrent(attemptedSessionId, transitionRevision)) {
        container.read(providerLocationSyncPauseProvider.notifier).state = null;
        container.read(providerStatusProvider.notifier).goOffline();
        container.read(providerLocationSessionProvider.notifier).clear();
        clearOnlineLocationPostAt();
        container.read(availabilityRestoreNoticeProvider.notifier).state =
            'MyShop kept you offline because the previous Online session is '
            'no longer current. Tap Go Online to start a fresh session.';
      }
      return;
    }
    if (offlineResult.disposition ==
        ProviderRecoveryOfflineDisposition.confirmed) {
      if (container.read(currentAuthSessionIdentityProvider) == authSession) {
        container.read(availabilityRestoreNoticeProvider.notifier).state =
            'MyShop kept you offline because the previous Online session was '
            'rejected. Review your provider requirements, then tap Go Online.';
      }
      return;
    }

    if (sessionCurrent(attemptedSessionId) &&
        container.read(providerStatusProvider).isOnline) {
      container.read(availabilityRestoreNoticeProvider.notifier).state =
          'Location reporting was paused because MyShop could not confirm '
          'that this rejected Online session is offline. Check your '
          'connection, reopen the app, and try again.';
    }
  }

  Future<void> handleTerminalRejection(
    ProviderLocationRejection rejection, {
    required String attemptedSessionId,
  }) async {
    // A slow response from epoch A must never pause, clear, or demote epoch B.
    if (terminalRecoveryInFlight || !sessionCurrent(attemptedSessionId)) return;
    terminalRecoveryInFlight = true;
    try {
      await recoverTerminalRejection(
        rejection,
        attemptedSessionId: attemptedSessionId,
      );
    } finally {
      terminalRecoveryInFlight = false;
    }
  }

  bool movedEnough(Position? from, Position to, double meters) {
    if (from == null) return true;
    final moved = Geolocator.distanceBetween(
      from.latitude,
      from.longitude,
      to.latitude,
      to.longitude,
    );
    return moved >= meters;
  }

  bool busySampleDue(Position position) {
    final last = lastQueuedDriverPosition;
    if (last == null) return true;
    final age = position.timestamp.difference(last.timestamp).abs();
    return age >= _busySampleMinAge ||
        movedEnough(last, position, _busySampleMinMeters);
  }

  bool syncDueFor(Position position) {
    final last = lastSyncAt;
    if (last == null) return true;
    if (DateTime.now().difference(last) >= cadence) return true;
    return movedEnough(lastSyncedPosition, position, movementThreshold);
  }

  void capDriverQueue() {
    if (driverQueue.length <= _maxQueuedDriverSamples) return;
    driverQueue.removeRange(0, driverQueue.length - _maxQueuedDriverSamples);
  }

  void stagePosition(Position position) {
    if (!authorityCurrent()) return;
    latestPosition = position;
    ref.read(lastKnownPositionProvider.notifier).state = position;

    if (isArtisan) return;
    final locationSession = ref.read(providerLocationSessionProvider);
    if (locationSession == null) return;
    if (queuedSessionId != locationSession.onlineSessionId) {
      driverQueue.clear();
      queuedSessionId = locationSession.onlineSessionId;
    }
    if (status.isBusy) {
      if (busySampleDue(position)) {
        driverQueue.add(
          _sampleFromPosition(
            position,
            ref.read(providerLocationSessionProvider.notifier).nextSequence(),
          ),
        );
        lastQueuedDriverPosition = position;
        capDriverQueue();
      }
    } else {
      driverQueue
        ..clear()
        ..add(
          _sampleFromPosition(
            position,
            ref.read(providerLocationSessionProvider.notifier).nextSequence(),
          ),
        );
      lastQueuedDriverPosition = position;
    }
  }

  Future<void> flush() async {
    if (disposed || flushInFlight) return;
    if (!authorityCurrent()) return;
    final locationSession = container.read(providerLocationSessionProvider);
    final currentSessionId = locationSession?.onlineSessionId;
    if (currentSessionId != observedSessionId) {
      observedSessionId = currentSessionId;
      retryGate.reset();
    }
    final pause = container.read(providerLocationSyncPauseProvider);
    if (pause != null && pause.authSession != authSession) {
      container.read(providerLocationSyncPauseProvider.notifier).state = null;
    }
    if (currentSessionId != null &&
        pause?.matches(authSession, currentSessionId) == true) {
      final canRetryRecovery = retryGate.canAttempt(
        container.read(providerLocationSyncNowProvider)(),
      );
      if (!container.read(providerStatusProvider).isBusy &&
          !terminalRecoveryInFlight &&
          canRetryRecovery) {
        // The active work that protected Busy has now settled. Converge the
        // same rejected epoch Offline instead of leaving an idle Online UI with
        // a permanently paused sender.
        unawaited(
          handleTerminalRejection(
            pause!.rejection,
            attemptedSessionId: currentSessionId,
          ),
        );
      } else {
        debugPrint('[LOC] background sync: rejected epoch remains paused');
      }
      return;
    }
    if (pause != null &&
        (currentSessionId == null ||
            !pause.matches(authSession, currentSessionId))) {
      container.read(providerLocationSyncPauseProvider.notifier).state = null;
    }
    if (!retryGate.canAttempt(
      container.read(providerLocationSyncNowProvider)(),
    )) {
      debugPrint('[LOC] background sync: waiting for bounded retry');
      return;
    }
    flushInFlight = true;
    var sent = false;
    String? attemptedSessionId;
    int? attemptedTransitionRevision;
    try {
      final refreshRequired = periodicOnlineFixRefreshRequired(latestPosition);
      Position latest;
      try {
        latest = await resolvePeriodicOnlinePosition(
          latestPosition,
          loader: positionLoader,
        );
      } catch (error) {
        debugPrint('[LOC] background sync: fresh-fix request failed: $error');
        retryGate.recordFailure(
          container.read(providerLocationSyncNowProvider)(),
        );
        return;
      }
      if (!authorityCurrent()) return;
      if (periodicOnlineFixRefreshRequired(latest) ||
          !isOnlineLocationFixAcceptable(latest)) {
        debugPrint(
          '[LOC] background sync: fresh-fix request returned an unusable sample',
        );
        retryGate.recordFailure(
          container.read(providerLocationSyncNowProvider)(),
        );
        return;
      }
      if (refreshRequired) {
        stagePosition(latest);
      }

      final activeLocationSession = container.read(
        providerLocationSessionProvider,
      );
      if (activeLocationSession == null) {
        debugPrint('[LOC] background sync: no server location epoch — waiting');
        return;
      }
      attemptedSessionId = activeLocationSession.onlineSessionId;
      attemptedTransitionRevision =
          container.read(providerStatusProvider.notifier).transitionRevision;
      if (isArtisan) {
        if (shouldSkipOnlineLocationPost()) return;
        final sampleSequence =
            ref.read(providerLocationSessionProvider.notifier).nextSequence();
        await locationService.updateArtisanLocation(
          latitude: latest.latitude,
          longitude: latest.longitude,
          accuracyMeters: latest.accuracy,
          recordedAt: latest.timestamp,
          status: 'online',
          onlineSessionId: activeLocationSession.onlineSessionId,
          sampleSequence: sampleSequence,
        );
        if (!requestCurrent(
          activeLocationSession.onlineSessionId,
          attemptedTransitionRevision,
        )) {
          return;
        }
      } else {
        if (!status.isBusy && shouldSkipOnlineLocationPost()) return;
        if (queuedSessionId != activeLocationSession.onlineSessionId) {
          driverQueue.clear();
          queuedSessionId = activeLocationSession.onlineSessionId;
          driverQueue.add(
            _sampleFromPosition(
              latest,
              ref.read(providerLocationSessionProvider.notifier).nextSequence(),
            ),
          );
        }
        final samples = driverQueue.take(_maxDriverSamplesPerBatch).toList();
        if (samples.isEmpty) return;
        await locationService.updateDriverLocationBatch(
          samples: samples,
          onlineSessionId: activeLocationSession.onlineSessionId,
        );
        // Stream events can install and stage a replacement epoch while this
        // request is in flight. Never let a late success from epoch A consume
        // epoch B's queue (or acknowledge a superseded local transition).
        if (!requestCurrent(
              activeLocationSession.onlineSessionId,
              attemptedTransitionRevision,
            ) ||
            queuedSessionId != activeLocationSession.onlineSessionId) {
          return;
        }
        final sentSequences =
            samples.map((sample) => sample.sampleSequence).toSet();
        driverQueue.removeWhere(
          (sample) => sentSequences.contains(sample.sampleSequence),
        );
      }

      if (!requestCurrent(
        activeLocationSession.onlineSessionId,
        attemptedTransitionRevision,
      )) {
        return;
      }
      sent = true;
      retryGate.reset();
      markOnlineLocationPosted();
      lastSyncAt = DateTime.now();
      lastSyncedPosition = latest;
      debugPrint(
        '[LOC] background sync: sent ${isArtisan ? 'artisan' : 'driver'} '
        'location update',
      );
    } on ApiException catch (e) {
      debugPrint('[LOC] background sync failed: $e');
      final rejectedSessionId = attemptedSessionId;
      final rejectedTransitionRevision = attemptedTransitionRevision;
      if (rejectedSessionId == null ||
          rejectedTransitionRevision == null ||
          !requestCurrent(
            rejectedSessionId,
            rejectedTransitionRevision,
          )) {
        return;
      }
      final rejection = classifyProviderLocationRejection(e);
      if (rejection != null) {
        await handleTerminalRejection(
          rejection,
          attemptedSessionId: rejectedSessionId,
        );
      } else if (isProviderCapabilityRegistrationRace(e) &&
          retryGate.consecutiveFailures >= 2) {
        await handleTerminalRejection(
          const ProviderLocationRejection(
            kind: ProviderLocationRejectionKind.eligibility,
            reasonCodes: <String>['OFFER_RECEIPT_CAPABILITY_REQUIRED'],
          ),
          attemptedSessionId: rejectedSessionId,
        );
      } else {
        retryGate.recordFailure(
          container.read(providerLocationSyncNowProvider)(),
        );
      }
    } catch (e) {
      debugPrint('[LOC] background sync error: $e');
      final failedSessionId = attemptedSessionId;
      final failedTransitionRevision = attemptedTransitionRevision;
      final stillOwnsRequest =
          failedSessionId == null || failedTransitionRevision == null
              ? authorityCurrent()
              : requestCurrent(failedSessionId, failedTransitionRevision);
      if (stillOwnsRequest) {
        retryGate.recordFailure(
          container.read(providerLocationSyncNowProvider)(),
        );
      }
    } finally {
      flushInFlight = false;
      if (!disposed &&
          sent &&
          !isArtisan &&
          status.isBusy &&
          driverQueue.length >= _maxDriverSamplesPerBatch) {
        unawaited(flush());
      }
    }
  }

  void onPosition(Position position) {
    if (!authorityCurrent()) return;
    stagePosition(position);

    if (syncDueFor(position)) {
      unawaited(flush());
    }
  }

  final heartbeat = Timer.periodic(cadence, (_) => unawaited(flush()));
  ref.onDispose(() {
    disposed = true;
    heartbeat.cancel();
  });

  ref.listen<AsyncValue<Position>>(driverLocationStreamProvider, (_, next) {
    next.when(
      data: onPosition,
      loading: () => debugPrint('[LOC] background sync: stream loading'),
      error: (e, _) => debugPrint('[LOC] background sync stream error: $e'),
    );
  });

  final initialSessionId =
      ref.read(providerLocationSessionProvider)?.onlineSessionId;
  final initialPause = ref.read(providerLocationSyncPauseProvider);
  if (!status.isBusy &&
      initialSessionId != null &&
      initialPause?.matches(authSession, initialSessionId) == true) {
    Timer.run(() {
      unawaited(
        handleTerminalRejection(
          initialPause!.rejection,
          attemptedSessionId: initialSessionId,
        ),
      );
    });
  }
});

Duration _syncCadence(DriverStatus status, {required bool isArtisan}) {
  if (!status.isBusy) return _idleCadence;
  return isArtisan ? _artisanBusyCadence : _driverBusyCadence;
}

DriverLocationSample _sampleFromPosition(
  Position position,
  int sampleSequence,
) {
  final heading = position.heading.isFinite &&
          position.heading >= 0 &&
          position.heading <= 360
      ? position.heading
      : null;
  final speedKmh = position.speed.isFinite && position.speed > 0
      ? position.speed * 3.6
      : null;

  return DriverLocationSample(
    latitude: position.latitude,
    longitude: position.longitude,
    accuracyMeters: position.accuracy,
    sampleSequence: sampleSequence,
    recordedAt: position.timestamp,
    heading: heading,
    speedKmh: speedKmh,
  );
}
