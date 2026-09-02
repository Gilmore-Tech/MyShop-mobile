import 'package:api_client/api_client.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:myshop_provider/src/core/providers/provider_location_sync_recovery.dart';

ApiException _eligibility(List<Object?>? reasonCodes) => ApiException(
      message: 'Provider is not eligible',
      statusCode: 403,
      errorCode: 'PROVIDER_NOT_ELIGIBLE',
      details: reasonCodes == null
          ? null
          : <String, dynamic>{'reasonCodes': reasonCodes},
    );

void main() {
  group('classifyProviderLocationRejection', () {
    test('reads a nested Online-session reason', () {
      final rejection = classifyProviderLocationRejection(
        _eligibility(<Object?>['DRIVER_ONLINE_SESSION_REQUIRED']),
      );

      expect(rejection?.kind, ProviderLocationRejectionKind.locationSession);
      expect(rejection?.reasonCodes, <String>[
        'DRIVER_ONLINE_SESSION_REQUIRED',
      ]);
    });

    test('unknown and malformed reason sets fail closed', () {
      final unknown = classifyProviderLocationRejection(
        _eligibility(<Object?>['FUTURE_SERVER_REQUIREMENT']),
      );
      final malformed = classifyProviderLocationRejection(
        _eligibility(<Object?>[42, 'not a machine code']),
      );

      expect(unknown?.kind, ProviderLocationRejectionKind.eligibility);
      expect(unknown?.hasUnrecognizedReason, isTrue);
      expect(malformed?.kind, ProviderLocationRejectionKind.eligibility);
      expect(malformed?.hasUnrecognizedReason, isTrue);
    });

    test('missing reasons and direct terminal codes fail closed', () {
      final missing = classifyProviderLocationRejection(
        _eligibility(null),
      );
      const suspended = ApiException(
        message: 'Provider is suspended',
        statusCode: 403,
        errorCode: 'ACCOUNT_SUSPENDED',
      );

      expect(missing?.kind, ProviderLocationRejectionKind.eligibility);
      expect(missing?.hasUnrecognizedReason, isTrue);
      expect(
        classifyProviderLocationRejection(suspended)?.kind,
        ProviderLocationRejectionKind.eligibility,
      );
    });

    test('request enforcement is terminal and retains exact safe copy', () {
      const error = ApiException(
        message: 'raw backend message',
        statusCode: 429,
        errorCode: 'PROVIDER_CANCELLATION_BLOCK',
        details: <String, dynamic>{
          'policyKind': 'accepted_cancellation',
          'blockedUntil': '2026-09-02T22:15:00.000Z',
          'retryAfterSeconds': 900,
        },
      );

      final rejection = classifyProviderLocationRejection(error);

      expect(rejection?.kind, ProviderLocationRejectionKind.eligibility);
      expect(
        rejection?.reasonCodes,
        const <String>['PROVIDER_CANCELLATION_BLOCK'],
      );
      expect(
        rejection?.requestBlockMessage,
        contains('repeated accepted-work cancellations'),
      );
      expect(rejection?.requestBlockMessage, isNot(contains('raw backend')));
    });

    test('a mixed session and persistent reason uses the stricter fence', () {
      final rejection = classifyProviderLocationRejection(
        _eligibility(<Object?>[
          'DRIVER_ONLINE_SESSION_REQUIRED',
          'RM_FINAL_APPROVAL_REQUIRED',
        ]),
      );

      expect(rejection?.kind, ProviderLocationRejectionKind.eligibility);
      expect(rejection?.reasonCodes, <String>[
        'DRIVER_ONLINE_SESSION_REQUIRED',
        'RM_FINAL_APPROVAL_REQUIRED',
      ]);
    });

    test('capability-only startup race remains bounded and retryable', () {
      final error = _eligibility(
        <Object?>['OFFER_RECEIPT_CAPABILITY_REQUIRED'],
      );
      expect(classifyProviderLocationRejection(error), isNull);
      expect(isProviderCapabilityRegistrationRace(error), isTrue);
      expect(
        isProviderCapabilityRegistrationRace(
          _eligibility(<Object?>[
            'OFFER_RECEIPT_CAPABILITY_REQUIRED',
            'RM_FINAL_APPROVAL_REQUIRED',
          ]),
        ),
        isFalse,
      );
    });
  });

  test('retry gate grows to its cap and resets after recovery', () {
    final gate = ProviderLocationRetryGate(const ProviderLocationRetryPolicy());
    final now = DateTime.utc(2026, 8, 12, 23);

    gate.recordFailure(now);
    expect(gate.retryAt, now.add(const Duration(seconds: 5)));
    gate.recordFailure(now);
    expect(gate.retryAt, now.add(const Duration(seconds: 10)));
    gate.recordFailure(now);
    gate.recordFailure(now);
    gate.recordFailure(now);
    expect(gate.retryAt, now.add(const Duration(minutes: 1)));
    expect(gate.canAttempt(now.add(const Duration(seconds: 59))), isFalse);

    gate.reset();
    expect(gate.consecutiveFailures, 0);
    expect(gate.canAttempt(now), isTrue);
  });
}
