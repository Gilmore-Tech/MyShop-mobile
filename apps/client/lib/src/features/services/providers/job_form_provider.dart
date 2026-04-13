import 'package:flutter_riverpod/flutter_riverpod.dart';

// ── Job Form State ─────────────────────────────────────────────────────────────
// PRD 4.5 — Client fills out service request: category, title, description,
// photos, destination, and preferred timing (immediate or scheduled).
// API: POST /v1/jobs (EDD § Marketplace Endpoints)

class JobFormState {
  /// ID of the selected ServiceCategory (null = nothing chosen yet).
  final String? selectedCategoryId;

  /// Display name of the selected category (shown in the dropdown chip).
  final String? selectedCategoryName;

  /// Short job title entered by the client.
  final String title;

  /// Detailed description of the work required.
  final String description;

  /// Number of photos attached (local path list kept separately in UI layer).
  final int photoCount;

  /// Human-readable destination address (geocoded or typed).
  final String destinationAddress;

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
    this.photoCount = 0,
    this.destinationAddress = '',
    this.landmarkNote = '',
    this.isImmediate = true,
    this.scheduledFor,
    this.isSubmitting = false,
    this.errorMessage,
  });

  /// Form is ready to submit once the three required fields are filled.
  bool get canSubmit =>
      selectedCategoryId != null &&
      title.trim().isNotEmpty &&
      destinationAddress.trim().isNotEmpty &&
      !isSubmitting;

  JobFormState copyWith({
    String? selectedCategoryId,
    String? selectedCategoryName,
    String? title,
    String? description,
    int? photoCount,
    String? destinationAddress,
    String? landmarkNote,
    bool? isImmediate,
    DateTime? scheduledFor,
    bool? isSubmitting,
    String? errorMessage,
    bool clearError = false,
    bool clearSchedule = false,
  }) {
    return JobFormState(
      selectedCategoryId: selectedCategoryId ?? this.selectedCategoryId,
      selectedCategoryName: selectedCategoryName ?? this.selectedCategoryName,
      title: title ?? this.title,
      description: description ?? this.description,
      photoCount: photoCount ?? this.photoCount,
      destinationAddress: destinationAddress ?? this.destinationAddress,
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
  JobFormNotifier() : super(const JobFormState());

  void selectCategory(String id, String name) =>
      state = state.copyWith(selectedCategoryId: id, selectedCategoryName: name, clearError: true);

  void setTitle(String value) =>
      state = state.copyWith(title: value, clearError: true);

  void setDescription(String value) =>
      state = state.copyWith(description: value);

  void incrementPhotos() =>
      state = state.copyWith(photoCount: state.photoCount + 1);

  void setDestinationAddress(String value) =>
      state = state.copyWith(destinationAddress: value, clearError: true);

  void setLandmarkNote(String value) =>
      state = state.copyWith(landmarkNote: value);

  void setImmediate(bool value) {
    state = state.copyWith(
      isImmediate: value,
      clearSchedule: value, // clear scheduled_for when switching back to Now
    );
  }

  void setScheduledFor(DateTime dt) =>
      state = state.copyWith(scheduledFor: dt, isImmediate: false);

  /// Submits the job request to POST /v1/jobs.
  /// EDD: payload = { categoryId, title, description, photos[], lat, lng,
  ///                  scheduledFor? }
  Future<void> submit() async {
    if (!state.canSubmit) return;
    state = state.copyWith(isSubmitting: true, clearError: true);
    // TODO: replace with real POST /v1/jobs via API client
    await Future.delayed(const Duration(milliseconds: 800)); // simulate network
    state = state.copyWith(isSubmitting: false);
  }

  void reset() => state = const JobFormState();
}

// ── Provider ──────────────────────────────────────────────────────────────────

/// autoDispose — state resets automatically when the user leaves the form.
final jobFormProvider =
    StateNotifierProvider.autoDispose<JobFormNotifier, JobFormState>(
  (_) => JobFormNotifier(),
);
