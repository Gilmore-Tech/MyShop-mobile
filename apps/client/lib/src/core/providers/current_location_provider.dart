import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

/// Cached last-known device GPS fix. Populated by [CurrentLocationService.ensure]
/// (which runs at app start and on demand). Stays null when location services
/// are off or permission is denied — callers must fall back themselves
/// (typically to the pilot-city centre).
final currentDevicePositionProvider = StateProvider<Position?>((_) => null);

/// Delay between the small number of cold-start GPS recovery attempts.
/// Kept injectable so the retry lifecycle can be tested without real waits.
final currentLocationRetryDelayProvider = Provider<Duration>(
  (_) => const Duration(seconds: 3),
);

/// Resolves and caches the device's current location. Use this instead of
/// calling Geolocator directly so every screen shares the same cached fix
/// and the user only sees the permission prompt once per session.
class CurrentLocationService {
  CurrentLocationService(this._ref);

  final Ref _ref;

  /// Serialises concurrent ensure() calls. Geolocator throws
  /// PermissionRequestInProgressException if requestPermission() is
  /// invoked while another request is still pending, which happens on
  /// first launch when several providers/widgets fire location reads
  /// during the initial build. Sharing a single in-flight Future across
  /// callers collapses the parallel requests into one.
  Future<Position?>? _inFlight;
  bool _inFlightRequiresFresh = false;
  bool _inFlightRetryOnFailure = true;
  Future<Position?>? _freshFixInFlight;
  bool _freshFixRetryOnFailure = true;
  int _freshFixGeneration = 0;
  int _lastCompletedFreshFixGeneration = 0;
  Position? _lastCompletedFreshFix;
  Timer? _coldStartRetryTimer;
  bool _coldStartRetryInFlight = false;
  int _coldStartRetryCount = 0;
  int _coldStartRetryGeneration = 0;
  bool _disposed = false;

  static const _maxColdStartRetries = 2;

  @visibleForTesting
  bool get hasScheduledRetry => _coldStartRetryTimer?.isActive ?? false;

  void dispose() {
    _disposed = true;
    _coldStartRetryTimer?.cancel();
    _coldStartRetryTimer = null;
  }

  /// Returns the cached fix if we already have one, otherwise requests
  /// permission (if needed), reads the GPS, caches it, and returns the
  /// new fix. Returns `null` when the user denies permission or location
  /// services are off — the caller decides the fallback.
  ///
  /// Strategy: yield the OS-cached fix first (fast, <100ms) so map screens
  /// open at the right place, then refresh with a fresh GPS read on a short
  /// timeout. Without the timeout, iOS can hang 30s–2min waiting for the
  /// sensor to settle (kCLErrorDomain 0). One-shot callers such as booking can
  /// set [retryOnFailure] false so a later background fix cannot trigger work
  /// after they have already moved on to a manual fallback.
  Future<Position?> ensure({
    bool forceRefresh = false,
    bool retryOnFailure = true,
  }) {
    if (_disposed) return Future<Position?>.value();
    if (!retryOnFailure) {
      // Invalidate both a pending timer and an already-running retry. The
      // latter must not schedule another attempt after a one-shot booking
      // caller has explicitly disabled background recovery.
      _coldStartRetryGeneration += 1;
      _coldStartRetryTimer?.cancel();
      _coldStartRetryTimer = null;
      _coldStartRetryCount = 0;
    }
    if (!forceRefresh) {
      final cached = _ref.read(currentDevicePositionProvider);
      if (cached != null) return Future.value(cached);
    }

    // A normal startup lookup can return its last-known fix while its fresh
    // native GPS request continues in the background. A forced booking lookup
    // must join that request rather than starting a second native GPS read.
    final existingFreshFix = _freshFixInFlight;
    if (forceRefresh && existingFreshFix != null) {
      if (!retryOnFailure) _freshFixRetryOnFailure = false;
      return existingFreshFix;
    }

    final existing = _inFlight;
    if (existing != null) {
      if (!forceRefresh) return existing;

      // Upgrade a normal startup lookup that has not chosen its last-known
      // fast path yet. If it has already chosen that path, wait for the fresh
      // request it starts instead of accepting the old outer result.
      final generationBeforeJoin = _freshFixGeneration;
      _inFlightRequiresFresh = true;
      if (!retryOnFailure) _inFlightRetryOnFailure = false;
      return _joinInFlightRequiringFresh(existing, generationBeforeJoin);
    }

    _inFlightRequiresFresh = forceRefresh;
    _inFlightRetryOnFailure = retryOnFailure;
    late final Future<Position?> tracked;
    tracked = _ensureInternal().whenComplete(() {
      if (identical(_inFlight, tracked)) {
        _inFlight = null;
        _inFlightRequiresFresh = false;
        _inFlightRetryOnFailure = true;
      }
    });
    _inFlight = tracked;
    return tracked;
  }

  Future<Position?> _joinInFlightRequiringFresh(
    Future<Position?> outer,
    int generationBeforeJoin,
  ) async {
    final outerResult = await outer;
    final activeFreshFix = _freshFixInFlight;
    if (activeFreshFix != null) return activeFreshFix;

    // A very fast platform response can finish and clear the shared Future
    // before this continuation runs. Preserve that exact generation's result
    // so the forced caller still receives the fresh attempt, not last-known.
    if (_lastCompletedFreshFixGeneration > generationBeforeJoin) {
      return _lastCompletedFreshFix;
    }
    return outerResult;
  }

  Future<Position?> _ensureInternal() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }

      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;

      // Fast path: seed the cache from the OS last-known position. Normal
      // callers return it immediately while a fresh fix updates the shared
      // cache in the background; map pickers can request forceRefresh=true.
      Position? bestSoFar;
      try {
        final last = await Geolocator.getLastKnownPosition();
        if (last != null) {
          bestSoFar = last;
        }
      } catch (error) {
        debugPrint('[LOC] getLastKnownPosition failed: $error');
      }

      if (_disposed) return null;

      if (bestSoFar != null && !_inFlightRequiresFresh) {
        _ref.read(currentDevicePositionProvider.notifier).state = bestSoFar;
        unawaited(
          _refreshCurrentPosition(
            bestSoFar,
            retryOnFailure: _inFlightRetryOnFailure,
          ),
        );
        return bestSoFar;
      }

      return _refreshCurrentPosition(
        bestSoFar,
        retryOnFailure: _inFlightRetryOnFailure,
      );
    } catch (error) {
      debugPrint('[LOC] location permission/service check failed: $error');
      return _disposed || _inFlightRequiresFresh
          ? null
          : _ref.read(currentDevicePositionProvider);
    }
  }

  Future<Position?> _refreshCurrentPosition(
    Position? fallback, {
    required bool retryOnFailure,
  }) {
    if (_disposed) return Future<Position?>.value(fallback);
    final existing = _freshFixInFlight;
    if (existing != null) {
      if (!retryOnFailure) _freshFixRetryOnFailure = false;
      return existing;
    }

    _freshFixRetryOnFailure = retryOnFailure;
    final generation = ++_freshFixGeneration;
    late final Future<Position?> tracked;
    tracked = _refreshCurrentPositionInternal(
      fallback,
    ).then((position) {
      _lastCompletedFreshFixGeneration = generation;
      _lastCompletedFreshFix = position;
      return position;
    }).whenComplete(() {
      if (identical(_freshFixInFlight, tracked)) {
        _freshFixInFlight = null;
        _freshFixRetryOnFailure = true;
      }
    });
    _freshFixInFlight = tracked;
    return tracked;
  }

  Future<Position?> _refreshCurrentPositionInternal(Position? fallback) async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );
      if (!_disposed) {
        _ref.read(currentDevicePositionProvider.notifier).state = position;
      }
      _coldStartRetryTimer?.cancel();
      _coldStartRetryTimer = null;
      _coldStartRetryCount = 0;
      return position;
    } catch (error) {
      debugPrint('[LOC] getCurrentPosition failed: $error — '
          'using ${fallback == null ? 'no fallback' : 'last-known'}');
      if (_freshFixRetryOnFailure) _scheduleColdStartRetry();
      return fallback;
    }
  }

  void _scheduleColdStartRetry() {
    if (_disposed ||
        _coldStartRetryCount >= _maxColdStartRetries ||
        _coldStartRetryInFlight ||
        (_coldStartRetryTimer?.isActive ?? false)) {
      return;
    }
    _coldStartRetryCount += 1;
    final generation = _coldStartRetryGeneration;
    _coldStartRetryTimer = Timer(
      _ref.read(currentLocationRetryDelayProvider),
      () {
        unawaited(_runColdStartRetry(generation));
      },
    );
  }

  bool _isCurrentRetryGeneration(int generation) {
    return !_disposed && generation == _coldStartRetryGeneration;
  }

  Future<void> _runColdStartRetry(int generation) async {
    if (!_isCurrentRetryGeneration(generation)) return;
    _coldStartRetryTimer = null;
    _coldStartRetryInFlight = true;
    Position? position;
    try {
      position = await _refreshCurrentPosition(
        null,
        retryOnFailure: false,
      );
    } finally {
      _coldStartRetryInFlight = false;
    }
    if (_isCurrentRetryGeneration(generation) && position == null) {
      _scheduleColdStartRetry();
    }
  }
}

final currentLocationServiceProvider = Provider<CurrentLocationService>((ref) {
  final service = CurrentLocationService(ref);
  ref.onDispose(service.dispose);
  return service;
});
