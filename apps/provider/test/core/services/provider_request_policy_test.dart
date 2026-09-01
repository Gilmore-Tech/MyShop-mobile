import 'package:api_client/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_provider/src/core/services/provider_request_policy.dart';

void main() {
  test('canonical offer-response block explains cooldown and rating safety',
      () {
    const error = ApiException(
      message: 'blocked',
      statusCode: 429,
      errorCode: 'PROVIDER_REQUEST_BLOCK',
      details: {
        'policyKind': 'offer_response',
        'retryAfterSeconds': 900,
        'points': 6,
        'threshold': 6,
      },
    );

    final message = providerRequestBlockMessage(error);

    expect(message, contains('declines or missed requests'));
    expect(message, contains('in 15 minutes'));
    expect(message, contains('does not change your customer rating'));
  });

  test('canonical accepted-cancellation block keeps cancellation copy', () {
    const error = ApiException(
      message: 'blocked',
      statusCode: 429,
      errorCode: 'PROVIDER_REQUEST_BLOCK',
      details: {'policyKind': 'accepted_cancellation'},
    );

    final message = providerRequestBlockMessage(error);

    expect(message, contains('accepted-work cancellations'));
    expect(message, isNot(contains('declines or missed requests')));
  });

  test('legacy cancellation code remains supported', () {
    const error = ApiException(
      message: 'blocked',
      statusCode: 429,
      errorCode: 'PROVIDER_CANCELLATION_BLOCK',
    );

    expect(isProviderRequestBlock(error), isTrue);
    expect(
      providerRequestBlockMessage(error),
      contains('accepted-work cancellations'),
    );
  });

  test('nested activeRestriction details are parsed', () {
    const error = ApiException(
      message: 'blocked',
      statusCode: 429,
      errorCode: 'PROVIDER_REQUEST_BLOCK',
      details: {
        'activeRestriction': {
          'policyKind': 'offer_response',
          'blockedUntil': '2026-08-31T12:20:00.000Z',
          'count': 4,
          'threshold': 6,
        },
      },
    );

    final restriction = providerRequestRestrictionFromError(error);

    expect(restriction?.policyKind, 'offer_response');
    expect(restriction?.count, 4);
    expect(restriction?.threshold, 6);
  });

  test('summary copy uses both authoritative rates when supplied', () {
    const summary = ProviderRequestResponseSummary(
      periodDays: 7,
      eligibleOffers: 10,
      acceptedOffers: 6,
      declinedOffers: 2,
      noResponseOffers: 2,
      acceptanceRatePercent: 60,
      responseRatePercent: 80,
    );

    final message = providerRequestResponseSummaryMessage(
      summary,
      isOnline: true,
    );

    expect(message, contains('responded to 80%'));
    expect(message, contains('accepted 60%'));
    expect(message, contains('last 7 days'));
    expect(message, contains('do not change your customer rating'));
  });

  test('summary copy stays neutral when an older server omits rates', () {
    const summary = ProviderRequestResponseSummary(
      periodDays: 7,
      eligibleOffers: 10,
      acceptedOffers: 0,
      declinedOffers: 0,
      noResponseOffers: 0,
    );

    final message = providerRequestResponseSummaryMessage(
      summary,
      isOnline: true,
    );

    expect(message, contains('no response or acceptance rate was supplied'));
    expect(message, isNot(contains('%')));
  });
}
