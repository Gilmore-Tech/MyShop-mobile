import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';

// ── Model ────────────────────────────────────────────────────────────────────────────────

enum NotifType { ride, job, payment, promo, safety, announcement, system }

class Notif {
  const Notif({
    required this.id,
    required this.type,
    required this.eventType,
    required this.title,
    required this.body,
    required this.time,
    this.payload = const {},
    this.isRead = false,
  });

  factory Notif.fromJson(Map<String, dynamic> json) {
    final payload = _notificationPayload(json['payload'] ?? json['data']);
    final eventType = _notificationText(json['eventType']) ??
        _notificationText(json['type']) ??
        _notificationText(payload['eventType']) ??
        _notificationText(payload['type']) ??
        '';
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
      body: _notificationText(json['body']) ??
          _notificationText(json['message']) ??
          _notificationText(payload['body']) ??
          _notificationText(payload['message']) ??
          '',
      time: _notificationText(json['timeAgo']) ??
          _notificationText(json['createdAt']) ??
          '',
      payload: payload,
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
  final bool isRead;

  Notif copyWithRead() => Notif(
        id: id,
        type: type,
        eventType: eventType,
        title: title,
        body: body,
        time: time,
        payload: payload,
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
  if (normalized == 'announcement') return NotifType.announcement;
  if (normalized.startsWith('ride')) return NotifType.ride;
  if (normalized.startsWith('job') || normalized.startsWith('bid')) {
    return NotifType.job;
  }
  if (normalized.startsWith('payment') || normalized.startsWith('payout')) {
    return NotifType.payment;
  }
  if (normalized.startsWith('promo')) return NotifType.promo;
  if (normalized.startsWith('safety')) return NotifType.safety;
  return NotifType.system;
}

/// Parses the current `{data: [...], meta: ...}` response and the legacy
/// `{items: [...]}` response. The API service has already unwrapped the outer
/// `{success, data}` envelope at this point.
List<Notif> clientNotificationItemsFromResponse(
  Map<String, dynamic> response,
) {
  final rawItems = response['data'] ?? response['items'];
  if (rawItems is! List) return const [];
  return rawItems
      .whereType<Map>()
      .where((item) => item['channel'] == null || item['channel'] == 'in_app')
      .map((item) => Notif.fromJson(Map<String, dynamic>.from(item)))
      .toList(growable: false);
}

// ── Provider ───────────────────────────────────────────────────────────────────────────────
// EDD: GET /v1/notifications?page=1&limit=30
//      PATCH /v1/notifications/:id/read

class NotifsNotifier extends StateNotifier<List<Notif>> {
  NotifsNotifier(this._notificationService) : super(const []) {
    _loadFromApi();
  }

  final NotificationService _notificationService;

  Future<void> _loadFromApi() async {
    try {
      final data =
          await _notificationService.getNotifications(page: 1, limit: 30);
      state = clientNotificationItemsFromResponse(data);
    } catch (_) {
      // Leave the list empty on failure. Pull-to-refresh retries the request.
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

final notifsProvider =
    StateNotifierProvider.autoDispose<NotifsNotifier, List<Notif>>((ref) {
  final notificationService = ref.watch(notificationServiceProvider);
  return NotifsNotifier(notificationService);
});
