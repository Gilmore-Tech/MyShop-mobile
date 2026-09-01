import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_provider/src/core/services/local_notification_service.dart';

void main() {
  const jobId = '11111111-1111-4111-8111-111111111111';
  const ticketId = '22222222-2222-4222-8222-222222222222';

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
    expect(
      NotificationPayload.normaliseType('verification.approved'),
      NotificationPayload.typeVerificationApproved,
    );
    expect(
      NotificationPayload.normaliseType('verification.rejected'),
      NotificationPayload.typeVerificationRejected,
    );
    expect(
      NotificationPayload.normaliseType('verification.document_reviewed'),
      NotificationPayload.typeVerificationDocumentReviewed,
    );
    expect(
      NotificationPayload.normaliseType('verification.document_approved'),
      NotificationPayload.typeVerificationDocumentApproved,
    );
    expect(
      NotificationPayload.normaliseType('verification.document_rejected'),
      NotificationPayload.typeVerificationDocumentRejected,
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
      'verification.approved',
      'verification.rejected',
      'verification.document_reviewed',
      'verification.document_approved',
      'verification.document_rejected',
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

  group('provider inbox action resolver', () {
    test('returns corrective document actions only when action is required',
        () {
      final rejected = providerInboxActionFor(
        eventType: 'verification.rejected',
        payload: const {'route': '/unsafe/admin'},
      );
      final reviewedRejected = providerInboxActionFor(
        eventType: 'verification.document_reviewed',
        payload: const {'status': 'rejected'},
      );

      expect(rejected?.label, 'Re-upload document');
      expect(rejected?.route, '/account/documents');
      expect(reviewedRejected?.label, 'Re-upload document');
      expect(
        providerInboxActionFor(
          eventType: 'verification.document_reviewed',
          payload: const {'status': 'approved'},
        ),
        isNull,
      );
      expect(
        providerInboxActionFor(eventType: 'verification.approved'),
        isNull,
      );
    });

    test('maps expiry, rejected category, location, and account alerts', () {
      expect(
        providerInboxActionFor(eventType: 'provider.document.expiry_24h')
            ?.label,
        'Renew document',
      );
      expect(
        providerInboxActionFor(eventType: 'provider.document.expired')?.label,
        'Replace document',
      );
      expect(
        providerInboxActionFor(eventType: 'ride_category.rejected')?.route,
        '/account/vehicle',
      );
      expect(
        providerInboxActionFor(eventType: 'provider.location_degraded')?.route,
        '/home',
      );
      expect(
        providerInboxActionFor(eventType: 'account.suspended.low_rating')
            ?.route,
        '/account/support',
      );
      expect(
        providerInboxActionFor(
          eventType: 'provider.cancellation_block_started',
        )?.label,
        'Contact support',
      );
      expect(
        providerInboxActionFor(eventType: 'account.rating.warning')?.route,
        '/earnings',
      );
      expect(
        providerInboxActionFor(eventType: 'ride_category.approved'),
        isNull,
      );
    });

    test('supports backend event names and mobile aliases for jobs', () {
      for (final eventType in const ['job.bid_selected', 'bid_accepted']) {
        final action = providerInboxActionFor(
          eventType: eventType,
          payload: const {NotificationPayload.keyJobId: jobId},
        );
        expect(action?.kind, ProviderInboxActionKind.activeJob);
        expect(action?.entityId, jobId);
        expect(action?.label, 'Open job');
      }

      final manual = providerInboxActionFor(
        eventType: 'job.manually_assigned',
        payload: const {NotificationPayload.keyJobId: jobId},
      );
      expect(manual?.kind, ProviderInboxActionKind.manualJob);
      expect(manual?.label, 'Review & bid');

      const offerId = '22222222-2222-4222-8222-222222222222';
      final exactQuote = providerInboxActionFor(
        eventType: 'job.manually_assigned',
        payload: const {
          NotificationPayload.keyJobId: jobId,
          NotificationPayload.keyOfferId: offerId,
          'offerVersion': 2,
          'mode': 'request_quote',
        },
      );
      expect(exactQuote?.requiresExactJobReceipt, isTrue);
      expect(exactQuote?.offerId, offerId);
      expect(exactQuote?.offerVersion, 2);
      expect(exactQuote?.assignmentMode, 'request_quote');

      expect(
        providerInboxActionFor(
          eventType: 'job.manually_assigned',
          payload: const {
            NotificationPayload.keyJobId: jobId,
            'offerVersion': 2,
            'mode': 'request_quote',
          },
        ),
        isNull,
      );

      final confirmed = providerInboxActionFor(
        eventType: 'job.manually_assigned',
        payload: const {
          NotificationPayload.keyJobId: jobId,
          'mode': 'confirm',
        },
      );
      expect(confirmed?.kind, ProviderInboxActionKind.activeJob);
      expect(confirmed?.label, 'Open job');
    });

    test('rejects malformed ids and excludes expiring request offers', () {
      expect(
        providerInboxActionFor(
          eventType: 'job.manually_assigned',
          payload: const {NotificationPayload.keyJobId: 'not-a-uuid'},
        ),
        isNull,
      );
      expect(
        providerInboxActionFor(
          eventType: 'job.request',
          payload: const {NotificationPayload.keyJobId: jobId},
        ),
        isNull,
      );
      expect(
        providerInboxActionFor(
          eventType: 'ride.request',
          payload: const {NotificationPayload.keyRideId: jobId},
        ),
        isNull,
      );
    });

    test('allows only bounded announcement destinations', () {
      expect(
        providerInboxActionFor(
          eventType: 'announcement',
          payload: const {NotificationPayload.keyDestination: 'promotions'},
        )?.route,
        '/earnings',
      );
      expect(
        providerInboxActionFor(
          eventType: 'announcement',
          payload: const {
            NotificationPayload.keyDestination: 'notifications',
            'route': '/unsafe/admin',
          },
        ),
        isNull,
      );
      expect(
        providerInboxActionFor(
          eventType: 'unknown.event',
          payload: const {'route': '/earnings'},
        ),
        isNull,
      );
    });

    test('validates support and rating entity ids', () {
      final support = providerInboxActionFor(
        eventType: 'support.ticket_message',
        payload: const {NotificationPayload.keyTicketId: ticketId},
      );
      final rating = providerInboxActionFor(
        eventType: 'rating.prompt',
        payload: const {
          NotificationPayload.keyBookingType: 'artisan_job',
          NotificationPayload.keyBookingId: jobId,
        },
      );

      expect(support?.label, 'View & reply');
      expect(support?.route, '/account/support/tickets/$ticketId');
      expect(rating?.kind, ProviderInboxActionKind.rating);
      expect(rating?.entityId, jobId);
      expect(rating?.bookingType, 'artisan_job');
    });

    test('maps earnings settlement events to the earnings screen', () {
      for (final eventType in const [
        'ride.settled',
        'payment.received',
        'earnings.updated',
        'job.payment_releasing',
      ]) {
        final action = providerInboxActionFor(eventType: eventType);
        expect(action?.label, 'View earnings');
        expect(action?.route, '/earnings');
      }
    });

    test('exposes only backend-proven payout and manual-assignment actions',
        () {
      final payoutRebind = providerInboxActionFor(
        eventType: 'payout_method.rebind_required',
        payload: const {
          'providerType': 'artisan',
          'reasonCode': 'PAYOUT_METHOD_REBIND_REQUIRED',
        },
      );
      expect(payoutRebind?.label, 'Re-add payout method');
      expect(payoutRebind?.route, '/account/payouts');

      // job.no_bids_escalated is emitted to the client role only. It must not
      // become a provider "Review & bid" action if a stale/malformed row ever
      // reaches the provider resolver.
      expect(
        providerInboxActionFor(
          eventType: 'job.no_bids_escalated',
          payload: const {NotificationPayload.keyJobId: jobId},
        ),
        isNull,
      );
    });

    test('response warning and started events expose safe local actions', () {
      final warning = providerInboxActionFor(
        eventType: 'provider.response_block_warning',
      );
      expect(warning?.label, 'Manage online status');
      expect(warning?.route, '/home');

      final started = providerInboxActionFor(
        eventType: 'provider.response_block_started',
      );
      expect(started?.label, 'Contact support');
      expect(started?.route, '/account/support');
    });
  });
}
