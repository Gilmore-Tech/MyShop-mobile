import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

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
    required this.createdAt,
    required this.fallbackTimeLabel,
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
    final rawCreatedAt = _notificationText(json['createdAt']);

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
      createdAt: rawCreatedAt == null ? null : DateTime.tryParse(rawCreatedAt),
      fallbackTimeLabel:
          _safeFallbackTimeLabel(_notificationText(json['timeAgo'])),
      payload: payload,
      isRead: explicitRead ?? _hasReadTimestamp(json['readAt']),
    );
  }

  final String id;
  final NotifType type;
  final String eventType;
  final String title;
  final String body;

  /// Authoritative server creation time. PostgreSQL `timestamptz` values are
  /// serialized by the API as ISO-8601 and converted to local time only when
  /// rendered. Keeping the parsed value also makes calendar grouping reliable.
  final DateTime? createdAt;

  /// Legacy fallback for old responses that do not include `createdAt`.
  /// Raw database timestamps are deliberately rejected here so they can never
  /// leak into the user interface again.
  final String fallbackTimeLabel;
  final Map<String, dynamic> payload;
  final bool isRead;

  Notif copyWithRead() => Notif(
        id: id,
        type: type,
        eventType: eventType,
        title: title,
        body: body,
        createdAt: createdAt,
        fallbackTimeLabel: fallbackTimeLabel,
        payload: payload,
        isRead: true,
      );
}

/// Human-friendly relative age for a notification.
///
/// [now] is injectable so tests and all tiles in one render use the exact same
/// clock snapshot. Future clock skew is displayed as "Just now" rather than a
/// negative duration.
String clientNotificationTimeAgo(
  Notif notification, {
  DateTime? now,
}) {
  final createdAt = notification.createdAt;
  if (createdAt == null) return notification.fallbackTimeLabel;

  final reference = now ?? DateTime.now();
  final elapsed = reference.toUtc().difference(createdAt.toUtc());
  if (elapsed.isNegative || elapsed.inSeconds < 60) return 'Just now';

  final minutes = elapsed.inMinutes;
  if (minutes < 60) return minutes == 1 ? '1 min ago' : '$minutes mins ago';

  final hours = elapsed.inHours;
  if (hours < 24) return hours == 1 ? '1 hour ago' : '$hours hours ago';

  final days = elapsed.inDays;
  if (days == 1) return 'Yesterday';
  if (days < 7) return '$days days ago';

  final weeks = days ~/ 7;
  if (days < 30) return weeks == 1 ? '1 week ago' : '$weeks weeks ago';

  final months = days ~/ 30;
  if (days < 365) return months == 1 ? '1 month ago' : '$months months ago';

  final years = days ~/ 365;
  return years == 1 ? '1 year ago' : '$years years ago';
}

/// Readable local date/time shown alongside the relative age.
String? clientNotificationLocalDateTime(Notif notification) {
  final createdAt = notification.createdAt;
  if (createdAt == null) return null;
  return DateFormat('d MMM yyyy · h:mm a').format(createdAt.toLocal());
}

/// Calendar-day grouping must use the local date, not English display text.
bool clientNotificationIsToday(
  Notif notification, {
  DateTime? now,
}) {
  final createdAt = notification.createdAt;
  if (createdAt == null) {
    final fallback = notification.fallbackTimeLabel.toLowerCase();
    return fallback == 'just now' ||
        fallback.contains('min') ||
        fallback.contains('hour');
  }
  final localCreatedAt = createdAt.toLocal();
  final localNow = (now ?? DateTime.now()).toLocal();
  return localCreatedAt.year == localNow.year &&
      localCreatedAt.month == localNow.month &&
      localCreatedAt.day == localNow.day;
}

String _safeFallbackTimeLabel(String? value) {
  if (value == null) return 'Recently';
  // An ISO/database timestamp belongs in [createdAt], never in a display
  // label. Accept only a concise server-produced relative label.
  if (DateTime.tryParse(value) != null || value.length > 40) return 'Recently';
  return value;
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

class NotifsNotifier extends StateNotifier<AsyncValue<List<Notif>>> {
  NotifsNotifier(this._notificationService) : super(const AsyncLoading()) {
    _loadFromApi();
  }

  final NotificationService _notificationService;

  Future<void> _loadFromApi() async {
    try {
      final data =
          await _notificationService.getNotifications(page: 1, limit: 30);
      if (!mounted) return;
      state = AsyncData(clientNotificationItemsFromResponse(data));
    } catch (error, stackTrace) {
      // Keep already-rendered data during a failed manual refresh. Initial
      // failures get an explicit retry state instead of masquerading as an
      // empty inbox.
      if (mounted && state.asData == null) {
        state = AsyncError(error, stackTrace);
      }
    }
  }

  Future<void> reload() {
    if (!state.hasValue) state = const AsyncLoading();
    return _loadFromApi();
  }

  void markRead(String id) {
    final notifications = state.asData?.value;
    if (notifications == null) return;
    state = AsyncData(
      notifications.map((n) => n.id == id ? n.copyWithRead() : n).toList(),
    );
    _notificationService.markAsRead(id).catchError((_) {});
  }

  void markAllRead() {
    final notifications = state.asData?.value;
    if (notifications == null) return;
    state = AsyncData(notifications.map((n) => n.copyWithRead()).toList());
    for (final n in notifications) {
      _notificationService.markAsRead(n.id).catchError((_) {});
    }
  }
}

final notifsProvider =
    StateNotifierProvider.autoDispose<NotifsNotifier, AsyncValue<List<Notif>>>(
        (ref) {
  final notificationService = ref.watch(notificationServiceProvider);
  return NotifsNotifier(notificationService);
});
