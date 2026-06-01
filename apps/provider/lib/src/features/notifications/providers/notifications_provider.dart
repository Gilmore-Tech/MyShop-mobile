import 'package:api_client/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';

// ── Model ────────────────────────────────────────────────────────────────────

enum NotifType { ride, job, payment, promo, safety, system }

class Notif {
  final String id;
  final NotifType type;
  final String title;
  final String body;
  final String time;
  final bool isRead;

  const Notif({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.time,
    this.isRead = false,
  });

  Notif copyWithRead() => Notif(
        id: id,
        type: type,
        title: title,
        body: body,
        time: time,
        isRead: true,
      );
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
      final items = data['items'] as List<dynamic>? ?? [];
      state = items.map((json) {
        final m = json as Map<String, dynamic>;
        return Notif(
          id: (m['id'] ?? '').toString(),
          type: _parseNotifType(m['type'] as String?),
          title: m['title'] as String? ?? '',
          body: m['body'] as String? ?? m['message'] as String? ?? '',
          time: m['timeAgo'] as String? ?? m['createdAt'] as String? ?? '',
          isRead: m['isRead'] as bool? ?? m['read'] as bool? ?? false,
        );
      }).toList();
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

  // Provider-side push types map onto these inbox icons. Anything outside
  // ride/job/payment/safety lands under "system" so a casing drift can't
  // crash the icon switch.
  static NotifType _parseNotifType(String? type) {
    if (type == null) return NotifType.system;
    if (type.startsWith('ride')) return NotifType.ride;
    if (type.startsWith('job') ||
        type.startsWith('bid') ||
        type.startsWith('supplement')) {
      return NotifType.job;
    }
    if (type.startsWith('payment') || type.startsWith('payout')) {
      return NotifType.payment;
    }
    if (type.startsWith('safety') || type.startsWith('welfare')) {
      return NotifType.safety;
    }
    return NotifType.system;
  }
}

final providerNotifsProvider =
    StateNotifierProvider.autoDispose<NotifsNotifier, List<Notif>>((ref) {
  final notificationService = ref.watch(apiNotificationServiceProvider);
  return NotifsNotifier(notificationService);
});
