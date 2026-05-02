import 'package:dio/dio.dart';

import '../models/api_exception.dart';

/// Service for `/v1/loyalty/*` endpoints.
///
/// The current points balance lives on the user profile (read via
/// `UserService.getMe()` → `client.loyaltyPointsBalance`); this service is
/// only for the transaction history and the in-booking redemption call.
class LoyaltyService {
  LoyaltyService(this._dio);
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

  /// GET /v1/loyalty/transactions — Paginated history, newest first.
  ///
  /// Returns the raw envelope `{ items: [...], meta: {...} }`. Item shape:
  ///   {
  ///     id, clientId, transactionType, points, balanceAfter,
  ///     bookingType?, bookingId?, description?, createdAt
  ///   }
  ///
  /// `transactionType` is one of:
  ///   'earned_ride' | 'earned_job' | 'earned_referral' |
  ///   'redeemed' | 'expired' | 'adjusted'
  ///
  /// `points` is signed: positive for earn, negative for redeem/expire.
  Future<Map<String, dynamic>> getTransactions({
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final response = await _dio.get(
        '/loyalty/transactions',
        queryParameters: {'page': page, 'limit': limit},
      );
      return _unwrap(response) as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// POST /v1/loyalty/redeem — Redeem points against an active booking.
  ///
  /// Returns `{ discountPesewas, newBalance }`. Caller is the payment screen
  /// during checkout, NOT the loyalty screen. Backend validates that the
  /// booking belongs to the caller and is in a redeemable status.
  Future<Map<String, dynamic>> redeemPoints({
    required int points,
    required String bookingType, // 'ride' | 'job'
    required String bookingId,
  }) async {
    try {
      final response = await _dio.post(
        '/loyalty/redeem',
        data: {
          'points': points,
          'bookingType': bookingType,
          'bookingId': bookingId,
        },
      );
      return _unwrap(response) as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
