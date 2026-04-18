import 'package:dio/dio.dart';

import '../models/api_exception.dart';

/// Service for payment API endpoints.
/// EDD § 5.2 — Payments (6 endpoints)
class PaymentService {
  PaymentService(this._dio);
  final Dio _dio;

  dynamic _unwrap(Response response) {
    final body = response.data as Map<String, dynamic>;
    if (body['success'] == true) return body['data'];
    throw ApiException.fromDioException(
      DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
      ),
    );
  }

  /// POST /payments/initiate — Initiate MoMo/card payment via Flutterwave.
  Future<Map<String, dynamic>> initiatePayment({
    required String bookingType,
    required String bookingId,
    required String paymentMethod,
    String? promoCode,
  }) async {
    try {
      final response = await _dio.post('/payments/initiate', data: {
        'bookingType': bookingType,
        'bookingId': bookingId,
        'paymentMethod': paymentMethod,
        if (promoCode != null) 'promoCode': promoCode,
      });
      return _unwrap(response) as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// GET /payments/:id/status — Payment status check.
  Future<Map<String, dynamic>> getPaymentStatus(String paymentId) async {
    try {
      final response = await _dio.get('/payments/$paymentId/status');
      return _unwrap(response) as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// POST /payments/:id/tip — Add tip post-completion (zero commission).
  Future<Map<String, dynamic>> addTip(
    String paymentId, {
    required int amountPesewas,
  }) async {
    try {
      final response = await _dio.post('/payments/$paymentId/tip', data: {
        'amountPesewas': amountPesewas,
      });
      return _unwrap(response) as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
