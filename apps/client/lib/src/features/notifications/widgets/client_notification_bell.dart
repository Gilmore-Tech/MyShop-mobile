import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';

import '../providers/notifications_provider.dart';

/// One notification entry point shared by the Client Home and Profile headers.
///
/// The red indicator is driven only by the backend-backed exact unread total,
/// preventing individual screens from maintaining stale or hard-coded badge
/// state.
class ClientNotificationBell extends ConsumerWidget {
  const ClientNotificationBell({
    super.key,
    this.contained = false,
  });

  final bool contained;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unreadCount = ref.watch(clientUnreadNotificationCountProvider);

    return IconButton(
      key: const Key('client-notification-bell'),
      onPressed: () => context.push('/notifications'),
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
              key: const Key('client-notification-unread-dot'),
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
