import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';

// ── Model ────────────────────────────────────────────────────────────────────

enum NotifType { ride, job, payment, promo, safety, system }

class Notif {
  const Notif({
    required this.id,
    required this.type,
    required this.eventType,
    required this.title,
    required this.body,
    required this.time,
    this.payload = const {},
    this.reason,
    this.isRead = false,
  });

  factory Notif.fromJson(Map<String, dynamic> json) {
    final payload = _notificationPayload(json['payload'] ?? json['data']);
    final eventType = _notificationText(json['eventType']) ??
        _notificationText(json['type']) ??
        _notificationText(payload['eventType']) ??
        _notificationText(payload['type']) ??
        '';
    final reason = _notificationText(json['rejectionReason']) ??
        _notificationText(json['reason']) ??
        _notificationText(payload['rejectionReason']) ??
        _notificationText(payload['reason']);
    final rawBody = _notificationText(json['body']) ??
        _notificationText(json['message']) ??
        _notificationText(payload['body']) ??
        _notificationText(payload['message']) ??
        '';
    final body = reason == null || rawBody.contains(reason)
        ? rawBody
        : rawBody.isEmpty
            ? 'Reason: $reason'
            : '$rawBody Reason: $reason';
    final explicitRead = json['isRead'] is bool
        ? json['isRead'] as bool
        : json['read'] is bool
            ? json['read'] as bool
            : null;

    return Notif(
      id: (json['id'] ?? '').toString(),
      type: _parseNotifType(eventType),
      eventType: eventType,
      title: _notificationText(json['title']) ??
          _notificationText(payload['title']) ??
          '',
      body: body,
      time: _notificationText(json['timeAgo']) ??
          _notificationText(json['createdAt']) ??
          '',
      payload: payload,
      reason: reason,
      isRead: explicitRead ?? _hasReadTimestamp(json['readAt']),
    );
  }

  final String id;
  final NotifType type;
  final String eventType;
  final String title;
  final String body;
  final String time;
  final Map<String, dynamic> payload;
  final String? reason;
  final bool isRead;

  Notif copyWithRead() => Notif(
        id: id,
        type: type,
        eventType: eventType,
        title: title,
        body: body,
        time: time,
        payload: payload,
        reason: reason,
        isRead: true,
      );
}

String? _notificationText(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

bool _hasReadTimestamp(Object? value) {
  if (value == null) return false;
  return value is! String || value.trim().isNotEmpty;
}

Map<String, dynamic> _notificationPayload(Object? raw) {
  if (raw is Map) return Map<String, dynamic>.from(raw);
  if (raw is String && raw.trim().startsWith('{')) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      // A malformed optional payload must not hide the notification itself.
    }
  }
  return const {};
}

NotifType _parseNotifType(String? type) {
  final normalized = type?.trim().toLowerCase().replaceAll('.', '_');
  if (normalized == null || normalized.isEmpty) return NotifType.system;
  if (normalized.startsWith('ride')) return NotifType.ride;
  if (normalized.startsWith('job') ||
      normalized.startsWith('bid') ||
      normalized.startsWith('supplement')) {
    return NotifType.job;
  }
  if (normalized.startsWith('payment') ||
      normalized.startsWith('payout') ||
      normalized.startsWith('earnings')) {
    return NotifType.payment;
  }
  if (normalized.startsWith('promo')) return NotifType.promo;
  if (normalized.startsWith('safety') || normalized.startsWith('welfare')) {
    return NotifType.safety;
  }
  return NotifType.system;
}

/// Parses both the current `{data: [...], meta: ...}` response and the legacy
/// `{items: [...]}` response. [NotificationService] already unwraps the outer
/// API envelope, so `data` here is the actual notification list.
List<Notif> providerNotificationItemsFromResponse(
  Map<String, dynamic> response,
) {
  final rawItems = response['data'] ?? response['items'];
  if (rawItems is! List) return const [];
  return rawItems
      .whereType<Map>()
      // The backend persists one sibling row per delivery channel. The inbox
      // is the in-app feed, while older rows may not have recorded a channel.
      .where((item) => item['channel'] == null || item['channel'] == 'in_app')
      .map((item) => Notif.fromJson(Map<String, dynamic>.from(item)))
      .toList(growable: false);
}

// ── Provider ─────────────────────────────────────────────────────────────────
// EDD: GET /v1/notifications?page=1&limit=30
//      PATCH /v1/notifications/:id/read
//      PATCH /v1/notifications/read-all

class NotifsNotifier extends StateNotifier<List<Notif>> {
  NotifsNotifier(this._notificationService) : super(const []) {
    _loadFromApi();
  }

  final NotificationService _notificationService;

  Future<void> _loadFromApi() async {
    try {
      final data =
          await _notificationService.getNotifications(page: 1, limit: 30);
      state = providerNotificationItemsFromResponse(data);
    } catch (_) {
      // Leave the list empty on failure — the inbox screen renders an
      // empty state and a pull-to-refresh re-runs reload().
    }
  }

  Future<void> reload() => _loadFromApi();

  void markRead(String id) {
    state = state.map((n) => n.id == id ? n.copyWithRead() : n).toList();
    _notificationService.markAsRead(id).catchError((_) {});
  }

  void markAllRead() {
    state = state.map((n) => n.copyWithRead()).toList();
    for (final n in state) {
      _notificationService.markAsRead(n.id).catchError((_) {});
    }
  }
}

final providerNotifsProvider =
    StateNotifierProvider.autoDispose<NotifsNotifier, List<Notif>>((ref) {
  final notificationService = ref.watch(apiNotificationServiceProvider);
  return NotifsNotifier(notificationService);
});
