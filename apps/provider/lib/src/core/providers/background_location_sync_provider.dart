import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_models/shared_models.dart';

import '../../features/auth/providers/current_user_provider.dart';
import '../../features/driver_home/providers/driver_location_provider.dart';
import '../../features/profile/providers/provider_type_provider.dart';
import '../di/providers.dart';
import 'availability_controller.dart';
import 'provider_status_provider.dart';

const int _maxDriverSamplesPerBatch = 120;
const int _maxQueuedDriverSamples = 360;
const Duration _driverBusyCadence = Duration(seconds: 5);
const Duration _artisanBusyCadence = Duration(seconds: 20);
const Duration _idleCadence = Duration(seconds: 60);
const Duration _busySampleMinAge = Duration(seconds: 4);
const double _busySampleMinMeters = 10;
const double _idleHeartbeatMinMeters = 50;

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
  final locationService = ref.read(locationServiceProvider);
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

  Future<void> flush() async {
    if (disposed || flushInFlight) return;
    final latest = latestPosition;
    if (latest == null) return;

    flushInFlight = true;
    var sent = false;
    try {
      if (isArtisan) {
        if (shouldSkipOnlineLocationPost()) return;
        await locationService.updateArtisanLocation(
          latitude: latest.latitude,
          longitude: latest.longitude,
          status: 'online',
        );
      } else {
        if (!status.isBusy && shouldSkipOnlineLocationPost()) return;
        final samples = status.isBusy
            ? driverQueue.take(_maxDriverSamplesPerBatch).toList()
            : <DriverLocationSample>[_sampleFromPosition(latest)];
        if (samples.isEmpty) return;
        await locationService.updateDriverLocationBatch(samples: samples);
        if (status.isBusy) {
          driverQueue.removeRange(0, samples.length);
        } else {
          driverQueue.clear();
        }
      }

      sent = true;
      markOnlineLocationPosted();
      lastSyncAt = DateTime.now();
      lastSyncedPosition = latest;
      debugPrint(
        '[LOC] background sync: sent ${isArtisan ? 'artisan' : 'driver'} '
        'location (${latest.latitude}, ${latest.longitude})',
      );
    } on ApiException catch (e) {
      debugPrint('[LOC] background sync failed: $e');
    } catch (e) {
      debugPrint('[LOC] background sync error: $e');
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
    latestPosition = position;
    ref.read(lastKnownPositionProvider.notifier).state = position;

    if (!isArtisan) {
      if (status.isBusy) {
        if (busySampleDue(position)) {
          driverQueue.add(_sampleFromPosition(position));
          lastQueuedDriverPosition = position;
          capDriverQueue();
        }
      } else {
        driverQueue
          ..clear()
          ..add(_sampleFromPosition(position));
        lastQueuedDriverPosition = position;
      }
    }

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
});

Duration _syncCadence(DriverStatus status, {required bool isArtisan}) {
  if (!status.isBusy) return _idleCadence;
  return isArtisan ? _artisanBusyCadence : _driverBusyCadence;
}

DriverLocationSample _sampleFromPosition(Position position) {
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
    recordedAt: position.timestamp,
    heading: heading,
    speedKmh: speedKmh,
  );
}
