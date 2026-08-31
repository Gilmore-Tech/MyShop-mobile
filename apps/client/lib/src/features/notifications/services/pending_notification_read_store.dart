import 'dart:convert';

import 'package:api_client/api_client.dart' show AuthSessionIdentity;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const clientNotificationCorrelationEntityKeys = <String>[
  'jobId',
  'rideId',
  'bidId',
  'chatId',
  'bookingId',
  'callId',
  'ticketId',
  'messageId',
];

String? validatedClientNotificationCorrelationId(Object? value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty || text.length > 128) return null;
  return RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{2,127}$').hasMatch(text)
      ? text
      : null;
}

/// Keeps only server-authored identifiers required to locate the persisted
/// in-app sibling. Push-row ids, remote routes, copy and financial values are
/// intentionally never written to local preferences.
Map<String, String>? sanitizeClientNotificationTrayCorrelation(
  Map<String, dynamic> payload,
) {
  final sanitized = <String, String>{};
  for (final key in <String>[
    'correlationId',
    'campaignId',
    ...clientNotificationCorrelationEntityKeys,
  ]) {
    final value = validatedClientNotificationCorrelationId(payload[key]);
    if (value != null) sanitized[key] = value;
  }

  final rawType = (payload['type'] ?? payload['eventType'])?.toString().trim();
  if (rawType != null &&
      rawType.isNotEmpty &&
      rawType.length <= 100 &&
      RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,99}$').hasMatch(rawType)) {
    sanitized['type'] = rawType;
  }

  final hasDirectCorrelation = sanitized.containsKey('correlationId') ||
      sanitized.containsKey('campaignId');
  final hasTypedEntity = sanitized.containsKey('type') &&
      clientNotificationCorrelationEntityKeys.any(sanitized.containsKey);
  return hasDirectCorrelation || hasTypedEntity ? sanitized : null;
}

class PendingClientNotificationRead {
  const PendingClientNotificationRead({
    required this.receiptId,
    required this.payload,
  });

  final String receiptId;
  final Map<String, dynamic> payload;
}

/// Durable one-slot handoff from a tray tap to the authenticated client inbox.
/// The latest explicit tap owns the pending acknowledgement; it is removed
/// only after the backend accepts the matching in-app row's read PATCH.
class PendingClientNotificationReadStore {
  const PendingClientNotificationReadStore();

  static const _storageKey = 'myshop.client.pending_notification_read.v1';
  static const _maxAge = Duration(hours: 24);

  Future<PendingClientNotificationRead?> save(
    Map<String, dynamic> payload, {
    required AuthSessionIdentity owner,
  }) async {
    if (owner.role != 'client') return null;
    final sanitized = sanitizeClientNotificationTrayCorrelation(payload);
    if (sanitized == null) return null;

    final now = DateTime.now().toUtc();
    final receiptId = now.microsecondsSinceEpoch.toString();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _storageKey,
      jsonEncode({
        'version': 1,
        'receiptId': receiptId,
        'savedAt': now.toIso8601String(),
        // The private phone-auth subject must never be persisted. The public
        // client role-account id plus role prevents cross-account replay on a
        // shared handset.
        'ownerRoleAccountId': owner.roleAccountId,
        'ownerRole': owner.role,
        'payload': sanitized,
      }),
    );
    return PendingClientNotificationRead(
      receiptId: receiptId,
      payload: Map<String, dynamic>.from(sanitized),
    );
  }

  Future<PendingClientNotificationRead?> loadFor(
    AuthSessionIdentity owner,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_storageKey);
    if (raw == null) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) throw const FormatException('not an object');
      final map = Map<String, dynamic>.from(decoded);
      final savedAt = DateTime.tryParse(map['savedAt']?.toString() ?? '');
      final receiptId = map['receiptId']?.toString().trim();
      final rawPayload = map['payload'];
      if (owner.role != 'client' ||
          map['version'] != 1 ||
          savedAt == null ||
          receiptId == null ||
          receiptId.isEmpty ||
          rawPayload is! Map ||
          DateTime.now().toUtc().difference(savedAt.toUtc()) > _maxAge ||
          map['ownerRoleAccountId'] != owner.roleAccountId ||
          map['ownerRole'] != owner.role) {
        await preferences.remove(_storageKey);
        return null;
      }
      final sanitized = sanitizeClientNotificationTrayCorrelation(
        Map<String, dynamic>.from(rawPayload),
      );
      if (sanitized == null) {
        await preferences.remove(_storageKey);
        return null;
      }
      return PendingClientNotificationRead(
        receiptId: receiptId,
        payload: Map<String, dynamic>.from(sanitized),
      );
    } catch (_) {
      await preferences.remove(_storageKey);
      return null;
    }
  }

  Future<void> clearIfReceipt(String receiptId) async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_storageKey);
    if (raw == null) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map && decoded['receiptId'] == receiptId) {
        await preferences.remove(_storageKey);
      }
    } catch (_) {
      await preferences.remove(_storageKey);
    }
  }
}

final pendingClientNotificationReadStoreProvider =
    Provider<PendingClientNotificationReadStore>(
  (_) => const PendingClientNotificationReadStore(),
);
