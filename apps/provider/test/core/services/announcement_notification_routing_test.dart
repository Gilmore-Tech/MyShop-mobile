import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_provider/src/core/services/local_notification_service.dart';

void main() {
  test('provider announcement destinations resolve through a local allowlist',
      () {
    expect(providerAnnouncementRoute('notifications'), '/notifications');
    expect(providerAnnouncementRoute('activity'), '/trips');
    expect(providerAnnouncementRoute('support'), '/account/support');
    expect(providerAnnouncementRoute('promotions'), '/earnings');
  });

  test('app-store, unknown, and arbitrary paths fall back to inbox', () {
    expect(providerAnnouncementRoute('app_store'), '/notifications');
    expect(providerAnnouncementRoute('unknown'), '/notifications');
    expect(providerAnnouncementRoute('/account/payouts'), '/notifications');
    expect(providerAnnouncementRoute(null), '/notifications');
  });

  test('tray shell destination selects the existing provider tab', () {
    expect(
      providerSystemTrayNavigationStack(
        providerAnnouncementRoute('promotions'),
      ),
      ['/earnings?source=tray'],
    );
    expect(providerSystemTrayNavigationStack('/home'), ['/home']);
    expect(providerRouteUsesPrimaryShell('/trips'), isTrue);
    expect(providerRouteUsesPrimaryShell('/account/support'), isFalse);
    expect(
      providerInAppNotificationInboxRoute(Uri.parse('/trips')),
      '/notifications?origin=trips',
    );
    expect(
      providerInboxShellActionRoute('/earnings'),
      '/earnings?source=notification_action',
    );
    expect(
      providerInboxShellActionRoute('/home'),
      '/home?source=notification_action',
    );
    expect(
      providerPrimaryShellOpenedFromNotification(
        Uri.parse('/home?source=notification_action'),
      ),
      isTrue,
    );
    expect(
      providerPrimaryShellOpenedFromNotification(Uri.parse('/home')),
      isFalse,
    );
    expect(
      providerInboxShellActionRoute('/home', returnTo: '/trips'),
      '/home?source=notification_action&origin=trips',
    );
    expect(
      providerNotificationShellBackRoute(
        Uri.parse('/home?source=notification_action&origin=trips'),
      ),
      '/notifications?origin=trips',
    );
    expect(
      providerNotificationShellBackRoute(
        Uri.parse('/earnings?source=notification_action'),
      ),
      '/notifications',
    );
  });

  test('tray inbox destination carries an explicit navigation origin', () {
    expect(
      providerSystemTrayNavigationStack('/notifications'),
      ['/home', '/notifications?source=tray'],
    );
    expect(
      providerNotificationOpenedFromSystemTray(
        Uri.parse('/notifications?source=tray'),
      ),
      isTrue,
    );
    expect(
      providerNotificationOpenedFromSystemTray(Uri.parse('/notifications')),
      isFalse,
    );
  });
}
