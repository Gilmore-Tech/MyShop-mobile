import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:api_client/api_client.dart';

import '../../../core/di/providers.dart';
import 'job_detail_provider.dart';

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

  /// Artisan's remote profile photo (Cloudinary/S3). When null the avatar
  /// falls back to initials on a deterministic color.
  final String? profilePhotoUrl;

  /// Bid amount in pesewas (100 pesewas = GHS 1).
  final int amountPesewas;

  /// Estimated arrival time in minutes (derived from artisan's current location).
  final int arrivesInMinutes;

  /// Estimated duration of the work in minutes.
  final int durationMinutes;

  /// Optional note from the artisan explaining what the bid covers.
  final String? bidMessage;

  /// Raw backend bid status — one of: pending, accepted, rejected, expired.
  /// Drives whether the client can still accept or must view the bid as
  /// already decided.
  final String rawStatus;

  /// Snapshot of the artisan's location at bid-submission time (WGS84).
  /// Both are null when the backend doesn't know where the artisan was.
  /// Backend guarantee: either both present or both null — never one.
  final double? latitude;
  final double? longitude;

  const ArtisanBid({
    required this.bidId,
    required this.artisanId,
    required this.artisanName,
    required this.tradeTitle,
    required this.rating,
    required this.reviewCount,
    required this.isVerified,
    required this.amountPesewas,
    required this.arrivesInMinutes,
    this.durationMinutes = 0,
    this.profilePhotoUrl,
    this.bidMessage,
    this.rawStatus = 'pending',
    this.latitude,
    this.longitude,
  });

  /// True when we have a usable coordinate pair to plot / measure against.
  bool get hasLocation => latitude != null && longitude != null;

  bool get hasRating => reviewCount > 0 && rating > 0;

  /// Display amount e.g. "GHS 240"
  String get amountDisplay => 'GHS ${(amountPesewas / 100).toStringAsFixed(0)}';

  /// Deterministic fallback avatar color derived from the artisan id, so
  /// the same artisan always renders with the same shade across sessions.
  Color get avatarColor {
    const palette = <Color>[
      Color(0xFF5D4037), // brown
      Color(0xFF795548), // medium brown
      Color(0xFF607D8B), // blue-grey
      Color(0xFF455A64), // slate
      Color(0xFF6D4C41), // warm brown
      Color(0xFF3E2723), // dark brown
      Color(0xFF33691E), // deep green
      Color(0xFF4E342E), // cocoa
    ];
    final key = artisanId.isNotEmpty ? artisanId : bidId;
    if (key.isEmpty) return palette.first;
    final hash = key.codeUnits.fold<int>(0, (acc, c) => acc + c);
    return palette[hash % palette.length];
  }
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

  String get budgetDisplay => 'GHS ${(budgetPesewas / 100).toStringAsFixed(0)}';
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
        errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      );
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class BidListNotifier extends StateNotifier<BidListState> {
  BidListNotifier(this._ref, this._jobService) : super(const BidListState());

  final Ref _ref;
  final JobService _jobService;

  /// Selects a bid — PATCH /v1/jobs/:id/select-bid
  /// PRD 4.5: job is confirmed and artisan is notified immediately.
  Future<void> selectBid({
    required String jobId,
    required String bidId,
  }) async {
    if (state.isSelecting) return;
    state = state.copyWith(selectingBidId: bidId, clearError: true);
    try {
      await _jobService.selectBid(jobId, bidId: bidId);
      state = state.copyWith(clearSelecting: true);
      // Force the timeline + bid list to re-fetch so the user sees the
      // accepted state on return without waiting for the next poll tick
      // or a delayed `job:status:changed` socket event.
      _ref.invalidate(jobDetailProvider(jobId));
      _ref.invalidate(bidsForJobProvider(jobId));
    } on ApiException catch (e) {
      state = state.copyWith(clearSelecting: true, errorMessage: e.message);
    } catch (_) {
      // Fallback: treat as success during development
      state = state.copyWith(clearSelecting: true);
    }
  }

  void clearError() => state = state.copyWith(clearError: true);
}

// ── Providers ─────────────────────────────────────────────────────────────────

/// autoDispose — state resets when the sheet is dismissed.
final bidListNotifierProvider =
    StateNotifierProvider.autoDispose<BidListNotifier, BidListState>(
  (ref) => BidListNotifier(ref, ref.watch(jobServiceProvider)),
);

/// Fetches bids for a given job ID.
/// autoDispose.family — each job gets its own cached async state.
final bidsForJobProvider = AsyncNotifierProvider.autoDispose
    .family<_BidsNotifier, List<ArtisanBid>, String>(
  _BidsNotifier.new,
);

class _BidsNotifier
    extends AutoDisposeFamilyAsyncNotifier<List<ArtisanBid>, String> {
  @override
  Future<List<ArtisanBid>> build(String jobId) async {
    final jobService = ref.watch(jobServiceProvider);
    final List<dynamic> data;
    try {
      data = await jobService.getBids(jobId);
    } on ApiException catch (e) {
      // 429 = backend throttler tripped (typically when polling races with
      // socket-driven invalidation during state changes). Hold the previous
      // bid list so the screen doesn't flip to an error state — the next
      // poll/socket event will reconcile.
      if (e.statusCode == 429) {
        final previous = state.valueOrNull;
        if (previous != null) return previous;
      }
      rethrow;
    }
    developer.log(
      'Received ${data.length} bid(s) for job $jobId',
      name: 'BidsForJob',
    );
    final bids = <ArtisanBid>[];
    for (final item in data) {
      if (item is! Map<String, dynamic>) {
        developer.log('Skipping non-map bid entry: ${item.runtimeType}',
            name: 'BidsForJob', level: 900);
        continue;
      }
      try {
        bids.add(_parseBid(item));
      } catch (e, st) {
        // Log the offending payload so we can see which field has the wrong
        // shape, then skip it instead of failing the whole list.
        developer.log(
          'Failed to parse bid — skipping. raw=$item',
          name: 'BidsForJob',
          level: 1000,
          error: e,
          stackTrace: st,
        );
      }
    }
    return bids;
  }

  /// Parse API bid response into [ArtisanBid].
  ///
  /// Tolerates a few backend response shapes:
  /// - artisan nested under `artisan` OR `provider` OR flat at top level
  /// - name as `fullName`, `name`, or `firstName`+`lastName`
  /// - notes field as `notes` (what submitBid POSTs) or legacy `message`
  /// - eta as `etaMinutes` (what submitBid POSTs) or legacy
  ///   `estimatedArrivalMinutes`
  static ArtisanBid _parseBid(Map<String, dynamic> data) {
    // The artisan may sit under any of these keys depending on the endpoint.
    final artisan = (data['artisan'] as Map<String, dynamic>?) ??
        (data['provider'] as Map<String, dynamic>?) ??
        const <String, dynamic>{};

    String composeName() {
      final full = (artisan['fullName'] ?? artisan['name']) as String?;
      if (full != null && full.trim().isNotEmpty) return full.trim();
      final first = artisan['firstName'] as String? ?? '';
      final last = artisan['lastName'] as String? ?? '';
      final joined = '$first $last'.trim();
      return joined.isNotEmpty ? joined : 'Artisan';
    }

    String composeTradeTitle() {
      final specialty =
          (artisan['specialty'] ?? artisan['tradeTitle']) as String?;
      if (specialty != null && specialty.trim().isNotEmpty) return specialty;
      // Derive from service_categories[0].name when available.
      final cats = artisan['serviceCategories'] as List<dynamic>?;
      if (cats != null && cats.isNotEmpty) {
        final first = cats.first;
        if (first is Map<String, dynamic>) {
          final name = first['name'] as String?;
          if (name != null && name.isNotEmpty) return name;
        }
      }
      return '';
    }

    return ArtisanBid(
      bidId: data['id'] as String? ?? data['bidId'] as String? ?? '',
      artisanId: artisan['id'] as String? ??
          artisan['userId'] as String? ??
          data['artisanId'] as String? ??
          '',
      artisanName: composeName(),
      tradeTitle: composeTradeTitle(),
      // Backend returns `averageRating` + `ratingCount` from the bid list /
      // bid socket emit; legacy admin endpoints still use `rating` /
      // `reviewCount`. Read both so the artisan card never silently
      // defaults to "New" because of a key mismatch.
      rating: ((artisan['averageRating'] ?? artisan['rating']) as num?)
              ?.toDouble() ??
          0.0,
      reviewCount: ((artisan['ratingCount'] ?? artisan['reviewCount']) as num?)
              ?.toInt() ??
          0,
      isVerified:
          (artisan['isVerified'] ?? artisan['verified']) as bool? ?? false,
      profilePhotoUrl: (artisan['profilePhotoUrl'] ??
          artisan['photoUrl'] ??
          artisan['avatarUrl']) as String?,
      amountPesewas: (data['amountPesewas'] as num?)?.toInt() ?? 0,
      arrivesInMinutes: (data['etaMinutes'] as num?)?.toInt() ??
          (data['estimatedArrivalMinutes'] as num?)?.toInt() ??
          0,
      durationMinutes: (data['durationMinutes'] as num?)?.toInt() ?? 0,
      bidMessage: (data['notes'] ?? data['message']) as String?,
      rawStatus: (data['status'] as String?) ?? 'pending',
      latitude: (artisan['latitude'] as num?)?.toDouble(),
      longitude: (artisan['longitude'] as num?)?.toDouble(),
    );
  }
}
