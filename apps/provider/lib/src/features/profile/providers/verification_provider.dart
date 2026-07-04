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
    String? expiresAt,
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
        expiresAt: expiresAt,
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
          if (result.remoteUrl != null) documentType.value: result.remoteUrl!,
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

  /// Retire the optimistic "uploaded — pending review" flag for a document
  /// type once the backend reflects it. After this the backend status is the
  /// single source of truth, so a later admin approval/rejection shows without
  /// an app restart. Idempotent — a no-op if the flag isn't set.
  void clearUploaded(String docType) {
    if (state.uploaded[docType] != true) return;
    final next = Map<String, bool>.from(state.uploaded)..remove(docType);
    state = state.copyWith(uploaded: next);
  }
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
//
// Per-role profile photo cache. Driver and Artisan profiles on the same
// phone each store their own photo to its own SharedPreferences keys —
// `local_profile_photo_path_driver` / `profile_photo_url_artisan` etc.
// Previously the cache was role-agnostic and the moment the user uploaded
// a photo for Artisan the same image flashed onto the Driver dashboard
// from the local cache (the backend column was per-role but the mobile
// cache read it ahead of the per-role profile object).
//
// The notifier reads the active role via [providerTypeProvider]. When the
// active role changes (login as the other role on the same device, or a
// post-logout role reset), the provider is invalidated by the logout
// cleanup bridge so a fresh notifier reads from the new role's keys.

String _photoPathKey(ProviderType role) =>
    'local_profile_photo_path_${role.name}';
String _photoUrlKey(ProviderType role) => 'profile_photo_url_${role.name}';

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
  LocalProfilePhotoNotifier(this._role) : super(const ProfilePhotoState()) {
    _restore();
  }

  final ProviderType _role;

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString(_photoUrlKey(_role));
    final path = prefs.getString(_photoPathKey(_role));

    File? file;
    if (path != null) {
      final f = File(path);
      if (await f.exists()) {
        file = f;
      } else {
        await prefs.remove(_photoPathKey(_role));
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
      await prefs.setString(_photoPathKey(_role), file.path);
    } else {
      await prefs.remove(_photoPathKey(_role));
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
    await prefs.setString(_photoUrlKey(_role), url);
  }

  /// Clear THIS ROLE's cache only (upload failure or per-role wipe).
  /// Use [clearAllRoles] to nuke every role's cache on logout.
  Future<void> clear() async {
    state = const ProfilePhotoState();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_photoPathKey(_role));
    await prefs.remove(_photoUrlKey(_role));
  }

  /// Clear every role's cache (logout path — the next account on this
  /// device must not see the previous account's photo).
  static Future<void> clearAllRoles() async {
    final prefs = await SharedPreferences.getInstance();
    for (final role in ProviderType.values) {
      await prefs.remove(_photoPathKey(role));
      await prefs.remove(_photoUrlKey(role));
    }
    // Legacy un-namespaced keys from before the per-role split — strip
    // them so they don't leak when the user opens the app for the first
    // time after the upgrade.
    await prefs.remove('local_profile_photo_path');
    await prefs.remove('profile_photo_url');
  }
}

final localProfilePhotoProvider =
    StateNotifierProvider<LocalProfilePhotoNotifier, ProfilePhotoState>((ref) {
  final role = ref.watch(providerTypeProvider);
  return LocalProfilePhotoNotifier(role);
});

/// The provider profile photo that is allowed to be displayed in avatar holders.
///
/// A provider-uploaded photo is a compliance document, not a free-form avatar:
/// it may appear publicly only after the active role's `profile_photo` document
/// is approved. While the current photo document is uploaded/pending/rejected,
/// hide the URL even if the backend profile row already has `profilePhotoUrl`
/// from upload confirmation. If there is no document row at all, fall back to
/// legacy profile URLs so existing approved/backfilled accounts keep their
/// avatar.
class ProviderProfilePhotoDisplay {
  const ProviderProfilePhotoDisplay({this.url, this.localFile});

  final String? url;
  final File? localFile;
}

final providerProfilePhotoDisplayProvider =
    Provider<ProviderProfilePhotoDisplay>((ref) {
  final role = ref.watch(providerTypeProvider);
  final roleValue = role.name;
  final verification = ref.watch(verificationStatusProvider).valueOrNull;
  final user = ref.watch(currentUserProvider);
  final isProviderFullyApproved =
      verification?.isProviderFullyApproved(roleValue) ??
          (role.isDriver
              ? user?.driverProfile?.verificationStatus == 'approved'
              : user?.artisanProfile?.verificationStatus == 'approved');
  final profilePhotoDoc = verification?.documentFor(
    DocumentType.profilePhoto.value,
    providerType: roleValue,
  );

  if (profilePhotoDoc != null) {
    final url = profilePhotoDoc.fileUrl;
    return ProviderProfilePhotoDisplay(
      url: profilePhotoDoc.isApproved && url != null && url.isNotEmpty
          ? url
          : null,
    );
  }

  if (!isProviderFullyApproved) {
    return const ProviderProfilePhotoDisplay();
  }

  final local = ref.watch(localProfilePhotoProvider);
  return ProviderProfilePhotoDisplay(
    url: user?.profilePhotoUrl ?? local.cloudinaryUrl,
    localFile: local.localFile,
  );
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
    return const ProfileCompletion(
        completed: 0, total: 1, missing: ['Sign in']);
  }

  // Backend document statuses — drives every doc-approval check below.
  final verificationAsync = ref.watch(verificationStatusProvider);
  final isLoadingDocs = verificationAsync.isLoading;
  final docs = verificationAsync.valueOrNull;
  final providerType = ref.watch(providerTypeProvider);
  final providerTypeValue = providerType.name;
  final isProviderFullyApproved =
      docs?.isProviderFullyApproved(providerTypeValue) ??
          (providerType.isDriver
              ? user.driverProfile?.verificationStatus == 'approved'
              : user.artisanProfile?.verificationStatus == 'approved');

  // An expired document no longer satisfies verification — the provider must
  // re-upload before it counts towards going online again. /verification/status
  // returns documents for every provider role on the user, so scope each lookup
  // to the active role to prevent Driver/Artisan document bleed.
  bool isDocApproved(DocumentType type) {
    final doc = docs?.documentFor(type.value, providerType: providerTypeValue);
    return isProviderFullyApproved &&
        doc != null &&
        doc.isApproved &&
        !doc.isExpired();
  }

  if (providerType.isDriver) {
    final dp = user.driverProfile;
    final items = <(bool, String)>[
      (user.fullName.isNotEmpty, 'Full name'),
      (isDocApproved(DocumentType.profilePhoto), 'Profile photo (approved)'),
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
      (isDocApproved(DocumentType.profilePhoto), 'Profile photo (approved)'),
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
