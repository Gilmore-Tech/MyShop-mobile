import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/local_notification_service.dart';
import '../providers/notifications_provider.dart';

// ── Screen ─────────────────────────────────────────────────────────────────────

class NotificationsListScreen extends ConsumerStatefulWidget {
  const NotificationsListScreen({super.key});

  @override
  ConsumerState<NotificationsListScreen> createState() =>
      _NotificationsListScreenState();
}

class _NotificationsListScreenState
    extends ConsumerState<NotificationsListScreen> {
  late DateTime _now;
  Timer? _relativeTimeTimer;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    // Relative labels remain correct while the inbox stays open. This is only
    // a local rebuild; it makes no API, map, or Redis calls.
    _relativeTimeTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _relativeTimeTimer?.cancel();
    super.dispose();
  }

  void _openNotification(
    BuildContext context,
    Notif notification,
  ) {
    ref.read(notifsProvider.notifier).markRead(notification.id);
    final eventType = NotificationPayload.normaliseType(notification.eventType);
    if (eventType != NotificationPayload.typeAnnouncement) return;
    final destination = clientAnnouncementRoute(
      notification.payload[NotificationPayload.keyDestination],
    );
    // This tap originated inside the app, so preserve the inbox beneath the
    // destination. A destination of "notifications" already means this page.
    if (destination != '/notifications') context.push(destination);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final w = size.width;
    final h = size.height;
    final notificationsState = ref.watch(notifsProvider);
    final notifs = notificationsState.asData?.value ?? const <Notif>[];
    final unread = notifs.where((n) => !n.isRead).length;

    return Scaffold(
      backgroundColor: MyShopColors.offWhite,
      appBar: AppBar(
        backgroundColor: MyShopColors.surfaceWhite,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: MyShopColors.textPrimary),
          onPressed: () => context.canPop()
              ? context.pop()
              : context.go(clientDashboardRoute),
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                'Notifications',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: MyShopColors.textPrimary,
                  fontSize: w * 0.044,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (unread > 0) ...[
              SizedBox(width: w * 0.020),
              Container(
                padding:
                    EdgeInsets.symmetric(horizontal: w * 0.020, vertical: 2),
                decoration: BoxDecoration(
                  color: MyShopColors.primaryGold,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('$unread',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: w * 0.026,
                      fontWeight: FontWeight.w700,
                    )),
              ),
            ],
          ],
        ),
        actions: [
          if (unread > 0)
            IconButton(
              onPressed: () => ref.read(notifsProvider.notifier).markAllRead(),
              tooltip: 'Mark all read',
              icon: const Icon(
                Icons.done_all_rounded,
                color: MyShopColors.primaryGold,
              ),
            ),
        ],
      ),
      body: notificationsState.when(
        loading: () => const _LoadingState(),
        error: (_, __) => _ErrorState(
          onRetry: () => ref.read(notifsProvider.notifier).reload(),
          w: w,
        ),
        data: (notifications) => RefreshIndicator(
          onRefresh: () => ref.read(notifsProvider.notifier).reload(),
          color: MyShopColors.primaryGold,
          child: notifications.isEmpty
              ? CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _EmptyState(w: w, h: h),
                    ),
                  ],
                )
              : _NotifList(
                  notifs: notifications,
                  now: _now,
                  onTap: (notification) =>
                      _openNotification(context, notification),
                  w: w,
                  h: h,
                ),
        ),
      ),
    );
  }
}

// ── Notification list ──────────────────────────────────────────────────────────

class _NotifList extends StatelessWidget {
  final List<Notif> notifs;
  final DateTime now;
  final void Function(Notif) onTap;
  final double w, h;

  const _NotifList({
    required this.notifs,
    required this.now,
    required this.onTap,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    // Use the actual local calendar date. The old implementation tried to
    // infer "today" from strings such as "2 hours ago", so ISO timestamps
    // from the API incorrectly placed every row under Earlier.
    final today =
        notifs.where((n) => clientNotificationIsToday(n, now: now)).toList();
    final earlier =
        notifs.where((n) => !clientNotificationIsToday(n, now: now)).toList();

    return ListView(
      padding: EdgeInsets.symmetric(vertical: h * 0.010),
      children: [
        if (today.isNotEmpty) ...[
          _GroupLabel(label: 'TODAY', w: w),
          ...today.map(
            (n) => _NotifTile(
              notif: n,
              now: now,
              onTap: onTap,
              w: w,
              h: h,
            ),
          ),
        ],
        if (earlier.isNotEmpty) ...[
          _GroupLabel(label: 'EARLIER', w: w),
          ...earlier.map(
            (n) => _NotifTile(
              notif: n,
              now: now,
              onTap: onTap,
              w: w,
              h: h,
            ),
          ),
        ],
      ],
    );
  }
}

class _GroupLabel extends StatelessWidget {
  final String label;
  final double w;
  const _GroupLabel({required this.label, required this.w});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(w * 0.05, w * 0.036, w * 0.05, w * 0.016),
      child: Text(label,
          style: TextStyle(
            color: MyShopColors.textSecondary,
            fontSize: w * 0.026,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
          )),
    );
  }
}

// ── Notification tile ──────────────────────────────────────────────────────────

class _NotifTile extends StatelessWidget {
  final Notif notif;
  final DateTime now;
  final void Function(Notif) onTap;
  final double w, h;

  const _NotifTile({
    required this.notif,
    required this.now,
    required this.onTap,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    final (iconData, iconColor, iconBg) = _iconFor(notif.type);
    final relativeTime = clientNotificationTimeAgo(notif, now: now);
    final absoluteTime = clientNotificationLocalDateTime(notif);

    return InkWell(
      onTap: () => onTap(notif),
      child: Container(
        color: notif.isRead ? MyShopColors.offWhite : MyShopColors.surfaceWhite,
        padding:
            EdgeInsets.symmetric(horizontal: w * 0.05, vertical: h * 0.016),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon
            Container(
              width: w * 0.12,
              height: w * 0.12,
              decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
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
                              color: MyShopColors.textPrimary,
                              fontSize: w * 0.036,
                              fontWeight: notif.isRead
                                  ? FontWeight.w500
                                  : FontWeight.w700,
                            )),
                      ),
                      SizedBox(width: w * 0.020),
                      Text(relativeTime,
                          style: TextStyle(
                              color: MyShopColors.textSecondary,
                              fontSize: w * 0.028)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(notif.body,
                      style: TextStyle(
                          color: MyShopColors.textSecondary,
                          fontSize: w * 0.032,
                          height: 1.4)),
                  if (absoluteTime != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      absoluteTime,
                      style: TextStyle(
                        color: MyShopColors.textSecondary.withAlpha(180),
                        fontSize: w * 0.027,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (!notif.isRead) ...[
              SizedBox(width: w * 0.020),
              Container(
                width: 8,
                height: 8,
                margin: EdgeInsets.only(top: h * 0.006),
                decoration: const BoxDecoration(
                    color: MyShopColors.primaryGold, shape: BoxShape.circle),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static (IconData, Color, Color) _iconFor(NotifType type) => switch (type) {
        NotifType.ride => (
            Icons.directions_car_rounded,
            MyShopColors.info,
            MyShopColors.infoLight
          ),
        NotifType.job => (
            Icons.work_rounded,
            MyShopColors.primaryGold,
            MyShopColors.primaryGoldLight
          ),
        NotifType.payment => (
            Icons.payments_rounded,
            MyShopColors.success,
            MyShopColors.successLight
          ),
        NotifType.promo => (
            Icons.local_offer_rounded,
            MyShopColors.warning,
            MyShopColors.warningLight
          ),
        NotifType.safety => (
            Icons.security_rounded,
            MyShopColors.error,
            MyShopColors.errorLight
          ),
        NotifType.announcement => (
            Icons.campaign_rounded,
            MyShopColors.primaryGold,
            MyShopColors.primaryGoldLight
          ),
        NotifType.system => (
            Icons.notifications_rounded,
            MyShopColors.darkSlate,
            MyShopColors.surfaceGrey
          ),
      };
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: CircularProgressIndicator(color: MyShopColors.primaryGold),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry, required this.w});

  final VoidCallback onRetry;
  final double w;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(w * 0.08),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_rounded,
              color: MyShopColors.textSecondary,
              size: w * 0.12,
            ),
            SizedBox(height: w * 0.04),
            Text(
              'Could not load notifications',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: MyShopColors.textPrimary,
                fontSize: w * 0.040,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: w * 0.02),
            Text(
              'Check your connection and try again.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: MyShopColors.textSecondary,
                fontSize: w * 0.032,
              ),
            ),
            SizedBox(height: w * 0.05),
            FilledButton(
              onPressed: onRetry,
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
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
              color: MyShopColors.textSecondary.withAlpha(80), size: w * 0.18),
          SizedBox(height: h * 0.016),
          Text('No notifications yet',
              style: TextStyle(
                color: MyShopColors.textPrimary,
                fontSize: w * 0.042,
                fontWeight: FontWeight.w700,
              )),
          SizedBox(height: h * 0.008),
          Text("You're all caught up!",
              style: TextStyle(
                  color: MyShopColors.textSecondary, fontSize: w * 0.034)),
        ],
      ),
    );
  }
}
