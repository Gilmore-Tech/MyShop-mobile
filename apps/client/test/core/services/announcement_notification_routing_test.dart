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
      [clientDashboardRoute, '/notifications'],
    );
    expect(
      clientTrayNavigationStack('/profile/support'),
      [clientDashboardRoute, '/profile/support'],
    );
    expect(
      clientTrayNavigationStack(clientDashboardRoute),
      [clientDashboardRoute],
    );
  });
}
