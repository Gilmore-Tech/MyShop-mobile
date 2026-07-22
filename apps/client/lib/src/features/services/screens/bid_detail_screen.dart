import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_models/shared_models.dart' show ChatBookingType;
import 'package:shared_ui/shared_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/router.dart';
import '../../../core/providers/chat_controller_provider.dart';
import '../../calls/helpers/start_in_app_call.dart';
import '../providers/artisan_live_location_provider.dart';
import '../providers/active_job_provider.dart';
import '../providers/bid_detail_provider.dart';
import '../providers/job_detail_provider.dart';
import '../providers/job_data_refresh_coordinator.dart';

// ── Screen ─────────────────────────────────────────────────────────────────────
// PRD 4.5 — Client reviews full bid details: artisan profile, bid breakdown,
// location, artisan note, and portfolio before accepting or declining.
// API: GET /v1/jobs/:id/bids  |  PATCH /v1/jobs/:id/select-bid

/// How often this screen polls for bid + job updates. Single-bid status
/// flips (pending → accepted/declined/expired) don't currently fire a
/// socket event, so without polling the screen would only refresh on
/// navigation. 12 s is the safety-net cadence — socket events still drive
/// the fast path; this just guarantees eventual consistency without
/// piling on top of the parent screen's poll and tripping the backend's
/// throttler.
const _bidDetailPollInterval = Duration(seconds: 12);

class BidDetailScreen extends ConsumerStatefulWidget {
  final String jobId;
  final String bidId;
  const BidDetailScreen({
    super.key,
    required this.jobId,
    required this.bidId,
  });

  @override
  ConsumerState<BidDetailScreen> createState() => _BidDetailScreenState();
}

class _BidDetailScreenState extends ConsumerState<BidDetailScreen> {
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(_bidDetailPollInterval, (_) {
      if (!mounted) return;
      // Refresh the bid list (which `bidDetailProvider` watches) and the
      // parent job so both the bid status and the footer's job-status
      // badge stay live without depending on socket delivery.
      unawaited(
        ref
            .read(jobDataRefreshCoordinatorProvider)
            .refreshJobAndBids(widget.jobId),
      );
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final w = size.width;
    final h = size.height;

    final key = (jobId: widget.jobId, bidId: widget.bidId);
    final bidAsync = ref.watch(bidDetailProvider(key));

    return Scaffold(
      backgroundColor: MyShopColors.offWhite,
      body: bidAsync.when(
        // Background refetches (socket / polling) must not flash the skeleton.
        // Keep showing the last good data while the refetch is in flight.
        skipLoadingOnReload: true,
        skipLoadingOnRefresh: true,
        loading: () => _LoadingSkeleton(w: w, h: h),
        error: (_, __) => MyShopErrorBody(
          message: 'Could not load bid details',
          onRetry: () => ref.invalidate(bidDetailProvider(key)),
        ),
        data: (bid) => _BidDetailBody(bid: bid, w: w, h: h),
      ),
    );
  }
}

// ── Full body ─────────────────────────────────────────────────────────────────

class _BidDetailBody extends ConsumerWidget {
  final BidDetail bid;
  final double w;
  final double h;
  const _BidDetailBody({required this.bid, required this.w, required this.h});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actionState = ref.watch(bidDetailActionProvider);
    // The backend bid status is the source of truth. The local action state
    // only drives transient UI (loading spinners, countdown) before the next
    // poll reconciles the real status.
    final confirmed =
        bid.status == BidStatus.accepted || actionState.isBidConfirmed;
    final expired = bid.status == BidStatus.expired || actionState.isBidExpired;
    final declined = bid.status == BidStatus.declined;
    final awaiting = !confirmed &&
        !expired &&
        !declined &&
        actionState.isAwaitingConfirmation;

    // Watch the parent job so the bottom bar reacts when the artisan
    // accepts and moves through confirmed → en_route → arrived → …
    // The socket handler invalidates jobDetailProvider on job:status:changed,
    // so this rebuilds live without any polling here.
    final jobAsync = ref.watch(jobDetailProvider(bid.jobId));
    final job = jobAsync.valueOrNull;
    final jobStatus = job?.isPaymentAcknowledgedPending == true
        ? JobStatus.pendingPayment
        : job?.status;
    // Once the job has left the bidding phase, the Accept button stops
    // making sense for non-winning bids — the client has already chosen,
    // or the job is done / cancelled. The `confirmed` path below still
    // takes over for the winning bid, which is what clients expect.
    final jobLocked =
        jobStatus != null && _isJobLocked(jobStatus) && !confirmed;

    return Column(
      children: [
        _AppBar(w: w, h: h),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: h * 0.019),
                if (confirmed) ...[
                  _BidProgressBanner(
                    artisanName: bid.artisan.name,
                    etaLabel: actionState.confirmedEtaLabel ?? '~18 mins',
                    status: jobStatus,
                    w: w,
                    h: h,
                  ),
                  SizedBox(height: h * 0.014),
                ] else if (expired) ...[
                  _BidExpiredBanner(
                    expiredDateLabel:
                        actionState.expiredDateLabel ?? 'Unknown date',
                    w: w,
                    h: h,
                  ),
                  SizedBox(height: h * 0.014),
                ] else if (awaiting) ...[
                  _AwaitingConfirmationBanner(
                    artisanFirstName: bid.artisan.firstName,
                    w: w,
                    h: h,
                  ),
                  SizedBox(height: h * 0.014),
                ],
                _ArtisanProfileCard(artisan: bid.artisan, w: w, h: h),
                SizedBox(height: h * 0.014),
                _TotalBidCard(bid: bid, w: w, h: h),
                SizedBox(height: h * 0.014),
                _BidBreakdownCard(bid: bid, w: w, h: h),
                SizedBox(height: h * 0.014),
                _LocationSection(
                  bid: bid,
                  showRoute: awaiting || confirmed,
                  w: w,
                  h: h,
                ),
                SizedBox(height: h * 0.014),
                if (bid.artisanNote != null)
                  _ArtisanNoteCard(
                    note: bid.artisanNote!,
                    timestamp: bid.noteTimestamp,
                    w: w,
                    h: h,
                  ),
                if (bid.artisanNote != null) SizedBox(height: h * 0.014),
                if (bid.portfolioColors.isNotEmpty) ...[
                  _RelatedPortfolioSection(
                    colors: bid.portfolioColors,
                    w: w,
                    h: h,
                  ),
                  SizedBox(height: h * 0.014),
                ],
                _TrustBadgesRow(w: w, h: h),
                SizedBox(height: h * 0.028),
              ],
            ),
          ),
        ),
        _BottomActionBar(
          bid: bid,
          confirmed: confirmed,
          expired: expired,
          declined: declined,
          awaiting: awaiting,
          jobLocked: jobLocked,
          jobStatus: jobStatus,
          w: w,
          h: h,
        ),
      ],
    );
  }
}

/// Returns true once the job has moved past the bidding phase — i.e. the
/// client has already selected a winning bid, the artisan is working on it,
/// or the job is finished/cancelled. Used by the bid detail screen to hide
/// the "Accept Bid" CTA on non-winning bids so the client can't double-book
/// an already-assigned job.
bool _isJobLocked(JobStatus status) {
  switch (status) {
    case JobStatus.adminAssigned:
    case JobStatus.confirmed:
    case JobStatus.enRoute:
    case JobStatus.arrived:
    case JobStatus.inProgress:
    case JobStatus.artisanMarkedComplete:
    case JobStatus.pendingPayment:
    case JobStatus.completed:
    case JobStatus.cancelled:
      return true;
    case JobStatus.open:
    case JobStatus.queued:
    case JobStatus.pendingAdmin:
      // No artisan yet — the bid window expired with zero bids and the
      // job is sitting in the admin queue waiting for re-routing.
      return false;
  }
}

// ── App Bar ────────────────────────────────────────────────────────────────────

class _AppBar extends StatelessWidget {
  final double w;
  final double h;
  const _AppBar({required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.paddingOf(context).top;
    return Container(
      color: MyShopColors.surfaceWhite,
      padding: EdgeInsets.only(
        top: topPad + h * 0.010,
        bottom: h * 0.017,
        left: w * 0.041,
        right: w * 0.041,
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).maybePop(),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: EdgeInsets.only(right: w * 0.031),
              child: Icon(Icons.arrow_back,
                  size: w * 0.056, color: MyShopColors.textPrimary),
            ),
          ),
          Text(
            'Bid Details',
            style: TextStyle(
              fontSize: w * 0.051,
              fontWeight: FontWeight.w700,
              color: MyShopColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Artisan Profile Card ──────────────────────────────────────────────────────

class _ArtisanProfileCard extends StatelessWidget {
  final BidArtisanProfile artisan;
  final double w;
  final double h;
  const _ArtisanProfileCard({
    required this.artisan,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return _Card(
      w: w,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Avatar(artisan: artisan, w: w),
          SizedBox(width: w * 0.038),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Name + verification badges
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        artisan.name,
                        style: TextStyle(
                          fontSize: w * 0.043,
                          fontWeight: FontWeight.w700,
                          color: MyShopColors.textPrimary,
                        ),
                      ),
                    ),
                    SizedBox(width: w * 0.010),
                    if (artisan.isKycVerified) _VerifyBadge(label: 'KYC', w: w),
                    SizedBox(width: w * 0.010),
                    if (artisan.isVetted) _VerifyBadge(label: 'Vetted', w: w),
                  ],
                ),
                SizedBox(height: h * 0.005),
                // Trade + experience
                if (artisan.tradeTitle.isNotEmpty ||
                    artisan.yearsExperience > 0)
                  Text(
                    _tradeLine(artisan),
                    style: TextStyle(
                      fontSize: w * 0.033,
                      fontWeight: FontWeight.w400,
                      color: MyShopColors.textSecondary,
                    ),
                  ),
                SizedBox(height: h * 0.007),
                // Rating
                Row(
                  children: [
                    Icon(
                      Icons.star_rounded,
                      size: w * 0.036,
                      color: artisan.reviewCount > 0
                          ? MyShopColors.primaryGold
                          : MyShopColors.textSecondary,
                    ),
                    SizedBox(width: w * 0.008),
                    Text(
                      artisan.reviewCount > 0
                          ? artisan.rating.toStringAsFixed(1)
                          : 'New',
                      style: TextStyle(
                        fontSize: w * 0.033,
                        fontWeight: FontWeight.w600,
                        color: MyShopColors.textPrimary,
                      ),
                    ),
                    if (artisan.reviewCount > 0)
                      Text(
                        ' (${artisan.reviewCount} reviews)',
                        style: TextStyle(
                          fontSize: w * 0.031,
                          color: MyShopColors.textSecondary,
                        ),
                      ),
                  ],
                ),
                SizedBox(height: h * 0.006),
                // Base + ETA (only when we have data to show)
                if (artisan.baseName.isNotEmpty || artisan.etaMinutes > 0)
                  Row(
                    children: [
                      Icon(Icons.location_on_outlined,
                          size: w * 0.033, color: MyShopColors.textHint),
                      SizedBox(width: w * 0.008),
                      Text(
                        _baseEtaLabel(artisan),
                        style: TextStyle(
                          fontSize: w * 0.031,
                          color: MyShopColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _tradeLine(BidArtisanProfile a) {
  final parts = <String>[
    if (a.tradeTitle.isNotEmpty) a.tradeTitle,
    if (a.yearsExperience > 0) '${a.yearsExperience}+ Years',
  ];
  return parts.join(' · ');
}

String _baseEtaLabel(BidArtisanProfile a) {
  final parts = <String>[
    if (a.baseName.isNotEmpty) 'Base: ${a.baseName}',
    if (a.etaMinutes > 0) 'ETA ${a.etaMinutes} min',
  ];
  return parts.join(' · ');
}

class _Avatar extends StatelessWidget {
  final BidArtisanProfile artisan;
  final double w;
  const _Avatar({required this.artisan, required this.w});

  String get _initials {
    final parts = artisan.name
        .trim()
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    final chars = parts.take(2).map((p) => p[0]).join();
    return chars.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final size = w * 0.154; // ~60dp
    final photo = artisan.profilePhotoUrl;
    final fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: artisan.avatarColor,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        _initials,
        style: TextStyle(
          fontSize: w * 0.054,
          fontWeight: FontWeight.w700,
          color: MyShopColors.surfaceWhite,
        ),
      ),
    );

    if (photo == null || photo.isEmpty) return fallback;

    return ClipOval(
      child: Image.network(
        photo,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
        loadingBuilder: (_, child, progress) =>
            progress == null ? child : fallback,
      ),
    );
  }
}

class _VerifyBadge extends StatelessWidget {
  final String label;
  final double w;
  const _VerifyBadge({required this.label, required this.w});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: w * 0.018,
        vertical: w * 0.010,
      ),
      decoration: BoxDecoration(
        color: MyShopColors.successLight,
        borderRadius: BorderRadius.circular(w * 0.041),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified_rounded,
              size: w * 0.028, color: MyShopColors.success),
          SizedBox(width: w * 0.008),
          Text(
            label,
            style: TextStyle(
              fontSize: w * 0.026,
              fontWeight: FontWeight.w700,
              color: MyShopColors.success,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Total Bid Card ─────────────────────────────────────────────────────────────

class _TotalBidCard extends StatelessWidget {
  final BidDetail bid;
  final double w;
  final double h;
  const _TotalBidCard({required this.bid, required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return _Card(
      w: w,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Total amount row
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TOTAL BID AMOUNT',
                      style: TextStyle(
                        fontSize: w * 0.026,
                        fontWeight: FontWeight.w900,
                        color: MyShopColors.textSecondary,
                        letterSpacing: 1.0,
                      ),
                    ),
                    SizedBox(height: h * 0.006),
                    Text(
                      bid.breakdown.totalDisplay,
                      style: TextStyle(
                        fontSize: w * 0.072, // ~28dp — large price
                        fontWeight: FontWeight.w800,
                        color: MyShopColors.textPrimary,
                        height: 1.0,
                      ),
                    ),
                  ],
                ),
              ),
              _BidStatusBadge(status: bid.status, w: w),
            ],
          ),
          SizedBox(height: h * 0.017),
          const Divider(height: 1, color: MyShopColors.divider),
          SizedBox(height: h * 0.017),
          // Duration + Availability row
          Row(
            children: [
              Expanded(
                child: _MetaCell(
                  icon: Icons.timer_outlined,
                  label: 'DURATION',
                  value: bid.durationLabel,
                  w: w,
                  h: h,
                ),
              ),
              Container(
                  width: 1, height: h * 0.050, color: MyShopColors.divider),
              Expanded(
                child: _MetaCell(
                  icon: Icons.calendar_today_outlined,
                  label: 'AVAILABILITY',
                  value: bid.availabilityLabel,
                  w: w,
                  h: h,
                  crossAxisAlignment: CrossAxisAlignment.end,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BidStatusBadge extends StatelessWidget {
  final BidStatus status;
  final double w;
  const _BidStatusBadge({required this.status, required this.w});

  @override
  Widget build(BuildContext context) {
    final color = status.color;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: w * 0.026,
        vertical: w * 0.013,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(w * 0.051),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          fontSize: w * 0.028,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _MetaCell extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final double w;
  final double h;
  final CrossAxisAlignment crossAxisAlignment;
  const _MetaCell({
    required this.icon,
    required this.label,
    required this.value,
    required this.w,
    required this.h,
    this.crossAxisAlignment = CrossAxisAlignment.start,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: crossAxisAlignment,
      children: [
        Row(
          mainAxisAlignment: crossAxisAlignment == CrossAxisAlignment.end
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          children: [
            Icon(icon, size: w * 0.036, color: MyShopColors.textHint),
            SizedBox(width: w * 0.010),
            Text(
              label,
              style: TextStyle(
                fontSize: w * 0.026,
                fontWeight: FontWeight.w900,
                color: MyShopColors.textSecondary,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
        SizedBox(height: h * 0.005),
        Text(
          value,
          style: TextStyle(
            fontSize: w * 0.038,
            fontWeight: FontWeight.w600,
            color: MyShopColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

// ── Bid Breakdown Card ────────────────────────────────────────────────────────

class _BidBreakdownCard extends ConsumerWidget {
  final BidDetail bid;
  final double w;
  final double h;
  const _BidBreakdownCard(
      {required this.bid, required this.w, required this.h});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actionState = ref.watch(bidDetailActionProvider);
    final expanded = actionState.materialItemsExpanded;
    final br = bid.breakdown;
    final hasMaterials =
        br.materialItems.isNotEmpty || br.materialsFeePesewas > 0;
    final hasVat = br.vatRate > 0;

    return _Card(
      w: w,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Bid Breakdown',
            style: TextStyle(
              fontSize: w * 0.041,
              fontWeight: FontWeight.w700,
              color: MyShopColors.textPrimary,
            ),
          ),
          SizedBox(height: h * 0.017),

          // Service Fee (Labor)
          _BreakdownRow(
            label: 'Service Fee (Labor)',
            amount: br.serviceFeeDisplay,
            w: w,
            h: h,
          ),
          if (hasMaterials) SizedBox(height: h * 0.014),

          // Estimated Materials (expandable) — shown when the bid has materials
          if (hasMaterials)
            GestureDetector(
              onTap: () =>
                  ref.read(bidDetailActionProvider.notifier).toggleMaterials(),
              behavior: HitTestBehavior.opaque,
              child: Column(
                children: [
                  Row(
                    children: [
                      Text(
                        'Estimated Materials',
                        style: TextStyle(
                          fontSize: w * 0.036,
                          fontWeight: FontWeight.w400,
                          color: MyShopColors.textPrimary,
                        ),
                      ),
                      SizedBox(width: w * 0.010),
                      AnimatedRotation(
                        turns: expanded ? 0 : -0.5,
                        duration: const Duration(milliseconds: 200),
                        child: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: w * 0.046,
                          color: MyShopColors.textSecondary,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        br.materialsFeeDisplay,
                        style: TextStyle(
                          fontSize: w * 0.036,
                          fontWeight: FontWeight.w600,
                          color: MyShopColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  // Expandable material items
                  AnimatedCrossFade(
                    firstChild: const SizedBox.shrink(),
                    secondChild: Padding(
                      padding: EdgeInsets.only(
                        top: h * 0.010,
                        left: w * 0.015,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: br.materialItems.map((item) {
                          return Padding(
                            padding: EdgeInsets.only(bottom: h * 0.007),
                            child: Row(
                              children: [
                                Text(
                                  '• ',
                                  style: TextStyle(
                                    fontSize: w * 0.031,
                                    color: MyShopColors.textSecondary,
                                  ),
                                ),
                                Text(
                                  item.name,
                                  style: TextStyle(
                                    fontSize: w * 0.031,
                                    fontWeight: FontWeight.w400,
                                    color: MyShopColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    crossFadeState: expanded
                        ? CrossFadeState.showSecond
                        : CrossFadeState.showFirst,
                    duration: const Duration(milliseconds: 200),
                  ),
                ],
              ),
            ),
          if (hasVat) ...[
            SizedBox(height: h * 0.014),
            _BreakdownRow(
              label: 'Transaction VAT (${br.vatPercent})',
              amount: br.vatDisplay,
              w: w,
              h: h,
              labelColor: MyShopColors.textSecondary,
            ),
          ],
          SizedBox(height: h * 0.014),

          const Divider(height: 1, color: MyShopColors.divider),
          SizedBox(height: h * 0.014),

          // Total
          _BreakdownRow(
            label: 'Total',
            amount: br.totalDisplay,
            w: w,
            h: h,
            isBold: true,
          ),

          // Materials disclaimer only makes sense when materials are estimated
          if (hasMaterials) ...[
            SizedBox(height: h * 0.014),
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(
                horizontal: w * 0.031,
                vertical: h * 0.012,
              ),
              decoration: BoxDecoration(
                color: MyShopColors.warningLight,
                borderRadius: BorderRadius.circular(w * 0.021),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: w * 0.036,
                    color: MyShopColors.warning,
                  ),
                  SizedBox(width: w * 0.015),
                  Expanded(
                    child: Text(
                      'Materials are estimated based on your description. '
                      'Final cost may vary upon physical inspection.',
                      style: TextStyle(
                        fontSize: w * 0.028,
                        fontWeight: FontWeight.w400,
                        color: MyShopColors.warning,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  final String label;
  final String amount;
  final double w;
  final double h;
  final bool isBold;
  final Color? labelColor;

  const _BreakdownRow({
    required this.label,
    required this.amount,
    required this.w,
    required this.h,
    this.isBold = false,
    this.labelColor,
  });

  @override
  Widget build(BuildContext context) {
    final weight = isBold ? FontWeight.w700 : FontWeight.w400;
    final size = isBold ? w * 0.038 : w * 0.036;
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: size,
              fontWeight: weight,
              color: labelColor ?? MyShopColors.textPrimary,
            ),
          ),
        ),
        Text(
          amount,
          style: TextStyle(
            fontSize: size,
            fontWeight: isBold ? FontWeight.w700 : FontWeight.w600,
            color: MyShopColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

// ── Location Section ──────────────────────────────────────────────────────────

class _LocationSection extends StatelessWidget {
  final BidDetail bid;
  final bool showRoute;
  final double w;
  final double h;
  const _LocationSection({
    required this.bid,
    required this.w,
    required this.h,
    this.showRoute = false,
  });

  BidArtisanProfile get artisan => bid.artisan;

  bool get _canOpenFullMap => bid.hasJobLocation || artisan.hasLocation;

  void _openFullMap(BuildContext context) {
    if (!_canOpenFullMap) return;
    context.push(AppRoutes.jobBidMapPath(bid.jobId, bid.bidId));
  }

  @override
  Widget build(BuildContext context) {
    return _Card(
      w: w,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Location',
                style: TextStyle(
                  fontSize: w * 0.041,
                  fontWeight: FontWeight.w700,
                  color: MyShopColors.textPrimary,
                ),
              ),
              const Spacer(),
              if (_canOpenFullMap)
                GestureDetector(
                  onTap: () => _openFullMap(context),
                  behavior: HitTestBehavior.opaque,
                  child: Row(
                    children: [
                      Text(
                        'View Map',
                        style: TextStyle(
                          fontSize: w * 0.033,
                          fontWeight: FontWeight.w600,
                          color: MyShopColors.primaryGold,
                        ),
                      ),
                      SizedBox(width: w * 0.008),
                      Icon(Icons.open_in_new_rounded,
                          size: w * 0.036, color: MyShopColors.primaryGold),
                    ],
                  ),
                ),
            ],
          ),
          SizedBox(height: h * 0.014),
          // Map placeholder
          ClipRRect(
            borderRadius: BorderRadius.circular(w * 0.021),
            child: Stack(
              children: [
                Container(
                  width: double.infinity,
                  height: h * 0.166, // ~140dp
                  color: const Color(0xFFD0E8C8), // map-like green
                  child: CustomPaint(
                      painter: _MapPlaceholderPainter(showRoute: showRoute)),
                ),
                // Distance chip — rebuilds only when the live-location
                // provider emits. Parent (_LocationSection) does not subscribe.
                Positioned(
                  top: h * 0.012,
                  left: w * 0.031,
                  child: _LiveDistanceChip(bid: bid, w: w, h: h),
                ),
                // Centre pin
                Positioned.fill(
                  child: Center(
                    child: Icon(
                      Icons.location_on_rounded,
                      size: w * 0.082,
                      color: MyShopColors.error,
                    ),
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

// Very light map-like pattern painted on the placeholder container.
// When showRoute is true, an orange/gold route path is drawn from an artisan
// origin point in the lower-left to the centre pin (job site).
class _MapPlaceholderPainter extends CustomPainter {
  final bool showRoute;
  const _MapPlaceholderPainter({this.showRoute = false});

  @override
  void paint(Canvas canvas, Size size) {
    final road = Paint()
      ..color = MyShopColors.surfaceWhite.withValues(alpha: 0.6)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    // horizontal road
    canvas.drawLine(
      Offset(0, size.height * 0.5),
      Offset(size.width, size.height * 0.5),
      road,
    );
    // vertical road
    canvas.drawLine(
      Offset(size.width * 0.4, 0),
      Offset(size.width * 0.4, size.height),
      road,
    );
    // diagonal accent road
    canvas.drawLine(
      Offset(size.width * 0.4, size.height * 0.5),
      Offset(size.width * 0.75, size.height * 0.2),
      road..strokeWidth = 2,
    );

    if (showRoute) {
      // Gold route line: artisan origin (lower-left) → job site (centre)
      final routePaint = Paint()
        ..color = MyShopColors.primaryGold
        ..strokeWidth = 4
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      final origin = Offset(size.width * 0.18, size.height * 0.80);
      final dest = Offset(size.width * 0.50, size.height * 0.50);
      final ctrl = Offset(size.width * 0.28, size.height * 0.35);

      final path = Path()
        ..moveTo(origin.dx, origin.dy)
        ..quadraticBezierTo(ctrl.dx, ctrl.dy, dest.dx, dest.dy);
      canvas.drawPath(path, routePaint);

      // Artisan origin dot (darkSlate)
      canvas.drawCircle(
        origin,
        6,
        Paint()..color = MyShopColors.darkSlate,
      );
      canvas.drawCircle(
        origin,
        4,
        Paint()..color = MyShopColors.surfaceWhite,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MapPlaceholderPainter old) =>
      old.showRoute != showRoute;
}

// ── Live Distance Chip ────────────────────────────────────────────────────────
// Scoped Consumer so polling the live-location provider only rebuilds this
// chip — the rest of the bid detail page stays still.

class _LiveDistanceChip extends ConsumerWidget {
  final BidDetail bid;
  final double w;
  final double h;
  const _LiveDistanceChip({
    required this.bid,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final live = ref.watch(artisanLiveLocationProvider(
      artisanLiveKey(jobId: bid.jobId, artisanId: bid.artisan.artisanId),
    ));

    // Prefer the live position; fall back to the snapshot we mapped on load.
    double distanceKm = bid.artisan.distanceKm;
    if (live != null && bid.hasJobLocation) {
      distanceKm = Geolocator.distanceBetween(
            bid.jobLatitude!,
            bid.jobLongitude!,
            live.latitude,
            live.longitude,
          ) /
          1000.0;
    }

    if (distanceKm <= 0) return const SizedBox.shrink();

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: w * 0.026,
        vertical: h * 0.007,
      ),
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(w * 0.041),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.near_me_rounded,
              size: w * 0.033, color: MyShopColors.primaryGold),
          SizedBox(width: w * 0.010),
          Text(
            '${distanceKm.toStringAsFixed(1)} km away',
            style: TextStyle(
              fontSize: w * 0.031,
              fontWeight: FontWeight.w600,
              color: MyShopColors.textPrimary,
            ),
          ),
          if (live != null && live.etaMinutes > 0) ...[
            SizedBox(width: w * 0.015),
            Container(
              width: 1,
              height: h * 0.014,
              color: MyShopColors.divider,
            ),
            SizedBox(width: w * 0.015),
            Text(
              '${live.etaMinutes} min',
              style: TextStyle(
                fontSize: w * 0.031,
                fontWeight: FontWeight.w600,
                color: MyShopColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Artisan's Note Card ────────────────────────────────────────────────────────

class _ArtisanNoteCard extends StatelessWidget {
  final String note;
  final String? timestamp;
  final double w;
  final double h;
  const _ArtisanNoteCard({
    required this.note,
    required this.timestamp,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return _Card(
      w: w,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Artisan's Note",
            style: TextStyle(
              fontSize: w * 0.041,
              fontWeight: FontWeight.w700,
              color: MyShopColors.textPrimary,
            ),
          ),
          SizedBox(height: h * 0.014),
          Text(
            note,
            style: TextStyle(
              fontSize: w * 0.036,
              fontWeight: FontWeight.w400,
              color: MyShopColors.textSecondary,
              height: 1.6,
              fontStyle: FontStyle.italic,
            ),
          ),
          if (timestamp != null) ...[
            SizedBox(height: h * 0.012),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                timestamp!,
                style: TextStyle(
                  fontSize: w * 0.028,
                  fontWeight: FontWeight.w400,
                  color: MyShopColors.textHint,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Related Portfolio Section ──────────────────────────────────────────────────

class _RelatedPortfolioSection extends StatelessWidget {
  final List<Color> colors;
  final double w;
  final double h;
  const _RelatedPortfolioSection({
    required this.colors,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return _Card(
      w: w,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Related Portfolio',
            style: TextStyle(
              fontSize: w * 0.041,
              fontWeight: FontWeight.w700,
              color: MyShopColors.textPrimary,
            ),
          ),
          SizedBox(height: h * 0.014),
          Row(
            children: colors.asMap().entries.map((e) {
              final isLast = e.key == colors.length - 1;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: isLast ? 0 : w * 0.026),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(w * 0.021),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: Container(color: e.value),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// ── Trust Badges Row ───────────────────────────────────────────────────────────

class _TrustBadgesRow extends StatelessWidget {
  final double w;
  final double h;
  const _TrustBadgesRow({required this.w, required this.h});

  static const _badges = [
    (Icons.cancel_outlined, '30mins Cancellation'),
    (Icons.shield_outlined, 'Service Guarantee'),
    (Icons.lock_outline_rounded, 'Secure Payment'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: w * 0.041),
      padding: EdgeInsets.symmetric(
        vertical: h * 0.017,
        horizontal: w * 0.026,
      ),
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(w * 0.031),
        border: Border.all(color: MyShopColors.divider),
      ),
      child: Row(
        children: _badges.asMap().entries.map((e) {
          final (icon, label) = e.value;
          final isLast = e.key == _badges.length - 1;
          return Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      Icon(icon,
                          size: w * 0.051, color: MyShopColors.textSecondary),
                      SizedBox(height: h * 0.006),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: w * 0.026,
                          fontWeight: FontWeight.w400,
                          color: MyShopColors.textSecondary,
                          height: 1.3,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                if (!isLast)
                  Container(
                    width: 1,
                    height: h * 0.050,
                    color: MyShopColors.divider,
                  ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Bottom Action Bar ──────────────────────────────────────────────────────────

class _BottomActionBar extends ConsumerWidget {
  final BidDetail bid;
  final bool confirmed;
  final bool expired;
  final bool declined;
  final bool awaiting;
  final bool jobLocked;
  final JobStatus? jobStatus;
  final double w;
  final double h;
  const _BottomActionBar({
    required this.bid,
    required this.confirmed,
    required this.expired,
    required this.declined,
    required this.awaiting,
    required this.jobLocked,
    required this.jobStatus,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actionState = ref.watch(bidDetailActionProvider);
    final bottomPad = MediaQuery.paddingOf(context).bottom;

    // Ordering matters: `confirmed` wins over `jobLocked` so the winning
    // bid keeps its "Message / Track" actions even after the job moves to
    // en_route. `expired` / `declined` come next, then the job-locked
    // fallback for every other non-winning bid on an in-progress job.
    final Widget content;
    if (confirmed) {
      content = _ConfirmedActionContent(bid: bid, w: w, h: h);
    } else if (expired) {
      content = _ExpiredActionContent(bid: bid, w: w, h: h);
    } else if (declined) {
      content = _DeclinedActionContent(w: w, h: h);
    } else if (jobLocked) {
      content = _JobLockedActionContent(status: jobStatus, w: w, h: h);
    } else if (awaiting) {
      content = _AwaitingActionContent(
        bid: bid,
        actionState: actionState,
        w: w,
        h: h,
        ref: ref,
      );
    } else {
      content = _PendingActionContent(
        bid: bid,
        actionState: actionState,
        w: w,
        h: h,
        ref: ref,
      );
    }

    return Container(
      decoration: const BoxDecoration(
        color: MyShopColors.surfaceWhite,
        border: Border(top: BorderSide(color: MyShopColors.divider)),
      ),
      padding: EdgeInsets.only(
        left: w * 0.041,
        right: w * 0.041,
        top: h * 0.014,
        bottom: bottomPad + h * 0.010,
      ),
      child: content,
    );
  }
}

// ── Job-locked state content ──────────────────────────────────────────────────
// Rendered when the job has moved past the bidding phase (artisan is en
// route, working, completed, or the job was cancelled) and this specific
// bid isn't the winning one. Replaces the "Accept Bid" CTA with a
// contextual read-only row so the client can't double-book.

class _JobLockedActionContent extends StatelessWidget {
  final JobStatus? status;
  final double w;
  final double h;
  const _JobLockedActionContent({
    required this.status,
    required this.w,
    required this.h,
  });

  (IconData, Color, String) get _content {
    switch (status) {
      case JobStatus.cancelled:
        return (
          Icons.cancel_outlined,
          MyShopColors.error,
          'This job was cancelled',
        );
      case JobStatus.completed:
        return (
          Icons.check_circle_outline,
          MyShopColors.success,
          'This job has been completed',
        );
      case JobStatus.enRoute:
      case JobStatus.arrived:
      case JobStatus.inProgress:
      case JobStatus.artisanMarkedComplete:
      case JobStatus.pendingPayment:
        return (
          Icons.directions_run_rounded,
          MyShopColors.primaryGold,
          'Work is already in progress with another artisan',
        );
      case JobStatus.confirmed:
      default:
        return (
          Icons.handshake_outlined,
          MyShopColors.textSecondary,
          "You've already chosen an artisan for this job",
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final (icon, color, message) = _content;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: w * 0.044, color: color),
        SizedBox(width: w * 0.018),
        Flexible(
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: w * 0.036,
              fontWeight: FontWeight.w600,
              color: MyShopColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Declined state content — shown when the bid was not the chosen one. ───────

class _DeclinedActionContent extends StatelessWidget {
  final double w;
  final double h;
  const _DeclinedActionContent({required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.block_rounded,
            size: w * 0.041, color: MyShopColors.disabled),
        SizedBox(width: w * 0.015),
        Text(
          'This bid was not selected',
          style: TextStyle(
            fontSize: w * 0.036,
            fontWeight: FontWeight.w600,
            color: MyShopColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

// ── Pending state content (before acceptance) ─────────────────────────────────

class _PendingActionContent extends StatelessWidget {
  final BidDetail bid;
  final BidDetailActionState actionState;
  final double w;
  final double h;
  final WidgetRef ref;
  const _PendingActionContent({
    required this.bid,
    required this.actionState,
    required this.w,
    required this.h,
    required this.ref,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _AcceptButton(
          artisanFirstName: bid.artisan.firstName,
          isLoading: actionState.isAccepting,
          isDisabled: actionState.isBusy,
          onPressed: () => ref
              .read(bidDetailActionProvider.notifier)
              .acceptBid(jobId: bid.jobId, bidId: bid.bidId),
          w: w,
          h: h,
        ),
        SizedBox(height: h * 0.010),
        // ── Pending hint ──
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bolt_rounded,
                size: w * 0.033, color: MyShopColors.primaryGold),
            SizedBox(width: w * 0.010),
            Expanded(
              child: Text(
                'Bid Pending: Tap Accept to request confirmation from '
                '${bid.artisan.firstName}.',
                style: TextStyle(
                  fontSize: w * 0.028,
                  fontWeight: FontWeight.w400,
                  color: MyShopColors.textSecondary,
                ),
                maxLines: 2,
              ),
            ),
          ],
        ),
        SizedBox(height: h * 0.010),
        const Divider(height: 1, color: MyShopColors.divider),
        SizedBox(height: h * 0.010),
        // ── Decline + Report row ──
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            GestureDetector(
              onTap: actionState.isBusy
                  ? null
                  : () => ref
                      .read(bidDetailActionProvider.notifier)
                      .declineBid(jobId: bid.jobId, bidId: bid.bidId),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: w * 0.026,
                  vertical: h * 0.005,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.close_rounded,
                      size: w * 0.036,
                      color: actionState.isBusy
                          ? MyShopColors.disabled
                          : MyShopColors.error,
                    ),
                    SizedBox(width: w * 0.010),
                    Text(
                      'Decline Bid',
                      style: TextStyle(
                        fontSize: w * 0.033,
                        fontWeight: FontWeight.w600,
                        color: actionState.isBusy
                            ? MyShopColors.disabled
                            : MyShopColors.error,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Awaiting confirmation state content (after acceptance) ────────────────────

class _AwaitingActionContent extends StatelessWidget {
  final BidDetail bid;
  final BidDetailActionState actionState;
  final double w;
  final double h;
  final WidgetRef ref;
  const _AwaitingActionContent({
    required this.bid,
    required this.actionState,
    required this.w,
    required this.h,
    required this.ref,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: double.infinity,
          height: h * 0.062,
          decoration: BoxDecoration(
            color: MyShopColors.surfaceGrey,
            borderRadius: BorderRadius.circular(w * 0.021),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_circle_outline_rounded,
                  size: w * 0.041, color: MyShopColors.disabled),
              SizedBox(width: w * 0.015),
              Text(
                'Acceptance Sent',
                style: TextStyle(
                  fontSize: w * 0.038,
                  fontWeight: FontWeight.w600,
                  color: MyShopColors.disabled,
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: h * 0.012),
        // ── Countdown timer ──
        if (actionState.countdownEndTime != null)
          _CountdownTimerRow(
            endTime: actionState.countdownEndTime!,
            onExpired: () =>
                ref.read(bidDetailActionProvider.notifier).onBidExpired(),
            w: w,
            h: h,
          ),
        SizedBox(height: h * 0.010),
        const Divider(height: 1, color: MyShopColors.divider),
        SizedBox(height: h * 0.010),
        // ── Cancel Job Request (PRD 4.5.5 free cancellation window) ──
        GestureDetector(
          onTap: actionState.isBusy
              ? null
              : () => ref
                  .read(bidDetailActionProvider.notifier)
                  .cancelJobRequest(jobId: bid.jobId),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: h * 0.005),
            child: Text(
              'Cancel Job Request',
              style: TextStyle(
                fontSize: w * 0.033,
                fontWeight: FontWeight.w600,
                color: actionState.isBusy
                    ? MyShopColors.disabled
                    : MyShopColors.error,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    );
  }
}

/// Circular chat-entry button wired to the chat orchestrator. Auto-opens
/// the channel for `(artisanJob, jobId)` so the unread badge is live the
/// moment the bid lands on the confirmed state, and pushes `/chat` with
/// the artisan's name + a status hint on tap.
class _ChatCircleButton extends ConsumerStatefulWidget {
  const _ChatCircleButton({
    required this.jobId,
    required this.artisanName,
    required this.w,
    required this.h,
  });

  final String jobId;
  final String artisanName;
  final double w;
  final double h;

  @override
  ConsumerState<_ChatCircleButton> createState() => _ChatCircleButtonState();
}

class _ChatCircleButtonState extends ConsumerState<_ChatCircleButton> {
  StreamSubscription<int>? _unreadSub;
  int _unread = 0;
  bool _opened = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ensureOpened();
  }

  @override
  void dispose() {
    _unreadSub?.cancel();
    super.dispose();
  }

  void _ensureOpened() {
    if (widget.jobId.isEmpty) return;
    final controller = ref.read(chatControllerProvider).valueOrNull;
    if (controller == null || _opened) return;
    _opened = true;
    scheduleMicrotask(() {
      if (!mounted) return;
      controller.openChannel(ChatBookingType.artisanJob, widget.jobId);
    });
    _unreadSub = controller.unreadCountStream.listen((n) {
      if (!mounted) return;
      setState(() => _unread = n);
    });
  }

  void _onTap() {
    if (widget.jobId.isEmpty) return;
    context.push(
      AppRoutes.chat,
      extra: <String, Object?>{
        'bookingType': ChatBookingType.artisanJob,
        'bookingId': widget.jobId,
        'peerName': widget.artisanName,
        'peerStatus': 'On your job',
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(chatControllerProvider);
    _ensureOpened();

    final size = widget.h * 0.062;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          onTap: _onTap,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: MyShopColors.surfaceWhite,
              shape: BoxShape.circle,
              border: Border.all(color: MyShopColors.divider, width: 1.5),
            ),
            child: Icon(
              Icons.chat_bubble_outline_rounded,
              size: widget.w * 0.051,
              color: MyShopColors.textPrimary,
            ),
          ),
        ),
        if (_unread > 0)
          Positioned(
            right: -2,
            top: -2,
            child: Container(
              constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: MyShopColors.error,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                  color: MyShopColors.surfaceWhite,
                  width: 1.5,
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                _unread > 99 ? '99+' : _unread.toString(),
                style: const TextStyle(
                  fontFamily: 'Raleway',
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  color: MyShopColors.textOnPrimary,
                  height: 1,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _AcceptButton extends StatelessWidget {
  final String artisanFirstName;
  final bool isLoading;
  final bool isDisabled;
  final VoidCallback onPressed;
  final double w;
  final double h;
  const _AcceptButton({
    required this.artisanFirstName,
    required this.isLoading,
    required this.isDisabled,
    required this.onPressed,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    final canTap = !isLoading && !isDisabled;
    return SizedBox(
      height: h * 0.062,
      child: ElevatedButton(
        onPressed: canTap ? onPressed : null,
        style: ElevatedButton.styleFrom(
          backgroundColor:
              canTap ? MyShopColors.darkSlate : MyShopColors.surfaceGrey,
          foregroundColor:
              canTap ? MyShopColors.surfaceWhite : MyShopColors.disabled,
          disabledBackgroundColor: MyShopColors.surfaceGrey,
          disabledForegroundColor: MyShopColors.disabled,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(w * 0.021),
          ),
        ),
        child: isLoading
            ? SizedBox(
                width: w * 0.051,
                height: w * 0.051,
                child: const CircularProgressIndicator(
                  strokeWidth: 2,
                  color: MyShopColors.surfaceWhite,
                ),
              )
            : Text(
                'Accept Bid',
                style: TextStyle(
                  fontSize: w * 0.038,
                  fontWeight: FontWeight.w600,
                  color: canTap
                      ? MyShopColors.surfaceWhite
                      : MyShopColors.disabled,
                  letterSpacing: 0.2,
                ),
              ),
      ),
    );
  }
}

// ── Awaiting Confirmation Banner ───────────────────────────────────────────────
// Shown at the top of the scroll area once the client has accepted a bid.
// PRD 4.5.5 — artisan must confirm within the countdown window.

class _AwaitingConfirmationBanner extends StatelessWidget {
  final String artisanFirstName;
  final double w;
  final double h;
  const _AwaitingConfirmationBanner({
    required this.artisanFirstName,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: w * 0.041),
      padding: EdgeInsets.all(w * 0.041),
      decoration: BoxDecoration(
        color: MyShopColors.primaryGoldLight,
        borderRadius: BorderRadius.circular(w * 0.031),
        border:
            Border.all(color: MyShopColors.primaryGold.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: w * 0.105,
            height: w * 0.105,
            decoration: BoxDecoration(
              color: MyShopColors.primaryGold.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.access_time_rounded,
                size: w * 0.051, color: MyShopColors.primaryGold),
          ),
          SizedBox(width: w * 0.031),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Awaiting Confirmation',
                  style: TextStyle(
                    fontSize: w * 0.038,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF9A6B00),
                  ),
                ),
                SizedBox(height: h * 0.005),
                Text(
                  'Acceptance sent. Waiting for $artisanFirstName to confirm '
                  'the job request.',
                  style: TextStyle(
                    fontSize: w * 0.031,
                    fontWeight: FontWeight.w400,
                    color: const Color(0xFF9A6B00),
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

// ── Countdown Timer Row ────────────────────────────────────────────────────────
// Live countdown displayed in the bottom action bar while awaiting confirmation.

class _CountdownTimerRow extends StatefulWidget {
  final DateTime endTime;
  final VoidCallback onExpired;
  final double w;
  final double h;
  const _CountdownTimerRow({
    required this.endTime,
    required this.onExpired,
    required this.w,
    required this.h,
  });

  @override
  State<_CountdownTimerRow> createState() => _CountdownTimerRowState();
}

class _CountdownTimerRowState extends State<_CountdownTimerRow> {
  late Duration _remaining;
  Timer? _timer;
  bool _expiredFired = false;

  @override
  void initState() {
    super.initState();
    _tick();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    final r = widget.endTime.difference(DateTime.now());
    final isZero = r.isNegative || r == Duration.zero;
    if (mounted) setState(() => _remaining = isZero ? Duration.zero : r);
    if (isZero && !_expiredFired) {
      _expiredFired = true;
      _timer?.cancel();
      // Schedule after current frame so widget tree is not mid-build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onExpired();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _label {
    final m = _remaining.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = _remaining.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.w;
    return Row(
      children: [
        Container(
          width: w * 0.023,
          height: w * 0.023,
          decoration: const BoxDecoration(
              color: MyShopColors.primaryGold, shape: BoxShape.circle),
        ),
        SizedBox(width: w * 0.026),
        Expanded(
          child: Text(
            'Artisan must respond within:',
            style: TextStyle(
              fontSize: w * 0.031,
              fontWeight: FontWeight.w400,
              color: MyShopColors.textSecondary,
            ),
          ),
        ),
        Text(
          _label,
          style: TextStyle(
            fontSize: w * 0.041,
            fontWeight: FontWeight.w700,
            color: MyShopColors.primaryGold,
          ),
        ),
      ],
    );
  }
}

// ── Accepted bid progress banner ─────────────────────────────────────────────
// The accepted bid remains the entry point for an active artisan job, so its
// banner must reflect the live job state instead of staying on "Bid Confirmed".

class _BidProgressBanner extends StatelessWidget {
  final String artisanName;
  final String etaLabel;
  final JobStatus? status;
  final double w;
  final double h;
  const _BidProgressBanner({
    required this.artisanName,
    required this.etaLabel,
    required this.status,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    final presentation = _presentationFor(status);
    return Container(
      margin: EdgeInsets.symmetric(horizontal: w * 0.041),
      padding: EdgeInsets.all(w * 0.041),
      decoration: BoxDecoration(
        color: presentation.background,
        borderRadius: BorderRadius.circular(w * 0.031),
        border: Border.all(
          color: presentation.foreground.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: w * 0.105,
            height: w * 0.105,
            decoration: BoxDecoration(
              color: presentation.foreground,
              shape: BoxShape.circle,
            ),
            child: Icon(presentation.icon,
                size: w * 0.054, color: MyShopColors.surfaceWhite),
          ),
          SizedBox(width: w * 0.031),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  presentation.title,
                  style: TextStyle(
                    fontSize: w * 0.038,
                    fontWeight: FontWeight.w700,
                    color: presentation.foreground,
                  ),
                ),
                SizedBox(height: h * 0.005),
                Text(
                  presentation.message,
                  style: TextStyle(
                    fontSize: w * 0.031,
                    fontWeight: FontWeight.w400,
                    color: presentation.foreground,
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

  _BidProgressPresentation _presentationFor(JobStatus? current) {
    return switch (current) {
      JobStatus.enRoute => _BidProgressPresentation(
          title: 'Artisan En Route',
          message: '$artisanName is on the way. Estimated arrival: $etaLabel.',
          icon: Icons.directions_walk_rounded,
          background: MyShopColors.primaryGoldLight,
          foreground: const Color(0xFF705400),
        ),
      JobStatus.arrived => _BidProgressPresentation(
          title: 'Artisan Arrived',
          message: '$artisanName has arrived at your job location.',
          icon: Icons.location_on_rounded,
          background: MyShopColors.primaryGoldLight,
          foreground: const Color(0xFF705400),
        ),
      JobStatus.inProgress => _BidProgressPresentation(
          title: 'Work In Progress',
          message: '$artisanName has started work on your job.',
          icon: Icons.handyman_rounded,
          background: MyShopColors.primaryGoldLight,
          foreground: const Color(0xFF705400),
        ),
      JobStatus.artisanMarkedComplete => _BidProgressPresentation(
          title: 'Review Completion',
          message: '$artisanName marked the work complete. Review it and '
              'confirm completion.',
          icon: Icons.fact_check_rounded,
          background: MyShopColors.warningLight,
          foreground: MyShopColors.warning,
        ),
      JobStatus.pendingPayment => const _BidProgressPresentation(
          title: 'Payment Processing',
          message:
              'Your completion is confirmed and payment is being processed.',
          icon: Icons.payments_rounded,
          background: MyShopColors.warningLight,
          foreground: MyShopColors.warning,
        ),
      JobStatus.completed => const _BidProgressPresentation(
          title: 'Job Completed',
          message: 'This job has been completed successfully.',
          icon: Icons.check_rounded,
          background: MyShopColors.successLight,
          foreground: MyShopColors.success,
        ),
      JobStatus.cancelled => const _BidProgressPresentation(
          title: 'Job Cancelled',
          message: 'This job has been cancelled.',
          icon: Icons.cancel_outlined,
          background: MyShopColors.errorLight,
          foreground: MyShopColors.error,
        ),
      JobStatus.adminAssigned => _BidProgressPresentation(
          title: 'Artisan Assigned',
          message: '$artisanName has been assigned to your job.',
          icon: Icons.person_pin_circle_rounded,
          background: MyShopColors.successLight,
          foreground: MyShopColors.success,
        ),
      _ => _BidProgressPresentation(
          title: 'Bid Accepted',
          message:
              '$artisanName has accepted your job and is preparing to leave.',
          icon: Icons.check_rounded,
          background: MyShopColors.successLight,
          foreground: MyShopColors.success,
        ),
    };
  }
}

class _BidProgressPresentation {
  const _BidProgressPresentation({
    required this.title,
    required this.message,
    required this.icon,
    required this.background,
    required this.foreground,
  });

  final String title;
  final String message;
  final IconData icon;
  final Color background;
  final Color foreground;
}

// ── Bid Expired Banner ─────────────────────────────────────────────────────────
// Shown when the 20-min confirmation window elapsed without artisan response.

class _BidExpiredBanner extends StatelessWidget {
  final String expiredDateLabel;
  final double w;
  final double h;
  const _BidExpiredBanner({
    required this.expiredDateLabel,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: w * 0.041),
      padding: EdgeInsets.all(w * 0.041),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF0F0),
        borderRadius: BorderRadius.circular(w * 0.031),
        border: Border.all(color: MyShopColors.error.withValues(alpha: 0.30)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: w * 0.105,
            height: w * 0.105,
            decoration: BoxDecoration(
              color: MyShopColors.error.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(w * 0.021),
            ),
            child: Icon(Icons.calendar_month_outlined,
                size: w * 0.051, color: MyShopColors.error),
          ),
          SizedBox(width: w * 0.031),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Bid Expired',
                  style: TextStyle(
                    fontSize: w * 0.038,
                    fontWeight: FontWeight.w700,
                    color: MyShopColors.error,
                  ),
                ),
                SizedBox(height: h * 0.005),
                Text(
                  'This bid expired on $expiredDateLabel. The artisan is no '
                  'longer committed to this price or timeline.',
                  style: TextStyle(
                    fontSize: w * 0.031,
                    fontWeight: FontWeight.w400,
                    color: MyShopColors.error,
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

// ── Confirmed state action content ─────────────────────────────────────────────

class _ConfirmedActionContent extends ConsumerWidget {
  final BidDetail bid;
  final double w;
  final double h;
  const _ConfirmedActionContent({
    required this.bid,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The accepted-bid payload intentionally contains no phone number. Fetch
    // the participant-scoped active job, which exposes contact details only
    // after assignment, so both in-app and phone-call choices are available
    // without leaking an artisan's number before the bid is accepted.
    final activeJob = ref.watch(activeJobProvider(bid.jobId)).valueOrNull;
    final artisanPhone = activeJob?.artisan.phone;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            _ChatCircleButton(
              jobId: bid.jobId,
              artisanName: bid.artisan.name,
              w: w,
              h: h,
            ),
            SizedBox(width: w * 0.026),
            MyShopCallButton(
              phoneNumber: artisanPhone,
              size: h * 0.062,
              semanticLabel: 'Call artisan',
              onInAppCall: () {
                unawaited(
                  startClientInAppCall(
                    context,
                    ref,
                    bookingType: 'artisan_job',
                    bookingId: bid.jobId,
                  ),
                );
              },
            ),
            SizedBox(width: w * 0.026),
            Expanded(
              child: SizedBox(
                height: h * 0.062,
                child: ElevatedButton(
                  onPressed: () => context.push(
                    AppRoutes.jobBidMapPath(bid.jobId, bid.bidId),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: MyShopColors.darkSlate,
                    foregroundColor: MyShopColors.surfaceWhite,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(w * 0.021),
                    ),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.near_me_rounded,
                          size: w * 0.041,
                          color: MyShopColors.surfaceWhite,
                        ),
                        SizedBox(width: w * 0.015),
                        Text(
                          'Track Artisan',
                          style: TextStyle(
                            fontSize: w * 0.038,
                            fontWeight: FontWeight.w600,
                            color: MyShopColors.surfaceWhite,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Expired state action content ──────────────────────────────────────────────

class _ExpiredActionContent extends StatelessWidget {
  final BidDetail bid;
  final double w;
  final double h;
  const _ExpiredActionContent({
    required this.bid,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: double.infinity,
          height: h * 0.062,
          child: ElevatedButton(
            onPressed: () => context.go('/services'),
            style: ElevatedButton.styleFrom(
              backgroundColor: MyShopColors.darkSlate,
              foregroundColor: MyShopColors.surfaceWhite,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(w * 0.021),
              ),
            ),
            child: Text(
              'Re-post Job',
              style: TextStyle(
                fontSize: w * 0.038,
                fontWeight: FontWeight.w600,
                color: MyShopColors.surfaceWhite,
              ),
            ),
          ),
        ),
        SizedBox(height: h * 0.010),
        const Divider(height: 1, color: MyShopColors.divider),
        SizedBox(height: h * 0.010),
        GestureDetector(
          onTap: () => Navigator.of(context).maybePop(),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: h * 0.005),
            child: Text(
              'Browse Other Bids',
              style: TextStyle(
                fontSize: w * 0.033,
                fontWeight: FontWeight.w600,
                color: MyShopColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Shared white card wrapper ─────────────────────────────────────────────────

class _Card extends StatelessWidget {
  final Widget child;
  final double w;
  const _Card({required this.child, required this.w});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: w * 0.041),
      padding: EdgeInsets.all(w * 0.041),
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(w * 0.031),
        border: Border.all(color: MyShopColors.divider),
      ),
      child: child,
    );
  }
}

// ── Loading Skeleton ───────────────────────────────────────────────────────────

class _LoadingSkeleton extends StatelessWidget {
  final double w;
  final double h;
  const _LoadingSkeleton({required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.paddingOf(context).top;
    return Column(
      children: [
        Container(
          color: MyShopColors.surfaceWhite,
          padding: EdgeInsets.only(
            top: topPad + h * 0.010,
            bottom: h * 0.017,
            left: w * 0.041,
          ),
          child: Row(
            children: [
              _Shimmer(w: w * 0.056, h: w * 0.056, r: w * 0.056),
              SizedBox(width: w * 0.031),
              _Shimmer(w: w * 0.41, h: h * 0.026),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: w * 0.041,
              vertical: h * 0.019,
            ),
            child: Column(
              children: [
                _Shimmer(w: double.infinity, h: h * 0.14, r: w * 0.031),
                SizedBox(height: h * 0.014),
                _Shimmer(w: double.infinity, h: h * 0.16, r: w * 0.031),
                SizedBox(height: h * 0.014),
                _Shimmer(w: double.infinity, h: h * 0.26, r: w * 0.031),
                SizedBox(height: h * 0.014),
                _Shimmer(w: double.infinity, h: h * 0.18, r: w * 0.031),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Shimmer extends StatelessWidget {
  final double w;
  final double h;
  final double r;
  const _Shimmer({required this.w, required this.h, this.r = 4});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: MyShopColors.divider,
        borderRadius: BorderRadius.circular(r),
      ),
    );
  }
}
