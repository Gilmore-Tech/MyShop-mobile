import 'package:api_client/mobile_diagnostics.dart' show debugLog;
import 'dart:async';
import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const int rideOfferReceiptProtocolVersion = 2;
const String _rideOfferStorePrefix = 'myshop.ride_offer.v2.';

@immutable
class ReceivedRideOffer {
  const ReceivedRideOffer({
    required this.rideId,
    required this.offerId,
    required this.decisionExpiresAt,
    required this.payload,
  });

  final String rideId;
  final String offerId;
  final DateTime decisionExpiresAt;
  final Map<String, dynamic> payload;
}

bool isReceiptRideOffer(Map<String, dynamic> payload) {
  final version = int.tryParse(payload['offerVersion']?.toString() ?? '');
  return version == rideOfferReceiptProtocolVersion &&
      _rideId(payload) != null &&
      _offerId(payload) != null;
}

/// Persist before acknowledging. A process kill after the server activates the
/// 45-second window can then be reconciled by the pending-request endpoint;
/// the server never mistakes transport success for device receipt.
Future<bool> persistIncomingRideOffer(Map<String, dynamic> payload) async {
  final offerId = _offerId(payload);
  final rideId = _rideId(payload);
  if (offerId == null || rideId == null) return false;
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return prefs.setString(
      '$_rideOfferStorePrefix$offerId',
      jsonEncode({
        'rideId': rideId,
        'offerId': offerId,
        'offerVersion': payload['offerVersion']?.toString(),
        if (payload['deliveryExpiresAt'] != null)
          'deliveryExpiresAt': payload['deliveryExpiresAt'].toString(),
        if (payload['decisionExpiresAt'] != null)
          'decisionExpiresAt': payload['decisionExpiresAt'].toString(),
        if (payload['acceptanceExpiresAt'] != null)
          'acceptanceExpiresAt': payload['acceptanceExpiresAt'].toString(),
        if (payload['serverDecisionExpiresAt'] != null)
          'serverDecisionExpiresAt':
              payload['serverDecisionExpiresAt'].toString(),
        if (payload['serverNow'] != null)
          'serverNow': payload['serverNow'].toString(),
        'localHandoffAt': DateTime.now().toUtc().toIso8601String()
      }),
    );
  } catch (error) {
    debugLog(() => '[RideOfferReceipt] durable handoff failed: $error');
    return false;
  }
}

Future<ReceivedRideOffer?> acknowledgeRideOfferWithSocket({
  required Map<String, dynamic> payload,
  required SocketService socket,
  required RideService rides,
}) async {
  final compatibility = _legacyOrInvalidReceipt(payload);
  if (!isReceiptRideOffer(payload)) return compatibility;
  if (!await persistIncomingRideOffer(payload)) return null;

  final rideId = _rideId(payload)!;
  final offerId = _offerId(payload)!;
  try {
    final transport = Stopwatch()..start();
    final ack = await socket.emitWithAck(
      'ride:offer:received',
      {'rideId': rideId, 'offerId': offerId},
      timeout: const Duration(seconds: 5),
    );
    transport.stop();
    final receipt = _receiptMap(ack);
    if (receipt != null) {
      return _applyReceipt(
        payload,
        receipt,
        transportElapsed: transport.elapsed,
      );
    }
  } catch (error) {
    debugLog(() => '[RideOfferReceipt] socket receipt failed: $error');
  }

  // A socket can disconnect between delivery and ack. Authenticated REST is
  // the same idempotent transition and may refresh a near-expiry JWT in the
  // foreground through the normal Dio client.
  try {
    final transport = Stopwatch()..start();
    final receipt = await rides.acknowledgeRideOffer(rideId, offerId);
    transport.stop();
    return _applyReceipt(
      payload,
      receipt,
      transportElapsed: transport.elapsed,
    );
  } catch (error) {
    debugLog(() => '[RideOfferReceipt] REST receipt fallback failed: $error');
    return null;
  }
}

/// Background-isolate acknowledgement. Deliberately does not refresh tokens:
/// rotating auth state from a short-lived isolate can race the main app. An
/// expired/missing access token means no receipt, so the server safely moves to
/// the next provider after the 10-second window.
Future<ReceivedRideOffer?> acknowledgeRideOfferFromBackground(
  Map<String, dynamic> payload,
) async {
  final compatibility = _legacyOrInvalidReceipt(payload);
  if (!isReceiptRideOffer(payload)) return compatibility;
  if (!await persistIncomingRideOffer(payload)) return null;

  final token = await SecureTokenStorage().readAccessToken();
  if (token == null || token.isEmpty) return null;
  final rideId = _rideId(payload)!;
  final offerId = _offerId(payload)!;
  final dio = Dio(
    BaseOptions(
      baseUrl: ApiConfig.fromEnvironment().baseUrl,
      connectTimeout: const Duration(seconds: 4),
      receiveTimeout: const Duration(seconds: 4),
      sendTimeout: const Duration(seconds: 4),
      headers: {'Authorization': 'Bearer $token'},
    ),
  );
  try {
    final transport = Stopwatch()..start();
    final response = await dio.post('/rides/$rideId/offers/$offerId/received');
    transport.stop();
    final receipt = _receiptMap(response.data);
    if (receipt == null) return null;
    return _applyReceipt(
      payload,
      receipt,
      transportElapsed: transport.elapsed,
    );
  } on DioException catch (error) {
    debugLog(
      () => '[RideOfferReceipt] background receipt rejected: '
          '${error.response?.statusCode ?? error.type}',
    );
    return null;
  } catch (error) {
    debugLog(() => '[RideOfferReceipt] background receipt failed: $error');
    return null;
  } finally {
    dio.close(force: true);
  }
}

Future<void> clearStoredRideOffer(String offerId) async {
  if (offerId.isEmpty) return;
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_rideOfferStorePrefix$offerId');
  } catch (error) {
    debugLog(() => '[RideOfferReceipt] local cleanup failed: $error');
  }
}

ReceivedRideOffer? _applyReceipt(
  Map<String, dynamic> delivery,
  Map<String, dynamic> receipt, {
  Duration transportElapsed = Duration.zero,
}) {
  final received = buildReceivedRideOfferForTesting(
    delivery: delivery,
    receipt: receipt,
    transportElapsed: transportElapsed,
  );
  if (received == null) return null;

  // Replace the pre-receipt disk envelope with the actionable one. Pending
  // request recovery remains the server-authoritative fallback if this
  // best-effort local update is interrupted.
  unawaited(persistIncomingRideOffer(received.payload));
  return received;
}

@visibleForTesting
ReceivedRideOffer? buildReceivedRideOfferForTesting({
  required Map<String, dynamic> delivery,
  required Map<String, dynamic> receipt,
  DateTime? now,
  Duration transportElapsed = Duration.zero,
}) {
  final rideId = _rideId(delivery);
  final offerId = _offerId(delivery);
  final rawDeadline = receipt['decisionExpiresAt'] ??
      receipt['acceptanceExpiresAt'] ??
      receipt['expiresAt'];
  final serverDeadline =
      DateTime.tryParse(rawDeadline?.toString() ?? '')?.toUtc();
  if (rideId == null || offerId == null || serverDeadline == null) return null;
  final localNow = (now ?? DateTime.now()).toUtc();
  final serverNow =
      DateTime.tryParse(receipt['serverNow']?.toString() ?? '')?.toUtc();
  late final DateTime presentationDeadline;
  if (serverNow != null) {
    final elapsed =
        transportElapsed.isNegative ? Duration.zero : transportElapsed;
    final remaining = serverDeadline.difference(serverNow) - elapsed;
    if (remaining <= Duration.zero) return null;
    presentationDeadline = localNow.add(remaining);
  } else {
    // Compatibility only for a pre-clock-projection backend. Protocol-v2
    // responses include serverNow, so the handset wall clock is not authority.
    if (!serverDeadline.isAfter(localNow)) return null;
    presentationDeadline = serverDeadline;
  }

  final safeDetails = _decodeJsonObject(
    delivery['offerPayload'] ?? delivery['ridePayload'],
  );
  final merged = <String, dynamic>{
    ...safeDetails,
    ...delivery,
    'offerId': offerId,
    'offerVersion': '$rideOfferReceiptProtocolVersion',
    'serverDecisionExpiresAt': serverDeadline.toIso8601String(),
    if (serverNow != null) 'serverNow': serverNow.toIso8601String(),
    'expiresAt': presentationDeadline.toIso8601String(),
    'acceptanceExpiresAt': presentationDeadline.toIso8601String(),
    'decisionExpiresAt': presentationDeadline.toIso8601String(),
    'acceptanceWindowSeconds':
        receipt['acceptanceWindowSeconds']?.toString() ?? '45',
  };
  return ReceivedRideOffer(
    rideId: rideId,
    offerId: offerId,
    decisionExpiresAt: presentationDeadline,
    payload: merged,
  );
}

ReceivedRideOffer? _legacyOrInvalidReceipt(Map<String, dynamic> payload) {
  final version = int.tryParse(payload['offerVersion']?.toString() ?? '');
  // Version 2+ must satisfy the authenticated receipt contract. Never fall
  // back to the legacy ride-id-as-offer-id path for a malformed or future
  // receipt envelope.
  if (version != null && version >= rideOfferReceiptProtocolVersion) {
    return null;
  }
  return _legacyReceipt(payload);
}

ReceivedRideOffer? _legacyReceipt(Map<String, dynamic> payload) {
  final rideId = _rideId(payload);
  final offerId = _offerId(payload) ?? rideId;
  final deadline = _deadline(payload);
  if (rideId == null || offerId == null || deadline == null) return null;
  if (!deadline.isAfter(DateTime.now().toUtc())) return null;
  return ReceivedRideOffer(
    rideId: rideId,
    offerId: offerId,
    decisionExpiresAt: deadline,
    payload: payload,
  );
}

Map<String, dynamic>? _receiptMap(Object? raw) {
  if (raw is! Map) return null;
  var map = Map<String, dynamic>.from(raw);
  if (map['success'] == true && map['data'] is Map) {
    map = Map<String, dynamic>.from(map['data'] as Map);
  }
  if (map['data'] is Map && !map.containsKey('decisionExpiresAt')) {
    map = Map<String, dynamic>.from(map['data'] as Map);
  }
  return map;
}

DateTime? _deadline(Map<String, dynamic> payload) {
  for (final key in const [
    'decisionExpiresAt',
    'acceptanceExpiresAt',
    'expiresAt',
  ]) {
    final parsed = DateTime.tryParse(payload[key]?.toString() ?? '')?.toUtc();
    if (parsed != null) return parsed;
  }
  return null;
}

String? _rideId(Map<String, dynamic> payload) =>
    _nonEmpty(payload['rideId']) ?? _nonEmpty(payload['id']);

String? _offerId(Map<String, dynamic> payload) => _nonEmpty(payload['offerId']);

String? _nonEmpty(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

Map<String, dynamic> _decodeJsonObject(Object? raw) {
  if (raw is Map) return Map<String, dynamic>.from(raw);
  if (raw is! String || raw.isEmpty) return const <String, dynamic>{};
  try {
    final decoded = jsonDecode(raw);
    return decoded is Map
        ? Map<String, dynamic>.from(decoded)
        : const <String, dynamic>{};
  } catch (_) {
    return const <String, dynamic>{};
  }
}
