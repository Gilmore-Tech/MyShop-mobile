import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/di/providers.dart';

// ── Profile Photo Local State ─────────────────────────────────────────────────
// Priority for display: localFile (instant) → cloudinaryUrl (persisted) → backend avatarUrl
//
// SharedPrefs keys use a 'client_' prefix so they don't clash with the
// provider app if both apps ever share the same device storage path.

const _kClientLocalPhotoPath = 'client_local_profile_photo_path';
const _kClientProfilePhotoUrl = 'client_profile_photo_url';

class ProfilePhotoState {
  const ProfilePhotoState({this.localFile, this.cloudinaryUrl});

  final File?   localFile;
  final String? cloudinaryUrl;
}

class LocalProfilePhotoNotifier extends StateNotifier<ProfilePhotoState> {
  LocalProfilePhotoNotifier() : super(const ProfilePhotoState()) {
    _restore();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final url   = prefs.getString(_kClientProfilePhotoUrl);
    final path  = prefs.getString(_kClientLocalPhotoPath);

    File? file;
    if (path != null) {
      final f = File(path);
      if (await f.exists()) {
        file = f;
      } else {
        await prefs.remove(_kClientLocalPhotoPath);
      }
    }

    if (url != null || file != null) {
      state = ProfilePhotoState(localFile: file, cloudinaryUrl: url);
    }
  }

  Future<void> setLocalFile(File? file) async {
    state = ProfilePhotoState(
      localFile:     file,
      cloudinaryUrl: state.cloudinaryUrl,
    );
    final prefs = await SharedPreferences.getInstance();
    if (file != null) {
      await prefs.setString(_kClientLocalPhotoPath, file.path);
    } else {
      await prefs.remove(_kClientLocalPhotoPath);
    }
  }

  Future<void> setCloudinaryUrl(String url) async {
    state = ProfilePhotoState(
      localFile:     state.localFile,
      cloudinaryUrl: url,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kClientProfilePhotoUrl, url);
  }

  Future<void> clear() async {
    state = const ProfilePhotoState();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kClientLocalPhotoPath);
    await prefs.remove(_kClientProfilePhotoUrl);
  }
}

final localProfilePhotoProvider =
    StateNotifierProvider<LocalProfilePhotoNotifier, ProfilePhotoState>((ref) {
  return LocalProfilePhotoNotifier();
});

// ── Document Upload State ─────────────────────────────────────────────────────

class DocumentUploadState {
  const DocumentUploadState({
    this.uploading  = const {},
    this.uploaded   = const {},
    this.remoteUrls = const {},
  });

  final Map<String, bool>   uploading;
  final Map<String, bool>   uploaded;
  final Map<String, String> remoteUrls;

  DocumentUploadState copyWith({
    Map<String, bool>?   uploading,
    Map<String, bool>?   uploaded,
    Map<String, String>? remoteUrls,
  }) =>
      DocumentUploadState(
        uploading:  uploading  ?? this.uploading,
        uploaded:   uploaded   ?? this.uploaded,
        remoteUrls: remoteUrls ?? this.remoteUrls,
      );
}

class DocumentUploadNotifier extends StateNotifier<DocumentUploadState> {
  DocumentUploadNotifier(this._service) : super(const DocumentUploadState());

  final VerificationService _service;

  Future<String?> upload({
    required String       providerType,
    required DocumentType documentType,
    required File         file,
  }) async {
    state = state.copyWith(
      uploading: {...state.uploading, documentType.value: true},
    );
    try {
      final result = await _service.uploadDocument(
        providerType: providerType,
        documentType: documentType,
        file: file,
      );
      state = state.copyWith(
        uploading: {...state.uploading, documentType.value: false},
        uploaded:  {...state.uploaded,  documentType.value: true},
        remoteUrls: {
          ...state.remoteUrls,
          if (result.remoteUrl != null) documentType.value: result.remoteUrl!,
        },
      );
      return null;
    } on ApiException catch (e) {
      state = state.copyWith(
        uploading: {...state.uploading, documentType.value: false},
      );
      return e.message;
    } catch (e) {
      state = state.copyWith(
        uploading: {...state.uploading, documentType.value: false},
      );
      return 'Upload failed. Please try again.';
    }
  }
}

final documentUploadProvider =
    StateNotifierProvider<DocumentUploadNotifier, DocumentUploadState>((ref) {
  return DocumentUploadNotifier(ref.watch(verificationServiceProvider));
});
