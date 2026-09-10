import 'package:api_client/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_provider/src/core/services/provider_online_recovery.dart';

void main() {
  test('retries transient transport, rate limits and GPS failures', () {
    for (final error in [
      const NetworkException(message: 'offline'),
      const ServerException(message: 'unavailable', statusCode: 503),
      const ApiException(message: 'timeout', statusCode: 408),
      const ApiException(message: 'limited', statusCode: 429),
      const ApiException(message: 'stale', errorCode: 'GPS_FIX_STALE'),
      const ApiException(
          message: 'capability',
          errorCode: 'PROVIDER_NOT_ELIGIBLE',
          details: {
            'reasonCodes': ['OFFER_RECEIPT_CAPABILITY_REQUIRED']
          }),
    ]) {
      expect(isRetryableProviderRestoreError(error), isTrue);
    }
  });
  test('restrictions and mixed or unknown eligibility failures remain terminal',
      () {
    for (final error in [
      const ApiException(
          message: 'blocked',
          statusCode: 429,
          errorCode: 'PROVIDER_REQUEST_BLOCK'),
      const ApiException(message: 'suspended', errorCode: 'ACCOUNT_SUSPENDED'),
      const ApiException(
          message: 'mixed',
          errorCode: 'PROVIDER_NOT_ELIGIBLE',
          details: {
            'reasonCodes': ['GPS_REQUIRED', 'RM_FINAL_APPROVAL_REQUIRED']
          }),
      const ApiException(
          message: 'unknown',
          errorCode: 'PROVIDER_NOT_ELIGIBLE',
          details: {
            'reasonCodes': ['UNKNOWN_REQUIREMENT']
          }),
    ]) {
      expect(isRetryableProviderRestoreError(error), isFalse);
    }
  });
}
