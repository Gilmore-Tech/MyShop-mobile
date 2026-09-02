import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../core/services/local_notification_service.dart';
import '../providers/notifications_provider.dart';

/// One notification entry point shared by every provider dashboard header.
///
/// The red indicator is rendered only while the server-backed unread count is
/// positive. Keeping that decision here prevents individual dashboards from
/// drifting back to hard-coded badge state.
class ProviderNotificationBell extends ConsumerWidget {
  const ProviderNotificationBell({
    super.key,
    this.contained = false,
  });

  final bool contained;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unreadCount = ref.watch(providerUnreadNotificationCountProvider);

    return IconButton(
      key: const Key('provider-notification-bell'),
      onPressed: () => context.push(
        providerInAppNotificationInboxRoute(GoRouterState.of(context).uri),
      ),
      tooltip: unreadCount > 0
          ? 'Notifications, $unreadCount unread'
          : 'Notifications',
      constraints: const BoxConstraints.tightFor(width: 44, height: 44),
      padding: const EdgeInsets.all(10),
      style: contained
          ? IconButton.styleFrom(
              backgroundColor: MyShopColors.surfaceWhite,
              shape: const CircleBorder(
                side: BorderSide(color: MyShopColors.divider),
              ),
            )
          : null,
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(
            Icons.notifications_none,
            size: 24,
            color: MyShopColors.textPrimary,
          ),
          if (unreadCount > 0)
            Positioned(
              key: const Key('provider-notification-unread-dot'),
              top: -2,
              right: -2,
              child: Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: MyShopColors.error,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: MyShopColors.surfaceWhite,
                    width: 1.5,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
