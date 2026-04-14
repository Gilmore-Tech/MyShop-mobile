import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ── Artisan Bid ───────────────────────────────────────────────────────────────
// Represents a single bid submitted by an artisan for a client's job request.
// PRD 4.5.2 — bid is a single total (labour + estimated materials).
// API: GET /v1/jobs/:id/bids  |  PATCH /v1/jobs/:id/select-bid

class ArtisanBid {
  final String bidId;
  final String artisanId;
  final String artisanName;
  final String tradeTitle;
  final double rating;
  final int reviewCount;
  final bool isVerified;

  /// Placeholder colour for the avatar until real network images land.
  final Color avatarColor;

  /// Bid amount in pesewas (100 pesewas = GHS 1).
  final int amountPesewas;

  /// Estimated arrival time in minutes (derived from artisan's current location).
  final int arrivesInMinutes;

  /// Optional note from the artisan explaining what the bid covers.
  final String? bidMessage;

  const ArtisanBid({
    required this.bidId,
    required this.artisanId,
    required this.artisanName,
    required this.tradeTitle,
    required this.rating,
    required this.reviewCount,
    required this.isVerified,
    required this.avatarColor,
    required this.amountPesewas,
    required this.arrivesInMinutes,
    this.bidMessage,
  });

  /// Display amount e.g. "GHS 240"
  String get amountDisplay =>
      'GHS ${(amountPesewas / 100).toStringAsFixed(0)}';
}

// ── Active Job Summary ────────────────────────────────────────────────────────
// The compact "active request" card shown at the top of the bid sheet.

class ActiveJobSummary {
  final String jobId;
  final String title;

  /// Client's original budget in pesewas (shown as context for bids).
  final int budgetPesewas;

  const ActiveJobSummary({
    required this.jobId,
    required this.title,
    required this.budgetPesewas,
  });

  String get budgetDisplay =>
      'GHS ${(budgetPesewas / 100).toStringAsFixed(0)}';
}

// ── Bid List State ────────────────────────────────────────────────────────────

class BidListState {
  /// The bid currently being selected (PATCH in-flight). Null = none.
  final String? selectingBidId;

  /// Non-null when PATCH /v1/jobs/:id/select-bid fails.
  final String? errorMessage;

  const BidListState({
    this.selectingBidId,
    this.errorMessage,
  });

  bool get isSelecting => selectingBidId != null;

  BidListState copyWith({
    String? selectingBidId,
    String? errorMessage,
    bool clearError = false,
    bool clearSelecting = false,
  }) =>
      BidListState(
        selectingBidId:
            clearSelecting ? null : (selectingBidId ?? this.selectingBidId),
        errorMessage:
            clearError ? null : (errorMessage ?? this.errorMessage),
      );
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class BidListNotifier extends StateNotifier<BidListState> {
  BidListNotifier() : super(const BidListState());

  /// Selects a bid — PATCH /v1/jobs/:id/select-bid
  /// PRD 4.5: job is confirmed and artisan is notified immediately.
  Future<void> selectBid({
    required String jobId,
    required String bidId,
  }) async {
    if (state.isSelecting) return;
    state = state.copyWith(selectingBidId: bidId, clearError: true);
    // TODO: PATCH /v1/jobs/:jobId/select-bid with { bidId }
    await Future.delayed(const Duration(milliseconds: 700)); // simulate network
    state = state.copyWith(clearSelecting: true);
  }

  void clearError() => state = state.copyWith(clearError: true);
}

// ── Providers ─────────────────────────────────────────────────────────────────

/// autoDispose — state resets when the sheet is dismissed.
final bidListNotifierProvider =
    StateNotifierProvider.autoDispose<BidListNotifier, BidListState>(
  (_) => BidListNotifier(),
);

/// Fetches bids for a given job ID.
/// autoDispose.family — each job gets its own cached async state.
final bidsForJobProvider =
    AsyncNotifierProvider.autoDispose.family<_BidsNotifier, List<ArtisanBid>, String>(
  _BidsNotifier.new,
);

class _BidsNotifier
    extends AutoDisposeFamilyAsyncNotifier<List<ArtisanBid>, String> {
  @override
  Future<List<ArtisanBid>> build(String jobId) async {
    // TODO: GET /v1/jobs/:jobId/bids via API client
    await Future.delayed(const Duration(milliseconds: 300));
    return _mockBids[jobId] ?? _defaultMockBids;
  }
}

// ── Mock data ─────────────────────────────────────────────────────────────────
// Max 3 bids per job (PRD/EDD § job_max_bids).

const _defaultMockBids = [
  ArtisanBid(
    bidId: 'BID-001',
    artisanId: 'ART-101',
    artisanName: 'Samuel Kwaku',
    tradeTitle: 'Master Electrician',
    rating: 4.9,
    reviewCount: 38,
    isVerified: true,
    avatarColor: Color(0xFF5D4037), // warm brown
    amountPesewas: 24000, // GHS 240
    arrivesInMinutes: 25,
    bidMessage:
        'Includes full inspection, rewiring and standard materials (wire, switches).',
  ),
  ArtisanBid(
    bidId: 'BID-002',
    artisanId: 'ART-102',
    artisanName: 'Isaac Osei',
    tradeTitle: 'Licensed Wireman',
    rating: 4.7,
    reviewCount: 12,
    isVerified: true,
    avatarColor: Color(0xFF795548), // medium brown
    amountPesewas: 21000, // GHS 210
    arrivesInMinutes: 45,
  ),
  ArtisanBid(
    bidId: 'BID-003',
    artisanId: 'ART-103',
    artisanName: 'Kwame Mensah',
    tradeTitle: 'Rapid Repair',
    rating: 4.5,
    reviewCount: 56,
    isVerified: true,
    avatarColor: Color(0xFF607D8B), // blue-grey
    amountPesewas: 28000, // GHS 280
    arrivesInMinutes: 15,
  ),
];

/// Job-specific mock overrides (keyed by jobId).
/// Both 'JOB-001' (dev menu) and 'JOB-3847' (job detail mock) resolve here.
const Map<String, List<ArtisanBid>> _mockBids = {
  'JOB-001':  _defaultMockBids,
  'JOB-3847': _defaultMockBids,
};
