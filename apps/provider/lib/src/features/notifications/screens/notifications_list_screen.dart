import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../core/di/providers.dart';
import '../../../core/providers/socket_provider.dart';
import '../../../core/services/job_offer_receipt_service.dart';
import '../../../core/services/local_notification_service.dart';
import '../../artisan_home/providers/active_job_provider.dart';
import '../../artisan_home/providers/job_poller_provider.dart';
import '../../artisan_home/widgets/rate_client_sheet.dart';
import '../../auth/providers/auth_controller.dart';
import '../../driver_home/widgets/rate_passenger_sheet.dart';
import '../../profile/providers/verification_provider.dart';
import '../providers/notifications_provider.dart';

typedef ProviderLocationRecoveryLauncher = Future<bool> Function();

/// Location-degradation alerts need to perform a real corrective action, not
/// push the already-mounted `/home` shell route underneath the inbox. Pushing
/// that shell route can duplicate GoRouter page keys and leave Back trapped on
/// the notification screen.
final providerLocationRecoveryLauncherProvider =
    Provider<ProviderLocationRecoveryLauncher>((_) {
  return () async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return Geolocator.openLocationSettings();
    }
    return Geolocator.openAppSettings();
  };
});

/// Only these authoritative states belong in [activeJobProvider]. Calling
/// `setJob` also marks the provider Busy, so a historical notification for a
/// completed/cancelled/pending job must never seed that slot.
bool providerInboxJobStatusCanOpenActive(JobStatus status) => switch (status) {
      JobStatus.confirmed ||
      JobStatus.artisanEnRoute ||
      JobStatus.arrived ||
      JobStatus.inProgress ||
      JobStatus.artisanMarkedComplete =>
        true,
      _ => false,
    };

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

  void _goBack(
    BuildContext context, {
    required bool openedFromSystemTray,
  }) {
    // A tray entry never inherits the route the app happened to have open in
    // the background. Force the provider dashboard even if duplicate native
    // callbacks stacked two copies of the same inbox route.
    if (openedFromSystemTray) {
      context.go('/home');
      return;
    }
    if (context.canPop()) {
      context.pop();
      return;
    }
    // A tray deep-link is opened with go(), so there is no meaningful inbox
    // route below it. Always return to the active role's /home dashboard.
    context.go('/home');
  }

  Future<void> _openNotification(
    BuildContext context,
    Notif notification,
    ProviderInboxAction? action,
  ) async {
    ref.read(providerNotifsProvider.notifier).markRead(notification.id);
    if (action == null) return;

    switch (action.kind) {
      case ProviderInboxActionKind.route:
        final route = action.route;
        if (route == null || route == '/notifications') return;
        if (route == '/account/documents') {
          ref.invalidate(verificationStatusProvider);
          // The document destination loads the authoritative review snapshot.
          // Refresh the authenticated profile in parallel so other provider
          // surfaces do not retain an older verification status.
          unawaited(ref.read(authControllerProvider.notifier).refreshProfile());
        }
        unawaited(context.push<void>(route));
        return;

      case ProviderInboxActionKind.locationSettings:
        await _openLocationRecoverySettings(context);
        return;

      case ProviderInboxActionKind.manualJob:
        await _hydrateAndOpenJob(
          context,
          action,
          notificationPayload: notification.payload,
          openAsManualRequest: true,
        );
        return;

      case ProviderInboxActionKind.activeJob:
        await _hydrateAndOpenJob(
          context,
          action,
          notificationPayload: notification.payload,
          openAsManualRequest: false,
        );
        return;

      case ProviderInboxActionKind.rating:
        await _openRatingAction(context, action);
        return;
    }
  }

  Future<void> _openLocationRecoverySettings(BuildContext context) async {
    try {
      final opened = await ref.read(providerLocationRecoveryLauncherProvider)();
      if (opened || !context.mounted) return;
    } catch (error) {
      debugPrint('[Notifications] opening location settings failed: $error');
      if (!context.mounted) return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text(
            'Could not open Location Settings. Open it from your phone settings.',
          ),
        ),
      );
  }

  Future<void> _hydrateAndOpenJob(
    BuildContext context,
    ProviderInboxAction action, {
    required Map<String, dynamic> notificationPayload,
    required bool openAsManualRequest,
  }) async {
    final jobId = action.entityId;
    if (jobId == null) return;
    final expectedSession = ref.read(currentAuthSessionIdentityProvider);
    if (expectedSession == null) return;
    var surfaceWasAlreadyClaimed = false;
    var claimedSurface = false;
    String? claimedOfferId;

    try {
      ReceivedJobOffer? received;
      if (openAsManualRequest && action.requiresExactJobReceipt) {
        received = await acknowledgeJobOffer(
          payload: <String, dynamic>{
            ...notificationPayload,
            NotificationPayload.keyType:
                NotificationPayload.typeJobManuallyAssigned,
            NotificationPayload.keyJobId: jobId,
            NotificationPayload.keyOfferId: action.offerId,
            'offerVersion': action.offerVersion.toString(),
            'mode': action.assignmentMode,
          },
          jobs: ref.read(jobServiceProvider),
        );
        if (received == null || !received.hasExactReceipt) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              const SnackBar(
                content: Text(
                  'This assignment is no longer available. Refresh your notifications.',
                ),
              ),
            );
          return;
        }
        if (ref.read(currentAuthSessionIdentityProvider) != expectedSession) {
          return;
        }
        claimedOfferId = received.offerId;
        ref.read(jobOfferIdByJobProvider.notifier).update(
              (offers) => {...offers, jobId: received!.offerId!},
            );
        ref.read(lastJobOfferIdByJobProvider.notifier).update(
              (offers) => {...offers, jobId: received!.offerId!},
            );
        final deadline = received.decisionExpiresAt;
        if (deadline != null) {
          ref.read(jobOfferDeadlineByJobProvider.notifier).update(
                (deadlines) => {...deadlines, jobId: deadline},
              );
        }
        ref.read(jobOfferDismissalProvider.notifier).state = null;
      }
      if (ref.read(currentAuthSessionIdentityProvider) != expectedSession) {
        return;
      }
      if (openAsManualRequest) {
        surfaceWasAlreadyClaimed =
            ref.read(surfacedJobIdsProvider).contains(jobId);
        ref
            .read(surfacedJobIdsProvider.notifier)
            .update((ids) => {...ids, jobId});
        claimedSurface = true;
        if (ref.read(incomingJobRequestProvider)?.id == jobId) {
          ref.read(incomingJobRequestProvider.notifier).state = null;
        }
      }
      final raw = await ref.read(jobServiceProvider).getJob(jobId);
      if (ref.read(currentAuthSessionIdentityProvider) != expectedSession) {
        return;
      }
      final hydrated = Job.fromJson(raw);
      final job = received?.decisionExpiresAt == null
          ? hydrated
          : hydrated.copyWith(
              expiresAt: received!.decisionExpiresAt!.toIso8601String(),
            );
      if (!context.mounted) return;
      if (openAsManualRequest) {
        unawaited(context.push<void>('/job-request', extra: job));
      } else {
        if (!providerInboxJobStatusCanOpenActive(job.status)) {
          final message = switch (job.status) {
            JobStatus.completed =>
              'This job is already completed. You can review it in My Jobs.',
            JobStatus.cancelled =>
              'This job was cancelled. You can review it in My Jobs.',
            _ =>
              'This job is no longer active. Check My Jobs for its latest status.',
          };
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(message)));
          unawaited(context.push<void>('/trips'));
          return;
        }
        ref.read(activeJobProvider.notifier).setJob(job);
        unawaited(context.push<void>('/active-job'));
      }
    } catch (error) {
      if (claimedSurface &&
          !surfaceWasAlreadyClaimed &&
          ref.read(currentAuthSessionIdentityProvider) == expectedSession) {
        final latestExact = ref.read(lastJobOfferIdByJobProvider)[jobId];
        if (claimedOfferId == null || latestExact == claimedOfferId) {
          ref
              .read(surfacedJobIdsProvider.notifier)
              .update((ids) => {...ids}..remove(jobId));
        }
      }
      if (ref.read(currentAuthSessionIdentityProvider) != expectedSession) {
        return;
      }
      if (!context.mounted) return;
      final message = openAsManualRequest
          ? 'This job could not be opened. Refresh and try again.'
          : 'This job could not be opened. Check My Jobs for its latest status.';
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
      if (!openAsManualRequest) {
        unawaited(context.push<void>('/trips'));
      }
    }
  }

  Future<void> _openRatingAction(
    BuildContext context,
    ProviderInboxAction action,
  ) async {
    final bookingId = action.entityId;
    if (bookingId == null) return;

    if (action.bookingType == 'ride') {
      var passengerFirstName = 'Passenger';
      try {
        final raw = await ref.read(rideServiceProvider).getRide(bookingId);
        final name = Ride.fromJson(raw).clientName?.trim();
        if (name != null && name.isNotEmpty) {
          passengerFirstName = name.split(RegExp(r'\s+')).first;
        }
      } catch (error) {
        debugPrint('[Notifications] rating ride hydration failed: $error');
      }
      if (!context.mounted) return;
      await showRatePassengerSheet(
        context,
        rideId: bookingId,
        passengerFirstName: passengerFirstName,
      );
      return;
    }

    var clientFirstName = 'Client';
    try {
      final raw = await ref.read(jobServiceProvider).getJob(bookingId);
      final name = Job.fromJson(raw).clientName?.trim();
      if (name != null && name.isNotEmpty) {
        clientFirstName = name.split(RegExp(r'\s+')).first;
      }
    } catch (error) {
      debugPrint('[Notifications] rating job hydration failed: $error');
    }
    if (!context.mounted) return;
    await showRateClientSheet(
      context,
      jobId: bookingId,
      clientFirstName: clientFirstName,
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final w = size.width;
    final h = size.height;
    final notificationState = ref.watch(providerNotifsProvider);
    final notifs = notificationState.items;
    // The first page can contain only a subset of unread rows. Use the exact
    // server total so the header and mark-all action agree with the bell.
    final unread = notificationState.unreadCount;
    final openedFromSystemTray = providerNotificationOpenedFromSystemTray(
      GoRouterState.of(context).uri,
    );

    return PopScope(
      // Let ordinary in-app navigation pop to the exact prior screen. Tray
      // routes own Back so a duplicate platform callback cannot reveal a
      // second inbox page or a stale background route.
      canPop: !openedFromSystemTray && context.canPop(),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _goBack(
            context,
            openedFromSystemTray: openedFromSystemTray,
          );
        }
      },
      child: Scaffold(
        backgroundColor: MyShopColors.offWhite,
        appBar: AppBar(
          backgroundColor: MyShopColors.surfaceWhite,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: MyShopColors.textPrimary),
            onPressed: () => _goBack(
              context,
              openedFromSystemTray: openedFromSystemTray,
            ),
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
                          onTap: (notification, action) => unawaited(
                            _openNotification(context, notification, action),
                          ),
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
  final void Function(Notif, ProviderInboxAction?) onTap;
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
          ...today.map((n) => _NotifTile(
                notif: n,
                action: providerInboxActionFor(
                  eventType: n.eventType,
                  payload: n.payload,
                ),
                onTap: onTap,
                w: w,
                h: h,
              )),
        ],
        if (earlier.isNotEmpty) ...[
          _GroupLabel(label: 'EARLIER', w: w),
          ...earlier.map((n) => _NotifTile(
                notif: n,
                action: providerInboxActionFor(
                  eventType: n.eventType,
                  payload: n.payload,
                ),
                onTap: onTap,
                w: w,
                h: h,
              )),
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
  final ProviderInboxAction? action;
  final void Function(Notif, ProviderInboxAction?) onTap;
  final double w, h;

  const _NotifTile({
    required this.notif,
    required this.action,
    required this.onTap,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    final (iconData, iconColor, iconBg) = _iconFor(notif.type);

    return InkWell(
      onTap: () => onTap(notif, action),
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
                  if (action case final action?) ...[
                    SizedBox(height: h * 0.008),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        key: ValueKey(
                            'provider-notification-action-${notif.id}'),
                        onPressed: () => onTap(notif, action),
                        style: TextButton.styleFrom(
                          foregroundColor: MyShopColors.primaryGold,
                          padding: EdgeInsets.symmetric(
                            horizontal: w * 0.020,
                            vertical: h * 0.004,
                          ),
                          minimumSize: const Size(0, 32),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                          textStyle: TextStyle(
                            fontSize: w * 0.031,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        child: Text(action.label),
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
