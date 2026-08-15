import 'package:api_client/api_client.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

void main() {
  late Dio dio;
  late RequestOptions capturedRequest;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/v1'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          capturedRequest = options;
          handler.resolve(
            Response<Map<String, dynamic>>(
              requestOptions: options,
              statusCode: 200,
              data: {
                'success': true,
                'data': {
                  'disputeId': 'dispute_123',
                  'verified': options.path.contains('verify-otp'),
                  'accountLast4': '4567',
                  'retryAfterSeconds': 60,
                },
              },
            ),
          );
        },
      ),
    );
  });

  test('requests cash-refund OTP for the exact entered destination', () async {
    await PaymentService(dio).requestCashRefundDestinationOtp(
      disputeId: 'dispute_123',
      method: 'momo_mtn',
      accountNumber: '0241234567',
      channel: 'whatsapp',
    );

    expect(capturedRequest.method, 'POST');
    expect(capturedRequest.path, '/payments/refund-destination/request-otp');
    expect(capturedRequest.data, {
      'disputeId': 'dispute_123',
      'method': 'momo_mtn',
      'accountNumber': '0241234567',
      'channel': 'whatsapp',
    });
  });

  test(
    'verifies cash-refund OTP without resending destination authority',
    () async {
      await PaymentService(dio).verifyCashRefundDestinationOtp(
        disputeId: 'dispute_123',
        code: '123456',
      );

      expect(capturedRequest.method, 'POST');
      expect(capturedRequest.path, '/payments/refund-destination/verify-otp');
      expect(capturedRequest.data, {
        'disputeId': 'dispute_123',
        'code': '123456',
      });
    },
  );

  test('reads only the masked verified destination status', () async {
    final result = await PaymentService(
      dio,
    ).getCashRefundDestinationStatus('dispute_123');

    expect(capturedRequest.method, 'GET');
    expect(capturedRequest.path, '/payments/refund-destination/dispute_123');
    expect(result['accountLast4'], '4567');
  });

  test('starts commission remittance with a mandatory idempotency key',
      () async {
    dio.interceptors.clear();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          capturedRequest = options;
          handler.resolve(
            Response<Map<String, dynamic>>(
              requestOptions: options,
              statusCode: 201,
              data: {
                'success': true,
                'data': {
                  'remitId': 'remit-001',
                  'chargeStatus': 'pay_offline',
                },
              },
            ),
          );
        },
      ),
    );

    await PaymentService(dio).remitCashCommission(
      amountPesewas: 1250,
      paymentMethod: 'momo_mtn',
      momoPhone: '0241234567',
      idempotencyKey: '  remit-intent-1  ',
    );

    expect(capturedRequest.method, 'POST');
    expect(capturedRequest.path, '/payments/cash-commission/remit');
    expect(capturedRequest.data, {
      'amountPesewas': 1250,
      'paymentMethod': 'momo_mtn',
      'momoPhone': '0241234567',
    });
    expect(capturedRequest.headers['Idempotency-Key'], 'remit-intent-1');
  });

  test('rejects an invalid commission remittance intent before transport',
      () async {
    final service = PaymentService(dio);

    expect(
      () => service.remitCashCommission(
        amountPesewas: 100,
        paymentMethod: 'momo_mtn',
        momoPhone: '0241234567',
        idempotencyKey: ' ',
      ),
      throwsArgumentError,
    );
    expect(
      () => service.remitCashCommission(
        amountPesewas: 0,
        paymentMethod: 'momo_mtn',
        momoPhone: '0241234567',
        idempotencyKey: 'remit-intent-2',
      ),
      throwsArgumentError,
    );
  });

  test(
    'forwards the commission-remittance OTP to the remit-scoped endpoint',
    () async {
      dio.interceptors.clear();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            capturedRequest = options;
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'success': true,
                  'data': {
                    'remitId': 'remit-001',
                    'status': 'processing',
                    'chargeStatus': 'pay_offline',
                    'displayText': 'Approve the payment on your phone.',
                  },
                },
              ),
            );
          },
        ),
      );

      final result = await PaymentService(dio).submitCashCommissionRemitOtp(
        remittanceId: 'remit-001',
        otp: '123456',
      );

      expect(capturedRequest.method, 'POST');
      expect(
        capturedRequest.path,
        '/payments/cash-commission/remittances/remit-001/submit-otp',
      );
      expect(capturedRequest.data, {'otp': '123456'});
      expect(result['chargeStatus'], 'pay_offline');
      expect(result['displayText'], 'Approve the payment on your phone.');
    },
  );

  test(
    'reads the authoritative provider commission-remittance status',
    () async {
      dio.interceptors.clear();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            capturedRequest = options;
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'success': true,
                  'data': {
                    'remitId': 'remit/with space',
                    'status': 'completed',
                    'gatewayStatus': 'success',
                    'amountPesewas': 500,
                    'owedPesewas': 750,
                    'completedAt': '2026-07-23T10:00:00.000Z',
                  },
                },
              ),
            );
          },
        ),
      );

      final result = await PaymentService(
        dio,
      ).getCashCommissionRemittanceStatus('remit/with space');

      expect(capturedRequest.method, 'GET');
      expect(
        capturedRequest.path,
        '/payments/cash-commission/remittances/remit%2Fwith%20space',
      );
      expect(result.isCompleted, isTrue);
      expect(result.amountPesewas, 500);
      expect(result.owedPesewas, 750);
      expect(result.completedAt?.toUtc(), DateTime.utc(2026, 7, 23, 10));
    },
  );

  test(
    'withdraws only the expected server-authored balance with idempotency',
    () async {
      dio.interceptors.clear();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            capturedRequest = options;
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: options,
                statusCode: 202,
                data: {'success': true, 'data': _withdrawalJson()},
              ),
            );
          },
        ),
      );

      final result = await PaymentService(dio).withdrawProviderEarnings(
        expectedWithdrawablePesewas: 5000,
        idempotencyKey: 'withdraw-attempt-1',
      );

      expect(capturedRequest.method, 'POST');
      expect(capturedRequest.path, '/payments/payouts/withdraw');
      expect(capturedRequest.data, {'expectedWithdrawablePesewas': 5000});
      expect(capturedRequest.headers['Idempotency-Key'], 'withdraw-attempt-1');
      expect(result.withdrawalId, 'withdrawal/123');
      expect(result.status, ProviderWithdrawalGroupStatus.queued);
      expect(result.transferQueuedPesewas, 4000);
      expect(result.deductionsAppliedPesewas, 1000);
      expect(result.isTerminal, isFalse);
    },
  );

  test('reads an encoded exact-withdrawal group status', () async {
    dio.interceptors.clear();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          capturedRequest = options;
          handler.resolve(
            Response<Map<String, dynamic>>(
              requestOptions: options,
              statusCode: 200,
              data: {
                'success': true,
                'data': {..._withdrawalJson(), 'status': 'completed'},
              },
            ),
          );
        },
      ),
    );

    final result = await PaymentService(
      dio,
    ).getProviderWithdrawalStatus('withdrawal/123');

    expect(capturedRequest.method, 'GET');
    expect(
      capturedRequest.path,
      '/payments/payouts/withdrawals/withdrawal%2F123',
    );
    expect(result.status, ProviderWithdrawalGroupStatus.completed);
    expect(result.isTerminal, isTrue);
  });

  test('withdrawal response parsing rejects unsafe money shapes', () {
    expect(
      () => ProviderWithdrawalStatus.fromJson({
        ..._withdrawalJson(),
        'transferQueuedPesewas': -1,
      }),
      throwsFormatException,
    );
    expect(
      () => ProviderWithdrawalStatus.fromJson({
        ..._withdrawalJson(),
        'currency': 'USD',
      }),
      throwsFormatException,
    );
    expect(
      () => ProviderWithdrawalStatus.fromJson({
        ..._withdrawalJson(),
        'selectedEarningsPesewas': 5001,
      }),
      throwsFormatException,
      reason: 'selected earnings must equal deductions plus transfer',
    );
    expect(
      () => ProviderWithdrawalStatus.fromJson({
        ..._withdrawalJson(),
        'paymentCount': 0,
        'payoutIds': <String>[],
      }),
      throwsFormatException,
    );
    expect(
      () => ProviderWithdrawalStatus.fromJson({
        ..._withdrawalJson(),
        'paymentCount': 30,
        'payoutIds': List.generate(26, (index) => 'payout-$index'),
      }),
      throwsFormatException,
      reason: 'the response list is capped at 25 ids',
    );
    expect(
      () => ProviderWithdrawalStatus.fromJson({
        ..._withdrawalJson(),
        'status': 'future_status',
      }),
      throwsFormatException,
      reason: 'POST parsing must reject an unknown group status',
    );
    expect(
      () => ProviderWithdrawalStatus.fromJson({
        ..._withdrawalJson(),
        'selectedEarningsPesewas': 9007199254740992,
        'transferQueuedPesewas': 9007199254740992,
        'deductionsAppliedPesewas': 0,
      }),
      throwsFormatException,
      reason: 'money must be exactly representable by JSON/Dart web',
    );
    expect(
      () => ProviderWithdrawalStatus.fromJson({
        ..._withdrawalJson(),
        'selectedEarningsPesewas': 1000,
        'deductionsAppliedPesewas': 1000,
        'transferQueuedPesewas': 0,
      }),
      throwsFormatException,
      reason: 'an accepted aggregate withdrawal must queue a transfer',
    );
    expect(
      () => ProviderWithdrawalStatus.fromJson({
        ..._withdrawalJson(),
        'remainingDebtPesewas': 1,
      }),
      throwsFormatException,
      reason: 'a transfer-bearing response cannot retain debt',
    );
    expect(
      () => ProviderWithdrawalStatus.fromJson({
        ..._withdrawalJson(),
        'payoutIds': ['aggregate-1', 'aggregate-2'],
      }),
      throwsFormatException,
      reason: 'new aggregate groups expose exactly one payout rail id',
    );
    expect(
      () => ProviderWithdrawalStatus.fromJson({
        ..._withdrawalJson(),
        'payoutIds': <String>[],
      }),
      throwsFormatException,
      reason: 'an aggregate group must identify its payout rail',
    );
  });

  test('aggregate response keeps one rail id for many earning payments', () {
    final result = ProviderWithdrawalStatus.fromJson({
      ..._withdrawalJson(),
      'paymentCount': 30,
      'payoutIds': ['aggregate-payout-1'],
    });

    expect(result.paymentCount, 30);
    expect(result.payoutIds, ['aggregate-payout-1']);
  });

  test('needs-review response exposes only a known provider-safe reason', () {
    final result = ProviderWithdrawalStatus.fromJson({
      ..._withdrawalJson(),
      'status': 'needs_review',
      'reasonCode': 'TRANSFER_REVERSED',
    });

    expect(result.status, ProviderWithdrawalGroupStatus.needsReview);
    expect(
      result.reviewReason,
      ProviderWithdrawalReviewReason.transferReversed,
    );
    expect(
      () => ProviderWithdrawalStatus.fromJson({
        ..._withdrawalJson(),
        'reasonCode': 'TRANSFER_REVERSED',
      }),
      throwsFormatException,
      reason: 'non-review states cannot carry a review reason',
    );
  });

  test('legacy partial-success group retains capped multi-id compatibility',
      () {
    final result = ProviderWithdrawalStatus.fromJson({
      ..._withdrawalJson(),
      'status': 'partial_success',
      'paymentCount': 30,
      'payoutIds': List.generate(25, (index) => 'payout-$index'),
    });

    expect(result.status, ProviderWithdrawalGroupStatus.partialSuccess);
    expect(result.payoutIds, hasLength(25));
  });

  test('GET parsing retains an unknown status without treating it as terminal',
      () async {
    dio.interceptors.clear();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.resolve(
            Response<Map<String, dynamic>>(
              requestOptions: options,
              statusCode: 200,
              data: {
                'success': true,
                'data': {
                  ..._withdrawalJson(),
                  'status': 'future_status',
                },
              },
            ),
          );
        },
      ),
    );

    final result =
        await PaymentService(dio).getProviderWithdrawalStatus('withdrawal-1');
    expect(result.status, ProviderWithdrawalGroupStatus.unknown);
    expect(result.isTerminal, isFalse);
  });
}

Map<String, dynamic> _withdrawalJson() => {
      'withdrawalId': 'withdrawal/123',
      'status': 'queued',
      'currency': 'GHS',
      'selectedEarningsPesewas': 5000,
      'deductionsAppliedPesewas': 1000,
      'transferQueuedPesewas': 4000,
      'remainingDebtPesewas': 0,
      'paymentCount': 2,
      'payoutIds': ['aggregate-payout-1'],
    };
