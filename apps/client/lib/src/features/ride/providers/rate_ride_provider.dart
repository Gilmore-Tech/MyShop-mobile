import 'dart:developer' as developer;

import 'package:api_client/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';

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

  const RideRatingState({
    this.selectedStars = 0,
    this.selectedTags = const {},
    this.note = '',
    this.isSubmitting = false,
  });

  bool get canSubmit => selectedStars > 0 && !isSubmitting;

  RideRatingState copyWith({
    int? selectedStars,
    Set<String>? selectedTags,
    String? note,
    bool? isSubmitting,
  }) {
    return RideRatingState(
      selectedStars: selectedStars ?? this.selectedStars,
      selectedTags: selectedTags ?? this.selectedTags,
      note: note ?? this.note,
      isSubmitting: isSubmitting ?? this.isSubmitting,
    );
  }
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class RideRatingNotifier extends StateNotifier<RideRatingState> {
  RideRatingNotifier(this._ref) : super(const RideRatingState());

  final Ref _ref;

  void setStars(int stars) => state = state.copyWith(selectedStars: stars);

  void toggleTag(String tag) {
    final updated = Set<String>.from(state.selectedTags);
    if (updated.contains(tag)) {
      updated.remove(tag);
    } else {
      updated.add(tag);
    }
    state = state.copyWith(selectedTags: updated);
  }

  void setNote(String note) => state = state.copyWith(note: note);

  /// Submits the rating to POST /v1/ratings (EDD § Other REST Endpoints).
  /// Blind 24-hour window: reveal cron runs every 15 minutes (EDD § Rating Module).
  Future<void> submit(String rideId) async {
    if (!state.canSubmit) return;
    state = state.copyWith(isSubmitting: true);

    try {
      final ratingService = _ref.read(ratingServiceProvider);
      await ratingService.submitRating(
        bookingType: 'ride',
        bookingId: rideId,
        stars: state.selectedStars,
        comment: state.note.isNotEmpty ? state.note : null,
      );
      developer.log('Rating submitted for ride $rideId', name: 'RideRating');
    } on ApiException catch (e) {
      developer.log(
        'submitRating failed (${e.statusCode}): ${e.message}',
        name: 'RideRating',
      );
      // Swallow the error — rating can be retried or the blind window will
      // close without a rating, which is acceptable per PRD § 9.4.
    } catch (e) {
      developer.log('submitRating error: $e', name: 'RideRating');
    }

    state = state.copyWith(isSubmitting: false);
  }

  void reset() => state = const RideRatingState();
}

// ── Provider ──────────────────────────────────────────────────────────────────

/// autoDispose so state resets automatically when the sheet is dismissed.
final rideRatingProvider =
    StateNotifierProvider.autoDispose<RideRatingNotifier, RideRatingState>(
  (ref) => RideRatingNotifier(ref),
);
