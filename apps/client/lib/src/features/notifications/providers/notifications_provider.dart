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
      // empty state and a pull-to-refresh re-runs reload(). Fabricating
      // a fallback list misleads the user about real notification state.
    }
  }

  /// Re-fetch notifications from the API.
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

  static NotifType _parseNotifType(String? type) => switch (type) {
        'ride' => NotifType.ride,
        'job' => NotifType.job,
        'payment' => NotifType.payment,
        'promo' => NotifType.promo,
        'safety' => NotifType.safety,
        _ => NotifType.system,
      };
}

final notifsProvider =
    StateNotifierProvider.autoDispose<NotifsNotifier, List<Notif>>((ref) {
  final notificationService = ref.watch(notificationServiceProvider);
  return NotifsNotifier(notificationService);
});

