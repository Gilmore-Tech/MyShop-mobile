import 'dart:io';

import 'package:dio/dio.dart';

import '../models/api_exception.dart';
import '../models/verification_dtos.dart';

/// Service for document verification and upload endpoints.
class VerificationService {
  VerificationService(this._dio);

  final Dio _dio;

  /// Request a presigned S3 upload URL for a document.
  /// POST /verification/documents
  Future<PresignedUrlResponse> getPresignedUrl(
    PresignedUrlRequest request,
  ) async {
    try {
      final response = await _dio.post(
        '/verification/documents',
        data: request.toJson(),
      );
      final body = response.data as Map<String, dynamic>;
      final data = body['data'] as Map<String, dynamic>? ?? body;
      return PresignedUrlResponse.fromJson(data);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// Upload raw file bytes to an S3 presigned URL.
  /// Uses a plain Dio instance (no auth interceptor, no JSON content-type).
  Future<void> uploadToS3({
    required String uploadUrl,
    required File file,
    required String mimeType,
  }) async {
    final plainDio = Dio();
    try {
      final bytes = await file.readAsBytes();
      await plainDio.put<void>(
        uploadUrl,
        data: bytes,
        options: Options(
          headers: {
            'Content-Type': mimeType,
            'Content-Length': bytes.length,
          },
        ),
      );
    } on DioException catch (e) {
      throw ApiException(
        statusCode: e.response?.statusCode ?? 0,
        errorCode: 'S3_UPLOAD_FAILED',
        message: 'Failed to upload file. Please try again.',
      );
    } finally {
      plainDio.close();
    }
  }

  /// Get the current verification status and all uploaded documents.
  /// GET /verification/status
  Future<VerificationStatusResponse> getVerificationStatus() async {
    try {
      final response = await _dio.get('/verification/status');
      final body = response.data as Map<String, dynamic>;
      final data = body['data'] as Map<String, dynamic>? ?? body;
      return VerificationStatusResponse.fromJson(data);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// Convenience: get presigned URL, then upload the file to S3.
  /// Returns the documentId on success.
  Future<String> uploadDocument({
    required String providerType,
    required DocumentType documentType,
    required File file,
  }) async {
    final fileName = file.path.split('/').last;
    final mimeType = _mimeFromExtension(fileName);
    final fileSize = await file.length();

    final presigned = await getPresignedUrl(PresignedUrlRequest(
      providerType: providerType,
      documentType: documentType.value,
      fileName: fileName,
      mimeType: mimeType,
      fileSize: fileSize,
    ));

    await uploadToS3(
      uploadUrl: presigned.uploadUrl,
      file: file,
      mimeType: mimeType,
    );

    return presigned.documentId;
  }
}

/// Infer MIME type from file extension.
String _mimeFromExtension(String fileName) {
  final ext = fileName.split('.').last.toLowerCase();
  return switch (ext) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'pdf' => 'application/pdf',
    _ => 'application/octet-stream',
  };
}
