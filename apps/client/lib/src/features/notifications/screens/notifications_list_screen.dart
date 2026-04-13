import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

// ── Design tokens ──────────────────────────────────────────────────────────────
const _bg            = Color(0xFFF6F7F8);
const _surfaceWhite  = Color(0xFFFFFFFF);
const _textPrimary   = Color(0xFF161A1D);
const _textSecondary = Color(0xFF555E68);
const _gold          = Color(0xFFF5A623);
const _goldLight     = Color(0xFFFFF8EC);
const _success       = Color(0xFF27AE60);
const _successLight  = Color(0xFFE8F8EE);
const _info          = Color(0xFF2F80ED);
const _infoLight     = Color(0xFFE8F0FD);
const _warning       = Color(0xFFF2994A);
const _warningLight  = Color(0xFFFEF3E8);
const _danger        = Color(0xFFEB5757);
const _dangerLight   = Color(0xFFFDE8E8);

// ── Model ──────────────────────────────────────────────────────────────────────

enum _NotifType { ride, job, payment, promo, safety, system }

class _Notif {
  final String    id;
  final _NotifType type;
  final String    title;
  final String    body;
  final String    time;
  final bool      isRead;

  const _Notif({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.time,
    this.isRead = false,
  });

  _Notif copyWithRead() => _Notif(
        id:     id,
        type:   type,
        title:  title,
        body:   body,
        time:   time,
        isRead: true,
      );
}

// ── Provider ───────────────────────────────────────────────────────────────────
// EDD: GET /v1/notifications?page=1&limit=30
//      PATCH /v1/notifications/:id/read
//      PATCH /v1/notifications/read-all

class _NotifsNotifier extends StateNotifier<List<_Notif>> {
  _NotifsNotifier() : super(_mockNotifs);

  void markRead(String id) {
    state = state
        .map((n) => n.id == id ? n.copyWithRead() : n)
        .toList();
    // TODO: PATCH /v1/notifications/:id/read
  }

  void markAllRead() {
    state = state.map((n) => n.copyWithRead()).toList();
    // TODO: PATCH /v1/notifications/read-all
  }
}

final _notifsProvider = StateNotifierProvider.autoDispose<
    _NotifsNotifier, List<_Notif>>((_) => _NotifsNotifier());

// ── Screen ─────────────────────────────────────────────────────────────────────

class NotificationsListScreen extends ConsumerWidget {
  const NotificationsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final size    = MediaQuery.sizeOf(context);
    final w       = size.width;
    final h       = size.height;
    final notifs  = ref.watch(_notifsProvider);
    final unread  = notifs.where((n) => !n.isRead).length;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surfaceWhite,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: _textPrimary),
          onPressed: () => context.pop(),
        ),
        title: Row(
          children: [
            Text('Notifications',
                style: TextStyle(
                    color:      _textPrimary,
                    fontSize:   w * 0.044,
                    fontWeight: FontWeight.w700)),
            if (unread > 0) ...[
              SizedBox(width: w * 0.020),
              Container(
                padding: EdgeInsets.symmetric(
                    horizontal: w * 0.020, vertical: 2),
                decoration: BoxDecoration(
                  color:        _gold,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('$unread',
                    style: TextStyle(
                      color:      Colors.white,
                      fontSize:   w * 0.026,
                      fontWeight: FontWeight.w700,
                    )),
              ),
            ],
          ],
        ),
        actions: [
          if (unread > 0)
            TextButton(
              onPressed: () =>
                  ref.read(_notifsProvider.notifier).markAllRead(),
              child: Text('Mark all read',
                  style: TextStyle(
                      color:    _gold,
                      fontSize: w * 0.032)),
            ),
        ],
      ),
      body: notifs.isEmpty
          ? _EmptyState(w: w, h: h)
          : _NotifList(
              notifs:   notifs,
              onTap:    (id) =>
                  ref.read(_notifsProvider.notifier).markRead(id),
              w: w,
              h: h,
            ),
    );
  }
}

// ── Notification list ──────────────────────────────────────────────────────────

class _NotifList extends StatelessWidget {
  final List<_Notif>          notifs;
  final void Function(String) onTap;
  final double                w, h;

  const _NotifList({
    required this.notifs,
    required this.onTap,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    // Group into "Today" and "Earlier"
    final today   = notifs.where((n) => _isToday(n.time)).toList();
    final earlier = notifs.where((n) => !_isToday(n.time)).toList();

    return ListView(
      padding: EdgeInsets.symmetric(vertical: h * 0.010),
      children: [
        if (today.isNotEmpty) ...[
          _GroupLabel(label: 'TODAY', w: w),
          ...today.map((n) => _NotifTile(
              notif: n, onTap: onTap, w: w, h: h)),
        ],
        if (earlier.isNotEmpty) ...[
          _GroupLabel(label: 'EARLIER', w: w),
          ...earlier.map((n) => _NotifTile(
              notif: n, onTap: onTap, w: w, h: h)),
        ],
      ],
    );
  }

  static bool _isToday(String time) =>
      time == 'Just now' ||
      time.contains('min') ||
      time.contains('hour');
}

class _GroupLabel extends StatelessWidget {
  final String label;
  final double w;
  const _GroupLabel({required this.label, required this.w});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          w * 0.05, w * 0.036, w * 0.05, w * 0.016),
      child: Text(label,
          style: TextStyle(
            color:         _textSecondary,
            fontSize:      w * 0.026,
            fontWeight:    FontWeight.w900,
            letterSpacing: 1.2,
          )),
    );
  }
}

// ── Notification tile ──────────────────────────────────────────────────────────

class _NotifTile extends StatelessWidget {
  final _Notif               notif;
  final void Function(String) onTap;
  final double               w, h;

  const _NotifTile({
    required this.notif,
    required this.onTap,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    final (iconData, iconColor, iconBg) = _iconFor(notif.type);

    return InkWell(
      onTap: () => onTap(notif.id),
      child: Container(
        color: notif.isRead ? _bg : _surfaceWhite,
        padding: EdgeInsets.symmetric(
            horizontal: w * 0.05, vertical: h * 0.016),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon
            Container(
              width:  w * 0.12,
              height: w * 0.12,
              decoration: BoxDecoration(
                  color: iconBg, shape: BoxShape.circle),
              child: Icon(iconData, color: iconColor, size: w * 0.056),
            ),
            SizedBox(width: w * 0.030),
            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(notif.title,
                            style: TextStyle(
                              color:      _textPrimary,
                              fontSize:   w * 0.036,
                              fontWeight: notif.isRead
                                  ? FontWeight.w500
                                  : FontWeight.w700,
                            )),
                      ),
                      SizedBox(width: w * 0.020),
                      Text(notif.time,
                          style: TextStyle(
                              color:    _textSecondary,
                              fontSize: w * 0.028)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(notif.body,
                      style: TextStyle(
                          color:    _textSecondary,
                          fontSize: w * 0.032,
                          height:   1.4)),
                ],
              ),
            ),
            if (!notif.isRead) ...[
              SizedBox(width: w * 0.020),
              Container(
                width:  8,
                height: 8,
                margin: EdgeInsets.only(top: h * 0.006),
                decoration: const BoxDecoration(
                    color: _gold, shape: BoxShape.circle),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static (IconData, Color, Color) _iconFor(_NotifType type) =>
      switch (type) {
        _NotifType.ride    => (Icons.directions_car_rounded, _info,    _infoLight),
        _NotifType.job     => (Icons.work_rounded,           _gold,    _goldLight),
        _NotifType.payment => (Icons.payments_rounded,       _success, _successLight),
        _NotifType.promo   => (Icons.local_offer_rounded,    _warning, _warningLight),
        _NotifType.safety  => (Icons.security_rounded,       _danger,  _dangerLight),
        _NotifType.system  => (Icons.notifications_rounded,  const Color(0xFF46535D),
                               const Color(0xFFF3F5F6)),
      };
}

// ── Empty state ────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final double w, h;
  const _EmptyState({required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.notifications_none_rounded,
              color: _textSecondary.withAlpha(80), size: w * 0.18),
          SizedBox(height: h * 0.016),
          Text('No notifications yet',
              style: TextStyle(
                color:      _textPrimary,
                fontSize:   w * 0.042,
                fontWeight: FontWeight.w700,
              )),
          SizedBox(height: h * 0.008),
          Text("You're all caught up!",
              style: TextStyle(
                  color:    _textSecondary,
                  fontSize: w * 0.034)),
        ],
      ),
    );
  }
}

// ── Mock data ──────────────────────────────────────────────────────────────────

const _mockNotifs = [
  _Notif(
    id:    'n1',
    type:  _NotifType.ride,
    title: 'Your driver is 3 mins away',
    body:  'Kwame Asante is approaching Airport Residential Area.',
    time:  'Just now',
  ),
  _Notif(
    id:    'n2',
    type:  _NotifType.job,
    title: 'New bid on your job',
    body:  'Kofi Mensah placed a bid of GHS 235.00 on "Emergency Electrical Repair".',
    time:  '12 min ago',
  ),
  _Notif(
    id:    'n3',
    type:  _NotifType.payment,
    title: 'Payment received',
    body:  'GHS 42.90 deducted from MTN MoMo for ride RIDE-2041.',
    time:  '1 hour ago',
  ),
  _Notif(
    id:    'n4',
    type:  _NotifType.promo,
    title: 'Weekend offer 🎉',
    body:  'Get 20% off all rides this Saturday and Sunday. Use code WEEKEND20.',
    time:  'Yesterday',
    isRead: true,
  ),
  _Notif(
    id:    'n5',
    type:  _NotifType.job,
    title: 'Job completed',
    body:  'Abena Osei has marked your cleaning job as complete. Please confirm.',
    time:  'Oct 23',
    isRead: true,
  ),
  _Notif(
    id:    'n6',
    type:  _NotifType.system,
    title: 'Profile verification',
    body:  'Your identity has been successfully verified. Full features are now unlocked.',
    time:  'Oct 20',
    isRead: true,
  ),
];
