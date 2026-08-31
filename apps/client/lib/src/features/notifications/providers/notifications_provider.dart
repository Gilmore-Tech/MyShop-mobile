import 'dart:async';
import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/di/providers.dart';
import '../../../core/providers/auth_session_identity_provider.dart';
import '../services/pending_notification_read_store.dart';

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

/// Returns the exact unread total when supported by the backend, with a
/// list-derived fallback for older deployments during a rolling release.
int clientNotificationUnreadCountFromResponse(
  Map<String, dynamic> response, {
  required List<Notif> items,
}) {
  final meta = response['meta'];
  final rawUnreadTotal = meta is Map ? meta['unreadTotal'] : null;
  final unreadTotal = switch (rawUnreadTotal) {
    int value => value,
    num value => value.toInt(),
    String value => int.tryParse(value),
    _ => null,
  };
  if (unreadTotal != null && unreadTotal >= 0) return unreadTotal;
  return items.where((notification) => !notification.isRead).length;
}

const _notificationTypeAliases = <String, String>{
  'job_bid_selected': 'bid_accepted',
  'job_bid_rejected': 'bid_rejected',
  'job_supplement_approved': 'supplement_approved',
  'job_supplement_rejected': 'supplement_rejected',
  'ride_cancelled': 'ride_cancelled',
  'ride_settled': 'ride_settled',
  'payment_received': 'payment_received',
  'chat_message': 'new_message',
  'support_ticket_message': 'support_ticket_message',
  'support_ticket_status_changed': 'support_ticket_status_changed',
};

String _canonicalNotificationType(Object? value) {
  final normalized = _notificationText(value)
          ?.toLowerCase()
          .replaceAll('.', '_')
          .replaceAll('-', '_') ??
      '';
  return _notificationTypeAliases[normalized] ?? normalized;
}

/// Finds the persisted in-app sibling represented by a system-tray payload.
///
/// A push `notificationId` belongs to the push row, not its inbox sibling, so
/// it is deliberately ignored. A server-authored correlation id is preferred;
/// legacy payloads fall back to campaign id or normalised type plus one
/// allowlisted entity id. Remote routes never participate in matching.
Notif? clientNotificationForTrayPayload(
  List<Notif> notifications,
  Map<String, dynamic> trayPayload,
) {
  final correlationId =
      validatedClientNotificationCorrelationId(trayPayload['correlationId']);
  if (correlationId != null) {
    for (final notification in notifications) {
      if (validatedClientNotificationCorrelationId(
            notification.payload['correlationId'],
          ) ==
          correlationId) {
        return notification;
      }
    }
  }

  final campaignId =
      validatedClientNotificationCorrelationId(trayPayload['campaignId']);
  if (campaignId != null) {
    for (final notification in notifications) {
      if (validatedClientNotificationCorrelationId(
            notification.payload['campaignId'],
          ) ==
          campaignId) {
        return notification;
      }
    }
  }

  final trayType = _canonicalNotificationType(
    trayPayload['type'] ?? trayPayload['eventType'],
  );
  if (trayType.isEmpty) return null;

  for (final entityKey in clientNotificationCorrelationEntityKeys) {
    final trayEntityId =
        validatedClientNotificationCorrelationId(trayPayload[entityKey]);
    if (trayEntityId == null) continue;
    for (final notification in notifications) {
      if (_canonicalNotificationType(notification.eventType) != trayType) {
        continue;
      }
      if (validatedClientNotificationCorrelationId(
            notification.payload[entityKey],
          ) ==
          trayEntityId) {
        return notification;
      }
    }
  }
  return null;
}

// ── Provider ───────────────────────────────────────────────────────────────────────────────
// EDD: GET /v1/notifications?page=1&limit=30
//      PATCH /v1/notifications/:id/read

class NotifsNotifier extends StateNotifier<AsyncValue<List<Notif>>> {
  NotifsNotifier(this._notificationService) : super(const AsyncLoading()) {
    _loadFromApi();
  }

  final NotificationService _notificationService;
  final Set<String> _optimisticallyReadIds = <String>{};
  Future<void>? _loadOperation;
  int _unreadCount = 0;

  int get unreadCount => _unreadCount;

  Future<void> _loadFromApi() {
    final activeLoad = _loadOperation;
    if (activeLoad != null) return activeLoad;

    late final Future<void> operation;
    operation = _performLoadFromApi().whenComplete(() {
      if (identical(_loadOperation, operation)) _loadOperation = null;
    });
    _loadOperation = operation;
    return operation;
  }

  Future<void> _performLoadFromApi() async {
    try {
      final data =
          await _notificationService.getNotifications(page: 1, limit: 30);
      if (!mounted) return;
      final items = clientNotificationItemsFromResponse(data);
      _optimisticallyReadIds.clear();
      _unreadCount = clientNotificationUnreadCountFromResponse(
        data,
        items: items,
      );
      state = AsyncData(items);
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
    final notificationIndex = notifications.indexWhere((item) => item.id == id);
    if (notificationIndex < 0) return;
    final notification = notifications[notificationIndex];
    if (notification.isRead && !_optimisticallyReadIds.contains(id)) return;
    if (!notification.isRead) _applyRead(id);
    unawaited(_acknowledgeRead(id));
  }

  Future<void> _acknowledgeRead(String id) async {
    try {
      await _notificationService.markAsRead(id);
      _optimisticallyReadIds.remove(id);
    } catch (_) {
      // Keep the optimistic marker so a later durable tray retry cannot treat
      // this local-only read as proof of a server acknowledgement.
    }
  }

  /// Reads only a safely-correlated in-app row and waits for server proof.
  /// Null leaves the durable cold-start receipt intact for a later retry.
  Future<String?> markReadForTrayPayload(Map<String, dynamic> payload) async {
    final notifications = state.asData?.value;
    if (notifications == null) return null;
    final notification = clientNotificationForTrayPayload(
      notifications,
      payload,
    );
    if (notification == null) return null;
    final hasUnacknowledgedOptimisticRead =
        _optimisticallyReadIds.contains(notification.id);
    if (notification.isRead && !hasUnacknowledgedOptimisticRead) {
      return notification.id;
    }

    if (!notification.isRead) _applyRead(notification.id);
    try {
      await _notificationService.markAsRead(notification.id);
      _optimisticallyReadIds.remove(notification.id);
      return notification.id;
    } catch (_) {
      return null;
    }
  }

  bool _applyRead(String id) {
    final notifications = state.asData?.value;
    if (notifications == null) return false;
    final notificationIndex = notifications.indexWhere((item) => item.id == id);
    if (notificationIndex < 0 || notifications[notificationIndex].isRead) {
      return false;
    }
    final firstOptimisticRead = _optimisticallyReadIds.add(id);
    if (firstOptimisticRead && _unreadCount > 0) _unreadCount -= 1;
    state = AsyncData(
      notifications.map((n) => n.id == id ? n.copyWithRead() : n).toList(),
    );
    return true;
  }

  Future<void> markAllRead() async {
    final notifications = state.asData?.value;
    if (notifications == null) return;
    final unreadItems =
        notifications.where((notification) => !notification.isRead).toList();
    _optimisticallyReadIds
        .addAll(unreadItems.map((notification) => notification.id));
    _unreadCount = 0;
    state = AsyncData(
      notifications.map((notification) => notification.copyWithRead()).toList(),
    );

    try {
      await _notificationService.markAllAsRead();
      _optimisticallyReadIds.clear();
    } catch (_) {
      // Rolling-deployment compatibility: settle the loaded rows through the
      // legacy endpoint, then reload the exact count for anything beyond page
      // one once the backend becomes reachable.
      await Future.wait(
        unreadItems.map(
          (notification) => _notificationService
              .markAsRead(notification.id)
              .catchError((_) {}),
        ),
      );
      await reload();
    }
  }
}

final notifsProvider =
    StateNotifierProvider.autoDispose<NotifsNotifier, AsyncValue<List<Notif>>>(
        (ref) {
  // Recreate the inbox for every exact Client role session so no cached rows
  // or badge count can cross accounts on a shared handset.
  ref.watch(currentClientAuthSessionIdentityProvider);
  final notificationService = ref.watch(notificationServiceProvider);
  return NotifsNotifier(notificationService);
});

/// Exact badge source shared by Home, Profile, and the authenticated shell.
final clientUnreadNotificationCountProvider = Provider.autoDispose<int>((ref) {
  // Recompute after every list/loading/error transition, then read the exact
  // metadata-backed count held by the notifier.
  ref.watch(notifsProvider);
  return ref.read(notifsProvider.notifier).unreadCount;
});

/// Completes a sanitized cold-start tray read only after the authenticated
/// Client inbox has loaded. Failures retain the receipt for the next resume.
final consumePendingClientNotificationReadProvider =
    Provider<Future<void> Function()>((ref) {
  return () async {
    try {
      final identity = ref.read(currentClientAuthSessionIdentityProvider);
      if (identity == null || !ref.exists(notifsProvider)) return;
      final store = ref.read(pendingClientNotificationReadStoreProvider);
      final pending = await store.loadFor(identity);
      if (pending == null) return;

      final notifier = ref.read(notifsProvider.notifier);
      await notifier.reload();
      final matchedId = await notifier.markReadForTrayPayload(pending.payload);
      if (matchedId != null) {
        await store.clearIfReceipt(pending.receiptId);
      }
    } catch (_) {
      // Auth, preferences, and network startup can race on a cold launch. The
      // sanitized receipt remains available for the next authenticated resume.
    }
  };
});
