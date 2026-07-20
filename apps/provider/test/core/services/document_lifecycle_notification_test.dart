import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_provider/src/core/services/local_notification_service.dart';

void main() {
  test('backend document lifecycle event types map to mobile constants', () {
    expect(
      NotificationPayload.normaliseType('provider.document.upload_confirmed'),
      NotificationPayload.typeProviderDocumentUploadConfirmed,
    );
    expect(
      NotificationPayload.normaliseType('provider.document.expiry_notice'),
      NotificationPayload.typeProviderDocumentExpiryNotice,
    );
    expect(
      NotificationPayload.normaliseType('provider.document.expired'),
      NotificationPayload.typeProviderDocumentExpired,
    );
    expect(
      NotificationPayload.normaliseType('provider.document.expiry_72h'),
      NotificationPayload.typeProviderDocumentExpiry72h,
    );
    expect(
      NotificationPayload.normaliseType('provider.document.expiry_24h'),
      NotificationPayload.typeProviderDocumentExpiry24h,
    );
    expect(
      NotificationPayload.normaliseType('provider.document.expiry_2h'),
      NotificationPayload.typeProviderDocumentExpiry2h,
    );
    expect(
      NotificationPayload.normaliseType(
        'provider.document.replacement_grace_started',
      ),
      NotificationPayload.typeProviderDocumentReplacementGraceStarted,
    );
    expect(
      NotificationPayload.normaliseType(
        'provider.document.replacement_grace_expired',
      ),
      NotificationPayload.typeProviderDocumentReplacementGraceExpired,
    );
  });

  test('only known document lifecycle events route to corrective screen', () {
    for (final event in const [
      'provider.document.upload_confirmed',
      'provider.document.expiry_notice',
      'provider.document.expiry_72h',
      'provider.document.expiry_24h',
      'provider.document.expiry_2h',
      'provider.document.expired',
      'provider.document.replacement_grace_started',
      'provider.document.replacement_grace_expired',
    ]) {
      expect(providerDocumentLifecycleRoute(event), '/account/documents');
    }

    expect(providerDocumentLifecycleRoute('ride.request'), isNull);
    expect(providerDocumentLifecycleRoute('/admin/unsafe'), isNull);
  });

  test('vehicle category events use local allowlisted tap destination', () {
    expect(
      providerLifecycleNotificationRoute('ride_category.approved'),
      '/account/vehicle',
    );
    expect(
      providerLifecycleNotificationRoute('ride_category.rejected'),
      '/account/vehicle',
    );
    expect(
      providerLifecycleNotificationRoute('unknown.event'),
      isNull,
    );
    expect(
      providerLifecycleNotificationRoute('/admin/unsafe'),
      isNull,
    );
  });
}
