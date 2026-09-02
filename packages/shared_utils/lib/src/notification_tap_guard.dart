import 'dart:async';

/// Builds a privacy-safe identity for one physical notification tap.
///
/// Android/iOS can report the same tap through both the local-notification
/// plugin and Firebase. The selected fields are routing identifiers only; no
/// notification title, body, phone number, or other user content is retained.
String notificationTapIdentity(Map<String, dynamic> payload) {
  String? first(Iterable<String> keys) {
    for (final key in keys) {
      final value = payload[key]?.toString().trim().toLowerCase();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  final parts = <String>[];
  final notificationId = first(const ['notificationId', 'notification_id']);
  if (notificationId != null) {
    // This is the authoritative persisted notification identity. Do not add
    // representation-sensitive fields: FCM can use dotted event types while
    // the local plugin replays the same type with underscores.
    parts.add('notification=$notificationId');
  } else {
    final type = first(const ['type'])?.replaceAll(RegExp(r'[.\-]'), '_');
    if (type != null) parts.add('type=$type');
    for (final group in const <(String, List<String>)>[
      ('message', ['messageId', 'message_id']),
      ('ride', ['rideId', 'ride_id']),
      ('job', ['jobId', 'job_id']),
      ('booking', ['bookingId', 'booking_id']),
      ('ticket', ['ticketId', 'ticket_id']),
      ('call', ['callId', 'call_id']),
      ('bid', ['bidId', 'bid_id']),
      ('offer', ['offerId', 'offer_id']),
      ('destination', ['destination']),
    ]) {
      final value = first(group.$2);
      if (value != null) parts.add('${group.$1}=$value');
    }
  }

  final rawAction = payload['actionId']?.toString().trim().toLowerCase();
  // A body tap and a native "View" button are the same navigation intent,
  // even though only the latter carries an action id. Mutating actions remain
  // distinct so Accept/Decline/Skip can never suppress one another.
  if (rawAction != null &&
      rawAction.isNotEmpty &&
      !rawAction.contains('view') &&
      !rawAction.contains('open')) {
    parts.add('action=$rawAction');
  }
  return parts.join('|');
}

/// Coalesces duplicate callbacks for the same recent navigation intent.
///
/// An in-flight duplicate joins the original operation. A successfully
/// handled tap leaves a short tombstone so a delayed second platform callback
/// cannot reopen the destination after the user has already pressed Back.
class NotificationTapGuard {
  NotificationTapGuard({this.replayWindow = const Duration(seconds: 5)});

  final Duration replayWindow;
  final Map<String, Future<void>> _inFlight = <String, Future<void>>{};
  final Map<String, Timer> _recent = <String, Timer>{};
  int _generation = 0;
  bool _disposed = false;

  Future<bool> run(String identity, Future<void> Function() operation) async {
    if (_disposed) return false;
    if (identity.isEmpty) {
      await operation();
      return true;
    }

    final existing = _inFlight[identity];
    if (existing != null) {
      await existing;
      return false;
    }
    if (_recent.containsKey(identity)) return false;

    final generation = _generation;
    final active = Future<void>.sync(operation);
    _inFlight[identity] = active;
    try {
      await active;
      if (_generation == generation && identical(_inFlight[identity], active)) {
        _inFlight.remove(identity);
      }
      if (!_disposed && _generation == generation) {
        _recent.remove(identity)?.cancel();
        _recent[identity] = Timer(replayWindow, () {
          _recent.remove(identity);
        });
      }
      return true;
    } catch (_) {
      if (_generation == generation && identical(_inFlight[identity], active)) {
        _inFlight.remove(identity);
      }
      rethrow;
    }
  }

  void reset() {
    _generation += 1;
    _inFlight.clear();
    for (final timer in _recent.values) {
      timer.cancel();
    }
    _recent.clear();
  }

  void dispose() {
    if (_disposed) return;
    reset();
    _disposed = true;
  }
}
