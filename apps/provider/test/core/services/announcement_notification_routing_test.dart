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

  test('tray destination seeds home before pushing the allowlisted route', () {
    expect(
      providerSystemTrayNavigationStack(
        providerAnnouncementRoute('promotions'),
      ),
      ['/home', '/earnings'],
    );
    expect(providerSystemTrayNavigationStack('/home'), ['/home']);
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
