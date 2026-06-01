import 'package:dio/dio.dart';

import '../models/api_exception.dart';
import '../models/user_dtos.dart';

/// Fetches service categories from GET /v1/categories.
class CategoryService {
  CategoryService(this._dio);

  final Dio _dio;

  /// Returns the full category tree (top-level + children).
  Future<List<ServiceCategory>> getCategories() async {
    try {
      final response = await _dio.get('/categories');
      final body = response.data as Map<String, dynamic>;
      final data = body['data'] as List<dynamic>;
      return data
          .map((e) => ServiceCategory.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
