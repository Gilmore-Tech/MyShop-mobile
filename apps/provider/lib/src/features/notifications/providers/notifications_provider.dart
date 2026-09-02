import 'dart:async';
import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/di/providers.dart';
import '../../auth/providers/auth_controller.dart';
import '../services/pending_notification_read_store.dart';

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

/// Returns the server-authoritative unread total when the API exposes it.
///
/// Older backend releases do not include `meta.unreadTotal`, so the provider
/// app remains backwards-compatible by deriving the count from the loaded
/// in-app rows. Once the new metadata is available this also counts unread
/// notifications beyond the first page.
int providerNotificationUnreadCountFromResponse(
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
  'earnings_updated': 'earnings_updated',
  'rating_prompt': 'rating_prompt',
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
/// A push channel row has a different `notificationId` from its in-app
/// sibling, so that id must never be used to clear the bell. Announcements are
/// correlated by their server-authored campaign id. Other notifications must
/// match both a locally-normalised event type and one allowlisted entity id;
/// remote route values are deliberately ignored.
Notif? providerNotificationForTrayPayload(
  List<Notif> notifications,
  Map<String, dynamic> trayPayload,
) {
  final correlationId =
      validatedProviderNotificationCorrelationId(trayPayload['correlationId']);
  if (correlationId != null) {
    for (final notification in notifications) {
      if (validatedProviderNotificationCorrelationId(
            notification.payload['correlationId'],
          ) ==
          correlationId) {
        return notification;
      }
    }
  }

  final campaignId =
      validatedProviderNotificationCorrelationId(trayPayload['campaignId']);
  if (campaignId != null) {
    for (final notification in notifications) {
      if (validatedProviderNotificationCorrelationId(
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

  for (final entityKey in providerNotificationCorrelationEntityKeys) {
    final trayEntityId =
        validatedProviderNotificationCorrelationId(trayPayload[entityKey]);
    if (trayEntityId == null) continue;
    for (final notification in notifications) {
      if (_canonicalNotificationType(notification.eventType) != trayType) {
        continue;
      }
      if (validatedProviderNotificationCorrelationId(
            notification.payload[entityKey],
          ) ==
          trayEntityId) {
        return notification;
      }
    }
  }
  return null;
}

// ── Provider ─────────────────────────────────────────────────────────────────
// EDD: GET /v1/notifications?page=1&limit=30
//      PATCH /v1/notifications/:id/read
//      PATCH /v1/notifications/read-all

class ProviderNotifsState {
  const ProviderNotifsState({
    this.items = const [],
    this.unreadCount = 0,
    this.isLoading = false,
    this.hasLoadError = false,
  });

  const ProviderNotifsState.initial()
      : items = const [],
        unreadCount = 0,
        isLoading = true,
        hasLoadError = false;

  final List<Notif> items;
  final int unreadCount;
  final bool isLoading;
  final bool hasLoadError;
}

class NotifsNotifier extends StateNotifier<ProviderNotifsState> {
  NotifsNotifier(this._notificationService)
      : super(const ProviderNotifsState.initial()) {
    _loadFromApi();
  }

  final NotificationService _notificationService;
  final Set<String> _optimisticallyReadIds = <String>{};
  Future<void>? _loadOperation;

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
    state = ProviderNotifsState(
      items: state.items,
      unreadCount: state.unreadCount,
      isLoading: true,
    );
    try {
      final data =
          await _notificationService.getNotifications(page: 1, limit: 30);
      if (!mounted) return;
      final items = providerNotificationItemsFromResponse(data);
      _optimisticallyReadIds.clear();
      state = ProviderNotifsState(
        items: items,
        unreadCount: providerNotificationUnreadCountFromResponse(
          data,
          items: items,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      // A failed request is not an empty inbox. Preserve prior items during
      // refreshes and let the screen offer an explicit retry.
      state = ProviderNotifsState(
        items: state.items,
        unreadCount: state.unreadCount,
        hasLoadError: true,
      );
    }
  }

  Future<void> reload() => _loadFromApi();

  /// Reads only a safely-correlated in-app notification and waits for the
  /// server acknowledgement. A null result leaves the durable pending receipt
  /// intact so it can be retried after auth/network recovery.
  Future<String?> markReadForTrayPayload(Map<String, dynamic> payload) async {
    final notification = providerNotificationForTrayPayload(
      state.items,
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
      // Keep the optimistic marker. A failed reload preserves the local read
      // item, and this marker ensures the next durable-receipt attempt retries
      // the PATCH instead of mistaking that local state for server proof.
      return null;
    }
  }

  void markRead(String id) {
    final notificationIndex = state.items.indexWhere((item) => item.id == id);
    final notification =
        notificationIndex < 0 ? null : state.items[notificationIndex];
    if (notification?.isRead == true && !_optimisticallyReadIds.contains(id)) {
      return;
    }
    if (notification?.isRead != true) _applyRead(id);
    unawaited(_acknowledgeRead(id));
  }

  Future<void> _acknowledgeRead(String id) async {
    try {
      await _notificationService.markAsRead(id);
      _optimisticallyReadIds.remove(id);
    } catch (_) {
      // Preserve the marker so a later tray/inbox retry cannot confuse the
      // optimistic local row with an acknowledged server read.
    }
  }

  bool _applyRead(String id) {
    final notificationIndex = state.items.indexWhere((item) => item.id == id);
    final notification =
        notificationIndex < 0 ? null : state.items[notificationIndex];
    if (notification?.isRead == true ||
        (notification == null && _optimisticallyReadIds.contains(id))) {
      return false;
    }
    final firstOptimisticRead = _optimisticallyReadIds.add(id);
    final shouldDecrement = firstOptimisticRead &&
        (notification == null || !notification.isRead) &&
        state.unreadCount > 0;
    state = ProviderNotifsState(
      items: state.items.map((n) => n.id == id ? n.copyWithRead() : n).toList(),
      unreadCount: shouldDecrement ? state.unreadCount - 1 : state.unreadCount,
      isLoading: state.isLoading,
      hasLoadError: state.hasLoadError,
    );
    return true;
  }

  Future<void> markAllRead() async {
    final unreadItems =
        state.items.where((notification) => !notification.isRead).toList();
    final items = state.items.map((n) => n.copyWithRead()).toList();
    _optimisticallyReadIds
        .addAll(unreadItems.map((notification) => notification.id));
    state = ProviderNotifsState(
      items: items,
      unreadCount: 0,
      isLoading: state.isLoading,
      hasLoadError: state.hasLoadError,
    );

    try {
      await _notificationService.markAllAsRead();
      _optimisticallyReadIds.removeAll(
        unreadItems.map((notification) => notification.id),
      );
    } catch (_) {
      // Compatibility with an older backend during rolling deployment: mark
      // the loaded rows through the legacy endpoint, then refetch the exact
      // total so unread rows beyond page one remain honest.
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

final providerNotifsProvider =
    StateNotifierProvider.autoDispose<NotifsNotifier, ProviderNotifsState>(
        (ref) {
  // Recreate the cache for every exact role session. A dual-role provider or
  // next account on the same handset must never inherit another inbox/badge.
  ref.watch(currentAuthSessionIdentityProvider);
  final notificationService = ref.watch(apiNotificationServiceProvider);
  return NotifsNotifier(notificationService);
});

/// Shared badge source for the driver, artisan and earnings headers.
///
/// The provider shell keeps [providerNotifsProvider] alive for the authenticated
/// session, so every bell observes one consistent unread total as users switch
/// tabs and mark inbox rows read.
final providerUnreadNotificationCountProvider = Provider.autoDispose<int>(
  (ref) => ref.watch(
    providerNotifsProvider.select((state) => state.unreadCount),
  ),
);

/// Completes a sanitized cold-start tray read only after the exact authenticated
/// role cache has loaded. Successful server acknowledgement atomically clears
/// the persisted receipt; failures remain retryable on the next shell resume.
final consumePendingProviderNotificationReadProvider =
    Provider<Future<void> Function()>((ref) {
  return () async {
    try {
      final identity = ref.read(currentAuthSessionIdentityProvider);
      if (identity == null || !ref.exists(providerNotifsProvider)) return;
      final store = ref.read(pendingProviderNotificationReadStoreProvider);
      final pending = await store.loadFor(identity);
      if (pending == null) return;

      final notifier = ref.read(providerNotifsProvider.notifier);
      await notifier.reload();
      final matchedId = await notifier.markReadForTrayPayload(pending.payload);
      if (matchedId != null) {
        await store.clearIfReceipt(pending.receiptId);
      }
    } catch (_) {
      // Authentication, storage and network startup can race on a cold launch.
      // The sanitized receipt remains available for the next shell resume.
    }
  };
});
