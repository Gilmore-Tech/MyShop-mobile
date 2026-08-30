import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/di/providers.dart';

// ── Model ────────────────────────────────────────────────────────────────────

enum NotifType { ride, job, payment, promo, safety, announcement, system }

class Notif {
  const Notif({
    required this.id,
    required this.type,
    required this.eventType,
    required this.title,
    required this.body,
    this.createdAt,
    this.fallbackTimeAgo = '',
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
      createdAt: _notificationDateTime(json['createdAt']),
      fallbackTimeAgo: _notificationFallbackTimeAgo(json['timeAgo']),
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

  /// Authoritative creation time normalised to the device's timezone.
  /// Keeping this parsed prevents database/ISO values leaking into the UI.
  final DateTime? createdAt;

  /// Compatibility fallback for legacy responses without `createdAt`.
  final String fallbackTimeAgo;
  final Map<String, dynamic> payload;
  final String? reason;
  final bool isRead;

  Notif copyWithRead() => Notif(
        id: id,
        type: type,
        eventType: eventType,
        title: title,
        body: body,
        createdAt: createdAt,
        fallbackTimeAgo: fallbackTimeAgo,
        payload: payload,
        reason: reason,
        isRead: true,
      );
}

DateTime? _notificationDateTime(Object? value) {
  if (value is DateTime) return value.toLocal();
  final text = _notificationText(value);
  return text == null ? null : DateTime.tryParse(text)?.toLocal();
}

String _notificationFallbackTimeAgo(Object? value) {
  final text = _notificationText(value);
  if (text == null) return '';
  // `timeAgo` is a legacy display fallback, never another timestamp field.
  // Reject ISO/database timestamp values so they cannot leak into the UI if a
  // response is mis-shaped or an older API aliases `createdAt` into it.
  if (DateTime.tryParse(text) != null) return '';
  final normalized = text.toLowerCase();
  if (const {
    'now',
    'just now',
    'recently',
    'today',
    'yesterday',
  }.contains(normalized)) {
    return text;
  }
  final relativePattern = RegExp(
    r'^(?:a|an|one|\d+)\s*'
    r'(?:s|sec|secs|second|seconds|m|min|mins|minute|minutes|h|hr|hrs|hour|hours|d|day|days|w|week|weeks|mo|month|months|y|yr|yrs|year|years)\s+ago$',
  );
  return relativePattern.hasMatch(normalized) ? text : '';
}

/// Human-readable relative time used by notification tiles.
///
/// An invalid/missing database timestamp is never shown verbatim. Legacy
/// server-rendered relative labels remain usable through [fallback].
String providerNotificationTimeAgo(
  DateTime? createdAt, {
  DateTime? now,
  String fallback = '',
}) {
  if (createdAt == null) return fallback;

  final difference =
      (now ?? DateTime.now()).toLocal().difference(createdAt.toLocal());
  if (difference.isNegative || difference.inMinutes < 1) return 'Just now';
  if (difference.inMinutes < 60) {
    final minutes = difference.inMinutes;
    return '$minutes ${minutes == 1 ? 'min' : 'mins'} ago';
  }
  if (difference.inHours < 24) {
    final hours = difference.inHours;
    return '$hours ${hours == 1 ? 'hour' : 'hours'} ago';
  }
  if (difference.inDays < 30) {
    final days = difference.inDays;
    return '$days ${days == 1 ? 'day' : 'days'} ago';
  }
  if (difference.inDays < 365) {
    final months = difference.inDays ~/ 30;
    return '$months ${months == 1 ? 'month' : 'months'} ago';
  }
  final years = difference.inDays ~/ 365;
  return '$years ${years == 1 ? 'year' : 'years'} ago';
}

/// Readable local date and time shown beneath the relative label.
String providerNotificationLocalDateTime(DateTime? createdAt) {
  if (createdAt == null) return '';
  return DateFormat('d MMM yyyy · h:mm a').format(createdAt.toLocal());
}

/// Uses the actual local calendar date instead of guessing from a rendered
/// label (which put every ISO timestamp under EARLIER).
bool providerNotificationIsToday(
  Notif notification, {
  DateTime? now,
}) {
  final createdAt = notification.createdAt;
  if (createdAt == null) {
    final fallback = notification.fallbackTimeAgo.toLowerCase();
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

class ProviderNotifsState {
  const ProviderNotifsState({
    this.items = const [],
    this.isLoading = false,
    this.hasLoadError = false,
  });

  const ProviderNotifsState.initial()
      : items = const [],
        isLoading = true,
        hasLoadError = false;

  final List<Notif> items;
  final bool isLoading;
  final bool hasLoadError;
}

class NotifsNotifier extends StateNotifier<ProviderNotifsState> {
  NotifsNotifier(this._notificationService)
      : super(const ProviderNotifsState.initial()) {
    _loadFromApi();
  }

  final NotificationService _notificationService;

  Future<void> _loadFromApi() async {
    state = ProviderNotifsState(
      items: state.items,
      isLoading: true,
    );
    try {
      final data =
          await _notificationService.getNotifications(page: 1, limit: 30);
      if (!mounted) return;
      state = ProviderNotifsState(
        items: providerNotificationItemsFromResponse(data),
      );
    } catch (_) {
      if (!mounted) return;
      // A failed request is not an empty inbox. Preserve prior items during
      // refreshes and let the screen offer an explicit retry.
      state = ProviderNotifsState(
        items: state.items,
        hasLoadError: true,
      );
    }
  }

  Future<void> reload() => _loadFromApi();

  void markRead(String id) {
    state = ProviderNotifsState(
      items: state.items.map((n) => n.id == id ? n.copyWithRead() : n).toList(),
      isLoading: state.isLoading,
      hasLoadError: state.hasLoadError,
    );
    _notificationService.markAsRead(id).catchError((_) {});
  }

  void markAllRead() {
    final items = state.items.map((n) => n.copyWithRead()).toList();
    state = ProviderNotifsState(
      items: items,
      isLoading: state.isLoading,
      hasLoadError: state.hasLoadError,
    );
    for (final n in items) {
      _notificationService.markAsRead(n.id).catchError((_) {});
    }
  }
}

final providerNotifsProvider =
    StateNotifierProvider.autoDispose<NotifsNotifier, ProviderNotifsState>(
        (ref) {
  final notificationService = ref.watch(apiNotificationServiceProvider);
  return NotifsNotifier(notificationService);
});
