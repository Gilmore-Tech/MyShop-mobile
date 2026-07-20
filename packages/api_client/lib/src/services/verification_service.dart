import 'dart:io';

import 'package:dio/dio.dart';

import '../models/api_exception.dart';
import '../models/verification_dtos.dart';

/// Service for document verification and upload endpoints.
class VerificationService {
  VerificationService(
    this._dio, {
    List<Duration> confirmationRetryDelays = const [
      Duration(milliseconds: 750),
      Duration(seconds: 2),
    ],
  }) : _confirmationRetryDelays = List.unmodifiable(confirmationRetryDelays);

  final Dio _dio;
  final List<Duration> _confirmationRetryDelays;

  /// Request an upload URL for a document.
  /// POST /verification/documents
  Future<DocumentUploadResponse> requestUpload(
    PresignedUrlRequest request,
  ) async {
    try {
      final response = await _dio.post(
        '/verification/documents',
        data: request.toJson(),
      );
      final body = response.data as Map<String, dynamic>;
      final data = body['data'] as Map<String, dynamic>? ?? body;
      return DocumentUploadResponse.fromJson(data);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// Upload a file to the URL provided by [requestUpload].
  ///
  /// Branches on [DocumentUploadResponse.uploadMethod]:
  /// - **POST** → Cloudinary-style multipart form upload
  /// - **PUT**  → S3-style raw bytes upload
  ///
  /// Returns the remote file URL on success (e.g. Cloudinary's `secure_url`),
  /// or `null` if the storage provider doesn't return one (S3 presigned PUT).
  Future<String?> uploadFile({
    required DocumentUploadResponse uploadInfo,
    required File file,
    required String mimeType,
  }) async {
    final plainDio = Dio();
    try {
      if (uploadInfo.isMultipart) {
        // Cloudinary — multipart POST
        final fieldName = uploadInfo.uploadFieldName ?? 'file';
        final formData = FormData.fromMap({
          fieldName: await MultipartFile.fromFile(
            file.path,
            contentType: DioMediaType.parse(mimeType),
          ),
        });
        final response = await plainDio.post<dynamic>(
          uploadInfo.uploadUrl,
          data: formData,
        );
        // Cloudinary returns { "secure_url": "https://..." } on success
        if (response.data is Map<String, dynamic>) {
          final data = response.data as Map<String, dynamic>;
          return data['secure_url'] as String? ?? data['url'] as String?;
        }
        return null;
      } else {
        // S3 — raw PUT
        final bytes = await file.readAsBytes();
        await plainDio.put<void>(
          uploadInfo.uploadUrl,
          data: bytes,
          options: Options(
            headers: {
              'Content-Type': mimeType,
              'Content-Length': bytes.length,
            },
          ),
        );
        return null;
      }
    } on DioException catch (e) {
      final responseBody = e.response?.data;
      final detail = responseBody is Map
          ? (responseBody['error']?['message'] ?? responseBody.toString())
          : responseBody?.toString() ?? e.message;
      throw ApiException(
        statusCode: e.response?.statusCode ?? 0,
        errorCode: 'UPLOAD_FAILED',
        message: 'Upload failed: $detail',
      );
    } finally {
      plainDio.close();
    }
  }

  /// Step 3: Confirm that the file was uploaded to cloud storage.
  /// POST /verification/documents/confirm
  ///
  /// This writes the remote URL to the document record and, for
  /// `profile_photo` documents, updates the role's `profilePhotoUrl`.
  Future<void> confirmUpload({
    required String documentId,
    required String remoteUrl,
  }) async {
    for (var attempt = 0;; attempt += 1) {
      try {
        await _dio.post(
          '/verification/documents/confirm',
          data: {
            'documentId': documentId,
            'remoteUrl': remoteUrl,
          },
        );
        return;
      } on DioException catch (e) {
        final apiError = ApiException.fromDioException(e);
        final retryable =
            apiError.errorCode == 'STORAGE_VERIFICATION_UNAVAILABLE' ||
                apiError.isNetworkError;
        if (!retryable || attempt >= _confirmationRetryDelays.length) {
          throw apiError;
        }
        // Confirmation is idempotent. Retrying this exact document ID avoids a
        // second sensitive-file upload and safely recovers both transient
        // storage lookups and a lost HTTP response after a committed confirm.
        await Future<void>.delayed(_confirmationRetryDelays[attempt]);
      }
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

  /// Full 3-step upload flow:
  ///   1. POST /verification/documents → get documentId + uploadUrl
  ///   2. Upload file to Cloudinary/S3 using uploadUrl
  ///   3. POST /verification/documents/confirm → write URL to profile
  ///
  /// Returns an [UploadResult] with the documentId and remote URL.
  Future<UploadResult> uploadDocument({
    required String providerType,
    required DocumentType documentType,
    required File file,
    String? vehicleId,
    String? expiresAt,
  }) async {
    if (documentType.isVehicleScoped && vehicleId == null) {
      throw ArgumentError.value(
        vehicleId,
        'vehicleId',
        'is required for vehicle evidence',
      );
    }
    if (!documentType.isVehicleScoped && vehicleId != null) {
      throw ArgumentError.value(
        vehicleId,
        'vehicleId',
        'is forbidden for identity and artisan documents',
      );
    }
    final fileName = file.path.split('/').last;
    final mimeType = _mimeFromExtension(fileName);
    final fileSize = await file.length();

    // Step 1: Get upload URL from backend
    final uploadInfo = await requestUpload(
      PresignedUrlRequest(
        providerType: providerType,
        documentType: documentType.value,
        fileName: fileName,
        mimeType: mimeType,
        fileSize: fileSize,
        vehicleId: vehicleId,
        expiresAt: expiresAt,
      ),
    );

    // Step 2: Upload file to cloud storage
    final remoteUrl = await uploadFile(
      uploadInfo: uploadInfo,
      file: file,
      mimeType: mimeType,
    );

    // Step 3 must run for every storage provider. Cloudinary returns a public
    // URL; an S3 presigned PUT has no response body, so the backend-issued
    // storage key is the canonical reference. Skipping this call leaves S3
    // documents permanently in `uploaded` and invisible to the review queue.
    await confirmUpload(
      documentId: uploadInfo.documentId,
      remoteUrl: remoteUrl ?? uploadInfo.storageKey,
    );

    return UploadResult(
      documentId: uploadInfo.documentId,
      remoteUrl: remoteUrl,
    );
  }
}

/// Result of [VerificationService.uploadDocument].
class UploadResult {
  const UploadResult({required this.documentId, this.remoteUrl});

  final String documentId;

  /// The remote file URL (e.g. Cloudinary `secure_url`).
  /// Null for S3 presigned PUT uploads.
  final String? remoteUrl;
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
