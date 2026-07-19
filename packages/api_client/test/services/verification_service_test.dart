import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

class _FlowVerificationService extends VerificationService {
  _FlowVerificationService({
    required this.uploadInfo,
    required this.uploadedRemoteUrl,
  }) : super(Dio());

  final DocumentUploadResponse uploadInfo;
  final String? uploadedRemoteUrl;
  String? confirmedDocumentId;
  String? confirmedRemoteUrl;
  PresignedUrlRequest? lastUploadRequest;

  @override
  Future<DocumentUploadResponse> requestUpload(
    PresignedUrlRequest request,
  ) async {
    lastUploadRequest = request;
    return uploadInfo;
  }

  @override
  Future<String?> uploadFile({
    required DocumentUploadResponse uploadInfo,
    required File file,
    required String mimeType,
  }) async {
    return uploadedRemoteUrl;
  }

  @override
  Future<void> confirmUpload({
    required String documentId,
    required String remoteUrl,
  }) async {
    confirmedDocumentId = documentId;
    confirmedRemoteUrl = remoteUrl;
  }
}

void main() {
  late Directory tempDirectory;
  late File document;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'verification-service-test-',
    );
    document = File('${tempDirectory.path}/ghana-card.jpg');
    await document.writeAsBytes(const [1, 2, 3]);
  });

  tearDown(() async {
    await tempDirectory.delete(recursive: true);
  });

  test('S3 PUT confirms with the backend-issued storage key', () async {
    final service = _FlowVerificationService(
      uploadInfo: const DocumentUploadResponse(
        documentId: 'document-1',
        uploadUrl: 'https://s3.example.test/presigned-put',
        uploadMethod: 'PUT',
        expiresIn: 3600,
        storageKey: 'documents/driver/driver-1/ghana_card/card.jpg',
      ),
      uploadedRemoteUrl: null,
    );

    final result = await service.uploadDocument(
      providerType: 'driver',
      documentType: DocumentType.ghanaCard,
      file: document,
    );

    expect(service.confirmedDocumentId, 'document-1');
    expect(
      service.confirmedRemoteUrl,
      'documents/driver/driver-1/ghana_card/card.jpg',
    );
    expect(result.remoteUrl, isNull);
  });

  test('Cloudinary POST confirms with the returned remote URL', () async {
    const remoteUrl = 'https://res.cloudinary.com/test/card.jpg';
    final service = _FlowVerificationService(
      uploadInfo: const DocumentUploadResponse(
        documentId: 'document-2',
        uploadUrl: 'https://api.cloudinary.com/upload',
        uploadMethod: 'POST',
        uploadFieldName: 'file',
        expiresIn: 3600,
        storageKey: 'myshop-dev/documents/driver/driver-1/card',
      ),
      uploadedRemoteUrl: remoteUrl,
    );

    final result = await service.uploadDocument(
      providerType: 'driver',
      documentType: DocumentType.ghanaCard,
      file: document,
    );

    expect(service.confirmedDocumentId, 'document-2');
    expect(service.confirmedRemoteUrl, remoteUrl);
    expect(result.remoteUrl, remoteUrl);
  });

  test('vehicle evidence keeps its exact vehicle binding in upload request',
      () async {
    final service = _FlowVerificationService(
      uploadInfo: const DocumentUploadResponse(
        documentId: 'document-3',
        uploadUrl: 'https://s3.example.test/presigned-put',
        uploadMethod: 'PUT',
        expiresIn: 3600,
        storageKey:
            'documents/driver/driver-1/vehicles/vehicle-1/insurance.pdf',
      ),
      uploadedRemoteUrl: null,
    );

    await service.uploadDocument(
      providerType: 'driver',
      documentType: DocumentType.vehicleInsurance,
      vehicleId: 'vehicle-1',
      file: document,
      expiresAt: '2027-07-18',
    );

    expect(service.lastUploadRequest?.vehicleId, 'vehicle-1');
    expect(
      service.lastUploadRequest?.toJson(),
      containsPair('vehicleId', 'vehicle-1'),
    );
    expect(DocumentType.vehicleInsurance.isVehicleScoped, isTrue);
    expect(DocumentType.roadworthinessCertificate.isVehicleScoped, isTrue);
    expect(DocumentType.driversLicence.isVehicleScoped, isFalse);
  });

  test('vehicle binding is required only for vehicle evidence', () async {
    final service = _FlowVerificationService(
      uploadInfo: const DocumentUploadResponse(
        documentId: 'document-4',
        uploadUrl: 'https://s3.example.test/presigned-put',
        uploadMethod: 'PUT',
        expiresIn: 3600,
        storageKey: 'unused',
      ),
      uploadedRemoteUrl: null,
    );

    expect(
      service.uploadDocument(
        providerType: 'driver',
        documentType: DocumentType.vehicleInsurance,
        file: document,
        expiresAt: '2027-07-18',
      ),
      throwsArgumentError,
    );
    expect(
      service.uploadDocument(
        providerType: 'driver',
        documentType: DocumentType.ghanaCard,
        vehicleId: 'vehicle-1',
        file: document,
      ),
      throwsArgumentError,
    );
  });
}
