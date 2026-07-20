import 'package:api_client/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_client/src/features/ride/data/ride_cancellation_coordinator.dart';
import 'package:mocktail/mocktail.dart';

class _MockRideService extends Mock implements RideService {}

void main() {
  late _MockRideService rideService;

  setUp(() {
    rideService = _MockRideService();
  });

  test('accepts the cancellation response without an unnecessary read',
      () async {
    when(() => rideService.cancelRide('ride-1', reason: 'rider_cancelled'))
        .thenAnswer(
      (_) async => <String, dynamic>{
        'rideId': 'ride-1',
        'cancellationFeePesewas': 50,
      },
    );

    final result = await cancelRideWithAuthority(
      rideService: rideService,
      rideId: 'ride-1',
      reason: 'rider_cancelled',
    );

    expect(result.confirmedCancelled, isTrue);
    expect(result.reconciled, isFalse);
    expect(result.response['cancellationFeePesewas'], 50);
    verifyNever(() => rideService.getRide(any()));
  });

  test('recognises a timeout-after-commit from the authoritative row',
      () async {
    when(() => rideService.cancelRide('ride-1', reason: 'rider_cancelled'))
        .thenThrow(const NetworkException(message: 'timeout'));
    when(() => rideService.getRide('ride-1')).thenAnswer(
      (_) async => <String, dynamic>{'id': 'ride-1', 'status': 'cancelled'},
    );

    final result = await cancelRideWithAuthority(
      rideService: rideService,
      rideId: 'ride-1',
      reason: 'rider_cancelled',
    );

    expect(result.confirmedCancelled, isTrue);
    expect(result.reconciled, isTrue);
  });

  test('preserves local state when the server still has an active ride',
      () async {
    when(() => rideService.cancelRide('ride-1', reason: 'rider_cancelled'))
        .thenThrow(
      const ApiException(
        message: 'raw backend status detail',
        statusCode: 400,
        errorCode: 'RIDE_NOT_CANCELLABLE',
      ),
    );
    when(() => rideService.getRide('ride-1')).thenAnswer(
      (_) async => <String, dynamic>{'id': 'ride-1', 'status': 'in_progress'},
    );

    final result = await cancelRideWithAuthority(
      rideService: rideService,
      rideId: 'ride-1',
      reason: 'rider_cancelled',
    );

    expect(result.confirmedCancelled, isFalse);
    expect(result.reconciled, isTrue);
    expect(result.message, contains('already started'));
    expect(result.message, isNot(contains('raw backend')));
  });

  test(
      'reports uncertainty and preserves local state when read-back also fails',
      () async {
    when(() => rideService.cancelRide('ride-1', reason: 'rider_cancelled'))
        .thenThrow(const NetworkException(message: 'timeout'));
    when(() => rideService.getRide('ride-1'))
        .thenThrow(const NetworkException(message: 'still offline'));

    final result = await cancelRideWithAuthority(
      rideService: rideService,
      rideId: 'ride-1',
      reason: 'rider_cancelled',
    );

    expect(result.confirmedCancelled, isFalse);
    expect(result.reconciled, isFalse);
    expect(result.message, contains("couldn't confirm"));
  });
}
