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

// ── Profile Photo Upload ──────────────────────────────────────────────────────
//
// Drives the 4-step client profile-photo flow:
//   1. POST /media/upload-url      (purpose: 'profile_photo')
//   2. PUT/POST to the storage URL (Cloudinary or S3)
//   3. POST /media/confirm
//   4. POST /users/me/profile-photo  ← persists the URL on Client row
//
// Steps 1–3 are wrapped in [MediaService.uploadProfilePhoto].
// Step 4 lives on [UserService.updateClientProfilePhoto].

class ProfilePhotoUploadState {
  const ProfilePhotoUploadState({
    this.isUploading = false,
    this.remoteUrl,
  });

  final bool    isUploading;
  final String? remoteUrl;

  ProfilePhotoUploadState copyWith({
    bool?   isUploading,
    String? remoteUrl,
    bool    clearRemoteUrl = false,
  }) =>
      ProfilePhotoUploadState(
        isUploading: isUploading ?? this.isUploading,
        remoteUrl:   clearRemoteUrl ? null : (remoteUrl ?? this.remoteUrl),
      );
}

class ProfilePhotoUploadNotifier
    extends StateNotifier<ProfilePhotoUploadState> {
  ProfilePhotoUploadNotifier(this._media, this._user)
      : super(const ProfilePhotoUploadState());

  final MediaService _media;
  final UserService  _user;

  /// Returns `null` on success and the final hosted URL via
  /// [ProfilePhotoUploadState.remoteUrl]. On failure returns a user-facing
  /// error message; UI surfaces it as a toast and clears the local preview.
  ///
  /// Guards every state write with [mounted] — the upload spans seconds of
  /// network I/O, and even though the provider is no longer autoDispose,
  /// a future logout/reset could still tear the notifier down mid-flight.
  Future<String?> upload(File file) async {
    if (!mounted) return 'Upload cancelled.';
    state = state.copyWith(isUploading: true, clearRemoteUrl: true);
    try {
      // Steps 1–3: upload bytes via /media/* and get back the final URL.
      final remoteUrl = await _media.uploadProfilePhoto(file.path);

      // Step 4: persist the URL onto the Client row server-side.
      await _user.updateClientProfilePhoto(profilePhotoUrl: remoteUrl);

      if (!mounted) return null;
      state = state.copyWith(isUploading: false, remoteUrl: remoteUrl);
      return null;
    } on ApiException catch (e) {
      if (mounted) state = state.copyWith(isUploading: false);
      return e.message.isNotEmpty
          ? e.message
          : 'Upload failed. Please try again.';
    } catch (_) {
      if (mounted) state = state.copyWith(isUploading: false);
      return 'Upload failed. Please try again.';
    }
  }
}

// NOT autoDispose — the upload is `ref.read`-only (the screen never watches
// the notifier directly), so an autoDispose provider would tear down the
// moment the read returns and the asynchronous state writes that come back
// seconds later would crash with `Tried to use after dispose`.
final profilePhotoUploadProvider = StateNotifierProvider<
    ProfilePhotoUploadNotifier, ProfilePhotoUploadState>(
  (ref) => ProfilePhotoUploadNotifier(
    ref.watch(mediaServiceProvider),
    ref.watch(userServiceProvider),
  ),
);
