import 'dart:async';
import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const int jobOfferReceiptProtocolVersion = 2;
const String _jobOfferStorePrefix = 'myshop.job_offer.v2.';
final Map<String, Future<ReceivedJobOffer?>> _jobReceiptInFlight = {};
final Map<String, ReceivedJobOffer> _receivedJobOfferCache = {};
final Set<String> _invalidatedJobOfferIds = <String>{};
int _jobReceiptGeneration = 0;

@immutable
class ReceivedJobOffer {
  const ReceivedJobOffer({
    required this.jobId,
    required this.payload,
    this.offerId,
    this.decisionExpiresAt,
  });

  final String jobId;
  final String? offerId;
  final DateTime? decisionExpiresAt;
  final Map<String, dynamic> payload;

  bool get hasExactReceipt => offerId != null && offerId!.isNotEmpty;
}

@immutable
class StoredJobOfferIdentity {
  const StoredJobOfferIdentity({
    required this.jobId,
    required this.offerId,
    required this.localHandoffAt,
  });

  final String jobId;
  final String offerId;
  final DateTime localHandoffAt;
}

bool isReceiptJobOffer(Map<String, dynamic> payload) {
  final version = int.tryParse(payload['offerVersion']?.toString() ?? '');
  return version == jobOfferReceiptProtocolVersion &&
      _jobId(payload) != null &&
      _offerId(payload) != null;
}

/// Persists only the exact offer identity and timing metadata before the
/// authenticated receipt call. Customer names, addresses and job details are
/// deliberately excluded from this durable handoff.
Future<bool> persistIncomingJobOffer(Map<String, dynamic> payload) async {
  final jobId = _jobId(payload);
  final offerId = _offerId(payload);
  if (jobId == null || offerId == null) return false;
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return prefs.setString(
      '$_jobOfferStorePrefix$offerId',
      jsonEncode({
        'jobId': jobId,
        'offerId': offerId,
        'offerVersion': payload['offerVersion']?.toString(),
        if (payload['deliveryExpiresAt'] != null)
          'deliveryExpiresAt': payload['deliveryExpiresAt'].toString(),
        if (payload['decisionExpiresAt'] != null)
          'decisionExpiresAt': payload['decisionExpiresAt'].toString(),
        if (payload['serverDecisionExpiresAt'] != null)
          'serverDecisionExpiresAt':
              payload['serverDecisionExpiresAt'].toString(),
        if (payload['serverNow'] != null)
          'serverNow': payload['serverNow'].toString(),
        'localHandoffAt': DateTime.now().toUtc().toIso8601String(),
      }),
    );
  } catch (error) {
    debugPrint('[JobOfferReceipt] durable handoff failed: $error');
    return false;
  }
}

/// Receipts a version-2 job offer through authenticated REST. Legacy payloads
/// are returned unchanged and never receive an invented offer identity.
Future<ReceivedJobOffer?> acknowledgeJobOffer({
  required Map<String, dynamic> payload,
  required JobService jobs,
}) async {
  final compatibility = _legacyOrInvalidReceipt(payload);
  if (!isReceiptJobOffer(payload)) return compatibility;
  final offerId = _offerId(payload)!;
  if (_invalidatedJobOfferIds.contains(offerId)) return null;
  final cached = _receivedJobOfferCache[offerId];
  if (cached != null &&
      (cached.decisionExpiresAt == null ||
          cached.decisionExpiresAt!.isAfter(DateTime.now().toUtc()))) {
    return _enrichReceivedOffer(cached, payload);
  }
  final existing = _jobReceiptInFlight[offerId];
  if (existing != null) {
    final generation = _jobReceiptGeneration;
    final received = await existing;
    if (generation != _jobReceiptGeneration ||
        _invalidatedJobOfferIds.contains(offerId)) {
      return null;
    }
    return received == null ? null : _enrichReceivedOffer(received, payload);
  }

  final generation = _jobReceiptGeneration;
  final operation = _acknowledgeExactJobOffer(
    payload: payload,
    jobs: jobs,
    generation: generation,
  );
  _jobReceiptInFlight[offerId] = operation;
  try {
    final received = await operation;
    // Logout/account replacement advances the generation before clearing the
    // durable store. A receipt that began under the old identity must never
    // repopulate memory or surface customer/job data for the next account.
    if (generation != _jobReceiptGeneration ||
        _invalidatedJobOfferIds.contains(offerId)) {
      await clearStoredJobOffer(offerId);
      return null;
    }
    if (received != null) {
      _receivedJobOfferCache[offerId] = received;
      unawaited(persistIncomingJobOffer(received.payload));
    }
    return received;
  } finally {
    if (identical(_jobReceiptInFlight[offerId], operation)) {
      _jobReceiptInFlight.remove(offerId);
    }
  }
}

Future<ReceivedJobOffer?> _acknowledgeExactJobOffer({
  required Map<String, dynamic> payload,
  required JobService jobs,
  required int generation,
}) async {
  if (!await persistIncomingJobOffer(payload)) return null;

  final jobId = _jobId(payload)!;
  final offerId = _offerId(payload)!;
  if (generation != _jobReceiptGeneration ||
      _invalidatedJobOfferIds.contains(offerId)) {
    await clearStoredJobOffer(offerId);
    return null;
  }
  try {
    final transport = Stopwatch()..start();
    final receipt = await jobs.acknowledgeJobOffer(jobId, offerId);
    transport.stop();
    final received = _applyReceipt(
      payload,
      receipt,
      transportElapsed: transport.elapsed,
    );
    if (generation != _jobReceiptGeneration ||
        _invalidatedJobOfferIds.contains(offerId)) {
      await clearStoredJobOffer(offerId);
      return null;
    }
    return received;
  } catch (error) {
    debugPrint('[JobOfferReceipt] REST receipt failed: $error');
    return null;
  }
}

/// Background-isolate receipt. It intentionally does not rotate auth tokens;
/// a missing/expired token means no receipt and the server can safely advance
/// after its delivery window.
Future<ReceivedJobOffer?> acknowledgeJobOfferFromBackground(
  Map<String, dynamic> payload,
) async {
  final compatibility = _legacyOrInvalidReceipt(payload);
  if (!isReceiptJobOffer(payload)) return compatibility;
  if (!await persistIncomingJobOffer(payload)) return null;

  final token = await SecureTokenStorage().readAccessToken();
  if (token == null || token.isEmpty) return null;
  final jobId = _jobId(payload)!;
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
    final response = await dio.post(
      '/jobs/$jobId/offers/$offerId/received',
    );
    transport.stop();
    final receipt = _receiptMap(response.data);
    if (receipt == null) return null;
    final received = _applyReceipt(
      payload,
      receipt,
      transportElapsed: transport.elapsed,
    );
    if (received != null) {
      unawaited(persistIncomingJobOffer(received.payload));
    }
    return received;
  } on DioException catch (error) {
    debugPrint(
      '[JobOfferReceipt] background receipt rejected: '
      '${error.response?.statusCode ?? error.type}',
    );
    return null;
  } catch (error) {
    debugPrint('[JobOfferReceipt] background receipt failed: $error');
    return null;
  } finally {
    dio.close(force: true);
  }
}

Future<void> clearStoredJobOffer(String? offerId) async {
  if (offerId == null || offerId.isEmpty) return;
  _invalidatedJobOfferIds.add(offerId);
  _receivedJobOfferCache.remove(offerId);
  _jobReceiptInFlight.remove(offerId);
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_jobOfferStorePrefix$offerId');
  } catch (error) {
    debugPrint('[JobOfferReceipt] local cleanup failed: $error');
  }
}

/// Purges every account-scoped job offer handoff on logout/account switch.
///
/// Incrementing the generation happens synchronously, before the first await,
/// so in-flight receipts are fenced even when the caller intentionally does
/// not wait for SharedPreferences cleanup before completing navigation.
Future<void> purgeStoredJobOffers() async {
  _jobReceiptGeneration += 1;
  _receivedJobOfferCache.clear();
  _jobReceiptInFlight.clear();
  _invalidatedJobOfferIds.clear();
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final keys = prefs
        .getKeys()
        .where((key) => key.startsWith(_jobOfferStorePrefix))
        .toList(growable: false);
    await Future.wait(keys.map(prefs.remove));
  } catch (error) {
    debugPrint('[JobOfferReceipt] account cleanup failed: $error');
  }
}

@visibleForTesting
void resetJobOfferReceiptMemoryForTesting() {
  _jobReceiptGeneration += 1;
  _receivedJobOfferCache.clear();
  _jobReceiptInFlight.clear();
  _invalidatedJobOfferIds.clear();
}

Future<List<StoredJobOfferIdentity>> readStoredJobOfferIdentities({
  int limit = maxKnownProviderOfferIds,
}) async {
  if (limit < 1 || limit > maxKnownProviderOfferIds) {
    throw RangeError.range(limit, 1, maxKnownProviderOfferIds, 'limit');
  }
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final identities = <StoredJobOfferIdentity>[];
    for (final key in prefs.getKeys()) {
      if (!key.startsWith(_jobOfferStorePrefix)) continue;
      final decoded = _decodeJsonObject(prefs.getString(key));
      final jobId = decoded['jobId']?.toString();
      final offerId = decoded['offerId']?.toString();
      final handoff = DateTime.tryParse(
        decoded['localHandoffAt']?.toString() ?? '',
      );
      if (!_isUuidV4(jobId) ||
          !_isUuidV4(offerId) ||
          handoff == null ||
          key != '$_jobOfferStorePrefix$offerId') {
        continue;
      }
      identities.add(
        StoredJobOfferIdentity(
          jobId: jobId!,
          offerId: offerId!,
          localHandoffAt: handoff.toUtc(),
        ),
      );
    }
    identities.sort(
      (left, right) => right.localHandoffAt.compareTo(left.localHandoffAt),
    );
    return identities.take(limit).toList(growable: false);
  } catch (error) {
    debugPrint('[JobOfferReceipt] durable identity read failed: $error');
    return const <StoredJobOfferIdentity>[];
  }
}

ReceivedJobOffer? _applyReceipt(
  Map<String, dynamic> delivery,
  Map<String, dynamic> receipt, {
  Duration transportElapsed = Duration.zero,
}) {
  final received = buildReceivedJobOfferForTesting(
    delivery: delivery,
    receipt: receipt,
    transportElapsed: transportElapsed,
  );
  return received;
}

@visibleForTesting
ReceivedJobOffer? buildReceivedJobOfferForTesting({
  required Map<String, dynamic> delivery,
  required Map<String, dynamic> receipt,
  DateTime? now,
  Duration transportElapsed = Duration.zero,
}) {
  final jobId = _jobId(delivery);
  final offerId = _offerId(delivery);
  final receiptJobId = _nonEmpty(receipt['jobId']);
  final receiptOfferId = _nonEmpty(receipt['offerId']);
  final receiptState = _nonEmpty(receipt['state'])?.toLowerCase();
  final rawDeadline = receipt['decisionExpiresAt'] ??
      receipt['quoteDeadlineAt'] ??
      receipt['expiresAt'];
  final serverDeadline =
      DateTime.tryParse(rawDeadline?.toString() ?? '')?.toUtc();
  if (jobId == null ||
      offerId == null ||
      receiptJobId != jobId ||
      receiptOfferId != offerId ||
      receiptState != 'active' ||
      serverDeadline == null) {
    return null;
  }

  final localNow = (now ?? DateTime.now()).toUtc();
  final serverNow =
      DateTime.tryParse(receipt['serverNow']?.toString() ?? '')?.toUtc();
  late final DateTime presentationDeadline;
  if (serverNow != null) {
    // `serverNow` and `decisionExpiresAt` are captured together in the
    // receipt response. Subtracting the entire client request RTT again
    // unfairly charges the provider for the outbound leg and server work.
    // Project the server-authored remaining window onto the handset clock.
    final remaining = serverDeadline.difference(serverNow);
    if (remaining <= Duration.zero) return null;
    presentationDeadline = localNow.add(remaining);
  } else {
    if (!serverDeadline.isAfter(localNow)) return null;
    presentationDeadline = serverDeadline;
  }

  final safeDetails = _decodeJsonObject(
    delivery['offerPayload'] ?? delivery['jobPayload'],
  );
  final merged = <String, dynamic>{
    ...safeDetails,
    ...delivery,
    'jobId': jobId,
    'offerId': offerId,
    'offerVersion': '$jobOfferReceiptProtocolVersion',
    'serverDecisionExpiresAt': serverDeadline.toIso8601String(),
    if (serverNow != null) 'serverNow': serverNow.toIso8601String(),
    'expiresAt': presentationDeadline.toIso8601String(),
    'decisionExpiresAt': presentationDeadline.toIso8601String(),
    'responseWindowSeconds':
        receipt['responseWindowSeconds']?.toString() ?? '45',
  };
  return ReceivedJobOffer(
    jobId: jobId,
    offerId: offerId,
    decisionExpiresAt: presentationDeadline,
    payload: merged,
  );
}

ReceivedJobOffer? _legacyOrInvalidReceipt(Map<String, dynamic> payload) {
  final version = int.tryParse(payload['offerVersion']?.toString() ?? '');
  if (version != null && version >= jobOfferReceiptProtocolVersion) {
    return null;
  }
  final jobId = _jobId(payload);
  if (jobId == null) return null;
  return ReceivedJobOffer(
    jobId: jobId,
    payload: payload,
    decisionExpiresAt: _deadline(payload),
  );
}

ReceivedJobOffer _enrichReceivedOffer(
  ReceivedJobOffer received,
  Map<String, dynamic> delivery,
) {
  final safeDetails = _decodeJsonObject(
    delivery['offerPayload'] ?? delivery['jobPayload'],
  );
  return ReceivedJobOffer(
    jobId: received.jobId,
    offerId: received.offerId,
    decisionExpiresAt: received.decisionExpiresAt,
    payload: <String, dynamic>{
      ...received.payload,
      ...safeDetails,
      ...delivery,
      'jobId': received.jobId,
      if (received.offerId != null) 'offerId': received.offerId,
      if (received.decisionExpiresAt != null) ...{
        'expiresAt': received.decisionExpiresAt!.toIso8601String(),
        'decisionExpiresAt': received.decisionExpiresAt!.toIso8601String(),
      },
    },
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
  for (final key in const ['decisionExpiresAt', 'expiresAt']) {
    final parsed = DateTime.tryParse(payload[key]?.toString() ?? '')?.toUtc();
    if (parsed != null) return parsed;
  }
  return null;
}

String? _jobId(Map<String, dynamic> payload) =>
    _nonEmpty(payload['jobId']) ?? _nonEmpty(payload['id']);

String? _offerId(Map<String, dynamic> payload) => _nonEmpty(payload['offerId']);

String? _nonEmpty(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

bool _isUuidV4(String? value) =>
    value != null &&
    RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      caseSensitive: false,
    ).hasMatch(value);

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
