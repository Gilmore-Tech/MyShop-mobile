import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';

// ── Bid Status ────────────────────────────────────────────────────────────────

enum BidStatus { pendingReview, awaitingConfirmation, accepted, declined }

extension BidStatusX on BidStatus {
  String get label => switch (this) {
        BidStatus.pendingReview        => 'Pending Review',
        BidStatus.awaitingConfirmation => 'Awaiting Confirmation',
        BidStatus.accepted             => 'Accepted',
        BidStatus.declined             => 'Declined',
      };

  Color get color => switch (this) {
        BidStatus.pendingReview        => MyShopColors.warning,
        BidStatus.awaitingConfirmation => MyShopColors.primaryGold,
        BidStatus.accepted             => MyShopColors.success,
        BidStatus.declined             => MyShopColors.error,
      };
}

// ── Material Line Item ────────────────────────────────────────────────────────

class MaterialLineItem {
  final String name;
  const MaterialLineItem({required this.name});
}

// ── Bid Breakdown ─────────────────────────────────────────────────────────────
// Bid is a single total amount covering labour + estimated materials (PRD 4.5.2).
// Platform adds a transaction VAT on top.

class BidBreakdown {
  /// Labour / service fee in pesewas.
  final int serviceFeePesewas;

  /// Estimated materials cost in pesewas.
  final int materialsFeePesewas;

  /// Individual material items shown in the expandable row.
  final List<MaterialLineItem> materialItems;

  /// VAT percentage applied as a decimal, e.g. 0.04 for 4%.
  final double vatRate;

  const BidBreakdown({
    required this.serviceFeePesewas,
    required this.materialsFeePesewas,
    required this.materialItems,
    this.vatRate = 0.04,
  });

  int get vatPesewas =>
      ((serviceFeePesewas + materialsFeePesewas) * vatRate).round();

  int get totalPesewas =>
      serviceFeePesewas + materialsFeePesewas + vatPesewas;

  String _fmt(int pesewas) =>
      'GHS ${(pesewas / 100).toStringAsFixed(2)}';

  String get serviceFeeDisplay  => _fmt(serviceFeePesewas);
  String get materialsFeeDisplay => _fmt(materialsFeePesewas);
  String get vatDisplay          => _fmt(vatPesewas);
  String get totalDisplay        => _fmt(totalPesewas);
  String get vatPercent          => '${(vatRate * 100).toStringAsFixed(0)}%';
}

// ── Artisan Profile (bid context) ─────────────────────────────────────────────

class BidArtisanProfile {
  final String artisanId;
  final String name;
  final String firstName;
  final String tradeTitle;
  final int yearsExperience;
  final double rating;
  final int reviewCount;
  final bool isKycVerified;
  final bool isVetted;

  /// Placeholder colour for avatar until real network images are wired.
  final Color avatarColor;

  /// Neighbourhood name used as the artisan's base location.
  final String baseName;

  /// Estimated travel time to the job site in minutes.
  final int etaMinutes;

  /// Distance from artisan to job site in kilometres.
  final double distanceKm;

  const BidArtisanProfile({
    required this.artisanId,
    required this.name,
    required this.firstName,
    required this.tradeTitle,
    required this.yearsExperience,
    required this.rating,
    required this.reviewCount,
    required this.isKycVerified,
    required this.isVetted,
    required this.avatarColor,
    required this.baseName,
    required this.etaMinutes,
    required this.distanceKm,
  });
}

// ── Bid Detail ────────────────────────────────────────────────────────────────
// Full detail for a single artisan bid as viewed by the client.
// API: GET /v1/jobs/:id/bids (EDD § Marketplace Endpoints)

class BidDetail {
  final String bidId;
  final String jobId;
  final BidStatus status;
  final BidArtisanProfile artisan;
  final BidBreakdown breakdown;

  /// Human-readable duration estimate from the artisan.
  final String durationLabel;

  /// Human-readable availability, e.g. "Today, 2PM".
  final String availabilityLabel;

  /// Free-text note the artisan included with their bid.
  final String? artisanNote;

  /// Timestamp of the artisan's note.
  final String? noteTimestamp;

  /// Placeholder colours for portfolio photo cards.
  final List<Color> portfolioColors;

  const BidDetail({
    required this.bidId,
    required this.jobId,
    required this.status,
    required this.artisan,
    required this.breakdown,
    required this.durationLabel,
    required this.availabilityLabel,
    this.artisanNote,
    this.noteTimestamp,
    required this.portfolioColors,
  });
}

// ── Bid Detail Action State ───────────────────────────────────────────────────

class BidDetailActionState {
  final bool isAccepting;
  final bool isDeclining;
  final bool materialItemsExpanded;
  final String? errorMessage;

  /// True once the client has sent acceptance and is waiting for artisan to confirm.
  final bool isAwaitingConfirmation;

  /// When the artisan confirmation window expires (set after accept succeeds).
  final DateTime? countdownEndTime;

  /// True once the artisan has confirmed the job (WebSocket push in production).
  final bool isBidConfirmed;

  /// Human-readable ETA shown in the confirmed banner, e.g. "~18 mins (2:30 PM)".
  final String? confirmedEtaLabel;

  /// True when the 20-min window elapsed with no artisan confirmation.
  final bool isBidExpired;

  /// Human-readable expiry date shown in the expired banner, e.g. "Oct 24, 2023".
  final String? expiredDateLabel;

  const BidDetailActionState({
    this.isAccepting = false,
    this.isDeclining = false,
    this.materialItemsExpanded = false,
    this.errorMessage,
    this.isAwaitingConfirmation = false,
    this.countdownEndTime,
    this.isBidConfirmed = false,
    this.confirmedEtaLabel,
    this.isBidExpired = false,
    this.expiredDateLabel,
  });

  bool get isBusy => isAccepting || isDeclining;

  BidDetailActionState copyWith({
    bool? isAccepting,
    bool? isDeclining,
    bool? materialItemsExpanded,
    String? errorMessage,
    bool clearError = false,
    bool? isAwaitingConfirmation,
    DateTime? countdownEndTime,
    bool? isBidConfirmed,
    String? confirmedEtaLabel,
    bool? isBidExpired,
    String? expiredDateLabel,
  }) =>
      BidDetailActionState(
        isAccepting: isAccepting ?? this.isAccepting,
        isDeclining: isDeclining ?? this.isDeclining,
        materialItemsExpanded:
            materialItemsExpanded ?? this.materialItemsExpanded,
        errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
        isAwaitingConfirmation:
            isAwaitingConfirmation ?? this.isAwaitingConfirmation,
        countdownEndTime: countdownEndTime ?? this.countdownEndTime,
        isBidConfirmed: isBidConfirmed ?? this.isBidConfirmed,
        confirmedEtaLabel: confirmedEtaLabel ?? this.confirmedEtaLabel,
        isBidExpired: isBidExpired ?? this.isBidExpired,
        expiredDateLabel: expiredDateLabel ?? this.expiredDateLabel,
      );
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class BidDetailNotifier extends StateNotifier<BidDetailActionState> {
  BidDetailNotifier(this._jobService) : super(const BidDetailActionState());

  final JobService _jobService;

  void toggleMaterials() => state = state.copyWith(
        materialItemsExpanded: !state.materialItemsExpanded,
      );

  /// Accepts the bid — PATCH /v1/jobs/:jobId/select-bid  (EDD § Marketplace)
  /// PRD 4.5: job enters awaitingConfirmation; artisan has 20 min to respond.
  Future<void> acceptBid({required String jobId, required String bidId}) async {
    if (state.isBusy) return;
    state = state.copyWith(isAccepting: true, clearError: true);
    try {
      await _jobService.selectBid(jobId, bidId: bidId);
      state = state.copyWith(
        isAccepting: false,
        isAwaitingConfirmation: true,
        countdownEndTime: DateTime.now().add(const Duration(minutes: 5)),
      );
    } on ApiException catch (e) {
      state = state.copyWith(isAccepting: false, errorMessage: e.message);
    } catch (_) {
      state = state.copyWith(
        isAccepting: false,
        errorMessage: 'Failed to accept bid. Please try again.',
      );
    }
  }

  /// Declines / ignores the bid — client simply does not call select-bid.
  /// If all 3 bids are declined the job re-enters the admin queue.
  Future<void> declineBid({required String jobId, required String bidId}) async {
    if (state.isBusy) return;
    state = state.copyWith(isDeclining: true, clearError: true);
    // No dedicated decline endpoint — just navigate back.
    state = state.copyWith(isDeclining: false);
  }

  /// Cancels a job after acceptance — PRD 4.5.5 free cancellation window.
  /// PATCH /v1/jobs/:jobId/cancel
  Future<void> cancelJobRequest({required String jobId}) async {
    if (state.isBusy) return;
    state = state.copyWith(isDeclining: true, clearError: true);
    try {
      await _jobService.cancelJob(jobId);
      state = state.copyWith(isDeclining: false, isAwaitingConfirmation: false);
    } on ApiException catch (e) {
      state = state.copyWith(isDeclining: false, errorMessage: e.message);
    } catch (_) {
      state = state.copyWith(
        isDeclining: false,
        errorMessage: 'Failed to cancel. Please try again.',
      );
    }
  }

  /// Called when the artisan confirms the appointment.
  /// In production this is triggered by a WebSocket push on the jobs channel.
  /// EDD § Real-Time Events — event: job.artisan_confirmed
  void onArtisanConfirmed({String etaLabel = '~18 mins (2:30 PM)'}) {
    state = state.copyWith(
      isAwaitingConfirmation: false,
      isBidConfirmed: true,
      confirmedEtaLabel: etaLabel,
    );
  }

  /// Called when the countdown timer reaches zero with no artisan confirmation.
  /// The job re-enters the admin queue for reassignment.
  void onBidExpired() {
    if (state.isBidConfirmed) return; // artisan already confirmed — ignore
    state = state.copyWith(
      isAwaitingConfirmation: false,
      isBidExpired: true,
      expiredDateLabel: _formatExpiredDate(DateTime.now()),
    );
  }

  static String _formatExpiredDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }
}

final bidDetailActionProvider =
    StateNotifierProvider.autoDispose<BidDetailNotifier, BidDetailActionState>(
  (ref) => BidDetailNotifier(ref.watch(jobServiceProvider)),
);

// ── Bid Detail Data Provider ──────────────────────────────────────────────────

final bidDetailProvider =
    AsyncNotifierProvider.autoDispose.family<_BidDetailNotifier, BidDetail, String>(
  _BidDetailNotifier.new,
);

class _BidDetailNotifier
    extends AutoDisposeFamilyAsyncNotifier<BidDetail, String> {
  @override
  Future<BidDetail> build(String bidId) async {
    // In production, bids are fetched via GET /jobs/:jobId/bids and filtered.
    // For now, fall back to mock if API isn't ready.
    try {
      // bidId format could include jobId context — for now use mock fallback
      return _mockBidDetails[bidId] ?? _defaultMockBid;
    } catch (_) {
      return _defaultMockBid;
    }
  }
}

// ── Mock data ─────────────────────────────────────────────────────────────────

const _defaultMockBid = BidDetail(
  bidId: 'BID-001',
  jobId: 'JOB-1001',
  status: BidStatus.pendingReview,
  artisan: BidArtisanProfile(
    artisanId: 'ART-101',
    name: 'Kofi Mensah',
    firstName: 'Kofi',
    tradeTitle: 'Master Electrician',
    yearsExperience: 8,
    rating: 4.9,
    reviewCount: 124,
    isKycVerified: true,
    isVetted: true,
    avatarColor: Color(0xFF5D4037),
    baseName: 'Bantama',
    etaMinutes: 18,
    distanceKm: 1.2,
  ),
  breakdown: BidBreakdown(
    serviceFeePesewas: 32000,   // GHS 320.00
    materialsFeePesewas: 14500, // GHS 145.00
    materialItems: [
      MaterialLineItem(name: 'Circuit Breaker (2x)'),
      MaterialLineItem(name: 'Copper Wiring (10m)'),
      MaterialLineItem(name: 'Junction Box'),
    ],
    vatRate: 0.04, // 4% transaction VAT → GHS 20.00 on GHS 465 = ~GHS 18.60 ≈ 20
  ),
  durationLabel: '2–3 Hours',
  availabilityLabel: 'Today, 2PM',
  artisanNote:
      '"Hi! I\'ve seen the photos of your electrical panel. This looks like '
      'a standard upgrade. I can bring all necessary parts and have it done '
      'before 5 PM today. I\'ve done 5 similar jobs in Bantama this week."',
  noteTimestamp: 'Today, 10:42 AM',
  portfolioColors: [
    Color(0xFF455A64),
    Color(0xFF37474F),
    Color(0xFF546E7A),
  ],
);

const Map<String, BidDetail> _mockBidDetails = {};
