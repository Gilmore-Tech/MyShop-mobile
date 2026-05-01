import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import 'bid_list_provider.dart';
import 'job_detail_provider.dart';

// ── Bid Status ────────────────────────────────────────────────────────────────

enum BidStatus { pendingReview, awaitingConfirmation, accepted, declined, expired }

extension BidStatusX on BidStatus {
  String get label => switch (this) {
        BidStatus.pendingReview        => 'Pending Review',
        BidStatus.awaitingConfirmation => 'Awaiting Confirmation',
        BidStatus.accepted             => 'Accepted',
        BidStatus.declined             => 'Declined',
        BidStatus.expired              => 'Expired',
      };

  Color get color => switch (this) {
        BidStatus.pendingReview        => MyShopColors.warning,
        BidStatus.awaitingConfirmation => MyShopColors.primaryGold,
        BidStatus.accepted             => MyShopColors.success,
        BidStatus.declined             => MyShopColors.error,
        BidStatus.expired              => MyShopColors.error,
      };
}

/// Map the backend bid status string (pending | accepted | rejected | expired)
/// to the client [BidStatus] enum.
BidStatus bidStatusFromRaw(String raw) => switch (raw) {
      'accepted' => BidStatus.accepted,
      'rejected' => BidStatus.declined,
      'expired'  => BidStatus.expired,
      _          => BidStatus.pendingReview,
    };

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

  /// Placeholder colour for avatar when no remote photo is available.
  final Color avatarColor;

  /// Optional remote profile photo. Falls back to initials on [avatarColor].
  final String? profilePhotoUrl;

  /// Neighbourhood name used as the artisan's base location.
  final String baseName;

  /// Estimated travel time to the job site in minutes.
  final int etaMinutes;

  /// Distance from artisan to job site in kilometres. Zero when coordinates
  /// aren't known for either end.
  final double distanceKm;

  /// Snapshot of the artisan's location at bid-submission time (WGS84).
  /// Null when the backend didn't record it.
  final double? latitude;
  final double? longitude;

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
    this.profilePhotoUrl,
    this.latitude,
    this.longitude,
  });

  bool get hasLocation => latitude != null && longitude != null;
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

  /// Job-site coordinates (WGS84). Null when unknown — used for the map view.
  final double? jobLatitude;
  final double? jobLongitude;

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
    this.jobLatitude,
    this.jobLongitude,
  });

  bool get hasJobLocation => jobLatitude != null && jobLongitude != null;
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
  BidDetailNotifier(this._ref, this._jobService)
      : super(const BidDetailActionState());

  final Ref _ref;
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
      // Force the timeline + bid list to re-fetch so the user sees the
      // accepted state on return without waiting for the next poll tick
      // or a delayed `job:status:changed` socket event.
      _ref.invalidate(jobDetailProvider(jobId));
      _ref.invalidate(bidsForJobProvider(jobId));
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
  (ref) => BidDetailNotifier(ref, ref.watch(jobServiceProvider)),
);

// ── Bid Detail Data Provider ──────────────────────────────────────────────────

/// Family key — a bid is always scoped to a job.
typedef BidDetailKey = ({String jobId, String bidId});

/// Resolves the selected artisan bid by reusing the cached bid list fetched
/// in [bidsForJobProvider]. No extra network call when navigated from the
/// bid sheet; a fresh fetch happens if the list provider has been disposed.
final bidDetailProvider = AsyncNotifierProvider.autoDispose
    .family<_BidDetailNotifier, BidDetail, BidDetailKey>(
  _BidDetailNotifier.new,
);

class _BidDetailNotifier
    extends AutoDisposeFamilyAsyncNotifier<BidDetail, BidDetailKey> {
  @override
  Future<BidDetail> build(BidDetailKey arg) async {
    // `bidsForJobProvider` IS subscribed to — a bid's status can flip
    // (accepted/rejected/expired) and we want that reflected here.
    //
    // `jobDetailProvider` is read ONCE (no subscription) because we only
    // consume the job's immutable coordinates. If we subscribed, every
    // invalidation from job_detail_screen's 10 s poll would cascade and
    // rebuild the bid detail + full-screen tracking map, flickering the UI
    // and resetting the map's camera/animation state.
    final bids = await ref.watch(bidsForJobProvider(arg.jobId).future);
    final job = await ref.read(jobDetailProvider(arg.jobId).future);
    final bid = bids.firstWhere(
      (b) => b.bidId == arg.bidId,
      orElse: () => throw StateError('Bid ${arg.bidId} not found for job ${arg.jobId}'),
    );
    return _toBidDetail(bid, job: job);
  }
}

// ── Mapping: ArtisanBid → BidDetail ───────────────────────────────────────────

BidDetail _toBidDetail(ArtisanBid bid, {required JobDetail job}) {
  final parts = bid.artisanName.trim().split(RegExp(r'\s+'));
  final firstName = parts.isNotEmpty && parts.first.isNotEmpty
      ? parts.first
      : bid.artisanName;

  // Real distance only when both endpoints are known.
  final double distanceKm = (bid.hasLocation && job.hasCoordinates)
      ? Geolocator.distanceBetween(
            job.latitude,
            job.longitude,
            bid.latitude!,
            bid.longitude!,
          ) /
          1000.0
      : 0.0;

  return BidDetail(
    bidId: bid.bidId,
    jobId: job.id,
    status: bidStatusFromRaw(bid.rawStatus),
    artisan: BidArtisanProfile(
      artisanId: bid.artisanId,
      name: bid.artisanName,
      firstName: firstName,
      tradeTitle: bid.tradeTitle,
      yearsExperience: 0,
      rating: bid.rating,
      reviewCount: bid.reviewCount,
      isKycVerified: bid.isVerified,
      isVetted: bid.isVerified,
      avatarColor: bid.avatarColor,
      profilePhotoUrl: bid.profilePhotoUrl,
      baseName: '',
      etaMinutes: bid.arrivesInMinutes,
      distanceKm: distanceKm,
      latitude: bid.latitude,
      longitude: bid.longitude,
    ),
    // Backend bid is a single total (labour + estimated materials).
    // Until the API splits it out, surface the whole amount as the service fee
    // and zero-out materials + VAT so the breakdown UI collapses gracefully.
    breakdown: BidBreakdown(
      serviceFeePesewas: bid.amountPesewas,
      materialsFeePesewas: 0,
      materialItems: const [],
      vatRate: 0.0,
    ),
    durationLabel: bid.durationMinutes > 0
        ? _formatDuration(bid.durationMinutes)
        : 'Not specified',
    availabilityLabel: bid.arrivesInMinutes > 0
        ? 'Arrives in ${bid.arrivesInMinutes} min'
        : 'Available now',
    artisanNote: bid.bidMessage,
    noteTimestamp: null,
    portfolioColors: const [],
    jobLatitude: job.hasCoordinates ? job.latitude : null,
    jobLongitude: job.hasCoordinates ? job.longitude : null,
  );
}

String _formatDuration(int minutes) {
  if (minutes < 60) return '$minutes min';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}
