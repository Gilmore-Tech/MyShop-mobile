import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/di/providers.dart';
import '../../auth/providers/current_user_provider.dart';
import '../providers/provider_type_provider.dart';

/// Provides the [VerificationService] backed by the app's Dio client.
final verificationServiceProvider = Provider<VerificationService>((ref) {
  return VerificationService(ref.watch(dioProvider));
});

/// Fetches the verification status (document list) from the backend.
/// Falls back to an empty response if the endpoint is unavailable.
final verificationStatusProvider =
    FutureProvider<VerificationStatusResponse>((ref) async {
  try {
    return await ref.watch(verificationServiceProvider).getVerificationStatus();
  } catch (_) {
    return const VerificationStatusResponse(documents: []);
  }
});

/// Manages document upload state.
class DocumentUploadNotifier extends StateNotifier<DocumentUploadState> {
  DocumentUploadNotifier(this._service) : super(const DocumentUploadState());

  final VerificationService _service;

  /// Upload a file as a specific document type.
  /// Returns an error message on failure, or `null` on success.
  /// After a successful upload, the remote URL (if available) is stored
  /// in [DocumentUploadState.remoteUrls].
  Future<String?> upload({
    required String providerType,
    required DocumentType documentType,
    required File file,
  }) async {
    state = state.copyWith(
      uploading: {
        ...state.uploading,
        documentType.value: true,
      },
    );
    try {
      final result = await _service.uploadDocument(
        providerType: providerType,
        documentType: documentType,
        file: file,
      );
      state = state.copyWith(
        uploading: {
          ...state.uploading,
          documentType.value: false,
        },
        uploaded: {
          ...state.uploaded,
          documentType.value: true,
        },
        remoteUrls: {
          ...state.remoteUrls,
          if (result.remoteUrl != null)
            documentType.value: result.remoteUrl!,
        },
      );
      return null;
    } on ApiException catch (e) {
      state = state.copyWith(
        uploading: {
          ...state.uploading,
          documentType.value: false,
        },
      );
      return e.message;
    } catch (e) {
      state = state.copyWith(
        uploading: {
          ...state.uploading,
          documentType.value: false,
        },
      );
      return 'Upload failed: $e';
    }
  }

  bool isUploading(String docType) => state.uploading[docType] == true;
  bool wasUploaded(String docType) => state.uploaded[docType] == true;
}

class DocumentUploadState {
  const DocumentUploadState({
    this.uploading = const {},
    this.uploaded = const {},
    this.remoteUrls = const {},
  });

  /// docType → true while uploading
  final Map<String, bool> uploading;

  /// docType → true after successful upload in this session
  final Map<String, bool> uploaded;

  /// docType → remote URL returned by the storage provider (e.g. Cloudinary)
  final Map<String, String> remoteUrls;

  DocumentUploadState copyWith({
    Map<String, bool>? uploading,
    Map<String, bool>? uploaded,
    Map<String, String>? remoteUrls,
  }) {
    return DocumentUploadState(
      uploading: uploading ?? this.uploading,
      uploaded: uploaded ?? this.uploaded,
      remoteUrls: remoteUrls ?? this.remoteUrls,
    );
  }
}

final documentUploadProvider =
    StateNotifierProvider<DocumentUploadNotifier, DocumentUploadState>((ref) {
  return DocumentUploadNotifier(ref.watch(verificationServiceProvider));
});

// ─── Local Profile Photo ────────────────────────────────────────────────────

const _kLocalPhotoPath = 'local_profile_photo_path';
const _kProfilePhotoUrl = 'profile_photo_url';

/// Holds both:
/// - A local [File] for instant preview while uploading
/// - A persisted Cloudinary URL for after upload completes
///
/// Priority: localFile (instant) → cloudinaryUrl (persisted) → backend profilePhotoUrl
class ProfilePhotoState {
  const ProfilePhotoState({this.localFile, this.cloudinaryUrl});

  final File? localFile;
  final String? cloudinaryUrl;
}

class LocalProfilePhotoNotifier extends StateNotifier<ProfilePhotoState> {
  LocalProfilePhotoNotifier() : super(const ProfilePhotoState()) {
    _restore();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString(_kProfilePhotoUrl);
    final path = prefs.getString(_kLocalPhotoPath);

    File? file;
    if (path != null) {
      final f = File(path);
      if (await f.exists()) {
        file = f;
      } else {
        await prefs.remove(_kLocalPhotoPath);
      }
    }

    if (url != null || file != null) {
      state = ProfilePhotoState(localFile: file, cloudinaryUrl: url);
    }
  }

  /// Set the local file for instant preview (before upload completes).
  Future<void> setLocalFile(File? file) async {
    state = ProfilePhotoState(
      localFile: file,
      cloudinaryUrl: state.cloudinaryUrl,
    );
    final prefs = await SharedPreferences.getInstance();
    if (file != null) {
      await prefs.setString(_kLocalPhotoPath, file.path);
    } else {
      await prefs.remove(_kLocalPhotoPath);
    }
  }

  /// Set the Cloudinary URL after a successful upload.
  /// This is the permanent URL that survives app restarts.
  Future<void> setCloudinaryUrl(String url) async {
    state = ProfilePhotoState(
      localFile: state.localFile,
      cloudinaryUrl: url,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kProfilePhotoUrl, url);
  }

  /// Clear everything (e.g. on upload failure or logout).
  Future<void> clear() async {
    state = const ProfilePhotoState();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kLocalPhotoPath);
    await prefs.remove(_kProfilePhotoUrl);
  }
}

final localProfilePhotoProvider =
    StateNotifierProvider<LocalProfilePhotoNotifier, ProfilePhotoState>((ref) {
  return LocalProfilePhotoNotifier();
});

// ─── Profile Completion ─────────────────────────────────────────────────────

/// Computes the profile completion percentage from real user data.
/// Tracks which specific items are missing so the UI can tell the user
/// exactly what they need to complete before going online.
///
/// **Driver**: full name, photo, vehicle info, plus 4 required documents
/// (Ghana Card, Driver's Licence, Vehicle Registration, Roadworthiness)
/// approved.
/// **Artisan**: full name, photo, categories, plus 3 required documents
/// (Ghana Card, Business Registration, Trade Certificate) approved.
final profileCompletionProvider = Provider<ProfileCompletion>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) {
    return const ProfileCompletion(completed: 0, total: 1, missing: ['Sign in']);
  }

  // Backend document statuses — drives every doc-approval check below.
  final verificationAsync = ref.watch(verificationStatusProvider);
  final isLoadingDocs = verificationAsync.isLoading;
  final docs = verificationAsync.valueOrNull;

  bool isDocApproved(DocumentType type) {
    final doc = docs?.documentFor(type.value);
    return doc != null && doc.isApproved;
  }

  final providerType = ref.watch(providerTypeProvider);
  if (providerType.isDriver) {
    final dp = user.driverProfile;
    final items = <(bool, String)>[
      (user.fullName.isNotEmpty, 'Full name'),
      (dp?.profilePhotoUrl != null, 'Profile photo'),
      (dp?.vehicleMake != null, 'Vehicle information'),
      (isDocApproved(DocumentType.ghanaCard), 'Ghana Card (approved)'),
      (
        isDocApproved(DocumentType.driversLicence),
        "Driver's Licence (approved)",
      ),
      (
        isDocApproved(DocumentType.vehicleRegistration),
        'Vehicle Registration (approved)',
      ),
      (
        isDocApproved(DocumentType.roadworthinessCertificate),
        'Roadworthiness Certificate (approved)',
      ),
    ];
    return ProfileCompletion.fromChecks(items, isLoading: isLoadingDocs);
  } else {
    final items = <(bool, String)>[
      (user.fullName.isNotEmpty, 'Full name'),
      (user.artisanProfile?.profilePhotoUrl != null, 'Profile photo'),
      (
        user.artisanProfile?.serviceCategories != null &&
            user.artisanProfile!.serviceCategories!.isNotEmpty,
        'Service categories',
      ),
      (isDocApproved(DocumentType.ghanaCard), 'Ghana Card (approved)'),
      (
        isDocApproved(DocumentType.businessRegistration),
        'Business Registration (approved)',
      ),
      (
        isDocApproved(DocumentType.tradeCertificate),
        'Trade Certificate (approved)',
      ),
    ];
    return ProfileCompletion.fromChecks(items, isLoading: isLoadingDocs);
  }
});

class ProfileCompletion {
  const ProfileCompletion({
    required this.completed,
    required this.total,
    this.missing = const [],
    this.isLoading = false,
  });

  factory ProfileCompletion.fromChecks(
    List<(bool, String)> items, {
    bool isLoading = false,
  }) {
    final missing = <String>[
      for (final (passed, label) in items)
        if (!passed) label,
    ];
    return ProfileCompletion(
      completed: items.length - missing.length,
      total: items.length,
      missing: missing,
      isLoading: isLoading,
    );
  }

  final int completed;
  final int total;

  /// Human-readable labels for items that are not yet complete.
  final List<String> missing;

  /// True while verification data is still being fetched from the backend.
  /// The go-online toggle should wait instead of showing the incomplete sheet.
  final bool isLoading;

  double get progress => total == 0 ? 0 : completed / total;
  int get percentage => (progress * 100).round();
  bool get isComplete => completed == total;
}
