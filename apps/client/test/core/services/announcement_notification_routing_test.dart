import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_client/src/core/services/local_notification_service.dart';

void main() {
  test('client announcement destinations resolve through a local allowlist',
      () {
    expect(clientAnnouncementRoute('notifications'), '/notifications');
    expect(clientAnnouncementRoute('activity'), '/activity');
    expect(clientAnnouncementRoute('support'), '/profile/support');
    expect(clientAnnouncementRoute('promotions'), '/home');
  });

  test('app-store, unknown, and arbitrary paths fall back to inbox', () {
    expect(clientAnnouncementRoute('app_store'), '/notifications');
    expect(clientAnnouncementRoute('unknown'), '/notifications');
    expect(clientAnnouncementRoute('/profile/payments'), '/notifications');
    expect(clientAnnouncementRoute(null), '/notifications');
  });

  test('tray destinations are stacked above the client dashboard', () {
    expect(
      clientTrayNavigationStack('/notifications'),
      [clientDashboardRoute, '/notifications?source=tray'],
    );
    expect(
      clientTrayNavigationStack('/profile/support'),
      [clientDashboardRoute, '/profile/support'],
    );
    expect(
      clientTrayNavigationStack(clientDashboardRoute),
      [clientDashboardRoute],
    );
    expect(
      clientTrayNavigationStack('/activity'),
      ['/activity?source=tray'],
    );
    expect(clientRouteUsesPrimaryShell('/activity'), isTrue);
    expect(clientRouteUsesPrimaryShell('/activity/ride/123'), isFalse);
    expect(
      clientInAppNotificationInboxRoute(Uri.parse('/profile')),
      '/notifications?origin=profile',
    );
    expect(
      clientInboxShellActionRoute('/activity'),
      '/activity?source=notification_action',
    );
    expect(
      clientInboxShellActionRoute('/home'),
      '/home?source=notification_action',
    );
    expect(
      clientPrimaryShellOpenedFromNotification(
        Uri.parse('/home?source=notification_action'),
      ),
      isTrue,
    );
    expect(
      clientPrimaryShellOpenedFromNotification(Uri.parse('/home')),
      isFalse,
    );
    expect(
      clientInboxShellActionRoute('/home', returnTo: '/profile'),
      '/home?source=notification_action&origin=profile',
    );
    expect(
      clientNotificationShellBackRoute(
        Uri.parse('/home?source=notification_action&origin=profile'),
      ),
      '/notifications?origin=profile',
    );
    expect(
      clientNotificationShellBackRoute(
        Uri.parse('/activity?source=notification_action'),
      ),
      clientNotificationInboxRoute,
    );
  });

  test('detail routes do not receive a tray-origin marker', () {
    expect(
      clientNotificationOpenedFromTray(
        Uri.parse('/notifications?source=tray'),
      ),
      isTrue,
    );
    expect(
      clientNotificationOpenedFromTray(Uri.parse('/notifications')),
      isFalse,
    );
    expect(
      clientTrayDestinationRoute('/profile/support'),
      '/profile/support',
    );
  });
}
