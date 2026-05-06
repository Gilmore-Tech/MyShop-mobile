import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:shared_preferences/shared_preferences.dart';

/// A locally-persisted handle to an in-flight Paystack charge, keyed on
/// the booking. Survives app restarts so the user can resume the OTP /
/// USSD flow on the next launch — without it, an app kill mid-charge
/// strands us in 409 PAYMENT_ALREADY_INITIATED with no paymentId to
/// abandon.
///
/// We store the bare minimum needed to reconcile state on resume:
///   - [paymentId] — local UUID, used to call /payments/:id/abandon
///   - [bookingType] / [bookingId] — to call /payments/abandon-by-booking
///     when we lost the paymentId or want a belt-and-braces clear before
///     /initiate.
class PendingPaymentRecord {
  final String paymentId;
  final String bookingType;
  final String bookingId;

  const PendingPaymentRecord({
    required this.paymentId,
    required this.bookingType,
    required this.bookingId,
  });

  Map<String, dynamic> toJson() => {
        'paymentId': paymentId,
        'bookingType': bookingType,
        'bookingId': bookingId,
      };

  static PendingPaymentRecord? fromJson(Map<String, dynamic> json) {
    final pid = json['paymentId'];
    final type = json['bookingType'];
    final id = json['bookingId'];
    if (pid is String && type is String && id is String) {
      return PendingPaymentRecord(
        paymentId: pid,
        bookingType: type,
        bookingId: id,
      );
    }
    return null;
  }
}

/// SharedPreferences-backed store of in-flight payment handles, keyed on
/// `${bookingType}:${bookingId}` so a ride and a job for the same id
/// (different namespaces) can't collide.
class PendingPaymentStore {
  PendingPaymentStore();

  static const _kKey = 'myshop.pending_payments.v1';

  Future<SharedPreferences> _prefs() => SharedPreferences.getInstance();

  String _composeKey(String bookingType, String bookingId) =>
      '$bookingType:$bookingId';

  /// Persist the in-flight charge for ([bookingType], [bookingId]).
  /// Overwrites any prior entry for the same booking.
  Future<void> save(PendingPaymentRecord record) async {
    final prefs = await _prefs();
    final all = _readAll(prefs);
    all[_composeKey(record.bookingType, record.bookingId)] = record.toJson();
    await prefs.setString(_kKey, jsonEncode(all));
  }

  /// Look up the in-flight charge for ([bookingType], [bookingId]), or
  /// null when nothing is stored.
  Future<PendingPaymentRecord?> read({
    required String bookingType,
    required String bookingId,
  }) async {
    final prefs = await _prefs();
    final all = _readAll(prefs);
    final raw = all[_composeKey(bookingType, bookingId)];
    if (raw is Map<String, dynamic>) return PendingPaymentRecord.fromJson(raw);
    return null;
  }

  /// Drop the entry for ([bookingType], [bookingId]) — call this when
  /// the charge has reached a terminal state (escrowed / completed /
  /// failed) so we don't accidentally try to abandon a settled payment.
  Future<void> clear({
    required String bookingType,
    required String bookingId,
  }) async {
    final prefs = await _prefs();
    final all = _readAll(prefs);
    final removed = all.remove(_composeKey(bookingType, bookingId));
    if (removed != null) {
      await prefs.setString(_kKey, jsonEncode(all));
    }
  }

  Map<String, dynamic> _readAll(SharedPreferences prefs) {
    final raw = prefs.getString(_kKey);
    if (raw == null || raw.isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (e) {
      developer.log('PendingPaymentStore: failed to decode — $e',
          name: 'Payment', level: 700);
    }
    return <String, dynamic>{};
  }
}
