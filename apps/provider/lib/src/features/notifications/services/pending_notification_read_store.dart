import 'dart:convert';

import 'package:api_client/api_client.dart' show AuthSessionIdentity;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const providerNotificationCorrelationEntityKeys = <String>[
  'jobId',
  'rideId',
  'bidId',
  'chatId',
  'bookingId',
  'callId',
  'ticketId',
  'messageId',
  'lifecycleEventId',
  'welfareCheckId',
  'documentId',
  'vehicleId',
  'rideCategoryId',
];

String? validatedProviderNotificationCorrelationId(Object? value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty || text.length > 128) return null;
  return RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{2,127}$').hasMatch(text)
      ? text
      : null;
}

/// Retains only server-authored correlation fields needed to identify one
/// persisted in-app sibling. Remote routes, copy and financial values are
/// intentionally never written to local preferences.
Map<String, String>? sanitizeProviderNotificationTrayCorrelation(
  Map<String, dynamic> payload,
) {
  final sanitized = <String, String>{};
  for (final key in <String>[
    'correlationId',
    'campaignId',
    ...providerNotificationCorrelationEntityKeys,
  ]) {
    final value = validatedProviderNotificationCorrelationId(payload[key]);
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
      providerNotificationCorrelationEntityKeys.any(sanitized.containsKey);
  return hasDirectCorrelation || hasTypedEntity ? sanitized : null;
}

class PendingProviderNotificationRead {
  const PendingProviderNotificationRead({
    required this.receiptId,
    required this.payload,
  });

  final String receiptId;
  final Map<String, dynamic> payload;
}

/// Durable one-slot handoff from a cold-start tray tap to the authenticated
/// notification cache. A globally unique correlation id makes one slot enough:
/// the latest explicit user tap owns the pending read acknowledgement.
class PendingProviderNotificationReadStore {
  const PendingProviderNotificationReadStore();

  static const _storageKey = 'myshop.provider.pending_notification_read.v1';
  static const _maxAge = Duration(hours: 24);

  Future<PendingProviderNotificationRead?> save(
    Map<String, dynamic> payload, {
    required AuthSessionIdentity owner,
  }) async {
    final sanitized = sanitizeProviderNotificationTrayCorrelation(payload);
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
        // `subject` is the private phone-auth root and must never be written to
        // preferences. The public role-account id plus role is enough to stop
        // a pending tray tap crossing accounts on a shared handset.
        'ownerRoleAccountId': owner.roleAccountId,
        'ownerRole': owner.role,
        'payload': sanitized,
      }),
    );
    return PendingProviderNotificationRead(
      receiptId: receiptId,
      payload: Map<String, dynamic>.from(sanitized),
    );
  }

  Future<PendingProviderNotificationRead?> loadFor(
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
      if (map['version'] != 1 ||
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
      final sanitized = sanitizeProviderNotificationTrayCorrelation(
        Map<String, dynamic>.from(rawPayload),
      );
      if (sanitized == null) {
        await preferences.remove(_storageKey);
        return null;
      }
      return PendingProviderNotificationRead(
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

final pendingProviderNotificationReadStoreProvider =
    Provider<PendingProviderNotificationReadStore>(
  (_) => const PendingProviderNotificationReadStore(),
);
