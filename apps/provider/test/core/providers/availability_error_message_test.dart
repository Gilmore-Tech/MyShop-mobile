import 'package:api_client/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_provider/src/core/providers/availability_controller.dart';

void main() {
  test('verified-state mismatch gives an actionable support path', () {
    const error = ApiException(
      message: 'internal verification aggregate mismatch',
      statusCode: 403,
      errorCode: 'NOT_VERIFIED',
    );

    expect(
      friendlyAvailabilityApiError(error),
      'The server could not confirm that this provider profile is eligible '
      'to go online. Refresh Documents & Verification. If every item is '
      'approved, contact support.',
    );
  });

  test('known availability codes use stable messages, not server text', () {
    const error = ApiException(
      message: 'No cached location — send coordinates to an internal route.',
      statusCode: 400,
      errorCode: 'GPS_REQUIRED',
    );

    expect(
      friendlyAvailabilityApiError(error),
      'A fresh location is required. Turn on Location Services, wait for GPS '
      'to settle, and try again.',
    );
  });

  test('stale and inaccurate GPS errors give distinct recovery instructions',
      () {
    const stale = ApiException(
      message: 'internal timestamp comparison detail',
      statusCode: 400,
      errorCode: 'GPS_FIX_STALE',
    );
    const inaccurate = ApiException(
      message: 'internal accuracy threshold detail',
      statusCode: 400,
      errorCode: 'GPS_ACCURACY_REQUIRED',
    );
    const outOfOrder = ApiException(
      message: 'internal monotonic timestamp detail',
      statusCode: 409,
      errorCode: 'GPS_FIX_OUT_OF_ORDER',
    );

    expect(
      friendlyAvailabilityApiError(stale),
      'Your location fix is out of date. Keep Location Services on, wait for '
      'a new GPS fix, and try again.',
    );
    expect(
      friendlyAvailabilityApiError(inaccurate),
      'GPS accuracy is too low. Move to an open area, wait for the location '
      'signal to improve, and try again.',
    );
    expect(
      friendlyAvailabilityApiError(outOfOrder),
      'A newer location is already saved. Wait for the next GPS fix and try again.',
    );
  });

  test('unknown API failures never expose arbitrary backend text', () {
    const error = ApiException(
      message: 'Prisma query failed for user 123',
      statusCode: 400,
      errorCode: 'UNRECOGNISED_INTERNAL_ERROR',
    );

    expect(
      friendlyAvailabilityApiError(error),
      "We couldn't change your availability. Try again. If it continues, "
      'contact support.',
    );
  });

  test('network and server failures are distinguished without leaking detail',
      () {
    const network = NetworkException(message: 'socket exception: host');
    const server = ServerException(
      message: 'database password rejected',
      statusCode: 503,
    );

    expect(
      friendlyAvailabilityApiError(network),
      'No connection to MyShop. Check your network and try again.',
    );
    expect(
      friendlyAvailabilityApiError(server),
      "MyShop couldn't complete the Go Online request. Try again shortly.",
    );
  });
}
