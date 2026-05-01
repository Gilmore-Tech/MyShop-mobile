import 'dart:developer' as developer;

import 'package:api_client/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import 'ride_receipt_provider.dart';

// ── Quick-feedback tags shown on the rating sheet ─────────────────────────────
// PRD 4.3 — client rates driver post-ride; tags feed the provider analytics dashboard.

const rideRatingTags = [
  'Clean Vehicle',
  'Safe Driving',
  'Professional',
  'Good Route',
];

// ── State ─────────────────────────────────────────────────────────────────────

class RideRatingState {
  /// 0 = nothing selected yet; 1–5 = star count.
  final int selectedStars;

  /// Multi-select tag set — any subset of [rideRatingTags].
  final Set<String> selectedTags;

  /// Optional free-text note to the driver.
  final String note;

  /// True while the POST /v1/ratings request is in-flight.
  final bool isSubmitting;

  /// True once the API has confirmed the rating saved.
  final bool isSubmitted;

  /// Surface for the sheet to render an inline error when submission fails.
  /// Cleared automatically when the user re-touches the form.
  final String? errorMessage;

  const RideRatingState({
    this.selectedStars = 0,
    this.selectedTags = const {},
    this.note = '',
    this.isSubmitting = false,
    this.isSubmitted = false,
    this.errorMessage,
  });

  bool get canSubmit => selectedStars > 0 && !isSubmitting && !isSubmitted;

  RideRatingState copyWith({
    int? selectedStars,
    Set<String>? selectedTags,
    String? note,
    bool? isSubmitting,
    bool? isSubmitted,
    String? errorMessage,
    bool clearError = false,
  }) {
    return RideRatingState(
      selectedStars: selectedStars ?? this.selectedStars,
      selectedTags: selectedTags ?? this.selectedTags,
      note: note ?? this.note,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      isSubmitted: isSubmitted ?? this.isSubmitted,
      errorMessage:
          clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class RideRatingNotifier extends StateNotifier<RideRatingState> {
  RideRatingNotifier(this._ref) : super(const RideRatingState());

  final Ref _ref;

  void setStars(int stars) =>
      state = state.copyWith(selectedStars: stars, clearError: true);

  void toggleTag(String tag) {
    final updated = Set<String>.from(state.selectedTags);
    if (updated.contains(tag)) {
      updated.remove(tag);
    } else {
      updated.add(tag);
    }
    state = state.copyWith(selectedTags: updated, clearError: true);
  }

  void setNote(String note) =>
      state = state.copyWith(note: note, clearError: true);

  /// Submits the rating to POST /v1/ratings (EDD § Other REST Endpoints).
  /// Blind 24-hour window: reveal cron runs every 15 minutes (EDD § Rating Module).
  ///
  /// Returns `true` on success so callers can decide whether to dismiss the
  /// sheet vs. keep it open for the user to fix the error.
  Future<bool> submit(String rideId) async {
    if (!state.canSubmit) return false;
    state = state.copyWith(isSubmitting: true, clearError: true);

    try {
      final ratingService = _ref.read(ratingServiceProvider);
      await ratingService.submitRating(
        bookingType: 'ride',
        bookingId: rideId,
        stars: state.selectedStars,
        comment: state.note.isNotEmpty ? state.note : null,
      );
      developer.log('Rating submitted for ride $rideId', name: 'RideRating');
      // Bust the cached ride receipt so any backend rollups that ride on
      // the same fetch land on the next visit. Blind 24-hour window means
      // the rating average won't move for the rater, but anything else on
      // the page should refresh.
      _ref.invalidate(rideReceiptByIdProvider(rideId));
      state = state.copyWith(isSubmitting: false, isSubmitted: true);
      return true;
    } on ApiException catch (e) {
      developer.log(
        'submitRating failed (${e.statusCode}): ${e.message}',
        name: 'RideRating',
      );
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: _friendlyError(e),
      );
      return false;
    } catch (e) {
      developer.log('submitRating error: $e', name: 'RideRating');
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: "Couldn't submit your rating. Please try again.",
      );
      return false;
    }
  }

  /// Maps the backend's structured error codes for `POST /v1/ratings` into
  /// messages a passenger can act on. Mirror of the artisan-side mapper in
  /// [RatingNotifier] so both rating surfaces speak the same language.
  String _friendlyError(ApiException e) {
    switch (e.errorCode) {
      case 'BOOKING_NOT_COMPLETED':
        return 'The trip is still being finalized. Wait a moment and try '
            'again — you can also rate later from your Activity.';
      case 'ALREADY_RATED':
        return "You've already rated this trip.";
      case 'RATING_WINDOW_CLOSED':
        return 'The rating window for this trip has closed.';
      default:
        return e.message.isNotEmpty
            ? e.message
            : "Couldn't submit your rating. Please try again.";
    }
  }

  void reset() => state = const RideRatingState();
}

// ── Provider ──────────────────────────────────────────────────────────────────

/// autoDispose so state resets automatically when the sheet is dismissed.
final rideRatingProvider =
    StateNotifierProvider.autoDispose<RideRatingNotifier, RideRatingState>(
  (ref) => RideRatingNotifier(ref),
);
