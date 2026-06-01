import 'package:dio/dio.dart';

import 'api_response.dart';

/// Base exception for all API errors.
class ApiException implements Exception {
  const ApiException({
    required this.message,
    this.statusCode,
    this.errorCode,
    this.details,
  });

  /// Create an [ApiException] from a Dio error, extracting the response
  /// envelope error if available.
  factory ApiException.fromDioException(DioException error) {
    final response = error.response;

    // Network / timeout errors (no response)
    if (response == null) {
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return const NetworkException(
            message: 'Connection timed out. Please try again.',
          );
        case DioExceptionType.connectionError:
          return const NetworkException(
            message:
                'No internet connection. Check your network and try again.',
          );
        default:
          return NetworkException(
            message: error.message ?? 'A network error occurred.',
          );
      }
    }

    final statusCode = response.statusCode ?? 0;
    final data = response.data;

    // Try to extract the error envelope
    String? errorCode;
    String message = 'Something went wrong. Please try again.';
    Map<String, dynamic>? details;

    if (data is Map<String, dynamic> && data['error'] != null) {
      final apiError = ApiError.fromJson(data['error'] as Map<String, dynamic>);
      errorCode = apiError.code;
      message = apiError.message;
      details = apiError.details;
    }

    if (statusCode == 401) {
      return UnauthorizedException(
        message: message,
        errorCode: errorCode,
        details: details,
      );
    }

    if (statusCode == 409) {
      return ConflictException(
        message: message,
        errorCode: errorCode,
        details: details,
      );
    }

    if (statusCode == 422) {
      return ValidationException(
        message: message,
        errorCode: errorCode,
        details: details,
      );
    }

    if (statusCode >= 500) {
      return ServerException(
        message: message,
        statusCode: statusCode,
        errorCode: errorCode,
      );
    }

    return ApiException(
      message: message,
      statusCode: statusCode,
      errorCode: errorCode,
      details: details,
    );
  }

  final String message;
  final int? statusCode;
  final String? errorCode;

  /// Per-field validation errors or additional context from the backend.
  final Map<String, dynamic>? details;

  /// Whether this is a network/connectivity error.
  bool get isNetworkError => this is NetworkException;

  /// Whether this is a server-side error (5xx).
  bool get isServerError => this is ServerException;

  /// Whether this is a validation error (422) with field-level details.
  bool get isValidationError => this is ValidationException;

  @override
  String toString() => 'ApiException($errorCode): $message';
}

/// Thrown on 401 — invalid or expired token.
class UnauthorizedException extends ApiException {
  const UnauthorizedException({
    required super.message,
    super.errorCode,
    super.details,
  }) : super(statusCode: 401);
}

/// Thrown on 409 — conflict (e.g. account already exists).
class ConflictException extends ApiException {
  const ConflictException({
    required super.message,
    super.errorCode,
    super.details,
  }) : super(statusCode: 409);
}

/// Thrown on 422 — validation error with per-field details.
class ValidationException extends ApiException {
  const ValidationException({
    required super.message,
    super.errorCode,
    super.details,
  }) : super(statusCode: 422);
}

/// Thrown when the device has no network connectivity or the request timed out.
class NetworkException extends ApiException {
  const NetworkException({required super.message}) : super(statusCode: null);
}

/// Thrown on 5xx server errors.
class ServerException extends ApiException {
  const ServerException({
    required super.message,
    super.statusCode,
    super.errorCode,
  });
}
