/// Standard response envelope returned by all MyShop API endpoints.
///
/// ```json
/// { "success": true, "data": { ... }, "error": null, "meta": { ... } }
/// ```
class ApiResponse<T> {
  const ApiResponse({
    required this.success,
    this.data,
    this.error,
    this.meta,
  });

  factory ApiResponse.fromJson(
    Map<String, dynamic> json,
    T Function(dynamic json) fromJsonT,
  ) {
    return ApiResponse<T>(
      success: json['success'] as bool,
      data: json['data'] != null ? fromJsonT(json['data']) : null,
      error: json['error'] != null
          ? ApiError.fromJson(json['error'] as Map<String, dynamic>)
          : null,
      meta: json['meta'] != null
          ? PaginationMeta.fromJson(json['meta'] as Map<String, dynamic>)
          : null,
    );
  }

  final bool success;
  final T? data;
  final ApiError? error;
  final PaginationMeta? meta;
}

/// Error object inside the response envelope.
class ApiError {
  const ApiError({
    required this.code,
    required this.message,
    this.details,
  });

  factory ApiError.fromJson(Map<String, dynamic> json) {
    // Capture sibling keys the backend tucks alongside code/message
    // (e.g. 409 PAYMENT_ALREADY_INITIATED carries paymentId, ageSeconds,
    // retryAfterSeconds at the top level of the error envelope rather
    // than nested under `details`). Merge them into a single details
    // bag so call sites have one place to look. Nested details wins
    // on key collisions for backward compat.
    final extras = <String, dynamic>{};
    for (final entry in json.entries) {
      final k = entry.key;
      if (k == 'code' || k == 'message' || k == 'details') continue;
      extras[k] = entry.value;
    }
    final nested = json['details'] as Map<String, dynamic>?;
    Map<String, dynamic>? merged;
    if (extras.isNotEmpty || nested != null) {
      merged = <String, dynamic>{...extras, if (nested != null) ...nested};
    }
    return ApiError(
      code: json['code'] as String,
      message: json['message'] as String,
      details: merged,
    );
  }

  final String code;
  final String message;
  final Map<String, dynamic>? details;
}

/// Pagination metadata for list endpoints.
class PaginationMeta {
  const PaginationMeta({
    required this.page,
    required this.limit,
    required this.total,
    required this.totalPages,
  });

  factory PaginationMeta.fromJson(Map<String, dynamic> json) {
    return PaginationMeta(
      page: json['page'] as int,
      limit: json['limit'] as int,
      total: json['total'] as int,
      totalPages: json['totalPages'] as int,
    );
  }

  final int page;
  final int limit;
  final int total;
  final int totalPages;
}
