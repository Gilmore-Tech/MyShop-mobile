/// DTOs for the verification & document upload endpoints.
/// Matches the contract in `docs/mobile-api-endpoints.md`.

/// Types of documents that can be uploaded for verification.
enum DocumentType {
  profilePhoto('profile_photo'),
  driversLicence('drivers_licence'),
  vehicleRegistration('vehicle_registration'),
  roadworthinessCertificate('roadworthiness_certificate'),
  vehicleInsurance('vehicle_insurance'),
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

  /// Whether this document carries a real-world expiry date printed on it,
  /// which the provider must supply at upload time so the platform can prompt
  /// a renewal once it lapses. Types without an expiry (photos, trade
  /// certificate, national ID) never prompt for one.
  bool get requiresExpiry => switch (this) {
    DocumentType.driversLicence ||
    DocumentType.roadworthinessCertificate ||
    DocumentType.vehicleInsurance => true,
    _ => false,
  };

  /// Documents whose authority belongs to one physical vehicle rather than
  /// to the driver account as a whole.
  bool get isVehicleScoped => switch (this) {
    DocumentType.roadworthinessCertificate ||
    DocumentType.vehicleInsurance => true,
    _ => false,
  };
}

/// POST /verification/documents — request body.
class PresignedUrlRequest {
  const PresignedUrlRequest({
    required this.providerType,
    required this.documentType,
    required this.fileName,
    required this.mimeType,
    required this.fileSize,
    this.vehicleId,
    this.fileHash,
    this.expiresAt,
  });

  final String providerType;
  final String documentType;
  final String fileName;
  final String mimeType;
  final int fileSize;
  final String? vehicleId;
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
    if (vehicleId != null) json['vehicleId'] = vehicleId;
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
    this.vehicleId,
    this.reviewedBy,
    this.reviewedAt,
    this.rejectionReason,
    this.expiresAt,
    this.expired,
    this.providerReplacementAllowed,
    this.resubmissionRequired,
    this.replacementOpensAt,
    this.version = 1,
  });

  factory DocumentInfo.fromJson(Map<String, dynamic> json) {
    return DocumentInfo(
      id: json['id'] as String,
      providerType: json['providerType'] as String,
      documentType: json['documentType'] as String,
      status: json['status'] as String,
      fileUrl: json['fileUrl'] as String?,
      vehicleId: json['vehicleId'] as String?,
      reviewedBy: json['reviewedBy'] as String?,
      reviewedAt: json['reviewedAt'] as String?,
      rejectionReason: json['rejectionReason'] as String?,
      expiresAt: json['expiresAt'] as String?,
      expired: json['expired'] as bool?,
      providerReplacementAllowed: json['providerReplacementAllowed'] as bool?,
      resubmissionRequired: json['resubmissionRequired'] as bool?,
      replacementOpensAt: json['replacementOpensAt'] as String?,
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
  ///   `confirmed` → Admin verified authenticity; awaiting Coordinator
  ///   `coordinator_validated` → Coordinator validated; awaiting RM
  ///   `approved` → RM gave final document approval
  ///   `rejected` → document was rejected in the review chain
  final String status;

  final String? fileUrl;
  final String? vehicleId;
  final String? reviewedBy;
  final String? reviewedAt;
  final String? rejectionReason;
  final String? expiresAt;

  /// Server-authoritative expiry state. Older APIs may omit this field, in
  /// which case [isExpired] retains a backwards-compatible local fallback.
  final bool? expired;

  /// Whether the authenticated provider may initiate a replacement now.
  /// Approved profile photos remain administrator-only.
  final bool? providerReplacementAllowed;

  /// Whether the provider-level rejection explicitly requires this document
  /// to be replaced. This is separate from the document's own review status:
  /// an RM can reject the overall verification while leaving an independently
  /// validated document row at `coordinator_validated`.
  ///
  /// Older APIs omit this field. Callers must then use the aggregate rejected
  /// state as the backwards-compatible recovery signal.
  final bool? resubmissionRequired;

  /// Exact server-computed GMT instant at which an expiring approved document
  /// becomes invalid and provider resubmission opens.
  final String? replacementOpensAt;
  final int version;
  final bool isCurrent;
  final String createdAt;

  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';
  bool get isPendingReview => status == 'pending_review';
  bool get isAdminVerified => status == 'confirmed';
  bool get isCoordinatorValidated => status == 'coordinator_validated';
  bool get isUploaded => status == 'uploaded';

  /// True if the document has been received and not rejected.
  bool get isSubmitted =>
      isPendingReview ||
      isAdminVerified ||
      isCoordinatorValidated ||
      isApproved;

  /// The parsed expiry date, or `null` when the document never expires or the
  /// backend value can't be parsed.
  DateTime? get expiresAtDate =>
      expiresAt == null ? null : DateTime.tryParse(expiresAt!);

  /// The first instant at which the printed document date is no longer valid.
  /// A value such as `2026-07-17` remains valid for all of 17 July GMT and
  /// becomes invalid at 00:00 GMT on 18 July.
  DateTime? get expiryInvalidAtUtc {
    final raw = expiresAt;
    if (raw == null) return null;
    final datePrefix = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(raw);
    if (datePrefix == null || DateTime.tryParse(raw) == null) return null;
    final expiryDate = DateTime.utc(
      int.parse(datePrefix.group(1)!),
      int.parse(datePrefix.group(2)!),
      int.parse(datePrefix.group(3)!),
    );
    return expiryDate.add(const Duration(days: 1));
  }

  /// True when this is an approved document whose expiry date has passed.
  ///
  /// Expiry is derived on the client — the backend keeps the row `approved`
  /// but exposes `expiresAt`, so the provider must re-upload once it lapses.
  /// Pass [now] in tests; defaults to the current time.
  bool isExpired([DateTime? now]) {
    if (expired != null) return expired!;
    final invalidAt = expiryInvalidAtUtc;
    if (invalidAt == null || !isApproved) return false;
    return !(now ?? DateTime.now()).toUtc().isBefore(invalidAt);
  }

  bool canProviderReplace([DateTime? now]) {
    if (resubmissionRequired == true) return true;
    if (providerReplacementAllowed != null) {
      return providerReplacementAllowed!;
    }
    if (documentType == DocumentType.profilePhoto.value && isApproved) {
      return false;
    }
    return isRejected || isExpired(now);
  }

  /// True when this approved document is valid but expires within [within]
  /// (30 days by default) — used to prompt an early, proactive re-upload.
  bool isExpiringSoon({
    DateTime? now,
    Duration within = const Duration(days: 30),
  }) {
    final invalidAt = expiryInvalidAtUtc;
    if (invalidAt == null || !isApproved) return false;
    final ref = (now ?? DateTime.now()).toUtc();
    return ref.isBefore(invalidAt) && !ref.add(within).isBefore(invalidAt);
  }
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
      documents:
          (json['documents'] as List<dynamic>?)
              ?.map((e) => DocumentInfo.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }

  final Map<String, dynamic>? driverData;
  final Map<String, dynamic>? artisanData;
  final List<DocumentInfo> documents;

  /// Returns the aggregate verification status for [providerType], or `null`
  /// when the backend omitted that role block from the response.
  ///
  /// Keeping the missing case distinct from a real non-approved status lets
  /// callers fall back to the authenticated profile snapshot for legacy
  /// accounts without treating an explicit `pending`, `rejected`, or
  /// `suspended` response as approved.
  String? providerVerificationStatus(String providerType) {
    final data = providerData(providerType);
    return data?['verificationStatus']?.toString().toLowerCase();
  }

  /// The active manual-review stage, when supplied by the backend.
  String? providerVerificationStage(String providerType) => providerData(
    providerType,
  )?['verificationStage']?.toString().toLowerCase();

  /// Durable provider-level rejection reason. Unlike a document rejection
  /// reason, this explains an RM decision that may target one or more otherwise
  /// provisionally validated documents.
  String? providerRejectionReason(String providerType) {
    final raw = providerData(providerType)?['rejectionReason']?.toString();
    final trimmed = raw?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  bool providerResubmissionRequired(String providerType) =>
      providerData(providerType)?['resubmissionRequired'] == true;

  List<String> providerResubmissionDocumentIds(String providerType) {
    final raw = providerData(providerType)?['resubmissionDocumentIds'];
    if (raw is! List) return const [];
    return raw
        .map((value) => value?.toString().trim() ?? '')
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
  }

  /// True only for the newer recovery contract. The distinction matters
  /// because the legacy API already emitted `providerReplacementAllowed=false`
  /// on stranded coordinator-validated rows; absence of the role-level plan is
  /// what activates the safe backwards-compatible fallback.
  bool hasProviderResubmissionPlan(String providerType) {
    final data = providerData(providerType);
    return data?.containsKey('resubmissionRequired') == true ||
        data?.containsKey('resubmissionDocumentIds') == true;
  }

  /// Whether [document] is actionable for this provider right now.
  ///
  /// New backends designate exact document IDs/rows. On an old backend an RM
  /// rejection left every current document at `coordinator_validated`, so the
  /// only recovery path is to permit current non-approved rows. Upload
  /// confirmation immediately resets the provider to pending, closing this
  /// fallback after the first successful replacement.
  bool requiresDocumentResubmission(
    String providerType,
    DocumentInfo document,
  ) {
    if (document.providerType != providerType || !document.isCurrent) {
      return false;
    }
    if (document.resubmissionRequired == true) return true;
    if (providerResubmissionDocumentIds(providerType).contains(document.id)) {
      return true;
    }
    if (hasProviderResubmissionPlan(providerType)) return false;
    return providerVerificationStatus(providerType) == 'rejected' &&
        !document.isApproved;
  }

  Map<String, dynamic>? providerData(String providerType) {
    return switch (providerType) {
      'driver' => driverData,
      'artisan' => artisanData,
      _ => null,
    };
  }

  /// Whether the active provider role has aggregate approval. This is separate
  /// from each document's independent review decision: callers must not rewrite
  /// an approved document as pending merely because this returns false.
  bool isProviderFullyApproved(String providerType) {
    return providerVerificationStatus(providerType) == 'approved';
  }

  /// Find the document for a given type, preferring the latest current row but
  /// falling back to the most recent approved row when legacy data has no
  /// `isCurrent` flag set.
  ///
  /// The match is case- and underscore-insensitive so a backend that
  /// emits `documentType: 'driversLicence'` (camelCase) still resolves
  /// against the `'drivers_licence'` enum value the mobile uses.
  DocumentInfo? documentFor(String type, {String? providerType}) {
    String normalize(String s) =>
        s.toLowerCase().replaceAll('_', '').replaceAll('-', '');
    final target = normalize(type);
    final matches = documents
        .where(
          (d) =>
              normalize(d.documentType) == target &&
              (providerType == null || d.providerType == providerType),
        )
        .toList();
    if (matches.isEmpty) return null;
    int newestFirst(DocumentInfo a, DocumentInfo b) {
      final byVersion = b.version.compareTo(a.version);
      if (byVersion != 0) return byVersion;
      final aCreated = DateTime.tryParse(a.createdAt);
      final bCreated = DateTime.tryParse(b.createdAt);
      if (aCreated != null && bCreated != null) {
        final byCreated = bCreated.compareTo(aCreated);
        if (byCreated != 0) return byCreated;
      }
      return b.id.compareTo(a.id);
    }

    // Preserve the existing renewal policy until the business decides whether
    // a still-valid approved document remains eligible while its replacement
    // is pending/rejected. Within each policy tier, choose deterministically by
    // version/date so duplicate legacy rows cannot produce random results.
    int policyScore(DocumentInfo d) {
      if (d.isCurrent && d.isApproved) return 0;
      if (d.isApproved) return 1;
      if (d.isCurrent) return 2;
      return 3;
    }

    matches.sort((a, b) {
      final byPolicy = policyScore(a).compareTo(policyScore(b));
      return byPolicy != 0 ? byPolicy : newestFirst(a, b);
    });
    return matches.first;
  }
}
