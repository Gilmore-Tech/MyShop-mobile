import 'package:api_client/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';

// ── Job Form State ─────────────────────────────────────────────────────────────
// PRD 4.5 — Client fills out service request: category, title, description,
// photos and destination. New scheduled obligations are release-contained;
// existing scheduled jobs remain visible/manageable elsewhere in the app.
// API: POST /v1/jobs (EDD § Marketplace Endpoints)

/// Maximum number of photos a client can attach to a job request.
const int kMaxJobPhotos = 4;

/// Approved emergency-release containment. The backend independently enforces
/// the same default-off boundary for old or modified clients.
const bool kScheduledJobCreationEnabled = false;

const outsideJobServiceAreaMessage =
    'Artisan services are not available at this job location yet. '
    'Choose a job location inside an active MyShop service area.';

String jobCreationErrorMessage(ApiException error) {
  return switch (error.errorCode?.trim().toUpperCase()) {
    'OUTSIDE_SERVICE_AREA' => outsideJobServiceAreaMessage,
    'INVALID_CATEGORY' =>
      'This artisan service is not available at the selected job location. '
          'Choose another service or job location.',
    _ => userSafeApiErrorMessage(
        error,
        fallback: 'Failed to submit the request. Please try again.',
        validationMessage:
            'Check the job details and location, then try again.',
      ),
  };
}

class JobFormState {
  /// ID of the selected ServiceCategory (null = nothing chosen yet).
  final String? selectedCategoryId;

  /// Display name of the selected category (shown in the dropdown chip).
  final String? selectedCategoryName;

  /// Short job title entered by the client.
  final String title;

  /// Detailed description of the work required.
  final String description;

  /// Local file paths of attached photos (max [kMaxJobPhotos]).
  final List<String> photoPaths;

  /// Human-readable destination address (geocoded or typed).
  final String destinationAddress;

  /// Latitude of the selected job location (from Places or map pin).
  final double? latitude;

  /// Longitude of the selected job location (from Places or map pin).
  final double? longitude;

  /// Optional landmark / additional direction hint.
  final String landmarkNote;

  /// true = "Now" (immediate), false = "Later" (scheduled).
  final bool isImmediate;

  /// Only relevant when [isImmediate] is false.
  final DateTime? scheduledFor;

  /// True while POST /v1/jobs is in-flight.
  final bool isSubmitting;

  /// Non-null when the last submit attempt failed.
  final String? errorMessage;

  const JobFormState({
    this.selectedCategoryId,
    this.selectedCategoryName,
    this.title = '',
    this.description = '',
    this.photoPaths = const [],
    this.destinationAddress = '',
    this.latitude,
    this.longitude,
    this.landmarkNote = '',
    this.isImmediate = true,
    this.scheduledFor,
    this.isSubmitting = false,
    this.errorMessage,
  });

  int get photoCount => photoPaths.length;
  int get photoSlotsLeft => kMaxJobPhotos - photoPaths.length;
  bool get canAddPhoto => photoSlotsLeft > 0;

  /// Form is ready to submit once the required fields are filled.
  /// Photos and landmark note are optional.
  bool get canSubmit =>
      selectedCategoryId != null &&
      title.trim().isNotEmpty &&
      description.trim().isNotEmpty &&
      destinationAddress.trim().isNotEmpty &&
      latitude != null &&
      longitude != null &&
      !isSubmitting;

  JobFormState copyWith({
    String? selectedCategoryId,
    String? selectedCategoryName,
    String? title,
    String? description,
    List<String>? photoPaths,
    String? destinationAddress,
    double? latitude,
    double? longitude,
    String? landmarkNote,
    bool? isImmediate,
    DateTime? scheduledFor,
    bool? isSubmitting,
    String? errorMessage,
    bool clearError = false,
    bool clearSchedule = false,
    bool clearLocation = false,
  }) {
    return JobFormState(
      selectedCategoryId: selectedCategoryId ?? this.selectedCategoryId,
      selectedCategoryName: selectedCategoryName ?? this.selectedCategoryName,
      title: title ?? this.title,
      description: description ?? this.description,
      photoPaths: photoPaths ?? this.photoPaths,
      destinationAddress: destinationAddress ?? this.destinationAddress,
      latitude: clearLocation ? null : (latitude ?? this.latitude),
      longitude: clearLocation ? null : (longitude ?? this.longitude),
      landmarkNote: landmarkNote ?? this.landmarkNote,
      isImmediate: isImmediate ?? this.isImmediate,
      scheduledFor: clearSchedule ? null : (scheduledFor ?? this.scheduledFor),
      isSubmitting: isSubmitting ?? this.isSubmitting,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class JobFormNotifier extends StateNotifier<JobFormState> {
  JobFormNotifier(this._jobService, this._mediaService)
      : super(const JobFormState());

  final JobService _jobService;
  final MediaService _mediaService;

  void selectCategory(String id, String name) => state = state.copyWith(
      selectedCategoryId: id, selectedCategoryName: name, clearError: true);

  void setTitle(String value) =>
      state = state.copyWith(title: value, clearError: true);

  void setDescription(String value) =>
      state = state.copyWith(description: value);

  /// Append [paths] up to [kMaxJobPhotos]. Extras silently dropped.
  void addPhotos(List<String> paths) {
    final room = state.photoSlotsLeft;
    if (room <= 0 || paths.isEmpty) return;
    final toAdd = paths.take(room).toList();
    state = state.copyWith(
      photoPaths: [...state.photoPaths, ...toAdd],
    );
  }

  void removePhotoAt(int index) {
    if (index < 0 || index >= state.photoPaths.length) return;
    final next = [...state.photoPaths]..removeAt(index);
    state = state.copyWith(photoPaths: next);
  }

  void setDestinationAddress(String value) =>
      state = state.copyWith(destinationAddress: value, clearError: true);

  /// Set the full location from Places autocomplete or map pin picker.
  void setLocation({
    required String address,
    required double latitude,
    required double longitude,
  }) {
    state = state.copyWith(
      destinationAddress: address,
      latitude: latitude,
      longitude: longitude,
      clearError: true,
    );
  }

  void setLandmarkNote(String value) =>
      state = state.copyWith(landmarkNote: value);

  void setImmediate(bool value) {
    state = state.copyWith(
      isImmediate: kScheduledJobCreationEnabled ? value : true,
      clearSchedule: !kScheduledJobCreationEnabled || value,
    );
  }

  void setScheduledFor(DateTime dt) {
    if (!kScheduledJobCreationEnabled) {
      state = state.copyWith(isImmediate: true, clearSchedule: true);
      return;
    }
    state = state.copyWith(scheduledFor: dt, isImmediate: false);
  }

  /// Submits the job request to POST /v1/jobs and returns the new job id on
  /// success (or null on failure / invalid state).
  /// EDD: payload = { categoryId, description, latitude, longitude,
  ///                  addressText?, scheduledFor? }
  Future<String?> submit() async {
    if (!state.canSubmit) return null;
    state = state.copyWith(isSubmitting: true, clearError: true);
    try {
      // Upload photos first (if any)
      List<String>? photoUrls;
      if (state.photoPaths.isNotEmpty) {
        photoUrls = await Future.wait(
          state.photoPaths.map((path) => _mediaService.uploadJobPhoto(path)),
        );
      }

      // Use only the location explicitly selected in this form. The client's
      // device may be outside the service area while they book for somebody
      // elsewhere, so the phone's current fix must not replace this address.
      final result = await _jobService.createJob(
        categoryId: state.selectedCategoryId!,
        description: '${state.title}\n\n${state.description}',
        latitude: state.latitude!,
        longitude: state.longitude!,
        addressText: state.destinationAddress,
        scheduledFor: kScheduledJobCreationEnabled && !state.isImmediate
            ? state.scheduledFor?.toIso8601String()
            : null,
        photoUrls: photoUrls,
      );
      state = state.copyWith(isSubmitting: false);
      return result['jobId'] as String?;
    } on ApiException catch (e) {
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: jobCreationErrorMessage(e),
      );
      return null;
    } catch (_) {
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: 'Failed to submit request. Please try again.',
      );
      return null;
    }
  }

  void reset() => state = const JobFormState();
}

// ── Provider ──────────────────────────────────────────────────────────────────

/// autoDispose — state resets automatically when the user leaves the form.
final jobFormProvider =
    StateNotifierProvider.autoDispose<JobFormNotifier, JobFormState>(
  (ref) => JobFormNotifier(
    ref.watch(jobServiceProvider),
    ref.watch(mediaServiceProvider),
  ),
);
