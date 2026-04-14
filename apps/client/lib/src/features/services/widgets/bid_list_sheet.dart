import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/bid_list_provider.dart';

// ── Design Tokens ─────────────────────────────────────────────────────────────
const _surfaceWhite  = Color(0xFFFFFFFF);
const _surfaceGrey   = Color(0xFFF3F5F6);
const _offWhite      = Color(0xFFF6F7F8);
const _textPrimary   = Color(0xFF161A1D);
const _textSecondary = Color(0xFF555E68);
const _textHint      = Color(0xFFBDBDBD);
const _gold          = Color(0xFFF5A623);
const _goldLight     = Color(0xFFFFF8EC);
const _darkSlate     = Color(0xFF46535D);
const _success       = Color(0xFF27AE60);
const _divider       = Color(0xFFE0E0E0);
const _disabled      = Color(0xFFBDBDBD);

// ── Public entry-point ────────────────────────────────────────────────────────

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
    builder: (_) => BidListSheet(job: job),
  );
}

// ── Sheet root ────────────────────────────────────────────────────────────────

class BidListSheet extends ConsumerWidget {
  final ActiveJobSummary job;
  const BidListSheet({super.key, required this.job});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final size = MediaQuery.sizeOf(context);
    final w    = size.width;
    final h    = size.height;

    final bidsAsync    = ref.watch(bidsForJobProvider(job.jobId));
    final selectState  = ref.watch(bidListNotifierProvider);

    return Container(
      // Sheet fills ~85 % of screen height so cards are scrollable
      height: h * 0.85,
      decoration: BoxDecoration(
        color: _offWhite,
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
        color: _divider,
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
                color: _textPrimary,
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
                color: _surfaceGrey,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.close_rounded,
                size: w * 0.046,
                color: _textPrimary,
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
        color: _goldLight,
        borderRadius: BorderRadius.circular(w * 0.031),
        border: Border.all(color: _gold.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Container(
            width: w * 0.082,
            height: w * 0.082,
            decoration: BoxDecoration(
              color: _gold.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.bolt_rounded,
              size: w * 0.046,
              color: _gold,
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
                    color: _gold,
                    letterSpacing: 1.0,
                  ),
                ),
                SizedBox(height: h * 0.004),
                Text(
                  '${job.title} · ${job.budgetDisplay}',
                  style: TextStyle(
                    fontSize: w * 0.036,
                    fontWeight: FontWeight.w600,
                    color: _textPrimary,
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

class _BidList extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return ListView.separated(
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
    final anySelecting       = selectState.isSelecting;

    return Container(
      decoration: BoxDecoration(
        color: _surfaceWhite,
        borderRadius: BorderRadius.circular(w * 0.031),
        border: Border.all(color: _divider),
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
                              color: _textPrimary,
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
                            color: _success,
                          ),
                        ],
                      ],
                    ),
                    SizedBox(height: h * 0.004),
                    // Rating row
                    Row(
                      children: [
                        Icon(
                          Icons.star_rounded,
                          size: w * 0.033,
                          color: _gold,
                        ),
                        SizedBox(width: w * 0.008),
                        Text(
                          bid.rating.toStringAsFixed(1),
                          style: TextStyle(
                            fontSize: w * 0.031,
                            fontWeight: FontWeight.w600,
                            color: _textPrimary,
                          ),
                        ),
                        Text(
                          ' (${bid.reviewCount} reviews)',
                          style: TextStyle(
                            fontSize: w * 0.028,
                            fontWeight: FontWeight.w400,
                            color: _textSecondary,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: h * 0.003),
                    Text(
                      bid.tradeTitle,
                      style: TextStyle(
                        fontSize: w * 0.031,
                        fontWeight: FontWeight.w500,
                        color: _textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: w * 0.021),
              // Bid amount
              Text(
                bid.amountDisplay,
                style: TextStyle(
                  fontSize: w * 0.043,
                  fontWeight: FontWeight.w800,
                  color: _textPrimary,
                  height: 1.1,
                ),
              ),
            ],
          ),

          SizedBox(height: h * 0.012),

          // ── Arrival time row ──
          Row(
            children: [
              Icon(
                Icons.access_time_rounded,
                size: w * 0.036,
                color: _textHint,
              ),
              SizedBox(width: w * 0.015),
              Text(
                'Arrives in ${bid.arrivesInMinutes} min',
                style: TextStyle(
                  fontSize: w * 0.031,
                  fontWeight: FontWeight.w400,
                  color: _textSecondary,
                ),
              ),
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
                color: _surfaceGrey,
                borderRadius: BorderRadius.circular(w * 0.021),
              ),
              child: Text(
                bid.bidMessage!,
                style: TextStyle(
                  fontSize: w * 0.028,
                  fontWeight: FontWeight.w400,
                  color: _textSecondary,
                  height: 1.5,
                ),
              ),
            ),
          ],

          SizedBox(height: h * 0.014),

          // ── Action buttons ──
          Row(
            children: [
              Expanded(
                child: _SelectBidButton(
                  isLoading: isThisBidSelecting,
                  isDisabled: anySelecting && !isThisBidSelecting,
                  onPressed: () => ref
                      .read(bidListNotifierProvider.notifier)
                      .selectBid(jobId: job.jobId, bidId: bid.bidId),
                  w: w,
                  h: h,
                ),
              ),
              SizedBox(width: w * 0.026),
              Expanded(
                child: _MessageButton(
                  artisanName: bid.artisanName.split(' ').first,
                  isDisabled: anySelecting,
                  onPressed: () {}, // TODO: navigate to chat screen
                  w: w,
                  h: h,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Artisan Avatar ────────────────────────────────────────────────────────────

class _ArtisanAvatar extends StatelessWidget {
  final String name;
  final Color color;
  final bool isVerified;
  final double w;

  const _ArtisanAvatar({
    required this.name,
    required this.color,
    required this.isVerified,
    required this.w,
  });

  @override
  Widget build(BuildContext context) {
    final size   = w * 0.138; // ~54dp
    final initials = name.trim().split(' ').take(2).map((s) => s[0]).join();

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          initials.toUpperCase(),
          style: TextStyle(
            fontSize: w * 0.046,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
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
          backgroundColor: canTap ? _darkSlate : const Color(0xFFF3F5F6),
          foregroundColor: canTap ? _surfaceWhite : _disabled,
          disabledBackgroundColor: const Color(0xFFF3F5F6),
          disabledForegroundColor: _disabled,
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
                  color: _surfaceWhite,
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

class _MessageButton extends StatelessWidget {
  final String artisanName;
  final bool isDisabled;
  final VoidCallback onPressed;
  final double w;
  final double h;

  const _MessageButton({
    required this.artisanName,
    required this.isDisabled,
    required this.onPressed,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: h * 0.054,
      child: OutlinedButton(
        onPressed: isDisabled ? null : onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: isDisabled ? _disabled : _textPrimary,
          side: BorderSide(
            color: isDisabled ? _disabled : _divider,
            width: 1.5,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(w * 0.021),
          ),
        ),
        child: Text(
          'Message',
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
        color: _surfaceWhite,
        borderRadius: BorderRadius.circular(w * 0.031),
        border: Border.all(color: _divider),
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
        color: const Color(0xFFE0E0E0),
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
              color: _textHint,
            ),
            SizedBox(height: h * 0.019),
            Text(
              'No bids yet',
              style: TextStyle(
                fontSize: w * 0.041,
                fontWeight: FontWeight.w700,
                color: _textPrimary,
              ),
            ),
            SizedBox(height: h * 0.009),
            Text(
              'Artisans have up to 5 minutes to submit bids. Check back shortly.',
              style: TextStyle(
                fontSize: w * 0.033,
                fontWeight: FontWeight.w400,
                color: _textSecondary,
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
              color: _textHint,
            ),
            SizedBox(height: h * 0.019),
            Text(
              'Could not load bids',
              style: TextStyle(
                fontSize: w * 0.041,
                fontWeight: FontWeight.w700,
                color: _textPrimary,
              ),
            ),
            SizedBox(height: h * 0.009),
            Text(
              'Check your connection and try again.',
              style: TextStyle(
                fontSize: w * 0.033,
                fontWeight: FontWeight.w400,
                color: _textSecondary,
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
                  color: _darkSlate,
                  borderRadius: BorderRadius.circular(w * 0.021),
                ),
                child: Text(
                  'Try Again',
                  style: TextStyle(
                    fontSize: w * 0.038,
                    fontWeight: FontWeight.w600,
                    color: _surfaceWhite,
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
