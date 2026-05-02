/// DTOs for the verification & document upload endpoints.
/// Matches the contract in `docs/mobile-api-endpoints.md`.

/// Types of documents that can be uploaded for verification.
enum DocumentType {
  profilePhoto('profile_photo'),
  driversLicence('drivers_licence'),
  vehicleRegistration('vehicle_registration'),
  roadworthinessCertificate('roadworthiness_certificate'),
  nationalId('national_id'),
  ghanaCard('ghana_card'),
  tradeCertificate('trade_certificate'),
  businessRegistration('business_registration'),
  portfolioPhoto('portfolio_photo');

  const DocumentType(this.value);
  final String value;

  static DocumentType? fromString(String? s) {
    if (s == null) return null;
    return DocumentType.values.where((e) => e.value == s).firstOrNull;
  }
}

/// POST /verification/documents — request body.
class PresignedUrlRequest {
  const PresignedUrlRequest({
    required this.providerType,
    required this.documentType,
    required this.fileName,
    required this.mimeType,
    required this.fileSize,
    this.fileHash,
    this.expiresAt,
  });

  final String providerType;
  final String documentType;
  final String fileName;
  final String mimeType;
  final int fileSize;
  final String? fileHash;
  final String? expiresAt;

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'providerType': providerType,
      'documentType': documentType,
      'fileName': fileName,
      'mimeType': mimeType,
      'fileSize': fileSize,
    };
    if (fileHash != null) json['fileHash'] = fileHash;
    if (expiresAt != null) json['expiresAt'] = expiresAt;
    return json;
  }
}

/// POST /verification/documents — response.
///
/// The backend tells the client exactly how to upload:
/// - `uploadMethod` "POST" → Cloudinary multipart form (dev/staging)
/// - `uploadMethod` "PUT"  → S3 presigned raw bytes (production)
class DocumentUploadResponse {
  const DocumentUploadResponse({
    required this.documentId,
    required this.uploadUrl,
    required this.uploadMethod,
    required this.expiresIn,
    required this.storageKey,
    this.uploadFieldName,
  });

  factory DocumentUploadResponse.fromJson(Map<String, dynamic> json) {
    return DocumentUploadResponse(
      documentId: json['documentId'] as String,
      uploadUrl: json['uploadUrl'] as String,
      uploadMethod: json['uploadMethod'] as String? ?? 'PUT',
      uploadFieldName: json['uploadFieldName'] as String?,
      expiresIn: json['expiresIn'] as int,
      storageKey: (json['storageKey'] ?? json['s3Key'] ?? '') as String,
    );
  }

  final String documentId;
  final String uploadUrl;

  /// "POST" for Cloudinary multipart, "PUT" for S3 raw bytes.
  final String uploadMethod;

  /// The form field name for multipart uploads (e.g. "file").
  /// Only present when [uploadMethod] is "POST".
  final String? uploadFieldName;

  final int expiresIn;
  final String storageKey;

  bool get isMultipart => uploadMethod.toUpperCase() == 'POST';
}

/// A single document from GET /verification/status → documents[].
class DocumentInfo {
  const DocumentInfo({
    required this.id,
    required this.providerType,
    required this.documentType,
    required this.status,
    required this.isCurrent,
    required this.createdAt,
    this.fileUrl,
    this.reviewedBy,
    this.reviewedAt,
    this.rejectionReason,
    this.expiresAt,
    this.version = 1,
  });

  factory DocumentInfo.fromJson(Map<String, dynamic> json) {
    return DocumentInfo(
      id: json['id'] as String,
      providerType: json['providerType'] as String,
      documentType: json['documentType'] as String,
      status: json['status'] as String,
      fileUrl: json['fileUrl'] as String?,
      reviewedBy: json['reviewedBy'] as String?,
      reviewedAt: json['reviewedAt'] as String?,
      rejectionReason: json['rejectionReason'] as String?,
      expiresAt: json['expiresAt'] as String?,
      version: json['version'] as int? ?? 1,
      isCurrent: json['isCurrent'] as bool? ?? true,
      createdAt: json['createdAt'] as String,
    );
  }

  final String id;
  final String providerType;
  final String documentType;

  /// Document status flow:
  ///   `uploaded` → presigned URL given, file not yet in storage
  ///   `pending_review` → file uploaded successfully, awaiting admin review
  ///   `approved` → admin approved the document
  ///   `rejected` → admin rejected the document
  final String status;

  final String? fileUrl;
  final String? reviewedBy;
  final String? reviewedAt;
  final String? rejectionReason;
  final String? expiresAt;
  final int version;
  final bool isCurrent;
  final String createdAt;

  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';
  bool get isPendingReview => status == 'pending_review';
  bool get isUploaded => status == 'uploaded';

  /// True if the document has been received and not rejected.
  bool get isSubmitted => isPendingReview || isApproved;
}

/// GET /verification/status — full response.
class VerificationStatusResponse {
  const VerificationStatusResponse({
    required this.documents,
    this.driverData,
    this.artisanData,
  });

  factory VerificationStatusResponse.fromJson(Map<String, dynamic> json) {
    return VerificationStatusResponse(
      driverData: json['driver'] as Map<String, dynamic>?,
      artisanData: json['artisan'] as Map<String, dynamic>?,
      documents: (json['documents'] as List<dynamic>?)
              ?.map(
                (e) => DocumentInfo.fromJson(e as Map<String, dynamic>),
              )
              .toList() ??
          const [],
    );
  }

  final Map<String, dynamic>? driverData;
  final Map<String, dynamic>? artisanData;
  final List<DocumentInfo> documents;

  /// Find the document for a given type, preferring the latest current
  /// row but falling back to the most recently approved row when the
  /// backend hasn't (or no longer has) any `isCurrent` flag set.
  ///
  /// The match is case- and underscore-insensitive so a backend that
  /// emits `documentType: 'driversLicence'` (camelCase) still resolves
  /// against the `'drivers_licence'` enum value the mobile uses.
  DocumentInfo? documentFor(String type) {
    String normalize(String s) =>
        s.toLowerCase().replaceAll('_', '').replaceAll('-', '');
    final target = normalize(type);
    final matches =
        documents.where((d) => normalize(d.documentType) == target).toList();
    if (matches.isEmpty) return null;
    // Preference: current+approved → approved → current → anything.
    int score(DocumentInfo d) {
      if (d.isCurrent && d.isApproved) return 0;
      if (d.isApproved) return 1;
      if (d.isCurrent) return 2;
      return 3;
    }

    matches.sort((a, b) => score(a).compareTo(score(b)));
    return matches.first;
  }
}
