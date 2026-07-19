import 'package:api_client/api_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('projects a server deadline onto the handset clock', () {
    final before = DateTime.now().toUtc();
    final request = ProviderPendingRequest.fromJson(
      {
        'kind': 'ride',
        'id': 'ride-1',
        'offerId': 'offer-1',
        // Deliberately far from the test handset's wall clock. The remaining
        // duration is authoritative, not either absolute local timestamp.
        'serverNow': '2020-01-01T00:00:00.000Z',
        'expiresAt': '2020-01-01T00:00:45.000Z',
      },
      transportElapsed: const Duration(seconds: 5),
    );
    final after = DateTime.now().toUtc();

    expect(request.serverExpiresAt, DateTime.utc(2020, 1, 1, 0, 0, 45));
    expect(request.expiresAt, isNotNull);
    expect(
      request.expiresAt!.difference(before),
      greaterThanOrEqualTo(const Duration(seconds: 39)),
    );
    expect(
      request.expiresAt!.difference(after),
      lessThanOrEqualTo(const Duration(seconds: 40)),
    );
    expect(request.isExpired, isFalse);
  });

  test('marks an already elapsed server window as expired despite clock skew',
      () {
    final request = ProviderPendingRequest.fromJson({
      'kind': 'ride',
      'id': 'ride-1',
      'serverNow': '2035-01-01T00:01:00.000Z',
      'expiresAt': '2035-01-01T00:00:45.000Z',
    });

    expect(request.isExpired, isTrue);
  });
}
