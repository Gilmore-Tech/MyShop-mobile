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
  NotifsNotifier(this._notificationService) : super(mockNotifs) {
    _loadFromApi();
  }

  final NotificationService _notificationService;

  Future<void> _loadFromApi() async {
    try {
      final data =
          await _notificationService.getNotifications(page: 1, limit: 30);
      final items = data['items'] as List<dynamic>? ?? [];
      if (items.isNotEmpty) {
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
      }
    } catch (_) {
      // Keep mock data as fallback — already set in super()
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

// ── Mock data ────────────────────────────────────────────────────────────────

const mockNotifs = [
  Notif(
    id: 'n1',
    type: NotifType.ride,
    title: 'Your driver is 3 mins away',
    body: 'Kwame Asante is approaching Airport Residential Area.',
    time: 'Just now',
  ),
  Notif(
    id: 'n2',
    type: NotifType.job,
    title: 'New bid on your job',
    body:
        'Kofi Mensah placed a bid of GHS 235.00 on "Emergency Electrical Repair".',
    time: '12 min ago',
  ),
  Notif(
    id: 'n3',
    type: NotifType.payment,
    title: 'Payment received',
    body: 'GHS 42.90 deducted from MTN MoMo for ride RIDE-2041.',
    time: '1 hour ago',
  ),
  Notif(
    id: 'n4',
    type: NotifType.promo,
    title: 'Weekend offer',
    body:
        'Get 20% off all rides this Saturday and Sunday. Use code WEEKEND20.',
    time: 'Yesterday',
    isRead: true,
  ),
  Notif(
    id: 'n5',
    type: NotifType.job,
    title: 'Job completed',
    body:
        'Abena Osei has marked your cleaning job as complete. Please confirm.',
    time: 'Oct 23',
    isRead: true,
  ),
  Notif(
    id: 'n6',
    type: NotifType.system,
    title: 'Profile verification',
    body:
        'Your identity has been successfully verified. Full features are now unlocked.',
    time: 'Oct 20',
    isRead: true,
  ),
];
