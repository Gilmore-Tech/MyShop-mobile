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

  /// POST /payments/initiate — Initiate a Paystack charge.
  ///
  /// Matches apps/api/src/modules/payment/dto/initiate-payment.dto.ts on
  /// the backend. Accepted [paymentMethod] values:
  ///   momo_mtn | momo_telecel | momo_airteltigo | visa | mastercard
  ///
  /// [momoPhone] is required for MoMo methods (accepts `+233XXXXXXXXX` or
  /// `0XXXXXXXXX`). [cardToken] is required for card charges on saved
  /// cards; omit it on first-time card payments and Paystack returns a
  /// hosted checkout URL in the response.
  Future<Map<String, dynamic>> initiatePayment({
    required String bookingType,
    required String bookingId,
    required String paymentMethod,
    String? momoPhone,
    String? cardToken,
    String? promoCode,
  }) async {
    try {
      final response = await _dio.post(
        '/payments/initiate',
        data: {
          'bookingType': bookingType,
          'bookingId': bookingId,
          'paymentMethod': paymentMethod,
          if (momoPhone != null) 'momoPhone': momoPhone,
          if (cardToken != null) 'cardToken': cardToken,
          if (promoCode != null) 'promoCode': promoCode,
        },
      );
      return _unwrap(response) as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// POST /payments/acknowledge-cash — Tell the backend the client has
  /// arrived at the payment screen and selected Cash. Sets
  /// `job.clientPaymentAcknowledgedAt`/`job.clientPaymentMethod` and emits
  /// `job:client_payment_acknowledged` to the artisan room. Without this
  /// call the artisan's `POST /jobs/:id/artisan-confirm-cash` will 409 with
  /// `CLIENT_PAYMENT_NOT_ACKNOWLEDGED` — the gate that prevents an artisan
  /// from marking a job paid before the client has even opened the payment
  /// screen.
  ///
  /// Idempotent: hitting it twice returns the same timestamp. Errors:
  ///   400 JOB_NOT_AWAITING_PAYMENT — job isn't `artisan_marked_complete`
  Future<Map<String, dynamic>> acknowledgeCash({
    required String bookingType,
    required String bookingId,
  }) async {
    try {
      final response = await _dio.post(
        '/payments/acknowledge-cash',
        data: {
          'bookingType': bookingType,
          'bookingId': bookingId,
        },
      );
      return _unwrap(response) as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// POST /payments/submit-otp — Forward an OTP for a Paystack MoMo charge
  /// that returned `data.status === 'send_otp'` from /payments/initiate.
  ///
  /// The backend should proxy this to Paystack's `/charge/submit_otp`
  /// endpoint with `{ otp, reference }` and surface the resulting
  /// `data.status` (typically `pay_offline` or `success` after the OTP).
  Future<Map<String, dynamic>> submitOtp({
    required String reference,
    required String otp,
  }) async {
    try {
      final response = await _dio.post(
        '/payments/submit-otp',
        data: {
          'reference': reference,
          'otp': otp,
        },
      );
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

  /// POST /payments/:paymentId/abandon — Cancel an in-flight Paystack
  /// charge. Use the local payment UUID (from the /initiate response),
  /// NOT the Paystack reference. Idempotent: a 200 comes back even if
  /// the payment is already failed. Errors:
  ///   400 PAYMENT_NOT_ABANDONABLE — payment is escrowed/completed
  ///   403 NOT_YOUR_PAYMENT
  ///   404 PAYMENT_NOT_FOUND
  /// On success the booking is unlocked and the next /payments/initiate
  /// for the same job goes through immediately.
  Future<Map<String, dynamic>> abandonPayment(String paymentId) async {
    try {
      final response = await _dio.post('/payments/$paymentId/abandon');
      return _unwrap(response) as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  // ── Payment Methods ───────────────────────────────────────────────────────────

  /// GET /payment-methods — List the user's saved payment methods.
  Future<List<dynamic>> getPaymentMethods() async {
    try {
      final response = await _dio.get('/payment-methods');
      final data = _unwrap(response);
      if (data is List) return data;
      if (data is Map<String, dynamic> && data['methods'] is List) {
        return data['methods'] as List<dynamic>;
      }
      return [];
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return [];
      throw ApiException.fromDioException(e);
    }
  }

  /// POST /payment-methods/momo — Save a mobile money account.
  Future<Map<String, dynamic>> addMomoMethod({
    required String provider,
    required String phone,
  }) async {
    try {
      final response = await _dio.post(
        '/payment-methods/momo',
        data: {
          'provider': provider,
          'phone': phone,
        },
      );
      return _unwrap(response) as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// PATCH /payment-methods/:id/default — Set a payment method as default.
  Future<void> setDefaultMethod(String id) async {
    try {
      await _dio.patch('/payment-methods/$id/default');
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// DELETE /payment-methods/:id — Remove a payment method.
  Future<void> deletePaymentMethod(String id) async {
    try {
      await _dio.delete('/payment-methods/$id');
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
      final response = await _dio.post(
        '/payments/$paymentId/tip',
        data: {
          'amountPesewas': amountPesewas,
        },
      );
      return _unwrap(response) as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
