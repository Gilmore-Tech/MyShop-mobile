import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_models/shared_models.dart';
import 'package:myshop_client/src/features/auth/data/auth_repository.dart';
import 'package:myshop_client/src/features/auth/providers/auth_controller.dart';
import 'package:myshop_client/src/features/auth/screens/otp_verification_screen.dart';

class _MockClientAuthRepository extends Mock implements ClientAuthRepository {}

const _phone = '+233241234567';
const _legalAcceptances = <LegalAcceptanceSelection>[
  LegalAcceptanceSelection(
    slug: 'terms',
    documentId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    version: '1.4.1',
  ),
  LegalAcceptanceSelection(
    slug: 'privacy',
    documentId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    version: '1.4.1',
  ),
];
const _activeDeliveryFailure = ServerException(
  message: 'provider detail',
  statusCode: 503,
  errorCode: 'OTP_DELIVERY_FAILED',
  details: {'channel': 'sms', 'otpActive': true},
);

void main() {
  late _MockClientAuthRepository repository;
  late ClientAuthController controller;

  setUp(() {
    repository = _MockClientAuthRepository();
    controller = ClientAuthController(repository);
  });

  test('login enters OTP screen state when delivery failed but code is active',
      () async {
    when(() => repository.loginClient(_phone))
        .thenThrow(_activeDeliveryFailure);

    await controller.submitPhone(phone: _phone);

    final state = controller.state;
    expect(state, isA<AuthOtpSent>());
    expect((state as AuthOtpSent).phone, _phone);
    expect(state.isNewUser, isFalse);
    expect(state.error, contains('code is still active'));
  });

  test(
      'registration enters OTP screen state when delivery failed but code is active',
      () async {
    when(
      () => repository.register(
        phone: _phone,
        fullName: 'Ama Mensah',
        legalAcceptances: _legalAcceptances,
      ),
    ).thenThrow(_activeDeliveryFailure);

    await controller.register(
      phone: _phone,
      fullName: 'Ama Mensah',
      legalAcceptances: _legalAcceptances,
    );

    final state = controller.state;
    expect(state, isA<AuthOtpSent>());
    expect((state as AuthOtpSent).isNewUser, isTrue);
    expect(state.error, contains('code is still active'));
  });

  test('daily issuance quota does not pretend an OTP is active', () async {
    when(() => repository.loginClient(_phone)).thenThrow(
      const ApiException(
        message: 'raw quota response',
        statusCode: 429,
        errorCode: 'OTP_DAILY_LIMIT',
        details: {'retryAfterSecs': 3600},
      ),
    );

    await controller.submitPhone(phone: _phone);

    final state = controller.state;
    expect(state, isA<AuthUnauthenticated>());
    expect(
      (state as AuthUnauthenticated).error,
      'You\'ve requested too many new codes today. Please try again later '
      'or contact support.',
    );
  });

  test('resend preserves OTP state and surfaces cooldown safely', () async {
    when(() => repository.loginClient(_phone)).thenAnswer((_) async {});
    await controller.submitPhone(phone: _phone);
    when(() => repository.resendOtp(phone: _phone, channel: 'sms')).thenThrow(
      const ApiException(
        message: 'raw cooldown response',
        statusCode: 400,
        errorCode: 'OTP_RESEND_COOLDOWN',
        details: {'retryAfterSecs': 14},
      ),
    );

    await controller.resendOtp();

    final state = controller.state;
    expect(state, isA<AuthOtpSent>());
    expect((state as AuthOtpSent).phone, _phone);
    expect(state.error, 'Please wait before resending this code.');
  });

  test('concurrent resend taps issue only one repository request', () async {
    when(() => repository.loginClient(_phone)).thenAnswer((_) async {});
    await controller.submitPhone(phone: _phone);
    final pending = Completer<void>();
    when(() => repository.resendOtp(phone: _phone, channel: 'sms'))
        .thenAnswer((_) => pending.future);

    final first = controller.resendOtp();
    final second = controller.resendOtp();
    verify(() => repository.resendOtp(phone: _phone, channel: 'sms')).called(1);

    pending.complete();
    await Future.wait([first, second]);
    expect(controller.state, isA<AuthOtpSent>());
  });

  test('concurrent verify triggers issue only one repository request',
      () async {
    when(() => repository.loginClient(_phone)).thenAnswer((_) async {});
    await controller.submitPhone(phone: _phone);
    final pending = Completer<TokenResponse>();
    when(() => repository.verifyOtp(phone: _phone, code: '123456'))
        .thenAnswer((_) => pending.future);

    final first = controller.verifyOtp('123456');
    final second = controller.verifyOtp('123456');
    verify(() => repository.verifyOtp(phone: _phone, code: '123456')).called(1);

    pending.completeError(
      const ApiException(
        message: 'Incorrect code',
        statusCode: 401,
        errorCode: 'INVALID_OTP',
      ),
    );
    await Future.wait([first, second]);
    expect(controller.state, isA<AuthOtpSent>());
    expect((controller.state as AuthOtpSent).isVerifying, isFalse);
  });

  testWidgets('OTP back action returns client to phone-entry state',
      (tester) async {
    when(() => repository.loginClient(_phone)).thenAnswer((_) async {});
    when(() => repository.getOtpChannels())
        .thenAnswer((_) async => const ['sms']);
    await controller.submitPhone(phone: _phone);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          clientAuthControllerProvider.overrideWith((_) => controller),
          clientOtpChannelsProvider.overrideWith(
            (_) async => const ['sms'],
          ),
        ],
        child: const MaterialApp(home: OtpVerificationScreen()),
      ),
    );
    await tester.pump();

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pump();

    expect(controller.state, isA<AuthUnauthenticated>());
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
