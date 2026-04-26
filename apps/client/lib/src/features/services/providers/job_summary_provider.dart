import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:api_client/api_client.dart';

import '../../../core/di/providers.dart';

// ── Artisan (job summary context) ─────────────────────────────────────────────
// Subset of provider profile needed for the post-completion summary screen.

class JobSummaryArtisan {
  final String artisanId;
  final String name;
  final String firstName;

  /// Role label, e.g. "Master Electrician".
  final String role;

  /// Formatted experience, e.g. "8+ Years".
  final String experienceLabel;

  final Color avatarColor;
  final bool isVerified;

  /// Overall lifetime rating (1.0 – 5.0).
  final double rating;

  final int reviewCount;

  /// Neighbourhood / area name shown under the artisan card.
  final String location;

  const JobSummaryArtisan({
    required this.artisanId,
    required this.name,
    required this.firstName,
    required this.role,
    required this.experienceLabel,
    required this.avatarColor,
    required this.isVerified,
    required this.rating,
    required this.reviewCount,
    required this.location,
  });
}

// ── Job Summary Data ──────────────────────────────────────────────────────────
// API: GET /v1/jobs/:id  (after dual confirmation / auto-finalization)
// Money fields are in pesewas (int) per EDD § Money Storage rules.
// totalPaidPesewas is the agreed price including any approved supplement;
// the 20% commission is deducted from the artisan payout — not added here.

class JobSummaryData {
  final String jobId;

  /// Formatted reference shown in the summary card, e.g. "#JOB-29384".
  final String jobRef;

  final JobSummaryArtisan artisan;

  /// Labour portion of the agreed bid (pesewas).
  final int laborChargePesewas;

  /// Materials portion of the agreed bid (pesewas).
  final int materialCostPesewas;

  /// Total the client was charged (pesewas); equals agreed bid price.
  final int totalPaidPesewas;

  /// True when a tip was added — used to show the "No commission on tip" note.
  final bool tipIncluded;

  const JobSummaryData({
    required this.jobId,
    required this.jobRef,
    required this.artisan,
    required this.laborChargePesewas,
    required this.materialCostPesewas,
    required this.totalPaidPesewas,
    this.tipIncluded = false,
  });

  String _fmt(int pesewas) => 'GHS ${(pesewas / 100).toStringAsFixed(2)}';

  String get laborChargeDisplay    => _fmt(laborChargePesewas);
  String get materialCostDisplay   => _fmt(materialCostPesewas);
  String get totalPaidDisplay      => _fmt(totalPaidPesewas);
}

// ── Rating State ──────────────────────────────────────────────────────────────
// PRD 4.8 / EDD § Rating Module:
//   POST /v1/ratings  { bookingType: "job", bookingId, rating, comment? }
//   Blind 24-hour window — rating is only visible once the artisan also rates
//   or the window closes.  Prevents retaliatory ratings.

class RatingState {
  /// 0 = nothing selected; 1–5 = star count.
  final int selectedStars;
  final String reviewText;
  final bool isSubmitting;

  /// True once the API call succeeds; used to show a success banner and
  /// disable re-submission.
  final bool isSubmitted;

  final String? errorMessage;

  const RatingState({
    this.selectedStars = 0,
    this.reviewText    = '',
    this.isSubmitting  = false,
    this.isSubmitted   = false,
    this.errorMessage,
  });

  /// "Submit & Finish" is enabled only when at least one star is selected.
  bool get canSubmit => selectedStars > 0 && !isSubmitting && !isSubmitted;

  RatingState copyWith({
    int?    selectedStars,
    String? reviewText,
    bool?   isSubmitting,
    bool?   isSubmitted,
    String? errorMessage,
    bool    clearError = false,
  }) =>
      RatingState(
        selectedStars: selectedStars ?? this.selectedStars,
        reviewText:    reviewText    ?? this.reviewText,
        isSubmitting:  isSubmitting  ?? this.isSubmitting,
        isSubmitted:   isSubmitted   ?? this.isSubmitted,
        errorMessage:
            clearError ? null : (errorMessage ?? this.errorMessage),
      );
}

// ── Rating Notifier ───────────────────────────────────────────────────────────

class RatingNotifier extends StateNotifier<RatingState> {
  RatingNotifier(this._ratingService) : super(const RatingState());

  final RatingService _ratingService;

  void selectStars(int stars) =>
      state = state.copyWith(selectedStars: stars, clearError: true);

  void updateReview(String text) =>
      state = state.copyWith(reviewText: text);

  /// Submits the blind rating.
  /// POST /v1/ratings  { bookingType: "job", bookingId, rating, comment? }
  ///
  /// Returns `true` on success so the caller (sheet, screen) can decide
  /// whether to dismiss UI or keep the form open for the user to retry.
  Future<bool> submitRating({required String jobId}) async {
    if (!state.canSubmit) return false;
    state = state.copyWith(isSubmitting: true, clearError: true);
    try {
      await _ratingService.submitRating(
        bookingType: 'job',
        bookingId: jobId,
        stars: state.selectedStars,
        comment: state.reviewText.isNotEmpty ? state.reviewText : null,
      );
      state = state.copyWith(isSubmitting: false, isSubmitted: true);
      return true;
    } on ApiException catch (e) {
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: e.message.isNotEmpty
            ? e.message
            : "Couldn't submit your rating. Please try again.",
      );
      return false;
    } catch (_) {
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: "Couldn't submit your rating. Please try again.",
      );
      return false;
    }
  }
}

final jobRatingProvider =
    StateNotifierProvider.autoDispose<RatingNotifier, RatingState>(
  (ref) => RatingNotifier(ref.watch(ratingServiceProvider)),
);

// ── Job Summary Provider ──────────────────────────────────────────────────────

final jobSummaryProvider = AsyncNotifierProvider.autoDispose
    .family<_JobSummaryNotifier, JobSummaryData, String>(
  _JobSummaryNotifier.new,
);

class _JobSummaryNotifier
    extends AutoDisposeFamilyAsyncNotifier<JobSummaryData, String> {
  @override
  Future<JobSummaryData> build(String jobId) async {
    try {
      final jobService = ref.watch(jobServiceProvider);
      final data = await jobService.getJob(jobId);
      return _parseJobSummary(data);
    } catch (_) {
      // Fallback to mock during development / if endpoint not ready
      return _mockJobs[jobId] ?? _defaultMockJob;
    }
  }

  /// Parse API response into [JobSummaryData].
  JobSummaryData _parseJobSummary(Map<String, dynamic> data) {
    final artisanData = data['provider'] as Map<String, dynamic>? ?? {};
    final costBreakdown = data['costBreakdown'] as Map<String, dynamic>? ?? {};
    final bidData = data['selectedBid'] as Map<String, dynamic>? ?? {};

    final artisanName = '${artisanData['firstName'] ?? ''} ${artisanData['lastName'] ?? ''}'.trim();
    final laborPesewas = (costBreakdown['laborPesewas'] as num?)?.toInt()
        ?? (bidData['amountPesewas'] as num?)?.toInt()
        ?? 0;
    final materialPesewas = (costBreakdown['materialsPesewas'] as num?)?.toInt() ?? 0;
    final totalPesewas = (data['totalPesewas'] as num?)?.toInt()
        ?? laborPesewas + materialPesewas;

    return JobSummaryData(
      jobId: data['id'] as String? ?? '',
      jobRef: '#${data['id'] ?? ''}',
      artisan: JobSummaryArtisan(
        artisanId: artisanData['id'] as String? ?? '',
        name: artisanName.isNotEmpty ? artisanName : 'Artisan',
        firstName: artisanData['firstName'] as String? ?? 'Artisan',
        role: artisanData['specialty'] as String? ?? '',
        experienceLabel: artisanData['experienceLabel'] as String? ?? '',
        avatarColor: MyShopColors.darkSlate,
        isVerified: artisanData['isVerified'] as bool? ?? false,
        rating: (artisanData['rating'] as num?)?.toDouble() ?? 0.0,
        reviewCount: (artisanData['reviewCount'] as num?)?.toInt() ?? 0,
        location: artisanData['location'] as String? ?? '',
      ),
      laborChargePesewas: laborPesewas,
      materialCostPesewas: materialPesewas,
      totalPaidPesewas: totalPesewas,
      tipIncluded: data['tipIncluded'] as bool? ?? false,
    );
  }
}

// ── Mock data ─────────────────────────────────────────────────────────────────

const _mockArtisan = JobSummaryArtisan(
  artisanId:       'ART-101',
  name:            'Kofi Mensah',
  firstName:       'Kofi',
  role:            'Master Electrician',
  experienceLabel: '8+ Years',
  avatarColor:     MyShopColors.darkSlate,
  isVerified:      true,
  rating:          4.9,
  reviewCount:     324,
  location:        'Bantama',
);

const _defaultMockJob = JobSummaryData(
  jobId:               'JOB-29384',
  jobRef:              '#JOB-29384',
  artisan:             _mockArtisan,
  laborChargePesewas:  25000,   // GHS 250.00
  materialCostPesewas: 12000,   // GHS 120.00
  totalPaidPesewas:    40000,   // GHS 400.00 (includes supplement)
  tipIncluded:         false,
);

const Map<String, JobSummaryData> _mockJobs = {};
