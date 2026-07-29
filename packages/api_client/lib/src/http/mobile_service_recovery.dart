import 'dart:async';
import 'dart:math';

typedef MobileServiceReadinessProbe = Future<void> Function();
typedef MobileServiceRecoveryDelayResolver = Duration Function(
  int consecutiveFailures,
);

/// Coordinates app-level readiness probes after a confirmed connectivity issue.
///
/// There is at most one readiness request in flight. Automatic probes pause
/// while the app is backgrounded, resume when it returns to the foreground,
/// and use bounded exponential backoff so a widespread outage cannot create a
/// synchronized retry storm. A user-initiated retry joins an existing probe or
/// starts one immediately.
class MobileServiceRecoveryCoordinator {
  MobileServiceRecoveryCoordinator({
    required MobileServiceReadinessProbe probe,
    MobileServiceRecoveryDelayResolver delayResolver =
        defaultMobileServiceRecoveryDelay,
  })  : _probe = probe,
        _delayResolver = delayResolver;

  final MobileServiceReadinessProbe _probe;
  final MobileServiceRecoveryDelayResolver _delayResolver;

  Timer? _timer;
  Future<void>? _inFlight;
  bool _recoveryNeeded = false;
  bool _foreground = true;
  bool _disposed = false;
  int _consecutiveFailures = 0;

  /// Updates the app-owned recovery conditions.
  ///
  /// Repeated calls with the same state are intentionally cheap and do not
  /// reset the current backoff window.
  void update({required bool recoveryNeeded, required bool foreground}) {
    if (_disposed) return;

    final becameEligible =
        recoveryNeeded && foreground && (!_recoveryNeeded || !_foreground);
    _recoveryNeeded = recoveryNeeded;
    _foreground = foreground;

    if (!recoveryNeeded) {
      _consecutiveFailures = 0;
      _cancelScheduledProbe();
      return;
    }

    if (!foreground) {
      _cancelScheduledProbe();
      return;
    }

    if (becameEligible || (_timer == null && _inFlight == null)) {
      _scheduleProbe();
    }
  }

  /// Runs a readiness check now, coalescing with any request already in flight.
  Future<void> retryNow() {
    if (_disposed) return Future<void>.value();
    _recoveryNeeded = true;
    _cancelScheduledProbe();
    return _runProbe();
  }

  void _scheduleProbe() {
    if (_disposed ||
        !_recoveryNeeded ||
        !_foreground ||
        _timer != null ||
        _inFlight != null) {
      return;
    }

    final delay = _delayResolver(_consecutiveFailures);
    _timer = Timer(delay, () {
      _timer = null;
      _runProbe();
    });
  }

  Future<void> _runProbe() {
    final activeProbe = _inFlight;
    if (activeProbe != null) return activeProbe;
    if (_disposed || !_foreground) return Future<void>.value();

    final completer = Completer<void>();
    _inFlight = completer.future;

    () async {
      var recovered = false;
      try {
        await _probe();
        recovered = true;
        _recoveryNeeded = false;
        _consecutiveFailures = 0;
        _cancelScheduledProbe();
      } catch (_) {
        _consecutiveFailures = min(_consecutiveFailures + 1, 30);
      } finally {
        _inFlight = null;
        if (!recovered) _scheduleProbe();
        completer.complete();
      }
    }();

    return completer.future;
  }

  void _cancelScheduledProbe() {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _cancelScheduledProbe();
  }
}

/// A 1–15 second exponential delay with ±20% jitter.
///
/// The cap keeps recovery responsive while jitter spreads readiness traffic
/// from devices that lose or regain connectivity at the same time.
Duration defaultMobileServiceRecoveryDelay(int consecutiveFailures) {
  const minimumMs = 1000;
  const maximumMs = 15000;
  final exponent = min(max(consecutiveFailures, 0), 5);
  final baseMs = min(minimumMs * (1 << exponent), maximumMs);
  final jitter = 0.8 + (Random().nextDouble() * 0.4);
  return Duration(milliseconds: (baseMs * jitter).round());
}
