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
}
