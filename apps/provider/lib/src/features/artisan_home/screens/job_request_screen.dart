import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io' show Platform;

import 'package:api_client/api_client.dart'
    show ApiException, userSafeApiErrorMessage;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:shared_utils/shared_utils.dart' as geo_utils;
import 'package:url_launcher/url_launcher.dart';

import '../../../core/di/providers.dart';
import '../../../core/providers/socket_provider.dart';
import '../../../core/services/incoming_request_overlay_presenter.dart';
import '../../../core/services/local_notification_service.dart';
import '../../../core/widgets/incoming_request_map_preview.dart';

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
    this.openBidSheet = false,
  });

  final Job job;
  final BidStatus bidStatus;
  final num submittedBidAmount;

  /// True for the native "Submit bid" notification action. The request
  /// screen hydrates first, then opens the existing bid form once.
  final bool openBidSheet;

  @override
  ConsumerState<JobRequestScreen> createState() => _JobRequestScreenState();
}

class _JobRequestScreenState extends ConsumerState<JobRequestScreen> {
  /// One-shot — prevents the active-work redirect from being scheduled on
  /// every rebuild (the `artisanJobsProvider` watch can fire many times
  /// during a status-update cycle, and stacking post-frame callbacks used
  /// to thrash navigation and retain widgets in memory).
  bool _hasRedirectedToActiveJob = false;
  bool _didAutoOpenBidSheet = false;
  bool _decliningRequest = false;

  /// Full-fat job fetched from `GET /jobs/:id` on mount. The artisan jobs
  /// feed (`GET /jobs`) returns slim records that drop client identity
  /// fields, so when the artisan opens the details from "My Jobs" (any
  /// tab — active, bids, completed) the constructor's `widget.job` has
  /// no client name / phone / photo. Hydrating once on mount fills those
  /// in for the entire screen + downstream active-job + chat handoff.
  Job? _hydratedJob;

  /// True while `GET /jobs/:id` is in flight on first mount. Drives the
  /// stub-mode loading skeleton — without it, an FCM-tap landing here
  /// with a placeholder Job would render the screen empty (lat/lng = 0,
  /// no description, "Location pending") until the fetch comes back.
  bool _hydrating = false;
  String? _hydrationError;

  /// True when [widget.job] is a stub (only an id and placeholder
  /// fields), meaning we have nothing useful to render until
  /// [_hydrateJob] completes. The FCM-tap handler creates such stubs;
  /// the modal/socket/poller paths always pass a fully-populated Job.
  bool get _hasUsableSeedData =>
      widget.job.description.isNotEmpty ||
      widget.job.latitude != 0 ||
      widget.job.longitude != 0;

  @override
  void initState() {
    super.initState();
    // Post-frame: modifying a provider synchronously inside initState can
    // fire rebuilds of widgets that are still building. Mirrors the ride
    // request screen's visible-marker handshake.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(visibleJobRequestIdProvider.notifier).state = widget.job.id;
    });
    _hydrateJob();
  }

  @override
  void dispose() {
    // Release the visible marker so the next notification tap for this job
    // navigates again. Guarded: a replacement screen for the same job may
    // already own the marker, and the container can be tearing down.
    try {
      final visibleId = ref.read(visibleJobRequestIdProvider);
      if (visibleId == widget.job.id) {
        ref.read(visibleJobRequestIdProvider.notifier).state = null;
      }
    } catch (_) {}
    super.dispose();
  }

  /// Fetch the full job record. Tracks loading + error state so the
  /// stub-data path (FCM tap with only a jobId) can render a skeleton
  /// while in-flight and an error/retry surface if the fetch ultimately
  /// fails. The non-stub path (modal/socket/poller) treats this as a
  /// best-effort enrichment — the screen falls back to `widget.job`'s
  /// already-populated fields.
  Future<void> _hydrateJob() async {
    setState(() {
      _hydrating = true;
      _hydrationError = null;
    });
    try {
      final raw = await ref.read(jobServiceProvider).getJob(widget.job.id);
      if (!mounted) return;
      setState(() {
        _hydratedJob = Job.fromJson(raw);
        _hydrating = false;
      });
      _scheduleAutoOpenBidSheet();
    } catch (e) {
      debugPrint('[JobRequest] hydration failed: ${e.runtimeType}');
      developer.log(
        'Job hydration failed: ${e.runtimeType}',
        name: 'JobRequest',
        level: 800,
      );
      if (!mounted) return;
      setState(() {
        _hydrating = false;
        _hydrationError = e.toString();
      });
      if (_hasUsableSeedData) _scheduleAutoOpenBidSheet();
    }
  }

  void _scheduleAutoOpenBidSheet() {
    if (!widget.openBidSheet || _didAutoOpenBidSheet) return;
    _didAutoOpenBidSheet = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        BidSubmissionScreen.show(
          context,
          job: _sourceJob,
          distanceKm: 0,
        ),
      );
    });
  }

  Future<void> _declineRequest(Job job) async {
    if (_decliningRequest) return;
    if (job.isAdminAssigned) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Decline assigned job?'),
          content: const Text(
            'MyShop assigned this request specifically to you. Declining sends '
            'it back for reassignment and you will no longer be able to quote.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Keep assignment'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: TextButton.styleFrom(foregroundColor: MyShopColors.error),
              child: const Text('Decline assignment'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    setState(() => _decliningRequest = true);
    try {
      await ref.read(jobServiceProvider).declineJobRequest(
            job.id,
            reason: 'provider_declined',
          );
      ref.read(pendingIncomingJobsProvider.notifier).remove(job.id);
      await clearIncomingRequestAlert(
        type: NotificationPayload.typeJobRequest,
        requestId: job.id,
      );
      if (mounted) context.pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _decliningRequest = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(job.isAdminAssigned
              ? 'Could not decline this assignment. Please try again.'
              : 'Could not decline this request. Please try again.'),
        ),
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
    // FCM-tap entry path hands us a stub Job with only an id — show a
    // loading skeleton (or error/retry) until `_hydrateJob` returns
    // real data, otherwise the screen renders "Location pending", an
    // empty description and a 0/0 map until the fetch lands. Skipped
    // when the constructor copy already has usable fields (modal,
    // socket, poller, in-app navigation), or once hydration succeeded.
    if (!_hasUsableSeedData && _hydratedJob == null) {
      if (_hydrationError != null) {
        return _JobRequestLoadFailureScreen(
          onRetry: _hydrateJob,
        );
      }
      if (_hydrating) {
        return _JobRequestLoadingScreen(requestId: _requestId);
      }
    }

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
            assignment: liveEntry.job.assignment ?? source.assignment,
            assignedArtisanId:
                liveEntry.job.assignedArtisanId ?? source.assignedArtisanId,
            assignedByAdmin:
                liveEntry.job.assignedByAdmin ?? source.assignedByAdmin,
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
    // Straight-line ETA from the artisan's current position to the
    // client. Computed alongside distance so the summary card can show
    // both without re-watching the location stream.
    final etaMinutes = distanceKm == null
        ? null
        : geo_utils.estimatedEtaMinutes(distanceKm * 1000);
    final currentUser = ref.watch(currentUserProvider);
    int? minimumBidPesewas;
    final categoryLinks = currentUser?.artisanProfile?.serviceCategories;
    if (categoryLinks != null) {
      for (final link in categoryLinks) {
        if (link.categoryId == effectiveJob.categoryId ||
            link.category.id == effectiveJob.categoryId) {
          minimumBidPesewas = link.category.minBidPesewas;
          break;
        }
      }
    }
    final canPlaceBid = effectiveBidStatus == BidStatus.none &&
        isJobBiddableForArtisan(
          effectiveJob,
          artisanUserId: currentUser?.id,
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
                      // Anchor the countdown to the actual bid expiry. Prefer
                      // the local SubmittedBid (set the moment we ACK a fresh
                      // submission), fall back to the live entry's
                      // bidSubmittedAt + 5-minute window so the timer is
                      // correct even when the bid came back from the
                      // backend's /jobs feed without ever passing through
                      // local state — otherwise the banner would default to
                      // "now + 5min" and visually reset every time the
                      // screen opens.
                      expiresAt: ref
                              .watch(submittedBidsProvider)[effectiveJob.id]
                              ?.expiresAt ??
                          _bidExpiresFromLive(liveEntry),
                      // Admin-assigned jobs have no bid window — swap the
                      // countdown for a "Quote when ready" hint.
                      showCountdown:
                          effectiveJob.status != JobStatus.adminAssigned,
                      directedAssignment: effectiveJob.isAdminAssigned,
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
                      onEdit: effectiveBidStatus == BidStatus.pending &&
                              liveEntry?.bidId != null
                          ? () => BidSubmissionScreen.show(
                                context,
                                job: effectiveJob,
                                editingBidId: liveEntry!.bidId,
                                initialAmountPesewas:
                                    liveEntry.bidAmountPesewas,
                                initialEtaMinutes: liveEntry.bidEtaMinutes,
                                initialDurationMinutes:
                                    liveEntry.bidDurationMinutes,
                                initialNotes: liveEntry.bidMessage,
                              )
                          : null,
                      onWithdraw: effectiveBidStatus == BidStatus.pending &&
                              liveEntry?.bidId != null
                          ? () => _confirmAndWithdraw(
                                context,
                                jobId: effectiveJob.id,
                                bidId: liveEntry!.bidId!,
                              )
                          : null,
                    ),
                    const SizedBox(height: MyShopSpacing.md),
                  ],
                  _JobDecisionHero(
                    title: _title,
                    minimumBidPesewas: minimumBidPesewas,
                    distanceKm: distanceKm,
                    etaMinutes: etaMinutes,
                    postedAgo: _formatPostedAgo(effectiveJob.createdAt),
                  ),
                  if (effectiveJob.isAdminAssigned &&
                      effectiveBidStatus == BidStatus.none) ...[
                    const SizedBox(height: MyShopSpacing.sm),
                    const _DirectedAssignmentNotice(),
                  ],
                  const SizedBox(height: MyShopSpacing.md),
                  _LocationCard(
                    label: effectiveJob.addressText ?? 'Location pending',
                    latitude: effectiveJob.latitude,
                    longitude: effectiveJob.longitude,
                  ),
                  const SizedBox(height: MyShopSpacing.md),
                  _ClientSummaryCard(
                    clientName: effectiveJob.clientName ?? 'Client',
                    clientPhotoUrl: effectiveJob.clientPhotoUrl,
                    distanceKm: distanceKm,
                    etaMinutes: etaMinutes,
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
                  const SizedBox(height: MyShopSpacing.md),
                  if (effectiveBidStatus == BidStatus.none) ...[
                    if (effectiveJob.artisansNotified != null &&
                        effectiveJob.artisansNotified! > 0)
                      _BidStatusCard(
                        artisansNotified: effectiveJob.artisansNotified!,
                      ),
                    const SizedBox(height: MyShopSpacing.lg),
                    if (canPlaceBid) ...[
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
                    ] else
                      _NotBiddableNotice(
                        status: effectiveJob.status,
                        assignmentPhase: effectiveJob.assignment?.phase,
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
                      // Estimate only; the backend snapshots the authoritative
                      // rate when money is finalized. Never invent a fallback.
                      feePercent:
                          ref.watch(commissionRatePercentProvider).valueOrNull,
                    ),
                  ],
                  const SizedBox(height: MyShopSpacing.lg),
                ],
              ),
            ),
            if (canPlaceBid)
              _JobRequestActionBar(
                onSubmitBid: () => BidSubmissionScreen.show(
                  context,
                  job: effectiveJob,
                  distanceKm: distanceKm ?? 0,
                ),
                onSkip: () => _declineRequest(effectiveJob),
                skipping: _decliningRequest,
                directedAssignment: effectiveJob.isAdminAssigned,
              ),
          ],
        ),
      ),
    );
  }

  /// Backend-anchored bid expiry. Prefers the explicit `expiresAt` from
  /// the live entry's `myBid` payload; falls back to `bidSubmittedAt + 5min`
  /// (the default bidding window) when only the submission time is known.
  /// Returns null when neither is available — the banner will then degrade
  /// to its "now + 5min" default, but only as a last resort.
  DateTime? _bidExpiresFromLive(ArtisanJobEntry? entry) {
    if (entry == null) return null;
    final explicit = entry.bidExpiresAt;
    if (explicit != null) {
      final parsed = DateTime.tryParse(explicit);
      if (parsed != null) return parsed;
    }
    final submitted = entry.bidSubmittedAt;
    if (submitted != null) {
      final parsed = DateTime.tryParse(submitted);
      if (parsed != null) return parsed.add(const Duration(minutes: 5));
    }
    return null;
  }

  /// Confirm + DELETE the artisan's pending bid. On success: clear the
  /// local SubmittedBid record (so the banner's countdown resets), kick a
  /// silent reload of /jobs (so `myBid` drops off), and pop back to home.
  Future<void> _confirmAndWithdraw(
    BuildContext context, {
    required String jobId,
    required String bidId,
  }) async {
    // Capture context-bound objects up-front so we don't reach into the
    // BuildContext after async gaps once the screen could be unmounted.
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Withdraw bid?'),
        content: const Text(
          "Your bid will be removed and the client won't see it anymore. "
          "You can place a new bid later if the job is still open.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: MyShopColors.error),
            child: const Text('Withdraw'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;

    try {
      await ref.read(jobServiceProvider).withdrawBid(jobId, bidId);
    } on ApiException catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(_friendlyWithdrawError(e))),
      );
      return;
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text("Couldn't withdraw the bid. Please try again."),
        ),
      );
      return;
    }

    // Success path: drop local persistence so the resume banner / countdown
    // don't linger, refresh the live feed so `myBid` falls away, then leave
    // the request details screen — the bid is gone, there's nothing to
    // monitor here.
    await ref.read(submittedBidsProvider.notifier).remove(jobId);
    try {
      ref.read(artisanJobsProvider.notifier).silentReload();
    } catch (_) {}
    if (!mounted) return;
    messenger.showSnackBar(
      const SnackBar(content: Text('Bid withdrawn.')),
    );
    if (router.canPop()) {
      router.pop();
    } else {
      router.go('/home');
    }
  }

  String _friendlyWithdrawError(ApiException e) {
    switch (e.errorCode) {
      case 'BID_ALREADY_ACCEPTED':
        return "The client already accepted this bid — you can't withdraw "
            'it now. Use the booking-cancel flow instead.';
      case 'BID_NOT_PENDING':
        return "This bid isn't pending anymore.";
      case 'JOB_NOT_IN_BIDDING_PHASE':
        return "The job has moved past bidding — withdraw isn't available.";
      case 'NOT_BID_OWNER':
        return 'Only the bid owner can withdraw it.';
      default:
        return userSafeApiErrorMessage(
          e,
          fallback: "Couldn't withdraw the bid. Please try again.",
          conflictMessage:
              'The bid changed before it could be withdrawn. Refresh and try again.',
        );
    }
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
bool isJobBiddableForArtisan(Job job, {String? artisanUserId}) {
  if (job.status == JobStatus.open) return true;
  if (job.status == JobStatus.adminAssigned) {
    final phase = job.assignment?.phase;
    if (phase != null && phase != JobAssignmentPhase.awaitingQuote) {
      return false;
    }
    // Only the artisan the admin picked can quote on an admin-assigned job.
    return artisanUserId != null &&
        job.assignedArtisanId != null &&
        job.assignedArtisanId == artisanUserId;
  }
  return false;
}

({String primary, String secondary}) jobRequestActionLabels({
  required bool directedAssignment,
}) =>
    directedAssignment
        ? (primary: 'Submit quote', secondary: 'Decline assignment')
        : (primary: 'Submit bid', secondary: 'Skip');

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
    this.assignmentPhase,
  });

  final JobStatus status;

  /// True when the job is admin-assigned and this artisan is the one picked.
  /// The notice also uses this after a quote advances beyond `awaiting_quote`.
  final bool assignedToMe;
  final JobAssignmentPhase? assignmentPhase;

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
        if (assignmentPhase == JobAssignmentPhase.awaitingAdminReview) {
          return (
            'Quote under review',
            'Your quote was submitted and is being reviewed. Wait for the next update before starting work.',
            Icons.fact_check_outlined,
            MyShopColors.warning,
          );
        }
        if (assignmentPhase == JobAssignmentPhase.awaitingClientAccept) {
          return (
            'Waiting for client',
            'Your quote was sent to the client. Start work only after they accept it.',
            Icons.hourglass_top,
            MyShopColors.warning,
          );
        }
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
// Decision summary + client card
// ─────────────────────────────────────────────────────────────────────────────

class _DirectedAssignmentNotice extends StatelessWidget {
  const _DirectedAssignmentNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(MyShopSpacing.md),
      decoration: BoxDecoration(
        color: MyShopColors.infoLight,
        borderRadius: BorderRadius.circular(MyShopRadius.card),
        border: Border.all(color: MyShopColors.info.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.assignment_ind_outlined,
              color: MyShopColors.info, size: 20),
          const SizedBox(width: MyShopSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Assigned to you by MyShop',
                  style: MyShopTypography.body1.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Review the request, submit your quote, then wait for the '
                  'client to accept it before starting work.',
                  style: MyShopTypography.body2.copyWith(
                    color: MyShopColors.textSecondary,
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

class _JobDecisionHero extends StatelessWidget {
  const _JobDecisionHero({
    required this.title,
    required this.minimumBidPesewas,
    required this.distanceKm,
    required this.etaMinutes,
    required this.postedAgo,
  });

  final String title;
  final int? minimumBidPesewas;
  final double? distanceKm;
  final int? etaMinutes;
  final String postedAgo;

  @override
  Widget build(BuildContext context) {
    final minimumBid = minimumBidPesewas;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(MyShopSpacing.md),
      decoration: BoxDecoration(
        color: MyShopColors.primaryGoldLight,
        borderRadius: BorderRadius.circular(MyShopRadius.card),
        border: Border.all(
          color: MyShopColors.primaryGold.withValues(alpha: 0.24),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: MyShopTypography.h2.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: MyShopSpacing.sm,
                  vertical: MyShopSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: MyShopColors.surfaceWhite,
                  borderRadius: BorderRadius.circular(MyShopRadius.pill),
                ),
                child: Text(
                  'NEW',
                  style: MyShopTypography.overline.copyWith(
                    color: MyShopColors.primaryGoldDark,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: MyShopSpacing.md),
          Text(
            minimumBid == null ? 'PRICE' : 'MINIMUM BID',
            style: MyShopTypography.overline.copyWith(
              color: MyShopColors.primaryGoldDark,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            minimumBid == null
                ? 'Submit your quote'
                : 'GHS ${(minimumBid / 100).toStringAsFixed(2)}',
            style: minimumBid == null
                ? MyShopTypography.h2.copyWith(fontWeight: FontWeight.w800)
                : MyShopTypography.price.copyWith(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                  ),
          ),
          const SizedBox(height: MyShopSpacing.md),
          Wrap(
            spacing: MyShopSpacing.sm,
            runSpacing: MyShopSpacing.sm,
            children: [
              if (distanceKm != null)
                _DecisionMetric(
                  icon: Icons.near_me_outlined,
                  label: '${distanceKm!.toStringAsFixed(1)} km away',
                ),
              if (etaMinutes != null && etaMinutes! > 0)
                _DecisionMetric(
                  icon: Icons.schedule,
                  label: '~${geo_utils.formatEtaLabel(etaMinutes!)}',
                ),
              _DecisionMetric(
                icon: Icons.bolt,
                label: postedAgo,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DecisionMetric extends StatelessWidget {
  const _DecisionMetric({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(MyShopRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: MyShopColors.darkSlate),
          const SizedBox(width: MyShopSpacing.xs),
          Text(
            label,
            style: MyShopTypography.body2.copyWith(
              color: MyShopColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ClientSummaryCard extends StatelessWidget {
  const _ClientSummaryCard({
    required this.clientName,
    required this.clientPhotoUrl,
    required this.distanceKm,
    required this.etaMinutes,
  });

  final String clientName;
  final String? clientPhotoUrl;
  final double? distanceKm;
  final int? etaMinutes;

  @override
  Widget build(BuildContext context) {
    final String distanceText;
    if (distanceKm == null) {
      distanceText = '—';
    } else {
      final km = '${distanceKm!.toStringAsFixed(1)} km away';
      distanceText = (etaMinutes != null && etaMinutes! > 0)
          ? '$km · ~${geo_utils.formatEtaLabel(etaMinutes!)}'
          : km;
    }

    return Container(
      padding: const EdgeInsets.all(MyShopSpacing.md),
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MyShopColors.divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _ClientAvatar(photoUrl: clientPhotoUrl),
          const SizedBox(width: MyShopSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CUSTOMER',
                  style: MyShopTypography.overline.copyWith(
                    color: MyShopColors.textSecondary,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  clientName,
                  style: MyShopTypography.h3.copyWith(fontSize: 16),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  distanceText,
                  style: MyShopTypography.body2.copyWith(
                    color: MyShopColors.primaryGoldDark,
                    fontWeight: FontWeight.w700,
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
    final hasUsableLocation =
        IncomingRequestMapPreview.isUsableCoordinate(latitude, longitude);
    return Column(
      children: [
        IncomingRequestMapPreview.location(
          latitude: latitude,
          longitude: longitude,
        ),
        const SizedBox(height: MyShopSpacing.sm),
        InkWell(
          onTap: hasUsableLocation ? () => _openDirections(context) : null,
          borderRadius: BorderRadius.circular(MyShopRadius.card),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: MyShopSpacing.md,
              vertical: MyShopSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: MyShopColors.surfaceWhite,
              borderRadius: BorderRadius.circular(MyShopRadius.card),
              border: Border.all(color: MyShopColors.divider),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.location_on_outlined,
                  size: 18,
                  color: MyShopColors.primaryGold,
                ),
                const SizedBox(width: MyShopSpacing.sm),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: MyShopTypography.body1,
                  ),
                ),
                const SizedBox(width: MyShopSpacing.sm),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: hasUsableLocation
                        ? MyShopColors.primaryGoldLight
                        : MyShopColors.surfaceGrey,
                    borderRadius: BorderRadius.circular(MyShopRadius.pill),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        hasUsableLocation
                            ? Icons.open_in_new
                            : Icons.location_off_outlined,
                        size: 14,
                        color: hasUsableLocation
                            ? MyShopColors.primaryGoldDark
                            : MyShopColors.textSecondary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        hasUsableLocation ? 'Open map' : 'Unavailable',
                        style: MyShopTypography.body2.copyWith(
                          color: hasUsableLocation
                              ? MyShopColors.primaryGoldDark
                              : MyShopColors.textSecondary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
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

class _JobRequestActionBar extends StatelessWidget {
  const _JobRequestActionBar({
    required this.onSubmitBid,
    required this.onSkip,
    required this.skipping,
    required this.directedAssignment,
  });

  final VoidCallback onSubmitBid;
  final VoidCallback onSkip;
  final bool skipping;
  final bool directedAssignment;

  @override
  Widget build(BuildContext context) {
    final labels = jobRequestActionLabels(
      directedAssignment: directedAssignment,
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(
        MyShopSpacing.md,
        MyShopSpacing.sm,
        MyShopSpacing.md,
        MyShopSpacing.md,
      ),
      decoration: const BoxDecoration(
        color: MyShopColors.surfaceWhite,
        border: Border(top: BorderSide(color: MyShopColors.divider)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: _DeclineButton(
              onTap: onSkip,
              loading: skipping,
              directedAssignment: directedAssignment,
              label: labels.secondary,
            ),
          ),
          const SizedBox(width: MyShopSpacing.sm),
          Expanded(
            flex: 3,
            child: _PlaceBidButton(
              onTap: skipping ? null : onSubmitBid,
              label: labels.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _PlaceBidButton extends StatelessWidget {
  const _PlaceBidButton({required this.onTap, required this.label});

  final VoidCallback? onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.edit_note, size: 19),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: MyShopColors.buttonPrimary,
          foregroundColor: MyShopColors.textOnDarkSlate,
          disabledBackgroundColor: MyShopColors.disabled,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(MyShopRadius.button),
          ),
          textStyle: MyShopTypography.button.copyWith(
            fontWeight: FontWeight.w800,
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
  final num? feePercent;

  @override
  Widget build(BuildContext context) {
    final rate = feePercent;
    final fee = rate == null ? null : (total * rate) / 100;
    final net = fee == null ? null : total - fee;
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
            if (rate != null && fee != null)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Estimated Platform Fee (${rate.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')}%)',
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
              )
            else
              Text(
                'The fee estimate is temporarily unavailable. Your final earnings will use the rate recorded by the server.',
                style: MyShopTypography.body2.copyWith(
                  color: MyShopColors.textSecondary,
                ),
              ),
            const SizedBox(height: MyShopSpacing.sm),
            const Divider(height: 1, color: MyShopColors.divider),
            const SizedBox(height: MyShopSpacing.sm),
            if (net != null)
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
  const _DeclineButton({
    required this.onTap,
    this.loading = false,
    this.directedAssignment = false,
    required this.label,
  });

  final VoidCallback onTap;
  final bool loading;
  final bool directedAssignment;
  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: OutlinedButton.icon(
        onPressed: loading ? null : onTap,
        icon: loading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.close, size: 18),
        label: Text(
          loading
              ? directedAssignment
                  ? 'Declining…'
                  : 'Skipping…'
              : label,
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: MyShopColors.error,
          side: const BorderSide(color: MyShopColors.error),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(MyShopRadius.button),
          ),
          textStyle: MyShopTypography.button.copyWith(
            color: MyShopColors.error,
            fontWeight: FontWeight.w800,
            fontSize: 15,
          ),
        ),
      ),
    );
  }
}

/// Loading state shown while [JobRequestScreen] hydrates a stub Job
/// (FCM-tap entry path, where the constructor receives only an id).
/// Renders the same Request Details shell (header + request id) as the
/// hydrated screen with a spinner in the body, so the fetch completing
/// only swaps the body content in place — the user never perceives a
/// separate loading screen between two details screens.
class _JobRequestLoadingScreen extends StatelessWidget {
  const _JobRequestLoadingScreen({required this.requestId});

  final String requestId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MyShopColors.offWhite,
      body: SafeArea(
        child: Column(
          children: [
            _Header(requestId: requestId),
            const Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(
                      color: MyShopColors.primaryGold,
                      strokeWidth: 2.4,
                    ),
                    SizedBox(height: MyShopSpacing.md),
                    Text(
                      'Loading job…',
                      style: MyShopTypography.body2,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Error + retry surface for the stub-hydration path. Shown when the
/// FCM-tap pushed `/job-request` with only a jobId and the follow-up
/// `GET /jobs/:id` failed (Render cold-start timeout, transient
/// network, etc.). The artisan can retry without leaving the screen
/// or back out to /home.
class _JobRequestLoadFailureScreen extends StatelessWidget {
  const _JobRequestLoadFailureScreen({
    required this.onRetry,
  });

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MyShopColors.offWhite,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(MyShopSpacing.lg),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(
                Icons.cloud_off,
                size: 48,
                color: MyShopColors.error,
              ),
              const SizedBox(height: MyShopSpacing.md),
              Text(
                'Could not load job details',
                style: MyShopTypography.h2,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: MyShopSpacing.sm),
              Text(
                'Check your connection and try again. If the job is no longer available, return to requests.',
                style: MyShopTypography.body2.copyWith(
                  color: MyShopColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: MyShopSpacing.lg),
              ElevatedButton(
                onPressed: onRetry,
                style: ElevatedButton.styleFrom(
                  backgroundColor: MyShopColors.primaryGold,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    vertical: MyShopSpacing.md,
                  ),
                ),
                child: Text(
                  'Retry',
                  style: MyShopTypography.button.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: MyShopSpacing.sm),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  'Back',
                  style: MyShopTypography.button.copyWith(
                    color: MyShopColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
