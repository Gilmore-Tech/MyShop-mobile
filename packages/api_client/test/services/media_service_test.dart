import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

class _FlowMediaService extends MediaService {
  _FlowMediaService(this.uploadInfo) : super(Dio());

  final UploadUrlResult uploadInfo;
  String? requestedPurpose;
  final List<String> confirmedIntentIds = [];
  int requestCount = 0;
  int uploadCount = 0;

  @override
  Future<UploadUrlResult> requestUploadUrl({
    required String purpose,
    required String mimeType,
    required int fileSize,
  }) async {
    requestCount++;
    requestedPurpose = purpose;
    return uploadInfo;
  }

  @override
  Future<String> uploadFile({
    required String filePath,
    required UploadUrlResult uploadInfo,
    required String mimeType,
  }) async {
    uploadCount++;
    return 'https://attacker-controlled.invalid/client-upload-response.jpg';
  }

  @override
  Future<String> confirmUpload({required String uploadIntentId}) async {
    confirmedIntentIds.add(uploadIntentId);
    return 'https://storage.example.test/server-verified.jpg';
  }
}

void main() {
  const intentId = '33333333-3333-4333-8333-333333333333';

  Dio dioReturning(
    Map<String, dynamic> data, {
    void Function(RequestOptions options)? capture,
  }) {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/v1'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          capture?.call(options);
          handler.resolve(
            Response<Map<String, dynamic>>(
              requestOptions: options,
              statusCode: 200,
              data: {'success': true, 'data': data},
            ),
          );
        },
      ),
    );
    return dio;
  }

  test('requestUploadUrl requires and retains the backend upload intent',
      () async {
    final service = MediaService(
      dioReturning({
        'uploadUrl': 'https://storage.example.test/presigned',
        'uploadMethod': 'PUT',
        'uploadFieldName': null,
        'uploadIntentId': intentId,
        'storageKey': 'media/profile_photo/user/source.jpg',
      }),
    );

    final result = await service.requestUploadUrl(
      purpose: 'profile_photo',
      mimeType: 'image/jpeg',
      fileSize: 4,
    );

    expect(result.uploadIntentId, intentId);
    expect(result.storageKey, 'media/profile_photo/user/source.jpg');
  });

  test('requestUploadUrl fails closed when the backend omits the intent',
      () async {
    final service = MediaService(
      dioReturning({
        'uploadUrl': 'https://storage.example.test/presigned',
        'uploadMethod': 'PUT',
        'storageKey': 'media/profile_photo/user/source.jpg',
      }),
    );

    await expectLater(
      service.requestUploadUrl(
        purpose: 'profile_photo',
        mimeType: 'image/jpeg',
        fileSize: 4,
      ),
      throwsA(
        isA<ApiException>().having(
          (error) => error.errorCode,
          'errorCode',
          'INVALID_UPLOAD_INTENT_RESPONSE',
        ),
      ),
    );
  });

  test('confirm sends only the intent and accepts only the server final URL',
      () async {
    RequestOptions? captured;
    final service = MediaService(
      dioReturning(
        {'url': 'https://storage.example.test/server-verified.jpg'},
        capture: (options) => captured = options,
      ),
    );

    final result = await service.confirmUpload(uploadIntentId: intentId);

    expect(result, 'https://storage.example.test/server-verified.jpg');
    expect(captured?.path, '/media/confirm');
    expect(captured?.data, {'uploadIntentId': intentId});
    expect(
      (captured?.data as Map<String, dynamic>).containsKey('remoteUrl'),
      isFalse,
    );
    expect(
      (captured?.data as Map<String, dynamic>).containsKey('storageKey'),
      isFalse,
    );
  });

  test('confirm fails closed when the server omits its verified final URL',
      () async {
    final service = MediaService(dioReturning({}));

    await expectLater(
      service.confirmUpload(uploadIntentId: intentId),
      throwsA(
        isA<ApiException>().having(
          (error) => error.errorCode,
          'errorCode',
          'INVALID_UPLOAD_CONFIRMATION_RESPONSE',
        ),
      ),
    );
  });

  test('convenience upload confirms with the intent, never the client URL',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('media-service-test-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/photo.jpg');
    await file.writeAsBytes(const [0xff, 0xd8, 0xff, 0xdb]);
    final service = _FlowMediaService(
      const UploadUrlResult(
        uploadUrl: 'https://storage.example.test/presigned',
        uploadMethod: 'PUT',
        uploadIntentId: intentId,
        storageKey: 'media/support_attachment/user/source.jpg',
      ),
    );

    final result = await service.uploadSupportAttachment(file.path);

    expect(service.requestedPurpose, 'support_attachment');
    expect(service.confirmedIntentIds, [intentId]);
    expect(result.url, 'https://storage.example.test/server-verified.jpg');
    expect(
      result.url,
      isNot('https://attacker-controlled.invalid/client-upload-response.jpg'),
    );
  });

  test('client Ghana Card uses its dedicated role-bound upload purpose',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('ghana-card-media-test-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/card.jpg');
    await file.writeAsBytes(const [0xff, 0xd8, 0xff, 0xdb]);
    final service = _FlowMediaService(
      const UploadUrlResult(
        uploadUrl: 'https://storage.example.test/presigned',
        uploadMethod: 'PUT',
        uploadIntentId: intentId,
        storageKey: 'media/client_ghana_card/user/source.jpg',
      ),
    );

    final result = await service.uploadClientGhanaCard(file.path);

    expect(service.requestedPurpose, 'client_ghana_card');
    expect(service.confirmedIntentIds, [intentId]);
    expect(result, 'https://storage.example.test/server-verified.jpg');
  });
}
