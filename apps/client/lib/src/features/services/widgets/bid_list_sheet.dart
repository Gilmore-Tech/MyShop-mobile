import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../providers/bid_list_provider.dart';

// ── Public entry-point ────────────────────────────────────────────────────────

/// How often the open sheet polls the bids endpoint. Keeps the list fresh
/// even when the socket `job:bid_new` event is delayed or not delivered.
const _bidsPollInterval = Duration(seconds: 5);

/// Shows the bid list bottom sheet over [context].
///
/// PRD 4.5 — client reviews bids alongside artisan profiles, ratings and
/// portfolio, then selects preferred artisan.
/// API: GET /v1/jobs/:id/bids  |  PATCH /v1/jobs/:id/select-bid
void showBidListSheet(
  BuildContext context, {
  required ActiveJobSummary job,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    // Dismiss via the close button / barrier tap. Disabling the sheet's
    // own drag lets the inner RefreshIndicator claim the vertical drag
    // gesture so pull-to-refresh actually fires.
    enableDrag: false,
    builder: (_) => BidListSheet(job: job),
  );
}

// ── Sheet root ────────────────────────────────────────────────────────────────

class BidListSheet extends ConsumerStatefulWidget {
  final ActiveJobSummary job;
  const BidListSheet({super.key, required this.job});

  @override
  ConsumerState<BidListSheet> createState() => _BidListSheetState();
}

class _BidListSheetState extends ConsumerState<BidListSheet> {
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(_bidsPollInterval, (_) {
      if (!mounted) return;
      ref.invalidate(bidsForJobProvider(widget.job.jobId));
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

    final job = widget.job;
    final bidsAsync = ref.watch(bidsForJobProvider(job.jobId));
    final selectState = ref.watch(bidListNotifierProvider);

    return Container(
      // Sheet fills ~85 % of screen height so cards are scrollable
      height: h * 0.85,
      decoration: BoxDecoration(
        color: MyShopColors.offWhite,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(w * 0.051), // ~20dp
        ),
      ),
      child: Column(
        children: [
          // ── Drag handle ──
          SizedBox(height: h * 0.014),
          _DragHandle(w: w, h: h),
          SizedBox(height: h * 0.019),
          // ── Sheet header ──
          _SheetHeader(job: job, w: w, h: h),
          SizedBox(height: h * 0.014),
          // ── Active request card ──
          _ActiveRequestCard(job: job, w: w, h: h),
          SizedBox(height: h * 0.014),
          // ── Bid list ──
          Expanded(
            child: bidsAsync.when(
              loading: () => _BidListSkeleton(w: w, h: h),
              error: (_, __) => _ErrorState(
                onRetry: () => ref.invalidate(bidsForJobProvider(job.jobId)),
                w: w,
                h: h,
              ),
              data: (bids) => bids.isEmpty
                  ? _NoBidsState(w: w, h: h)
                  : _BidList(
                      bids: bids,
                      job: job,
                      selectState: selectState,
                      w: w,
                      h: h,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Drag Handle ───────────────────────────────────────────────────────────────

class _DragHandle extends StatelessWidget {
  final double w;
  final double h;
  const _DragHandle({required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: w * 0.103, // ~40dp
      height: h * 0.005, // ~4dp
      decoration: BoxDecoration(
        color: MyShopColors.divider,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

// ── Sheet Header ──────────────────────────────────────────────────────────────

class _SheetHeader extends StatelessWidget {
  final ActiveJobSummary job;
  final double w;
  final double h;
  const _SheetHeader({required this.job, required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: w * 0.041),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Bids for ${job.title}',
              style: TextStyle(
                fontSize: w * 0.046, // ~18dp
                fontWeight: FontWeight.w700,
                color: MyShopColors.textPrimary,
                height: 1.2,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(width: w * 0.026),
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: w * 0.082,
              height: w * 0.082,
              decoration: const BoxDecoration(
                color: MyShopColors.surfaceGrey,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.close_rounded,
                size: w * 0.046,
                color: MyShopColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Active Request Card ───────────────────────────────────────────────────────

class _ActiveRequestCard extends StatelessWidget {
  final ActiveJobSummary job;
  final double w;
  final double h;
  const _ActiveRequestCard({
    required this.job,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: w * 0.041),
      padding: EdgeInsets.symmetric(
        horizontal: w * 0.041,
        vertical: h * 0.014,
      ),
      decoration: BoxDecoration(
        color: MyShopColors.primaryGoldLight,
        borderRadius: BorderRadius.circular(w * 0.031),
        border:
            Border.all(color: MyShopColors.primaryGold.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Container(
            width: w * 0.082,
            height: w * 0.082,
            decoration: BoxDecoration(
              color: MyShopColors.primaryGold.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.bolt_rounded,
              size: w * 0.046,
              color: MyShopColors.primaryGold,
            ),
          ),
          SizedBox(width: w * 0.031),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ACTIVE REQUEST',
                  style: TextStyle(
                    fontSize: w * 0.026,
                    fontWeight: FontWeight.w900,
                    color: MyShopColors.primaryGold,
                    letterSpacing: 1.0,
                  ),
                ),
                SizedBox(height: h * 0.004),
                Text(
                  '${job.title} · ${job.budgetDisplay}',
                  style: TextStyle(
                    fontSize: w * 0.036,
                    fontWeight: FontWeight.w600,
                    color: MyShopColors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Bid list ──────────────────────────────────────────────────────────────────

class _BidList extends ConsumerWidget {
  final List<ArtisanBid> bids;
  final ActiveJobSummary job;
  final BidListState selectState;
  final double w;
  final double h;

  const _BidList({
    required this.bids,
    required this.job,
    required this.selectState,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      color: MyShopColors.primaryGold,
      onRefresh: () async {
        ref.invalidate(bidsForJobProvider(job.jobId));
        // Wait for the new build to complete so the spinner lingers until
        // data is actually ready.
        await ref.read(bidsForJobProvider(job.jobId).future);
      },
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.symmetric(
          horizontal: w * 0.041,
          vertical: h * 0.005,
        ),
        itemCount: bids.length,
        separatorBuilder: (_, __) => SizedBox(height: h * 0.012),
        itemBuilder: (context, i) => _BidCard(
          bid: bids[i],
          job: job,
          selectState: selectState,
          w: w,
          h: h,
        ),
      ),
    );
  }
}

// ── Bid Card ──────────────────────────────────────────────────────────────────

class _BidCard extends ConsumerWidget {
  final ArtisanBid bid;
  final ActiveJobSummary job;
  final BidListState selectState;
  final double w;
  final double h;

  const _BidCard({
    required this.bid,
    required this.job,
    required this.selectState,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isThisBidSelecting = selectState.selectingBidId == bid.bidId;
    final anySelecting = selectState.isSelecting;

    return Container(
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(w * 0.031),
        border: Border.all(color: MyShopColors.divider),
      ),
      padding: EdgeInsets.all(w * 0.041),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Artisan info row ──
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ArtisanAvatar(
                name: bid.artisanName,
                color: bid.avatarColor,
                photoUrl: bid.profilePhotoUrl,
                isVerified: bid.isVerified,
                w: w,
              ),
              SizedBox(width: w * 0.031),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Name + verified
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            bid.artisanName,
                            style: TextStyle(
                              fontSize: w * 0.038,
                              fontWeight: FontWeight.w700,
                              color: MyShopColors.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (bid.isVerified) ...[
                          SizedBox(width: w * 0.010),
                          Icon(
                            Icons.verified_rounded,
                            size: w * 0.038,
                            color: MyShopColors.success,
                          ),
                        ],
                      ],
                    ),
                    SizedBox(height: h * 0.004),
                    // Rating row — show "New" badge if no ratings yet.
                    bid.hasRating
                        ? Row(
                            children: [
                              Icon(
                                Icons.star_rounded,
                                size: w * 0.033,
                                color: MyShopColors.primaryGold,
                              ),
                              SizedBox(width: w * 0.008),
                              Text(
                                bid.rating.toStringAsFixed(1),
                                style: TextStyle(
                                  fontSize: w * 0.031,
                                  fontWeight: FontWeight.w600,
                                  color: MyShopColors.textPrimary,
                                ),
                              ),
                              Text(
                                ' (${bid.reviewCount} review${bid.reviewCount == 1 ? '' : 's'})',
                                style: TextStyle(
                                  fontSize: w * 0.028,
                                  fontWeight: FontWeight.w400,
                                  color: MyShopColors.textSecondary,
                                ),
                              ),
                            ],
                          )
                        : Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: w * 0.018,
                              vertical: h * 0.003,
                            ),
                            decoration: BoxDecoration(
                              color: MyShopColors.primaryGoldLight,
                              borderRadius: BorderRadius.circular(w * 0.021),
                            ),
                            child: Text(
                              'New artisan',
                              style: TextStyle(
                                fontSize: w * 0.026,
                                fontWeight: FontWeight.w700,
                                color: MyShopColors.primaryGold,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                    if (bid.tradeTitle.isNotEmpty) ...[
                      SizedBox(height: h * 0.003),
                      Text(
                        bid.tradeTitle,
                        style: TextStyle(
                          fontSize: w * 0.031,
                          fontWeight: FontWeight.w500,
                          color: MyShopColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(width: w * 0.021),
              // Bid amount — dual price when a promo is applied: original
              // struck through above the discounted price + campaign tag.
              bid.hasPromo
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          bid.promoOriginalAmountDisplay,
                          style: TextStyle(
                            fontSize: w * 0.031,
                            fontWeight: FontWeight.w500,
                            color: MyShopColors.textSecondary,
                            decoration: TextDecoration.lineThrough,
                            height: 1.1,
                          ),
                        ),
                        SizedBox(height: h * 0.002),
                        Text(
                          bid.effectiveAmountDisplay,
                          style: TextStyle(
                            fontSize: w * 0.043,
                            fontWeight: FontWeight.w800,
                            color: MyShopColors.textPrimary,
                            height: 1.1,
                          ),
                        ),
                        if (bid.promoName?.trim().isNotEmpty ?? false) ...[
                          SizedBox(height: h * 0.004),
                          Container(
                            constraints: BoxConstraints(maxWidth: w * 0.31),
                            padding: EdgeInsets.symmetric(
                              horizontal: w * 0.015,
                              vertical: h * 0.002,
                            ),
                            decoration: BoxDecoration(
                              color: MyShopColors.primaryGoldLight,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              bid.promoName!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: w * 0.023,
                                fontWeight: FontWeight.w700,
                                color: MyShopColors.primaryGoldDark,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                        ],
                      ],
                    )
                  : Text(
                      bid.amountDisplay,
                      style: TextStyle(
                        fontSize: w * 0.043,
                        fontWeight: FontWeight.w800,
                        color: MyShopColors.textPrimary,
                        height: 1.1,
                      ),
                    ),
            ],
          ),

          SizedBox(height: h * 0.012),

          // ── Arrival + duration row ──
          Row(
            children: [
              Icon(
                Icons.access_time_rounded,
                size: w * 0.036,
                color: MyShopColors.textHint,
              ),
              SizedBox(width: w * 0.015),
              Text(
                _etaLabel(bid.arrivesInMinutes),
                style: TextStyle(
                  fontSize: w * 0.031,
                  fontWeight: FontWeight.w400,
                  color: MyShopColors.textSecondary,
                ),
              ),
              if (bid.durationMinutes > 0) ...[
                SizedBox(width: w * 0.026),
                Icon(
                  Icons.schedule_rounded,
                  size: w * 0.036,
                  color: MyShopColors.textHint,
                ),
                SizedBox(width: w * 0.015),
                Text(
                  'Est. ${_durationLabel(bid.durationMinutes)}',
                  style: TextStyle(
                    fontSize: w * 0.031,
                    fontWeight: FontWeight.w400,
                    color: MyShopColors.textSecondary,
                  ),
                ),
              ],
            ],
          ),

          // ── Bid message (if present) ──
          if (bid.bidMessage != null) ...[
            SizedBox(height: h * 0.009),
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(
                horizontal: w * 0.031,
                vertical: h * 0.010,
              ),
              decoration: BoxDecoration(
                color: MyShopColors.surfaceGrey,
                borderRadius: BorderRadius.circular(w * 0.021),
              ),
              child: Text(
                bid.bidMessage!,
                style: TextStyle(
                  fontSize: w * 0.028,
                  fontWeight: FontWeight.w400,
                  color: MyShopColors.textSecondary,
                  height: 1.5,
                ),
              ),
            ),
          ],

          SizedBox(height: h * 0.014),

          // ── Action button ──
          SizedBox(
            width: double.infinity,
            child: _SelectBidButton(
              isLoading: isThisBidSelecting,
              isDisabled: anySelecting && !isThisBidSelecting,
              onPressed: () {
                Navigator.of(context).pop();
                context.push(
                  AppRoutes.jobBidsPath(job.jobId, bid.bidId),
                );
              },
              w: w,
              h: h,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Formatters ────────────────────────────────────────────────────────────────

String _etaLabel(int minutes) {
  if (minutes <= 0) return 'ETA pending';
  if (minutes < 60) return 'Arrives in $minutes min';
  final hours = minutes ~/ 60;
  final rem = minutes % 60;
  return rem == 0 ? 'Arrives in ${hours}h' : 'Arrives in ${hours}h ${rem}m';
}

String _durationLabel(int minutes) {
  if (minutes < 60) return '$minutes min';
  final hours = minutes ~/ 60;
  final rem = minutes % 60;
  return rem == 0 ? '${hours}h' : '${hours}h ${rem}m';
}

// ── Artisan Avatar ────────────────────────────────────────────────────────────

class _ArtisanAvatar extends StatelessWidget {
  final String name;
  final Color color;
  final String? photoUrl;
  final bool isVerified;
  final double w;

  const _ArtisanAvatar({
    required this.name,
    required this.color,
    required this.photoUrl,
    required this.isVerified,
    required this.w,
  });

  String get _initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    final chars =
        parts.where((p) => p.isNotEmpty).take(2).map((p) => p[0]).join();
    return chars.isEmpty ? '?' : chars.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final size = w * 0.138; // ~54dp
    final hasPhoto = photoUrl != null && photoUrl!.isNotEmpty;

    final fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text(
        _initials,
        style: TextStyle(
          fontSize: w * 0.046,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );

    if (!hasPhoto) return fallback;

    return ClipOval(
      child: Image.network(
        photoUrl!,
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

// ── Select Bid Button ─────────────────────────────────────────────────────────

class _SelectBidButton extends StatelessWidget {
  final bool isLoading;
  final bool isDisabled;
  final VoidCallback onPressed;
  final double w;
  final double h;

  const _SelectBidButton({
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
      height: h * 0.054, // ~46dp
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
                width: w * 0.046,
                height: w * 0.046,
                child: const CircularProgressIndicator(
                  strokeWidth: 2,
                  color: MyShopColors.surfaceWhite,
                ),
              )
            : Text(
                'Select Bid',
                style: TextStyle(
                  fontSize: w * 0.036,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
      ),
    );
  }
}

// ── Message Button ────────────────────────────────────────────────────────────

// ── Skeleton loader ───────────────────────────────────────────────────────────

class _BidListSkeleton extends StatelessWidget {
  final double w;
  final double h;
  const _BidListSkeleton({required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: EdgeInsets.symmetric(
        horizontal: w * 0.041,
        vertical: h * 0.005,
      ),
      itemCount: 3,
      separatorBuilder: (_, __) => SizedBox(height: h * 0.012),
      itemBuilder: (_, __) => _SkeletonCard(w: w, h: h),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  final double w;
  final double h;
  const _SkeletonCard({required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: h * 0.19,
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(w * 0.031),
        border: Border.all(color: MyShopColors.divider),
      ),
      padding: EdgeInsets.all(w * 0.041),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Shimmer(size: w * 0.138, radius: w * 0.138),
          SizedBox(width: w * 0.031),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Shimmer(width: w * 0.31, height: h * 0.022),
                SizedBox(height: h * 0.008),
                _Shimmer(width: w * 0.21, height: h * 0.017),
                SizedBox(height: h * 0.006),
                _Shimmer(width: w * 0.18, height: h * 0.017),
                const Spacer(),
                Row(
                  children: [
                    Expanded(
                      child: _Shimmer(height: h * 0.054),
                    ),
                    SizedBox(width: w * 0.026),
                    Expanded(
                      child: _Shimmer(height: h * 0.054),
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

class _Shimmer extends StatelessWidget {
  final double? width;
  final double? height;
  final double? size;
  final double? radius;

  const _Shimmer({this.width, this.height, this.size, this.radius});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size ?? width,
      height: size ?? height,
      decoration: BoxDecoration(
        color: MyShopColors.divider,
        borderRadius: BorderRadius.circular(radius ?? 4),
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _NoBidsState extends StatelessWidget {
  final double w;
  final double h;
  const _NoBidsState({required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: w * 0.082),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.hourglass_empty_rounded,
              size: w * 0.154,
              color: MyShopColors.textHint,
            ),
            SizedBox(height: h * 0.019),
            Text(
              'No bids yet',
              style: TextStyle(
                fontSize: w * 0.041,
                fontWeight: FontWeight.w700,
                color: MyShopColors.textPrimary,
              ),
            ),
            SizedBox(height: h * 0.009),
            Text(
              'Artisans have up to 5 minutes to submit bids. Check back shortly.',
              style: TextStyle(
                fontSize: w * 0.033,
                fontWeight: FontWeight.w400,
                color: MyShopColors.textSecondary,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Error state ───────────────────────────────────────────────────────────────

class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  final double w;
  final double h;
  const _ErrorState({
    required this.onRetry,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: w * 0.082),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: w * 0.154,
              color: MyShopColors.textHint,
            ),
            SizedBox(height: h * 0.019),
            Text(
              'Could not load bids',
              style: TextStyle(
                fontSize: w * 0.041,
                fontWeight: FontWeight.w700,
                color: MyShopColors.textPrimary,
              ),
            ),
            SizedBox(height: h * 0.009),
            Text(
              'Check your connection and try again.',
              style: TextStyle(
                fontSize: w * 0.033,
                fontWeight: FontWeight.w400,
                color: MyShopColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: h * 0.028),
            GestureDetector(
              onTap: onRetry,
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: w * 0.077,
                  vertical: h * 0.017,
                ),
                decoration: BoxDecoration(
                  color: MyShopColors.darkSlate,
                  borderRadius: BorderRadius.circular(w * 0.021),
                ),
                child: Text(
                  'Try Again',
                  style: TextStyle(
                    fontSize: w * 0.038,
                    fontWeight: FontWeight.w600,
                    color: MyShopColors.surfaceWhite,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
