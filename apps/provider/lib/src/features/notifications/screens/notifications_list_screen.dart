import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../core/services/local_notification_service.dart';
import '../../auth/providers/auth_controller.dart';
import '../../profile/providers/verification_provider.dart';
import '../providers/notifications_provider.dart';

/// Notification inbox — backend-backed list of ride/job/payment/safety/system
/// notifications. Mirrors the client inbox, but with provider-specific push
/// types (bid accepted, supplement approved, payout received, etc.) grouped
/// onto the same five icons.
///
/// EDD § 5.4 — GET /notifications, PATCH /notifications/:id/read.
class ProviderNotificationsScreen extends ConsumerStatefulWidget {
  const ProviderNotificationsScreen({super.key});

  @override
  ConsumerState<ProviderNotificationsScreen> createState() =>
      _ProviderNotificationsScreenState();
}

class _ProviderNotificationsScreenState
    extends ConsumerState<ProviderNotificationsScreen> {
  Timer? _relativeTimeTicker;

  @override
  void initState() {
    super.initState();
    // Recompute relative labels locally. This makes "1 min ago" advance while
    // the inbox is open without polling the API.
    _relativeTimeTicker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _relativeTimeTicker?.cancel();
    super.dispose();
  }

  void _goBack(BuildContext context) {
    if (context.canPop()) {
      context.pop();
      return;
    }
    // A tray deep-link is opened with go(), so there is no meaningful inbox
    // route below it. Always return to the active role's /home dashboard.
    context.go('/home');
  }

  void _openNotification(
    BuildContext context,
    Notif notification,
  ) {
    ref.read(providerNotifsProvider.notifier).markRead(notification.id);

    final eventType = NotificationPayload.normaliseType(notification.eventType);
    if (eventType == NotificationPayload.typeAnnouncement) {
      final route = providerAnnouncementRoute(
        notification.payload[NotificationPayload.keyDestination],
      );
      // Do not stack a second copy of the inbox for an announcement whose
      // destination is Notifications. Other in-app taps push so Back returns
      // to this inbox and then to the user's original screen.
      if (route != '/notifications') context.push(route);
      return;
    }

    // Never navigate to a route supplied by the notification payload. Only
    // known event types can resolve to a local corrective destination.
    final route = providerLifecycleNotificationRoute(notification.eventType);
    if (route == null) return;

    if (route == '/account/documents') {
      ref.invalidate(verificationStatusProvider);
      // Refresh the authenticated profile snapshot as well. Navigation should
      // not wait on this best-effort request; the destination already fetches
      // the authoritative verification response on entry.
      unawaited(ref.read(authControllerProvider.notifier).refreshProfile());
    }
    // Lifecycle destinations come only from the local allowlist above. Push
    // them so opening an inbox item never destroys the user's prior stack.
    context.push(route);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final w = size.width;
    final h = size.height;
    final notificationState = ref.watch(providerNotifsProvider);
    final notifs = notificationState.items;
    final unread = notifs.where((n) => !n.isRead).length;

    return PopScope(
      canPop: context.canPop(),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goBack(context);
      },
      child: Scaffold(
        backgroundColor: MyShopColors.offWhite,
        appBar: AppBar(
          backgroundColor: MyShopColors.surfaceWhite,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: MyShopColors.textPrimary),
            onPressed: () => _goBack(context),
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
                onPressed: () =>
                    ref.read(providerNotifsProvider.notifier).markAllRead(),
                tooltip: 'Mark all as read',
                icon: const Icon(
                  Icons.done_all_rounded,
                  color: MyShopColors.primaryGold,
                ),
              ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: () => ref.read(providerNotifsProvider.notifier).reload(),
          color: MyShopColors.primaryGold,
          child: notificationState.isLoading && notifs.isEmpty
              ? _LoadingState(w: w, h: h)
              : notificationState.hasLoadError && notifs.isEmpty
                  ? _LoadErrorState(
                      w: w,
                      h: h,
                      onRetry: () =>
                          ref.read(providerNotifsProvider.notifier).reload(),
                    )
                  : notifs.isEmpty
                      ? _EmptyState(w: w, h: h)
                      : _NotifList(
                          notifs: notifs,
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
  final void Function(Notif) onTap;
  final double w, h;

  const _NotifList({
    required this.notifs,
    required this.onTap,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    final today = notifs.where(providerNotificationIsToday).toList();
    final earlier =
        notifs.where((n) => !providerNotificationIsToday(n)).toList();

    return ListView(
      padding: EdgeInsets.symmetric(vertical: h * 0.010),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        if (today.isNotEmpty) ...[
          _GroupLabel(label: 'TODAY', w: w),
          ...today.map((n) => _NotifTile(notif: n, onTap: onTap, w: w, h: h)),
        ],
        if (earlier.isNotEmpty) ...[
          _GroupLabel(label: 'EARLIER', w: w),
          ...earlier.map((n) => _NotifTile(notif: n, onTap: onTap, w: w, h: h)),
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
  final void Function(Notif) onTap;
  final double w, h;

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
      onTap: () => onTap(notif),
      child: Container(
        color: notif.isRead ? MyShopColors.offWhite : MyShopColors.surfaceWhite,
        padding:
            EdgeInsets.symmetric(horizontal: w * 0.05, vertical: h * 0.016),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: w * 0.12,
              height: w * 0.12,
              decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
              child: Icon(iconData, color: iconColor, size: w * 0.056),
            ),
            SizedBox(width: w * 0.030),
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
                      _NotificationTime(notification: notif, w: w),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(notif.body,
                      style: TextStyle(
                          color: MyShopColors.textSecondary,
                          fontSize: w * 0.032,
                          height: 1.4)),
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

// ── Empty state ────────────────────────────────────────────────────────────────

class _NotificationTime extends StatelessWidget {
  const _NotificationTime({
    required this.notification,
    required this.w,
  });

  final Notif notification;
  final double w;

  @override
  Widget build(BuildContext context) {
    final relative = providerNotificationTimeAgo(
      notification.createdAt,
      fallback: notification.fallbackTimeAgo,
    );
    final exact = providerNotificationLocalDateTime(notification.createdAt);

    if (relative.isEmpty && exact.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (relative.isNotEmpty)
          Text(
            relative,
            textAlign: TextAlign.end,
            style: TextStyle(
              color: MyShopColors.textSecondary,
              fontSize: w * 0.028,
            ),
          ),
        if (exact.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            exact,
            textAlign: TextAlign.end,
            style: TextStyle(
              color: MyShopColors.textSecondary.withAlpha(180),
              fontSize: w * 0.024,
            ),
          ),
        ],
      ],
    );
  }
}

class _LoadingState extends StatelessWidget {
  final double w, h;
  const _LoadingState({required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(height: h * 0.28),
        Center(
          child: Column(
            children: [
              SizedBox(
                width: w * 0.08,
                height: w * 0.08,
                child: const CircularProgressIndicator(
                  color: MyShopColors.primaryGold,
                  strokeWidth: 3,
                ),
              ),
              SizedBox(height: h * 0.018),
              Text(
                'Loading notifications…',
                style: TextStyle(
                  color: MyShopColors.textSecondary,
                  fontSize: w * 0.034,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LoadErrorState extends StatelessWidget {
  final double w, h;
  final VoidCallback onRetry;
  const _LoadErrorState({
    required this.w,
    required this.h,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(height: h * 0.20),
        Center(
          child: Column(
            children: [
              Icon(
                Icons.cloud_off_rounded,
                color: MyShopColors.textSecondary.withAlpha(100),
                size: w * 0.16,
              ),
              SizedBox(height: h * 0.016),
              Text(
                'Could not load notifications',
                style: TextStyle(
                  color: MyShopColors.textPrimary,
                  fontSize: w * 0.040,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: h * 0.012),
              TextButton(
                onPressed: onRetry,
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  final double w, h;
  const _EmptyState({required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(height: h * 0.18),
        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.notifications_none_rounded,
                  color: MyShopColors.textSecondary.withAlpha(80),
                  size: w * 0.18),
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
        ),
      ],
    );
  }
}
