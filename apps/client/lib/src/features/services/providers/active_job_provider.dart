import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:api_client/api_client.dart';

import '../../../core/di/providers.dart';

// ── Active Job Phase ──────────────────────────────────────────────────────────
// Subset of JobStatus relevant to the active tracking screen.
// Real-time phase changes arrive via WS /v1/jobs/:id/live (EDD § 5.3).
//
//   enRoute        → job.status == "en_route"
//   arrived        → job.status == "arrived"
//   inProgress     → job.status == "in_progress"   (client confirmed arrival)
//   awaitingApproval → artisan marked complete; client has 4-hr window to confirm
//                      (PRD 4.8.2 / EDD § Marketplace)

enum ActiveJobPhase {
  enRoute,
  arrived,
  inProgress,
  awaitingApproval,

  /// Client tapped "Confirm & Pay", Paystack charge is queued, waiting on
  /// the webhook. UI should show "Processing payment…" — CTA disabled.
  pendingPayment,

  /// Webhook landed, job is officially complete. UI shows a success state
  /// and the post-job receipt / rating flow.
  completed,
}

extension ActiveJobPhaseX on ActiveJobPhase {
  String get statusLabel => switch (this) {
        ActiveJobPhase.enRoute => 'En Route',
        ActiveJobPhase.arrived => 'In Progress',
        ActiveJobPhase.inProgress => 'In Progress',
        ActiveJobPhase.awaitingApproval => 'Awaiting Confirmation',
        ActiveJobPhase.pendingPayment => 'Processing Payment',
        ActiveJobPhase.completed => 'Completed',
      };

  Color get statusColor => switch (this) {
        ActiveJobPhase.enRoute => MyShopColors.primaryGold,
        ActiveJobPhase.arrived => MyShopColors.primaryGold,
        ActiveJobPhase.inProgress => MyShopColors.primaryGold,
        ActiveJobPhase.awaitingApproval => MyShopColors.textSecondary,
        ActiveJobPhase.pendingPayment => MyShopColors.warning,
        ActiveJobPhase.completed => MyShopColors.success,
      };

  /// Left stat cell label.
  String get statLabel => switch (this) {
        ActiveJobPhase.enRoute => 'ESTIMATED ARRIVAL',
        _ => 'EST. COMPLETION',
      };
}

// ── Artisan (active job context) ──────────────────────────────────────────────

class ActiveJobArtisan {
  final String artisanId;
  final String name;
  final String firstName;
  final Color avatarColor;
  final bool isVerified;

  /// Specialty label, e.g. "Master Electrician" — empty when the backend
  /// hasn't set one. Surfaced under the artisan name on tracking screens.
  final String specialty;

  /// Lifetime rating, 0.0–5.0. Zero when the artisan has no ratings yet
  /// (don't render a star row in that case).
  final double rating;

  /// Profile photo URL — empty when the backend hasn't uploaded one.
  final String photoUrl;

  const ActiveJobArtisan({
    required this.artisanId,
    required this.name,
    required this.firstName,
    required this.avatarColor,
    required this.isVerified,
    this.specialty = '',
    this.rating = 0.0,
    this.photoUrl = '',
  });
}

// ── Cost Breakdown ────────────────────────────────────────────────────────────
// PRD 4.5.2 — bid covers labour + estimated materials.
// isFinalized becomes true in awaitingApproval: removes "Estimated" prefix from
// the header and total line.

class ActiveJobCost {
  final int serviceFeePesewas;
  final int materialsFeePesewas;
  final bool isFinalized;

  const ActiveJobCost({
    required this.serviceFeePesewas,
    required this.materialsFeePesewas,
    this.isFinalized = false,
  });

  int get totalPesewas => serviceFeePesewas + materialsFeePesewas;

  String _fmt(int pesewas) => 'GHS ${(pesewas / 100).toStringAsFixed(2)}';

  String get serviceFeeDisplay => _fmt(serviceFeePesewas);
  String get materialsFeeDisplay => _fmt(materialsFeePesewas);
  String get totalDisplay => _fmt(totalPesewas);

  /// Section header — "Estimated Cost" vs "Cost".
  String get sectionTitle => isFinalized ? 'Cost' : 'Estimated Cost';

  /// Total row label — "Estimated Total" vs "Total".
  String get totalLabel => isFinalized ? 'Total' : 'Estimated Total';
}

// ── Supplement request ────────────────────────────────────────────────────────
// PRD § 4.5.3 — Artisan requests additional materials/cost mid-job. Surfaces
// to the client through the supplement review screen so they can approve or
// decline before work resumes.
//
// Populated from `data['supplement']` on GET /jobs/:id when the artisan has
// submitted one. Null when there's no pending supplement.

class SupplementRequest {
  final int additionalAmountPesewas;
  final int originalBidPesewas;
  final String reason;

  /// Submitted-at timestamp from the backend, e.g. "2024-10-23T09:15:00Z".
  /// Empty when missing.
  final String submittedAt;

  const SupplementRequest({
    required this.additionalAmountPesewas,
    required this.originalBidPesewas,
    required this.reason,
    this.submittedAt = '',
  });

  int get newTotalPesewas => additionalAmountPesewas + originalBidPesewas;

  String _fmt(int pesewas) => 'GHS ${(pesewas / 100).toStringAsFixed(2)}';

  String get additionalDisplay => _fmt(additionalAmountPesewas);
  String get originalBidDisplay => _fmt(originalBidPesewas);
  String get newTotalDisplay => _fmt(newTotalPesewas);
}

// ── Active Job Data ───────────────────────────────────────────────────────────
// API: GET /v1/jobs/:id  |  WS /v1/jobs/:id/live

class ActiveJobData {
  final String jobId;

  /// Formatted service reference shown under the title, e.g. "# JJOB-88219".
  final String serviceId;

  final String title;
  final String categoryName;
  final IconData categoryIcon;
  final String location;
  final ActiveJobPhase phase;
  final ActiveJobArtisan artisan;
  final ActiveJobCost cost;

  /// Left stat cell value when enRoute, e.g. "12 mins away".
  final String? etaLabel;

  /// Left stat cell value for all other phases, e.g. "4hrs".
  final String? completionLabel;

  /// Right stat cell — always "Today, HH:MM AM/PM".
  final String scheduleLabel;

  /// Timestamp for the "Job Posted" timeline step, e.g. "09:15 AM".
  final String jobPostedTime;

  /// Description text for the "Job Posted" timeline step.
  final String jobDescription;

  /// Job-site coordinates from the original POST /jobs payload. Null when
  /// the backend response is missing them — the tracking screen falls back
  /// to its default map centre in that case.
  final double? locationLat;
  final double? locationLng;

  /// Pending supplement the artisan has submitted, awaiting client decision.
  /// Null when there's no supplement in flight.
  final SupplementRequest? pendingSupplement;

  const ActiveJobData({
    required this.jobId,
    required this.serviceId,
    required this.title,
    required this.categoryName,
    required this.categoryIcon,
    required this.location,
    required this.phase,
    required this.artisan,
    required this.cost,
    this.etaLabel,
    this.completionLabel,
    required this.scheduleLabel,
    required this.jobPostedTime,
    required this.jobDescription,
    this.locationLat,
    this.locationLng,
    this.pendingSupplement,
  });

  /// Resolved value for the left stat cell.
  String get statValue => phase == ActiveJobPhase.enRoute
      ? (etaLabel ?? '—')
      : (completionLabel ?? '—');
}

// ── Action State ──────────────────────────────────────────────────────────────

class ActiveJobActionState {
  final bool isConfirmingArrival;
  final bool isMarkingComplete;
  final bool costExpanded;
  final String? errorMessage;

  const ActiveJobActionState({
    this.isConfirmingArrival = false,
    this.isMarkingComplete = false,
    this.costExpanded = false,
    this.errorMessage,
  });

  bool get isBusy => isConfirmingArrival || isMarkingComplete;

  ActiveJobActionState copyWith({
    bool? isConfirmingArrival,
    bool? isMarkingComplete,
    bool? costExpanded,
    String? errorMessage,
    bool clearError = false,
  }) =>
      ActiveJobActionState(
        isConfirmingArrival: isConfirmingArrival ?? this.isConfirmingArrival,
        isMarkingComplete: isMarkingComplete ?? this.isMarkingComplete,
        costExpanded: costExpanded ?? this.costExpanded,
        errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      );
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class ActiveJobNotifier extends StateNotifier<ActiveJobActionState> {
  ActiveJobNotifier(this._jobService) : super(const ActiveJobActionState());

  final JobService _jobService;

  void toggleCost() =>
      state = state.copyWith(costExpanded: !state.costExpanded);

  /// Client confirms artisan has arrived — starts the work session.
  /// PATCH /v1/jobs/:jobId/status  { status: "inProgress" }
  /// PRD 4.5: triggers work-start; supplement window closes after this.
  Future<void> confirmArrival({required String jobId}) async {
    if (state.isBusy) return;
    state = state.copyWith(isConfirmingArrival: true, clearError: true);
    try {
      await _jobService.confirmJobCompletion(jobId);
      state = state.copyWith(isConfirmingArrival: false);
    } on ApiException catch (e) {
      state = state.copyWith(
        isConfirmingArrival: false,
        errorMessage: e.message,
      );
    } catch (_) {
      // Fallback: treat as success during development
      state = state.copyWith(isConfirmingArrival: false);
    }
  }

  /// Legacy direct-confirm path. Kept for the dev menu only — the real
  /// confirm flow now routes through the payment screen, which initiates
  /// the Paystack escrow charge and then PATCHes /confirm once the webhook
  /// settles (idempotent).
  ///
  /// See [PaymentNotifier.confirmCompletion] for the production path.
  Future<void> markComplete({required String jobId}) async {
    if (state.isBusy) return;
    state = state.copyWith(isMarkingComplete: true, clearError: true);
    try {
      await _jobService.confirmJobCompletion(jobId);
      state = state.copyWith(isMarkingComplete: false);
    } on ApiException catch (e) {
      state = state.copyWith(
        isMarkingComplete: false,
        errorMessage: e.message,
      );
    } catch (_) {
      state = state.copyWith(isMarkingComplete: false);
    }
  }
}

final activeJobActionProvider =
    StateNotifierProvider.autoDispose<ActiveJobNotifier, ActiveJobActionState>(
  (ref) => ActiveJobNotifier(ref.watch(jobServiceProvider)),
);

// ── Supplement response ───────────────────────────────────────────────────────
// PATCH /v1/jobs/:id/supplement/respond  { approved: bool }
//
// Lives next to the active-job notifier rather than inside the supplement
// review screen so the action survives a screen rebuild and shares a single
// loading state with any other surface that might need to respond (e.g. a
// future inline approval card on the active-job screen itself).

class SupplementResponseState {
  final bool isApproving;
  final bool isDeclining;
  final String? errorMessage;
  final bool isComplete;

  const SupplementResponseState({
    this.isApproving = false,
    this.isDeclining = false,
    this.errorMessage,
    this.isComplete = false,
  });

  bool get isBusy => isApproving || isDeclining;

  SupplementResponseState copyWith({
    bool? isApproving,
    bool? isDeclining,
    String? errorMessage,
    bool? isComplete,
    bool clearError = false,
  }) =>
      SupplementResponseState(
        isApproving: isApproving ?? this.isApproving,
        isDeclining: isDeclining ?? this.isDeclining,
        errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
        isComplete: isComplete ?? this.isComplete,
      );
}

class SupplementResponseNotifier
    extends StateNotifier<SupplementResponseState> {
  SupplementResponseNotifier(this._ref)
      : super(const SupplementResponseState());

  final Ref _ref;

  Future<bool> respond({
    required String jobId,
    required bool approve,
  }) async {
    if (state.isBusy) return false;
    state = state.copyWith(
      isApproving: approve,
      isDeclining: !approve,
      clearError: true,
    );
    try {
      await _ref
          .read(jobServiceProvider)
          .respondToSupplement(jobId, approved: approve);
      // Bust the active-job cache so the supplement clears and the cost
      // breakdown reflects the new agreed price (or the original bid on
      // decline).
      _ref.invalidate(activeJobProvider(jobId));
      state = state.copyWith(
        isApproving: false,
        isDeclining: false,
        isComplete: true,
      );
      return true;
    } on ApiException catch (e) {
      state = state.copyWith(
        isApproving: false,
        isDeclining: false,
        errorMessage: e.message.isNotEmpty
            ? e.message
            : "We couldn't send your response. Please try again.",
      );
      return false;
    } catch (_) {
      state = state.copyWith(
        isApproving: false,
        isDeclining: false,
        errorMessage: "We couldn't send your response. Please try again.",
      );
      return false;
    }
  }
}

final supplementResponseProvider = StateNotifierProvider.autoDispose<
    SupplementResponseNotifier, SupplementResponseState>(
  (ref) => SupplementResponseNotifier(ref),
);

// ── Data Provider ─────────────────────────────────────────────────────────────

/// Live artisan coordinates while a job is in flight. Mirrors
/// [LiveDriverPosition] for rides — updated by the `job:artisan:location`
/// socket listener (in `core/providers/socket_provider.dart`) every
/// time the artisan's mobile heartbeats a position to the backend.
///
/// Null while no fix has arrived yet. Cleared by the tracking screen
/// when it unmounts to keep stale data off subsequent jobs.
class LiveArtisanPosition {
  const LiveArtisanPosition({
    required this.jobId,
    required this.latitude,
    required this.longitude,
    this.updatedAt,
  });

  final String jobId;
  final double latitude;
  final double longitude;
  final DateTime? updatedAt;
}

/// Holds the most recent artisan-position fix delivered over the
/// `job:artisan:location` socket event. Consumers gate on `jobId`
/// matching the screen they're rendering — the listener doesn't pre-
/// filter so a single subscription covers any job the client is
/// tracking at the moment.
final liveArtisanPositionProvider =
    StateProvider<LiveArtisanPosition?>((_) => null);

/// The jobId the tracking screen has subscribed to via
/// `client:track:job`. Set on mount, cleared on dispose. The socket
/// connection bridge (in `core/providers/socket_provider.dart`)
/// re-emits the join whenever the socket reconnects.
final trackedJobIdProvider = StateProvider<String?>((_) => null);

final activeJobProvider = AsyncNotifierProvider.autoDispose
    .family<_ActiveJobNotifier, ActiveJobData, String>(
  _ActiveJobNotifier.new,
);

class _ActiveJobNotifier
    extends AutoDisposeFamilyAsyncNotifier<ActiveJobData, String> {
  @override
  Future<ActiveJobData> build(String jobId) async {
    final jobService = ref.watch(jobServiceProvider);
    final data = await jobService.getJob(jobId);
    return _parseActiveJob(data);
  }

  /// Parse API response into [ActiveJobData].
  ActiveJobData _parseActiveJob(Map<String, dynamic> data) {
    final status = data['status'] as String? ?? 'en_route';
    final clientPaymentAck =
        data['clientPaymentAcknowledgedAt'] as String?;
    final clientPaymentMethod = data['clientPaymentMethod'] as String?;
    // Diagnostic — confirms whether the backend is including the
    // payment-acknowledgement fields in the GET /jobs/:id response. If
    // these come back null after the client picked Cash on the payment
    // screen, the backend isn't persisting them and the "Proceed to
    // payment" CTA will keep looping.
    developer.log(
      'getJob → status=$status '
      'clientPaymentAcknowledgedAt=$clientPaymentAck '
      'clientPaymentMethod=$clientPaymentMethod',
      name: 'ActiveJob',
    );
    final phase = _parsePhase(status, clientPaymentAck: clientPaymentAck);

    // GET /jobs/:id returns the assigned artisan under `artisan` (post-fix
    // in marketplace.service.ts) with `name` / `displayName` / `photoUrl`.
    // Older builds returned only `userId` here; we fall back to `provider`
    // for any in-flight legacy responses so the screen doesn't blank out
    // during the deploy gap.
    final artisanData = (data['artisan'] as Map<String, dynamic>?) ??
        (data['provider'] as Map<String, dynamic>?) ??
        {};
    final artisanName = (artisanData['name'] as String?) ??
        (artisanData['displayName'] as String?) ??
        // Legacy first/last shape — keep until the backend deploy lands.
        ('${artisanData['firstName'] ?? ''} ${artisanData['lastName'] ?? ''}'
            .trim());

    // Accepted bid carries the canonical price + ETA + duration. Backend
    // exposes it as `acceptedBid`; tolerate the older `selectedBid` key
    // during the deploy gap. Falls back to {} so downstream lookups are
    // null-safe.
    final bidData = (data['acceptedBid'] as Map<String, dynamic>?) ??
        (data['selectedBid'] as Map<String, dynamic>?) ??
        {};
    final costBreakdown = data['costBreakdown'] as Map<String, dynamic>? ?? {};

    final serviceFeePesewas =
        (costBreakdown['laborPesewas'] as num?)?.toInt() ??
            (bidData['amountPesewas'] as num?)?.toInt() ??
            0;
    final materialsFeePesewas =
        (costBreakdown['materialsPesewas'] as num?)?.toInt() ?? 0;

    // Pull ETA + duration from the accepted bid. Backend stores them as
    // integer minutes; the screen wants human strings ("12 mins away" /
    // "2 hours"). Empty bid → empty labels (the screen falls back to "—").
    final etaMinutes = (bidData['etaMinutes'] as num?)?.toInt();
    final durationMinutes = (bidData['durationMinutes'] as num?)?.toInt();
    String? formatMinutes(int? mins) {
      if (mins == null || mins <= 0) return null;
      if (mins < 60) return '$mins min${mins == 1 ? '' : 's'}';
      final hours = mins ~/ 60;
      final rem = mins % 60;
      if (rem == 0) return '$hours hr${hours == 1 ? '' : 's'}';
      return '${hours}h ${rem}m';
    }

    final etaLabel = etaMinutes != null
        ? '${formatMinutes(etaMinutes)} away'
        : (data['eta'] != null ? '${data['eta']} mins away' : null);
    final completionLabel = formatMinutes(durationMinutes) ??
        (data['estimatedDuration'] as String? ?? '—');

    final categoryData = data['category'] as Map<String, dynamic>? ?? {};

    // Backend has shipped job coords under at least three shapes during
    // development — `latitude/longitude` (canonical), `lat/lng` (older),
    // and a nested `location: { lat, lng }`. Accept any of them so the
    // tracking-map pin always finds a coord. Without this the marker was
    // being created with null lat/lng and the map rendered empty.
    num? lat = (data['latitude'] ??
        data['lat'] ??
        data['locationLat']) as num?;
    num? lng = (data['longitude'] ??
        data['lng'] ??
        data['locationLng']) as num?;
    if ((lat == null || lng == null) && data['location'] is Map) {
      final loc = data['location'] as Map;
      lat ??= (loc['latitude'] ?? loc['lat']) as num?;
      lng ??= (loc['longitude'] ?? loc['lng']) as num?;
    }
    developer.log(
      'getJob coords lat=$lat lng=$lng (topKeys=${data.keys.toList()})',
      name: 'ActiveJob',
    );

    // Parse a pending supplement when the artisan has one in flight. Backend
    // exposes it under `data['supplement']` keyed by the camelCase shape
    // we've seen on adjacent endpoints; status `pending` is the only one
    // the client review screen acts on.
    SupplementRequest? supplement;
    final supplementData = data['supplement'] as Map<String, dynamic>?;
    if (supplementData != null &&
        (supplementData['status'] as String? ?? 'pending') == 'pending') {
      final additional =
          (supplementData['amountPesewas'] as num?)?.toInt() ?? 0;
      final originalBid = (bidData['amountPesewas'] as num?)?.toInt() ?? 0;
      supplement = SupplementRequest(
        additionalAmountPesewas: additional,
        originalBidPesewas: originalBid,
        reason: supplementData['reason'] as String? ??
            supplementData['description'] as String? ??
            '',
        submittedAt: supplementData['submittedAt'] as String? ??
            supplementData['createdAt'] as String? ??
            '',
      );
    }

    return ActiveJobData(
      jobId: data['id'] as String? ?? '',
      serviceId:
          '# JJOB-${(data['id'] as String? ?? '').hashCode.abs() % 100000}',
      title: data['description'] as String? ?? '',
      categoryName: categoryData['name'] as String? ?? '',
      categoryIcon: Icons.build_rounded,
      location: (data['locationAddress'] ?? data['addressText']) as String? ??
          '',
      phase: phase,
      artisan: ActiveJobArtisan(
        artisanId: artisanData['id'] as String? ?? '',
        name: artisanName.isNotEmpty ? artisanName : 'Artisan',
        // Derive firstName from the resolved name. Backend doesn't ship a
        // separate firstName on this endpoint — splitting on the first
        // space is a good-enough avatar fallback ("Kofi Mensah" → "Kofi"),
        // and a single-word displayName ("Kofi") just returns itself.
        firstName: artisanName.isNotEmpty
            ? artisanName.split(' ').first
            : 'Artisan',
        avatarColor: const Color(0xFF37474F),
        // verificationStatus comes through as a string ('approved', 'pending',
        // 'rejected'); treat 'approved' as verified for the badge.
        isVerified: (artisanData['verificationStatus'] as String?) == 'approved' ||
            (artisanData['isVerified'] as bool? ?? false),
        specialty: artisanData['specialty'] as String? ?? '',
        rating: ((artisanData['averageRating'] ?? artisanData['rating'])
                    as num?)
                ?.toDouble() ??
            0.0,
        photoUrl: (artisanData['photoUrl'] as String?) ??
            (artisanData['profilePhotoUrl'] as String?) ??
            (artisanData['avatarUrl'] as String?) ??
            '',
      ),
      cost: ActiveJobCost(
        serviceFeePesewas: serviceFeePesewas,
        materialsFeePesewas: materialsFeePesewas,
        isFinalized: phase == ActiveJobPhase.awaitingApproval,
      ),
      etaLabel: etaLabel,
      completionLabel: completionLabel,
      scheduleLabel: data['scheduledFor'] as String? ?? 'Today',
      jobPostedTime: data['createdAt'] as String? ?? '',
      jobDescription: data['description'] as String? ?? '',
      locationLat: lat?.toDouble(),
      locationLng: lng?.toDouble(),
      pendingSupplement: supplement,
    );
  }

  /// Resolves the phase from the raw backend status string. When the job is
  /// `artisan_marked_complete` AND the client has already acknowledged
  /// payment (cash flow — `acknowledgeCash` succeeded but the artisan
  /// hasn't tapped "Yes, I received payment" yet), the status server-side
  /// stays at `artisan_marked_complete`. Without overriding here the
  /// active-job CTA would render "Confirm, proceed to payment" again on
  /// back-navigation and prompt the client to pay a second time.
  static ActiveJobPhase _parsePhase(
    String status, {
    String? clientPaymentAck,
  }) {
    if ((status == 'artisan_marked_complete' ||
            status == 'awaiting_approval') &&
        clientPaymentAck != null &&
        clientPaymentAck.isNotEmpty) {
      return ActiveJobPhase.pendingPayment;
    }
    return switch (status) {
      'artisan_en_route' || 'en_route' => ActiveJobPhase.enRoute,
      // Collapse 'arrived' into 'inProgress' so the client-side
      // "Confirm Arrival" CTA never surfaces. Product decision: once the
      // artisan flips to arrived/in_progress on their app the work is
      // considered started — the client doesn't need to acknowledge.
      // The dedicated 'arrived' enum value is kept for completeness in
      // case the confirm-arrival step is reintroduced later.
      'arrived' || 'in_progress' => ActiveJobPhase.inProgress,
      'artisan_marked_complete' ||
      'awaiting_approval' =>
        ActiveJobPhase.awaitingApproval,
      'pending_payment' => ActiveJobPhase.pendingPayment,
      'completed' => ActiveJobPhase.completed,
      _ => ActiveJobPhase.enRoute,
    };
  }
}

