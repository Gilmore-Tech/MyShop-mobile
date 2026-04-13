import 'package:dio/dio.dart';
import 'package:shared_models/shared_models.dart';

/// Service for fetching provider earnings from the backend.
class EarningsService {
  EarningsService(this._dio);

  final Dio _dio;

  /// Fetch earnings summary for the given [period] (today, week, month).
  Future<DriverEarnings> getEarnings({String period = 'today'}) async {
    final response = await _dio.get(
      '/payments/earnings',
      queryParameters: {'period': period},
    );
    final body = response.data as Map<String, dynamic>;
    if (body['success'] == true && body['data'] != null) {
      return DriverEarnings.fromJson(body['data'] as Map<String, dynamic>);
    }
    throw Exception('Failed to load earnings');
  }
}
