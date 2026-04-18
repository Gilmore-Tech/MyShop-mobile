import 'package:dio/dio.dart';

import '../models/api_exception.dart';

/// Service for artisan marketplace API endpoints.
/// EDD § 5.2 — Marketplace (12 endpoints)
class JobService {
  JobService(this._dio);
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

  /// GET /jobs — List client's jobs with optional filters.
  /// Returns empty list if the endpoint is not yet available (404).
  Future<List<dynamic>> listJobs({
    int page = 1,
    int limit = 50,
    String? status,
    String? search,
  }) async {
    try {
      final response = await _dio.get('/jobs', queryParameters: {
        'page': page,
        'limit': limit,
        if (status != null) 'status': status,
        if (search != null && search.isNotEmpty) 'q': search,
      });
      // ignore: avoid_print
      print('[JobService] raw response.data: ${response.data}');
      final body = response.data;
      // Handle various response shapes from the backend.
      if (body is Map<String, dynamic>) {
        final data = body['data'];
        // { success: true, data: [...] }
        if (data is List) return data;
        // { success: true, data: { items: [...] } }
        if (data is Map<String, dynamic>) {
          if (data['items'] is List) return data['items'] as List<dynamic>;
          if (data['jobs'] is List) return data['jobs'] as List<dynamic>;
        }
        // { success: true, data: { data: [...] } } (nested pagination)
        if (data is Map<String, dynamic> && data['data'] is List) {
          return data['data'] as List<dynamic>;
        }
      }
      return [];
    } on DioException catch (e) {
      // Return empty list if endpoint not implemented yet.
      if (e.response?.statusCode == 404) return [];
      throw ApiException.fromDioException(e);
    }
  }

  /// POST /jobs — Create artisan job request.
  Future<Map<String, dynamic>> createJob({
    required String categoryId,
    required String description,
    required double latitude,
    required double longitude,
    String? addressText,
    String? scheduledFor,
    List<String>? photoUrls,
  }) async {
    try {
      final response = await _dio.post('/jobs', data: {
        'categoryId': categoryId,
        'description': description,
        'latitude': latitude,
        'longitude': longitude,
        if (addressText != null) 'addressText': addressText,
        if (scheduledFor != null) 'scheduledFor': scheduledFor,
        if (photoUrls != null) 'photos': photoUrls,
      });
      return _unwrap(response) as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// GET /jobs/:id — Get job details.
  Future<Map<String, dynamic>> getJob(String jobId) async {
    try {
      final response = await _dio.get('/jobs/$jobId');
      return _unwrap(response) as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// GET /jobs/:id/bids — Get bids for a job.
  Future<List<dynamic>> getBids(String jobId) async {
    try {
      final response = await _dio.get('/jobs/$jobId/bids');
      return _unwrap(response) as List<dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// PATCH /jobs/:id/select-bid — Client: accept a bid.
  Future<Map<String, dynamic>> selectBid(
    String jobId, {
    required String bidId,
  }) async {
    try {
      final response = await _dio.patch('/jobs/$jobId/select-bid', data: {
        'bidId': bidId,
      });
      return _unwrap(response) as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// PATCH /jobs/:id/supplement/respond — Client: approve or reject supplement.
  Future<Map<String, dynamic>> respondToSupplement(
    String jobId, {
    required bool approved,
  }) async {
    try {
      final response =
          await _dio.patch('/jobs/$jobId/supplement/respond', data: {
        'approved': approved,
      });
      return _unwrap(response) as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// PATCH /jobs/:id/confirm — Client: confirm job completion (dual confirmation).
  Future<Map<String, dynamic>> confirmJobCompletion(String jobId) async {
    try {
      final response = await _dio.patch('/jobs/$jobId/confirm');
      return _unwrap(response) as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// POST /jobs/:id/dispute — Dispute job (2-hour window).
  Future<Map<String, dynamic>> disputeJob(
    String jobId, {
    required String reason,
    String? description,
  }) async {
    try {
      final response = await _dio.post('/jobs/$jobId/dispute', data: {
        'reason': reason,
        if (description != null) 'description': description,
      });
      return _unwrap(response) as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// PATCH /jobs/:id/cancel — Cancel job (30-min free, 20% fee after).
  Future<Map<String, dynamic>> cancelJob(String jobId,
      {String? reason}) async {
    try {
      final response = await _dio.patch('/jobs/$jobId/cancel', data: {
        if (reason != null) 'reason': reason,
      });
      return _unwrap(response) as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
