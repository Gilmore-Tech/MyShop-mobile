import 'dart:io';

import 'package:dio/dio.dart';

import '../models/api_exception.dart';

/// Service for media upload via presigned URLs.
/// Backend flow: request URL → upload to storage → confirm → get final URL.
class MediaService {
  MediaService(this._dio);

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

  /// POST /media/upload-url — Get a presigned URL for uploading.
  Future<UploadUrlResult> requestUploadUrl({
    required String purpose,
    required String mimeType,
    required int fileSize,
  }) async {
    try {
      final response = await _dio.post(
        '/media/upload-url',
        data: {
          'purpose': purpose,
          'mimeType': mimeType,
          'fileSize': fileSize,
        },
      );
      final data = _unwrap(response) as Map<String, dynamic>;
      final uploadIntentId = data['uploadIntentId'];
      if (uploadIntentId is! String || uploadIntentId.trim().isEmpty) {
        throw const ApiException(
          message: 'The upload service returned an invalid upload intent.',
          errorCode: 'INVALID_UPLOAD_INTENT_RESPONSE',
        );
      }
      return UploadUrlResult(
        uploadUrl: data['uploadUrl'] as String,
        uploadMethod: data['uploadMethod'] as String? ?? 'PUT',
        uploadFieldName: data['uploadFieldName'] as String?,
        uploadIntentId: uploadIntentId.trim(),
        storageKey: data['storageKey'] as String,
      );
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// Upload a file directly to the storage provider using the presigned URL.
  Future<String> uploadFile({
    required String filePath,
    required UploadUrlResult uploadInfo,
    required String mimeType,
  }) async {
    final uploadDio = Dio();
    final file = File(filePath);

    try {
      if (uploadInfo.uploadMethod == 'POST' &&
          uploadInfo.uploadFieldName != null) {
        // Cloudinary-style multipart POST
        final formData = FormData.fromMap({
          uploadInfo.uploadFieldName!: await MultipartFile.fromFile(
            filePath,
            contentType: DioMediaType.parse(mimeType),
          ),
        });
        final response = await uploadDio.post(
          uploadInfo.uploadUrl,
          data: formData,
        );
        // Cloudinary returns the URL in secure_url
        final data = response.data as Map<String, dynamic>;
        return data['secure_url'] as String? ?? data['url'] as String? ?? '';
      } else {
        // S3-style PUT with raw bytes
        await uploadDio.put(
          uploadInfo.uploadUrl,
          data: file.openRead(),
          options: Options(
            headers: {
              'Content-Type': mimeType,
              'Content-Length': await file.length(),
            },
          ),
        );
        // For S3, the public URL is the upload URL without query params
        final uri = Uri.parse(uploadInfo.uploadUrl);
        return '${uri.scheme}://${uri.host}${uri.path}';
      }
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// POST /media/confirm — Confirm the upload and get the final URL.
  Future<String> confirmUpload({
    required String uploadIntentId,
  }) async {
    try {
      final response = await _dio.post(
        '/media/confirm',
        data: {
          'uploadIntentId': uploadIntentId,
        },
      );
      final data = _unwrap(response) as Map<String, dynamic>;
      final finalUrl = data['url'];
      if (finalUrl is! String || finalUrl.trim().isEmpty) {
        throw const ApiException(
          message: 'The upload service did not return a verified file URL.',
          errorCode: 'INVALID_UPLOAD_CONFIRMATION_RESPONSE',
        );
      }
      return finalUrl;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// Upload a job reference photo through the purpose-bound confirmed flow.
  Future<String> uploadJobPhoto(String localPath) =>
      _uploadImage(localPath, purpose: 'job_photo');

  /// Convenience: upload a profile photo through the full three-step flow.
  /// Uses `purpose: 'profile_photo'` so the backend stores it under
  /// `media/profile_photo/<userId>/...`. Caller must then PATCH the URL onto
  /// the user via `UserService.updateClientProfilePhoto`.
  Future<String> uploadProfilePhoto(String localPath) =>
      _uploadImage(localPath, purpose: 'profile_photo');

  /// Upload a client Ghana Card image through its own purpose-bound intent.
  /// Keeping this separate from profile photos prevents a confirmed object
  /// from being replayed across two unrelated consumers.
  Future<String> uploadClientGhanaCard(String localPath) =>
      _uploadImage(localPath, purpose: 'client_ghana_card');

  /// Upload an image attached to a support ticket / reply. Reuses the
  /// 3-step presigned-URL flow under `purpose: 'support_attachment'`.
  /// Returns `(remoteUrl, sizeBytes, mimeType)` so the support service
  /// can build a [TicketAttachment] without re-statting the file.
  Future<({String url, int sizeBytes, String mimeType})>
      uploadSupportAttachment(String localPath) async {
    final file = File(localPath);
    final fileSize = await file.length();
    final mimeType =
        localPath.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg';
    final uploadInfo = await requestUploadUrl(
      purpose: 'support_attachment',
      mimeType: mimeType,
      fileSize: fileSize,
    );
    await uploadFile(
      filePath: localPath,
      uploadInfo: uploadInfo,
      mimeType: mimeType,
    );
    final finalUrl = await confirmUpload(
      uploadIntentId: uploadInfo.uploadIntentId,
    );
    return (url: finalUrl, sizeBytes: fileSize, mimeType: mimeType);
  }

  Future<String> _uploadImage(
    String localPath, {
    required String purpose,
  }) async {
    final file = File(localPath);
    final fileSize = await file.length();
    final mimeType =
        localPath.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg';

    final uploadInfo = await requestUploadUrl(
      purpose: purpose,
      mimeType: mimeType,
      fileSize: fileSize,
    );
    await uploadFile(
      filePath: localPath,
      uploadInfo: uploadInfo,
      mimeType: mimeType,
    );
    return confirmUpload(
      uploadIntentId: uploadInfo.uploadIntentId,
    );
  }
}

/// Result from POST /media/upload-url.
class UploadUrlResult {
  const UploadUrlResult({
    required this.uploadUrl,
    required this.uploadMethod,
    this.uploadFieldName,
    required this.uploadIntentId,
    required this.storageKey,
  });
  final String uploadUrl;
  final String uploadMethod;
  final String? uploadFieldName;
  final String uploadIntentId;
  final String storageKey;
}
