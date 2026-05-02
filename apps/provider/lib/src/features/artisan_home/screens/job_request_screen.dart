import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io' show Platform;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/maps_config.dart';
import '../../../core/di/providers.dart';

import '../../artisan_jobs/providers/artisan_jobs_provider.dart';
import '../../artisan_jobs/providers/pending_incoming_jobs_provider.dart';
import '../../artisan_jobs/providers/submitted_bids_provider.dart';
import '../../auth/providers/current_user_provider.dart';
import '../../driver_home/providers/driver_location_provider.dart';
import '../providers/active_job_provider.dart';
import '../providers/bid_drafts_provider.dart';
import '../widgets/bid_status_banner.dart';
import 'bid_submission_screen.dart';

/// Full job request details — opened when an incoming job request is
/// received via Socket.IO or from the live job feed cards.
///
/// PRD Reference: PRD 5.3 — incoming job notification (category, description,
/// photos, client location, 5-minute bid window).
class JobRequestScreen extends ConsumerStatefulWidget {
  const JobRequestScreen({
    super.key,
    required this.job,
    this.bidStatus = BidStatus.none,
    this.submittedBidAmount = 0,
    this.platformFeePercent = 10,
  });

  final Job job;
  final BidStatus bidStatus;
  final num submittedBidAmount;
  final num platformFeePercent;

  @override
  ConsumerState<JobRequestScreen> createState() => _JobRequestScreenState();
}

class _JobRequestScreenState extends ConsumerState<JobRequestScreen> {
  /// One-shot — prevents the active-work redirect from being scheduled on
  /// every rebuild (the `artisanJobsProvider` watch can fire many times
  /// during a status-update cycle, and stacking post-frame callbacks used
  /// to thrash navigation and retain widgets in memory).
  bool _hasRedirectedToActiveJob = false;

  /// Full-fat job fetched from `GET /jobs/:id` on mount. The artisan jobs
  /// feed (`GET /jobs`) returns slim records that drop client identity
  /// fields, so when the artisan opens the details from "My Jobs" (any
  /// tab — active, bids, completed) the constructor's `widget.job` has
  /// no client name / phone / photo. Hydrating once on mount fills those
  /// in for the entire screen + downstream active-job + chat handoff.
  Job? _hydratedJob;

  @override
  void initState() {
    super.initState();
    _hydrateJob();
  }

  /// Fire-and-forget fetch of the full job record. Failure is non-fatal —
  /// the screen falls back to whatever `widget.job` already had.
  Future<void> _hydrateJob() async {
    try {
      final raw = await ref.read(jobServiceProvider).getJob(widget.job.id);
      if (!mounted) return;
      setState(() => _hydratedJob = Job.fromJson(raw));
    } catch (e) {
      developer.log(
        'Job hydration failed for ${widget.job.id}: $e',
        name: 'JobRequest',
        level: 800,
      );
    }
  }

  /// The richest source we have for this job's static fields (client
  /// identity, category, address). Prefers the hydrated record from
  /// `GET /jobs/:id` (which always includes the `client: {...}` object)
  /// and falls back to the constructor copy.
  Job get _sourceJob => _hydratedJob ?? widget.job;

  String get _requestId => widget.job.id.length >= 8
      ? '#${widget.job.id.substring(0, 8).toUpperCase()}'
      : '#${widget.job.id}';
  String get _title =>
      _sourceJob.categoryName != null && _sourceJob.categoryName!.isNotEmpty
          ? '${_sourceJob.categoryName} request'
          : 'Service Request';

  @override
  Widget build(BuildContext context) {
    final positionAsync = ref.watch(driverLocationStreamProvider);
    // Watch the jobs list so the banner updates live as the backend pushes
    // `job:status` events (e.g. "your bid was accepted"). Falls back to
    // the constructor params when the job isn't in the list yet (fresh
    // incoming request, or backend hasn't enriched the response).
    final jobsState = ref.watch(artisanJobsProvider);
    ArtisanJobEntry? liveEntry;
    for (final e in jobsState.entries) {
      if (e.job.id == widget.job.id) {
        liveEntry = e;
        break;
      }
    }
    // The artisan jobs feed (`GET /jobs`) returns a slim record — it omits
    // the client identity fields (`clientName`, `clientPhone`,
    // `clientPhotoUrl`) and the cosmetic `categoryName` / `addressText`.
    // Without merging, the feed lands and silently replaces our richer
    // copy, so the artisan sees "Client" + a generic avatar through the
    // rest of the flow. We prefer live values (lifecycle owns those) and
    // fall back to `_sourceJob` — either the hydrated `GET /jobs/:id`
    // response or the constructor copy (which itself may carry socket
    // `job:new` data on the modal-entry path).
    final source = _sourceJob;
    final effectiveJob = liveEntry == null
        ? source
        : liveEntry.job.copyWith(
            clientName: liveEntry.job.clientName ?? source.clientName,
            clientPhone: liveEntry.job.clientPhone ?? source.clientPhone,
            clientPhotoUrl:
                liveEntry.job.clientPhotoUrl ?? source.clientPhotoUrl,
            categoryName: liveEntry.job.categoryName ?? source.categoryName,
            addressText: liveEntry.job.addressText ?? source.addressText,
          );
    final effectiveBidStatus = liveEntry != null
        ? _bidStatusFor(liveEntry, fallback: widget.bidStatus)
        : widget.bidStatus;
    final effectiveBidAmount = liveEntry?.bidAmountPesewas != null
        ? liveEntry!.bidAmountPesewas! / 100
        : widget.submittedBidAmount;

    // If the job has already advanced into active work (artisan accepted +
    // is en route), the request-details screen no longer applies — bounce
    // straight to the map view with this job seeded as the active one.
    // Guarded by a one-shot flag so re-renders during the nav transition
    // can't stack more callbacks.
    if (!_hasRedirectedToActiveJob && _isActiveWork(effectiveJob.status)) {
      _hasRedirectedToActiveJob = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(activeJobProvider.notifier).setJob(effectiveJob);
        context.pushReplacement('/active-job');
      });
    }

    final distanceKm = positionAsync.maybeWhen(
      data: (pos) => _distanceKm(
        pos.latitude,
        pos.longitude,
        effectiveJob.latitude,
        effectiveJob.longitude,
      ),
      orElse: () => null,
    );

    return Scaffold(
      backgroundColor: MyShopColors.offWhite,
      body: SafeArea(
        child: Column(
          children: [
            _Header(requestId: _requestId),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: MyShopSpacing.md,
                  vertical: MyShopSpacing.md,
                ),
                children: [
                  if (effectiveBidStatus != BidStatus.none) ...[
                    BidStatusBanner(
                      status: effectiveBidStatus,
                      // Anchor the countdown to the actual bid expiry so it
                      // keeps decreasing across screen opens / rebuilds.
                      expiresAt: ref
                          .watch(submittedBidsProvider)[effectiveJob.id]
                          ?.expiresAt,
                      // Admin-assigned jobs have no bid window — swap the
                      // countdown for a "Quote when ready" hint.
                      showCountdown:
                          effectiveJob.status != JobStatus.adminAssigned,
                      onAcceptStartJob: () {
                        // Seed the active-job slot so the next screen can
                        // drive the status machine from this job. Kicking
                        // off the en_route transition happens inside the
                        // active-job screen once the map is mounted.
                        ref
                            .read(activeJobProvider.notifier)
                            .setJob(effectiveJob);
                        context.pushReplacement('/active-job');
                      },
                      onMessage: () => context.push('/chat'),
                    ),
                    const SizedBox(height: MyShopSpacing.md),
                  ],
                  _ClientSummaryCard(
                    clientName: effectiveJob.clientName ?? 'Client',
                    clientPhotoUrl: effectiveJob.clientPhotoUrl,
                    clientLocation:
                        effectiveJob.addressText ?? 'Location pending',
                    distanceKm: distanceKm,
                    title: _title,
                    postedAgo: _formatPostedAgo(effectiveJob.createdAt),
                  ),
                  const SizedBox(height: MyShopSpacing.lg),
                  const _SectionHeader(
                    icon: Icons.info_outline,
                    label: 'JOB DESCRIPTION',
                  ),
                  const SizedBox(height: MyShopSpacing.sm),
                  _DescriptionCard(
                    text: effectiveJob.description.isNotEmpty
                        ? effectiveJob.description
                        : 'No description provided.',
                  ),
                  if (effectiveJob.photos.isNotEmpty) ...[
                    const SizedBox(height: MyShopSpacing.lg),
                    const _SectionHeader(
                      icon: Icons.photo_library_outlined,
                      label: 'PHOTOS',
                    ),
                    const SizedBox(height: MyShopSpacing.sm),
                    _PhotosRow(photos: effectiveJob.photos),
                  ],
                  const SizedBox(height: MyShopSpacing.lg),
                  const _SectionHeader(
                    icon: Icons.near_me_outlined,
                    label: 'LOCATION',
                  ),
                  const SizedBox(height: MyShopSpacing.sm),
                  _LocationCard(
                    label: effectiveJob.addressText ?? 'Location pending',
                    latitude: effectiveJob.latitude,
                    longitude: effectiveJob.longitude,
                  ),
                  const SizedBox(height: MyShopSpacing.md),
                  if (effectiveBidStatus == BidStatus.none) ...[
                    if (effectiveJob.artisansNotified != null &&
                        effectiveJob.artisansNotified! > 0)
                      _BidStatusCard(
                        artisansNotified: effectiveJob.artisansNotified!,
                      ),
                    const SizedBox(height: MyShopSpacing.lg),
                    if (_isBiddable(
                      effectiveJob,
                      artisanUserId: ref.watch(currentUserProvider)?.id,
                    )) ...[
                      // If the artisan started a bid in a previous session
                      // (or got force-killed mid-submit), surface a tappable
                      // banner above PLACE BID. The bid sheet itself
                      // restores the form values; this is just discoverability.
                      Builder(builder: (_) {
                        final draft = ref.watch(
                          bidDraftsProvider.select((s) => s[effectiveJob.id]),
                        );
                        if (draft == null) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(
                            bottom: MyShopSpacing.md,
                          ),
                          child: _BidDraftBanner(
                            submitting: draft.submitting,
                            onResume: draft.submitting
                                ? null
                                : () => BidSubmissionScreen.show(
                                      context,
                                      job: effectiveJob,
                                      distanceKm: distanceKm ?? 0,
                                    ),
                            onDiscard: draft.submitting
                                ? null
                                : () => ref
                                    .read(bidDraftsProvider.notifier)
                                    .remove(effectiveJob.id),
                          ),
                        );
                      }),
                      _PlaceBidButton(
                        onTap: () => BidSubmissionScreen.show(
                          context,
                          job: effectiveJob,
                          distanceKm: distanceKm ?? 0,
                        ),
                      ),
                      const SizedBox(height: MyShopSpacing.md),
                      _DeclineButton(
                        onTap: () {
                          ref
                              .read(pendingIncomingJobsProvider.notifier)
                              .remove(effectiveJob.id);
                          context.pop();
                        },
                      ),
                    ] else
                      _NotBiddableNotice(
                        status: effectiveJob.status,
                        assignedToMe: effectiveJob.assignedArtisanId != null &&
                            effectiveJob.assignedArtisanId ==
                                ref.watch(currentUserProvider)?.id,
                      ),
                  ] else ...[
                    Text(
                      'Your Submitted Bid',
                      style: MyShopTypography.h3.copyWith(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: MyShopSpacing.sm),
                    _SubmittedBidCard(
                      total: effectiveBidAmount,
                      feePercent: widget.platformFeePercent,
                    ),
                  ],
                  const SizedBox(height: MyShopSpacing.lg),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── helpers ─────────────────────────────────────────────────────────────────

/// Maps the artisan's live relationship with a job into a [BidStatus] the
/// banner can render. Mirrors the same derivation the My Jobs list uses so
/// the outcome the list shows ("ACCEPTED", "NOT SELECTED", etc.) and the
/// banner on the detail screen can't drift apart.
///
/// [fallback] is returned when the entry is ambiguous (no bid, job still
/// bidding) — callers pass the constructor's original `bidStatus` so we
/// don't regress to [BidStatus.none] mid-flight.
BidStatus _bidStatusFor(
  ArtisanJobEntry entry, {
  required BidStatus fallback,
}) {
  final status = entry.job.status;
  // Once the job has advanced into active work, the banner (and its
  // "Accept & Start Job" CTA) no longer apply — the artisan is already
  // en route. Return `none` so the caller hides the banner; the build
  // method pairs this with a redirect to `/active-job`.
  if (_isActiveWork(status)) return BidStatus.none;

  // Terminal / awaiting-settlement states take precedence over the bid
  // result because the job's global status is what actually governs what
  // the artisan can still do. Without this gate, a completed job where
  // the artisan won the bid would fall through to `bidAccepted` and the
  // request screen would offer "Accept & Start Job" on a job that's
  // already paid out.
  if (status == JobStatus.completed) return BidStatus.completed;
  if (status == JobStatus.pendingPayment) return BidStatus.awaitingPayment;
  if (status == JobStatus.cancelled) return BidStatus.cancelled;

  if (entry.bidAccepted) return BidStatus.accepted;
  if (entry.bidRejected) return BidStatus.notSelected;
  // A bid is only "pending" if the artisan actually placed one and it's
  // still awaiting a decision. Without this guard, every new incoming
  // job (status=open) surfaces as pending the moment it lands in the
  // backend's /jobs list, which hides the PLACE BID CTA entirely.
  if (entry.hasBid &&
      (status == JobStatus.pendingAdmin ||
          status == JobStatus.adminAssigned ||
          status == JobStatus.open ||
          status == JobStatus.queued)) {
    return BidStatus.pending;
  }
  if (entry.hasBid) return BidStatus.notSelected;
  return fallback;
}

/// True for the statuses the artisan moves through *after* tapping
/// "Accept & Start Job". These are owned by the /active-job screen.
bool _isActiveWork(JobStatus status) =>
    status == JobStatus.artisanEnRoute ||
    status == JobStatus.arrived ||
    status == JobStatus.inProgress ||
    status == JobStatus.artisanMarkedComplete;

/// Whether a bid can be placed on a job in its current state for the given
/// authenticated artisan.
///
/// Two bid-accepting states:
///   - `open`             → standard public bid window (first 5 min after post)
///   - `adminAssigned`    → admin manually routed the job to this specific
///                          artisan after the public window closed with zero
///                          bids. Only the assigned artisan may quote.
///
/// Everything else (`pendingAdmin`, `queued`, `confirmed+`, `cancelled`)
/// rejects bids with `JOB_NOT_OPEN` (400) — we mirror that gate in the UI.
bool _isBiddable(Job job, {String? artisanUserId}) {
  if (job.status == JobStatus.open) return true;
  if (job.status == JobStatus.adminAssigned) {
    // Only the artisan the admin picked can quote on an admin-assigned job.
    return artisanUserId != null &&
        job.assignedArtisanId != null &&
        job.assignedArtisanId == artisanUserId;
  }
  return false;
}

double _distanceKm(double lat1, double lng1, double lat2, double lng2) {
  final meters = Geolocator.distanceBetween(lat1, lng1, lat2, lng2);
  return meters / 1000;
}

/// Banner shown in place of the "Place Bid" button when the job isn't in
/// a state that accepts bids (pending admin approval, already confirmed,
/// cancelled, etc.).
class _NotBiddableNotice extends StatelessWidget {
  const _NotBiddableNotice({
    required this.status,
    this.assignedToMe = false,
  });

  final JobStatus status;

  /// True when the job is admin-assigned and this artisan is the one
  /// picked. (We only get here if `_isBiddable` returned false — which for
  /// an admin-assigned job means the assignment belongs to someone else,
  /// so this is almost always false.)
  final bool assignedToMe;

  (String, String, IconData, Color) get _content {
    switch (status) {
      case JobStatus.pendingAdmin:
        return (
          'Awaiting admin review',
          "No artisans bid on this job in time. An admin is reviewing it "
              'and will assign it shortly.',
          Icons.hourglass_top,
          MyShopColors.warning,
        );
      case JobStatus.adminAssigned:
        return assignedToMe
            ? (
                'Ready to quote',
                'You can submit your price on this job.',
                Icons.check_circle_outline,
                MyShopColors.success,
              )
            : (
                'Assigned to another artisan',
                'An admin has routed this job to a different artisan.',
                Icons.lock_outline,
                MyShopColors.textSecondary,
              );
      case JobStatus.queued:
        return (
          'Queued',
          "This job is waiting for artisans to become available. Check back shortly.",
          Icons.schedule,
          MyShopColors.warning,
        );
      case JobStatus.confirmed:
      case JobStatus.artisanEnRoute:
      case JobStatus.arrived:
      case JobStatus.inProgress:
      case JobStatus.artisanMarkedComplete:
      case JobStatus.pendingPayment:
      case JobStatus.completed:
        return (
          'Already assigned',
          "The client has already chosen an artisan for this job.",
          Icons.lock_outline,
          MyShopColors.textSecondary,
        );
      case JobStatus.cancelled:
        return (
          'Cancelled',
          "This job has been cancelled and is no longer accepting bids.",
          Icons.cancel_outlined,
          MyShopColors.error,
        );
      case JobStatus.open:
        return (
          'Ready',
          'You can place a bid on this job.',
          Icons.check_circle_outline,
          MyShopColors.success,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final (title, body, icon, color) = _content;
    return Container(
      padding: const EdgeInsets.all(MyShopSpacing.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: MyShopSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: MyShopTypography.h3.copyWith(
                    color: color,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: MyShopTypography.body2.copyWith(
                    color: MyShopColors.textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _formatPostedAgo(String? createdAt) {
  if (createdAt == null) return 'Just posted';
  final parsed = DateTime.tryParse(createdAt);
  if (parsed == null) return 'Just posted';
  final diff = DateTime.now().toUtc().difference(parsed.toUtc());
  if (diff.inSeconds < 30) return 'Just posted';
  if (diff.inMinutes < 1) return '${diff.inSeconds}s ago';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}

// ─────────────────────────────────────────────────────────────────────────────
// Header
// ─────────────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.requestId});

  final String requestId;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        MyShopSpacing.sm,
        MyShopSpacing.sm,
        MyShopSpacing.md,
        MyShopSpacing.md,
      ),
      decoration: const BoxDecoration(
        color: MyShopColors.surfaceWhite,
        border: Border(
          bottom: BorderSide(color: MyShopColors.divider),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: MyShopColors.textPrimary),
            onPressed: () => context.pop(),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Request Details',
                style: MyShopTypography.h1.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'ID: $requestId',
                style: MyShopTypography.overline.copyWith(
                  color: MyShopColors.textSecondary,
                  fontSize: 11,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Client summary card
// ─────────────────────────────────────────────────────────────────────────────

class _ClientSummaryCard extends StatelessWidget {
  const _ClientSummaryCard({
    required this.clientName,
    required this.clientPhotoUrl,
    required this.clientLocation,
    required this.distanceKm,
    required this.title,
    required this.postedAgo,
  });

  final String clientName;
  final String? clientPhotoUrl;
  final String clientLocation;
  final double? distanceKm;
  final String title;
  final String postedAgo;

  @override
  Widget build(BuildContext context) {
    final distanceText =
        distanceKm != null ? '${distanceKm!.toStringAsFixed(1)} km away' : '—';

    return Container(
      padding: const EdgeInsets.all(MyShopSpacing.md),
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MyShopColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _ClientAvatar(photoUrl: clientPhotoUrl),
              const SizedBox(width: MyShopSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      clientName,
                      style: MyShopTypography.h3.copyWith(fontSize: 16),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(
                          Icons.location_on,
                          size: 14,
                          color: MyShopColors.primaryGold,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            '$clientLocation  •  $distanceText',
                            style: MyShopTypography.body2.copyWith(
                              color: MyShopColors.primaryGold,
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: MyShopColors.error,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'NOW',
                  style: MyShopTypography.caption.copyWith(
                    color: MyShopColors.textOnPrimary,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: MyShopSpacing.md),
          const Divider(height: 1, color: MyShopColors.divider),
          const SizedBox(height: MyShopSpacing.md),
          Text(
            title,
            style: MyShopTypography.h2.copyWith(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              height: 1.3,
            ),
          ),
          const SizedBox(height: MyShopSpacing.sm),
          Row(
            children: [
              const Icon(
                Icons.access_time,
                size: 14,
                color: MyShopColors.textSecondary,
              ),
              const SizedBox(width: 4),
              Text(postedAgo, style: MyShopTypography.body2),
            ],
          ),
        ],
      ),
    );
  }
}

class _ClientAvatar extends StatelessWidget {
  const _ClientAvatar({required this.photoUrl});

  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    if (photoUrl != null && photoUrl!.isNotEmpty) {
      return ClipOval(
        child: CachedNetworkImage(
          imageUrl: photoUrl!,
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          // Decode at ~3x retina. Without this, a 12MP avatar upload
          // decodes to ~50 MB in RAM even though we only draw 48×48.
          memCacheWidth: 144,
          memCacheHeight: 144,
          placeholder: (_, __) => _placeholder(),
          errorWidget: (_, __, ___) => _placeholder(),
        ),
      );
    }
    return _placeholder();
  }

  Widget _placeholder() {
    return Container(
      width: 48,
      height: 48,
      decoration: const BoxDecoration(
        color: MyShopColors.avatarPlaceholder,
        shape: BoxShape.circle,
      ),
      child: const Icon(
        Icons.person,
        color: MyShopColors.textSecondary,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section header (icon + uppercase label)
// ─────────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: MyShopColors.textPrimary),
        const SizedBox(width: MyShopSpacing.sm),
        Text(
          label,
          style: MyShopTypography.overline.copyWith(
            color: MyShopColors.textPrimary,
            fontWeight: FontWeight.w900,
            fontSize: 12,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Description card
// ─────────────────────────────────────────────────────────────────────────────

class _DescriptionCard extends StatelessWidget {
  const _DescriptionCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(MyShopSpacing.md),
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MyShopColors.divider),
      ),
      child: Text(
        text,
        style: MyShopTypography.body1.copyWith(
          color: MyShopColors.textPrimary,
          fontWeight: FontWeight.w400,
          height: 1.55,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Photos row — real Cloudinary URLs
// ─────────────────────────────────────────────────────────────────────────────

class _PhotosRow extends StatelessWidget {
  const _PhotosRow({required this.photos});

  final List<String> photos;

  @override
  Widget build(BuildContext context) {
    // Show up to 3 inline; collapse the rest into a "+N More" tile.
    const maxInline = 3;
    final inlineCount = photos.length > maxInline ? maxInline : photos.length;
    final remaining = photos.length - inlineCount;

    return SizedBox(
      height: 110,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (int i = 0; i < inlineCount; i++) ...[
            _PhotoThumb(
              url: photos[i],
              onTap: () => _openGallery(context, photos, i),
            ),
            const SizedBox(width: MyShopSpacing.md),
          ],
          if (remaining > 0)
            _MorePhotosTile(
              remaining: remaining,
              onTap: () => _openGallery(context, photos, inlineCount),
            ),
        ],
      ),
    );
  }

  void _openGallery(BuildContext context, List<String> urls, int initialIndex) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _PhotoGallery(urls: urls, initialIndex: initialIndex),
      ),
    );
  }
}

class _PhotoThumb extends StatelessWidget {
  const _PhotoThumb({required this.url, required this.onTap});

  final String url;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: CachedNetworkImage(
          imageUrl: url,
          width: 110,
          height: 110,
          fit: BoxFit.cover,
          // Decode at ~3x retina. A 12MP client upload otherwise takes
          // ~50 MB per thumb — three of them blow past iOS's jetsam limit.
          memCacheWidth: 330,
          memCacheHeight: 330,
          placeholder: (_, __) => Container(
            width: 110,
            height: 110,
            color: MyShopColors.surfaceGrey,
          ),
          errorWidget: (_, __, ___) => Container(
            width: 110,
            height: 110,
            color: MyShopColors.surfaceGrey,
            alignment: Alignment.center,
            child: const Icon(
              Icons.broken_image_outlined,
              color: MyShopColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _MorePhotosTile extends StatelessWidget {
  const _MorePhotosTile({required this.remaining, required this.onTap});

  final int remaining;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: DottedBorderBox(
        child: Container(
          width: 90,
          height: 110,
          alignment: Alignment.center,
          child: Text(
            '+$remaining More',
            style: MyShopTypography.body1.copyWith(
              color: MyShopColors.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _PhotoGallery extends StatelessWidget {
  const _PhotoGallery({required this.urls, required this.initialIndex});

  final List<String> urls;
  final int initialIndex;

  @override
  Widget build(BuildContext context) {
    // Cap decode resolution to the device's pixel width so the user gets
    // a sharp image without the app holding a 50 MB bitmap per page.
    final size = MediaQuery.sizeOf(context);
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    final decodeWidth = (size.width * devicePixelRatio).round();
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: PageView.builder(
        controller: PageController(initialPage: initialIndex),
        itemCount: urls.length,
        itemBuilder: (_, i) => InteractiveViewer(
          child: Center(
            child: CachedNetworkImage(
              imageUrl: urls[i],
              fit: BoxFit.contain,
              memCacheWidth: decodeWidth,
              errorWidget: (_, __, ___) => const Icon(
                Icons.broken_image_outlined,
                color: Colors.white,
                size: 64,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Lightweight dashed-border container — avoids pulling in a third-party dep.
class DottedBorderBox extends StatelessWidget {
  const DottedBorderBox({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedBorderPainter(),
      child: child,
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = MyShopColors.divider
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(12),
    );

    final path = Path()..addRRect(rrect);
    const dashWidth = 5.0;
    const dashSpace = 4.0;

    for (final metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final next = distance + dashWidth;
        canvas.drawPath(
          metric.extractPath(distance, next.clamp(0, metric.length)),
          paint,
        );
        distance = next + dashSpace;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
// Location card — real Google Map
// ─────────────────────────────────────────────────────────────────────────────

class _LocationCard extends StatelessWidget {
  const _LocationCard({
    required this.label,
    required this.latitude,
    required this.longitude,
  });

  final String label;
  final double latitude;
  final double longitude;

  Future<void> _openDirections(BuildContext context) async {
    // Use the device's "pick" behavior where possible:
    //  - iOS: Apple Maps (always installed) with driving directions.
    //  - Android: `geo:` with a directions query so Google Maps or whatever
    //    the user has mapped to the geo intent picks it up.
    //  - Fallback (web or unknown): Google Maps URL that works in Safari /
    //    Chrome and also opens the GMaps app if installed.
    final candidates = <Uri>[
      if (Platform.isIOS)
        Uri.parse('http://maps.apple.com/?daddr=$latitude,$longitude&dirflg=d')
      else if (Platform.isAndroid)
        Uri.parse('geo:$latitude,$longitude?q=$latitude,$longitude'),
      Uri.parse(
        'https://www.google.com/maps/dir/?api=1'
        '&destination=$latitude,$longitude&travelmode=driving',
      ),
    ];

    for (final uri in candidates) {
      try {
        final launched = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        if (launched) return;
      } catch (_) {
        // Try the next candidate.
      }
    }

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Could not open a maps app.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _openDirections(context),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: MyShopColors.surfaceWhite,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: MyShopColors.divider),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            // A full `GoogleMap` widget here is a ~50 MB native GL
            // allocation per mount — on iOS `liteModeEnabled` is ignored
            // so every request-details open ate that cost even though
            // this preview is only 160 px tall. Swap for a Google Static
            // Maps PNG — it's a ~30 KB image, cached and sized to the
            // screen, and the tap handler already launches real maps.
            SizedBox(
              height: 160,
              child: _StaticMapPreview(
                latitude: latitude,
                longitude: longitude,
                onTap: () => _openDirections(context),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: MyShopSpacing.md,
                vertical: MyShopSpacing.sm,
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.location_on,
                    size: 16,
                    color: MyShopColors.textPrimary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      label,
                      style: MyShopTypography.body1,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: MyShopColors.primaryGold,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.navigation,
                          size: 14,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Navigate',
                          style: MyShopTypography.body2.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Static-map preview — replaces the heavy `GoogleMap` preview on the
// request-details screen. Uses Google's Static Maps endpoint to fetch a
// PNG sized to the card; that's a ~30 KB bitmap vs. a full GL map
// instance that costs ~50 MB of native memory per mount and was
// blowing iOS's jetsam budget on open.
// ─────────────────────────────────────────────────────────────────────────────

class _StaticMapPreview extends StatelessWidget {
  const _StaticMapPreview({
    required this.latitude,
    required this.longitude,
    required this.onTap,
  });

  final double latitude;
  final double longitude;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final widthPx = (MediaQuery.sizeOf(context).width.clamp(320, 640)).round();
    // Static Maps caps scale at 2 — anything beyond renders aliased but
    // doesn't buy more resolution, so clamp to stay within quota.
    final scale = dpr >= 2 ? 2 : 1;
    final url = Uri.https(
      'maps.googleapis.com',
      '/maps/api/staticmap',
      {
        'center': '$latitude,$longitude',
        'zoom': '15',
        'size': '${widthPx}x160',
        'scale': '$scale',
        'markers': 'color:orange|$latitude,$longitude',
        'key': MapsConfig.apiKey,
      },
    ).toString();

    return GestureDetector(
      onTap: onTap,
      child: CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        // Decode at the displayed width so the bitmap in RAM stays small.
        memCacheWidth: (widthPx * scale).toInt(),
        placeholder: (_, __) => Container(
          color: MyShopColors.surfaceGrey,
          alignment: Alignment.center,
          child: const Icon(
            Icons.map_outlined,
            color: MyShopColors.textSecondary,
          ),
        ),
        errorWidget: (_, __, ___) => Container(
          color: MyShopColors.surfaceGrey,
          alignment: Alignment.center,
          child: const Icon(
            Icons.map_outlined,
            color: MyShopColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bid status card — uses real artisansNotified count
// ─────────────────────────────────────────────────────────────────────────────

class _BidStatusCard extends StatelessWidget {
  const _BidStatusCard({required this.artisansNotified});

  final int artisansNotified;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(MyShopSpacing.md),
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MyShopColors.divider),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.group_outlined,
            size: 18,
            color: MyShopColors.primaryGold,
          ),
          const SizedBox(width: MyShopSpacing.sm),
          Expanded(
            child: Text(
              '$artisansNotified artisan${artisansNotified == 1 ? '' : 's'} '
              'notified — be quick to bid',
              style: MyShopTypography.body1,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Action buttons
// ─────────────────────────────────────────────────────────────────────────────

class _PlaceBidButton extends StatelessWidget {
  const _PlaceBidButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: MyShopColors.darkSlate,
          borderRadius: BorderRadius.circular(28),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 14,
              offset: Offset(0, 6),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Text(
          'PLACE BID',
          style: MyShopTypography.button.copyWith(
            color: MyShopColors.textOnDarkSlate,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
            fontSize: 15,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Submitted bid summary (dashed border)
// ─────────────────────────────────────────────────────────────────────────────

class _SubmittedBidCard extends StatelessWidget {
  const _SubmittedBidCard({required this.total, required this.feePercent});

  final num total;
  final num feePercent;

  @override
  Widget build(BuildContext context) {
    final fee = (total * feePercent) / 100;
    final net = total - fee;
    return DottedBorderBox(
      child: Padding(
        padding: const EdgeInsets.all(MyShopSpacing.md),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Total Bid Amount',
                    style: MyShopTypography.body1.copyWith(
                      color: MyShopColors.textSecondary,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
                Text(
                  'GHS ${total.toStringAsFixed(2)}',
                  style: MyShopTypography.h3.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: MyShopSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Platform Fee (${feePercent.toInt()}%)',
                    style: MyShopTypography.body1.copyWith(
                      color: MyShopColors.textSecondary,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
                Text(
                  '-GHS ${fee.toStringAsFixed(2)}',
                  style: MyShopTypography.body1.copyWith(
                    color: MyShopColors.error,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: MyShopSpacing.sm),
            const Divider(height: 1, color: MyShopColors.divider),
            const SizedBox(height: MyShopSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Estimated Net',
                    style: MyShopTypography.body1.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  'GHS ${net.toStringAsFixed(2)}',
                  style: MyShopTypography.h3.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Resume-draft banner — shown above PLACE BID when a previous session left
// an unsubmitted draft on this job. Tap to reopen the bid sheet (which
// rehydrates from the draft); × to discard. While the draft is mid-submit
// (app got killed between request fire and ACK), both controls are inert
// and the banner reads "Submitting your bid…" — the app-bootstrap
// reconcile in `BidDraftsNotifier.reconcile` resolves it shortly after.
// ─────────────────────────────────────────────────────────────────────────────

class _BidDraftBanner extends StatelessWidget {
  const _BidDraftBanner({
    required this.submitting,
    required this.onResume,
    required this.onDiscard,
  });

  final bool submitting;
  final VoidCallback? onResume;
  final VoidCallback? onDiscard;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onResume,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: MyShopSpacing.md,
          vertical: MyShopSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: MyShopColors.primaryGold.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: MyShopColors.primaryGold.withValues(alpha: 0.45),
          ),
        ),
        child: Row(
          children: [
            if (submitting)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(
                    MyShopColors.primaryGold,
                  ),
                ),
              )
            else
              const Icon(
                Icons.drafts_outlined,
                size: 20,
                color: MyShopColors.primaryGold,
              ),
            const SizedBox(width: MyShopSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    submitting
                        ? 'Submitting your bid…'
                        : 'Draft saved · tap to continue',
                    style: MyShopTypography.body1.copyWith(
                      fontWeight: FontWeight.w800,
                      color: MyShopColors.textPrimary,
                    ),
                  ),
                  Text(
                    submitting
                        ? 'Hang tight — we\'re confirming with the server.'
                        : 'Your last entries are saved on this device.',
                    style: MyShopTypography.body2.copyWith(
                      color: MyShopColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (!submitting)
              IconButton(
                icon: const Icon(
                  Icons.close,
                  size: 18,
                  color: MyShopColors.textSecondary,
                ),
                onPressed: onDiscard,
                tooltip: 'Discard draft',
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
      ),
    );
  }
}

class _DeclineButton extends StatelessWidget {
  const _DeclineButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: MyShopColors.surfaceWhite,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: MyShopColors.divider),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: MyShopColors.surfaceWhite,
                shape: BoxShape.circle,
                border: Border.all(color: MyShopColors.error, width: 1.5),
              ),
              child: const Icon(
                Icons.close,
                size: 14,
                color: MyShopColors.error,
              ),
            ),
            const SizedBox(width: MyShopSpacing.sm),
            Text(
              'Decline',
              style: MyShopTypography.button.copyWith(
                color: MyShopColors.error,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
