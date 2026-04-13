import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../auth/providers/current_user_provider.dart';

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
  /// Returns null on success, or an error message on failure.
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
      await _service.uploadDocument(
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
    } catch (_) {
      state = state.copyWith(
        uploading: {
          ...state.uploading,
          documentType.value: false,
        },
      );
      return 'Upload failed. Please try again.';
    }
  }

  bool isUploading(String docType) => state.uploading[docType] == true;
  bool wasUploaded(String docType) => state.uploaded[docType] == true;
}

class DocumentUploadState {
  const DocumentUploadState({
    this.uploading = const {},
    this.uploaded = const {},
  });

  /// docType → true while uploading
  final Map<String, bool> uploading;

  /// docType → true after successful upload in this session
  final Map<String, bool> uploaded;

  DocumentUploadState copyWith({
    Map<String, bool>? uploading,
    Map<String, bool>? uploaded,
  }) {
    return DocumentUploadState(
      uploading: uploading ?? this.uploading,
      uploaded: uploaded ?? this.uploaded,
    );
  }
}

final documentUploadProvider =
    StateNotifierProvider<DocumentUploadNotifier, DocumentUploadState>((ref) {
  return DocumentUploadNotifier(ref.watch(verificationServiceProvider));
});

// ─── Profile Completion ─────────────────────────────────────────────────────

/// Computes the profile completion percentage from real user data.
/// Returns a value between 0.0 and 1.0.
final profileCompletionProvider = Provider<ProfileCompletion>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return const ProfileCompletion(completed: 0, total: 1);

  if (user.isDriver) {
    final dp = user.driverProfile;
    final checks = <bool>[
      user.fullName.isNotEmpty,
      dp?.profilePhotoUrl != null,
      dp?.vehicleMake != null,
      dp?.ghanaCardVerified == true,
      dp?.kycStatus == 'verified',
      dp?.policeCheckStatus == 'clear',
      dp?.licenceNumber != null,
    ];
    return ProfileCompletion(
      completed: checks.where((c) => c).length,
      total: checks.length,
    );
  } else {
    final ap = user.artisanProfile;
    final checks = <bool>[
      user.fullName.isNotEmpty,
      ap?.profilePhotoUrl != null,
      ap?.serviceCategories != null && ap!.serviceCategories!.isNotEmpty,
      ap?.ghanaCardVerified == true,
      ap?.kycStatus == 'verified',
      ap?.policeCheckStatus == 'clear',
    ];
    return ProfileCompletion(
      completed: checks.where((c) => c).length,
      total: checks.length,
    );
  }
});

class ProfileCompletion {
  const ProfileCompletion({required this.completed, required this.total});

  final int completed;
  final int total;

  double get progress => total == 0 ? 0 : completed / total;
  int get percentage => (progress * 100).round();
  bool get isComplete => completed == total;
}
