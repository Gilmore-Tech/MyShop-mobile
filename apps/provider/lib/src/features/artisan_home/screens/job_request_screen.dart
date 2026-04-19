import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

import '../widgets/bid_status_banner.dart';
import 'bid_submission_screen.dart';

/// Full job request details — opened when an incoming job request is
/// received via Socket.IO or from the live job feed cards.
///
/// PRD Reference: PRD 5.3 — incoming job notification (category, description,
/// photos, client location, 5-minute bid window).
class JobRequestScreen extends StatelessWidget {
  const JobRequestScreen({
    super.key,
    this.job,
    this.bidStatus = BidStatus.none,
    this.submittedBidAmount = 420,
    this.platformFeePercent = 10,
  });

  /// The live job from the backend. When null, the screen falls back to
  /// placeholder data (legacy path — remove once the feed is wired).
  final Job? job;

  final BidStatus bidStatus;
  final num submittedBidAmount;
  final num platformFeePercent;

  String get requestId => job != null ? '#${job!.id.substring(0, 8)}' : '#GH-204-ADUM';
  String get clientName => job?.clientName ?? 'Client';
  String get clientLocation => job?.addressText ?? 'Nearby';
  double get distanceKm => 0;
  String get title => job?.categoryName != null
      ? '${job!.categoryName} request'
      : 'Emergency: Burst Main Pipe in Kitchen';
  String get postedAgo => job?.createdAt != null ? 'Just posted' : 'Posted 2 mins ago';
  double get rating => 0;
  int get reviewsCount => 0;
  String get description =>
      job?.description ??
      '"The main pipe under our kitchen sink just burst. Water is everywhere. I\'ve turned off the main valve but need a permanent fix and possibly a replacement pipe section."';
  int get photoCount => job?.photos.length ?? 3;
  String get locationLabel => job?.addressText ?? 'Adum, Main Market Area';
  int get bidsTaken => 0;
  int get bidsTotal => 3;
  num get highestBid => 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MyShopColors.offWhite,
      body: SafeArea(
        child: Column(
          children: [
            _Header(requestId: requestId),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: MyShopSpacing.md,
                  vertical: MyShopSpacing.md,
                ),
                children: [
                  if (bidStatus != BidStatus.none) ...[
                    BidStatusBanner(
                      status: bidStatus,
                      onAcceptStartJob: () => context.push('/active-job'),
                      onMessage: () => context.push('/chat'),
                    ),
                    const SizedBox(height: MyShopSpacing.md),
                  ],
                  _ClientSummaryCard(
                    clientName: clientName,
                    clientLocation: clientLocation,
                    distanceKm: distanceKm,
                    title: title,
                    postedAgo: postedAgo,
                    rating: rating,
                    reviewsCount: reviewsCount,
                  ),
                  const SizedBox(height: MyShopSpacing.lg),
                  const _SectionHeader(
                    icon: Icons.info_outline,
                    label: 'JOB DESCRIPTION',
                  ),
                  const SizedBox(height: MyShopSpacing.sm),
                  _DescriptionCard(text: description),
                  const SizedBox(height: MyShopSpacing.lg),
                  const _SectionHeader(
                    icon: Icons.build_outlined,
                    label: 'PHOTOS',
                  ),
                  const SizedBox(height: MyShopSpacing.sm),
                  _PhotosRow(count: photoCount),
                  const SizedBox(height: MyShopSpacing.lg),
                  const _SectionHeader(
                    icon: Icons.near_me_outlined,
                    label: 'LOCATION',
                  ),
                  const SizedBox(height: MyShopSpacing.sm),
                  _LocationCard(label: locationLabel),
                  const SizedBox(height: MyShopSpacing.md),
                  if (bidStatus == BidStatus.none) ...[
                    _BidStatusCard(
                      bidsTaken: bidsTaken,
                      bidsTotal: bidsTotal,
                      highestBid: highestBid,
                    ),
                    const SizedBox(height: MyShopSpacing.lg),
                    _PlaceBidButton(
                      onTap: () => BidSubmissionScreen.show(
                        context,
                        clientName: clientName,
                        clientLocation: clientLocation,
                        distanceKm: distanceKm,
                      ),
                    ),
                    const SizedBox(height: MyShopSpacing.md),
                    _DeclineButton(onTap: () => context.pop()),
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
                      total: submittedBidAmount,
                      feePercent: platformFeePercent,
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
    required this.clientLocation,
    required this.distanceKm,
    required this.title,
    required this.postedAgo,
    required this.rating,
    required this.reviewsCount,
  });

  final String clientName;
  final String clientLocation;
  final double distanceKm;
  final String title;
  final String postedAgo;
  final double rating;
  final int reviewsCount;

  @override
  Widget build(BuildContext context) {
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
              Container(
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
              ),
              const SizedBox(width: MyShopSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            clientName,
                            style: MyShopTypography.h3.copyWith(fontSize: 16),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.verified,
                          size: 16,
                          color: MyShopColors.info,
                        ),
                      ],
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
                            '$clientLocation  •  ${distanceKm.toStringAsFixed(1)} km away',
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
              const SizedBox(width: MyShopSpacing.md),
              const Icon(
                Icons.star,
                size: 14,
                color: MyShopColors.ratingStar,
              ),
              const SizedBox(width: 4),
              Text(
                rating.toStringAsFixed(1),
                style: MyShopTypography.body1.copyWith(
                  color: MyShopColors.primaryGold,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '($reviewsCount Reviews)',
                style: MyShopTypography.body2,
              ),
            ],
          ),
        ],
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
// Photos row
// ─────────────────────────────────────────────────────────────────────────────

class _PhotosRow extends StatelessWidget {
  const _PhotosRow({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    // Show 2 thumbnails inline; everything beyond becomes a "+N More" tile.
    final inlineCount = count >= 2 ? 2 : count;
    final remaining = count - inlineCount;

    return SizedBox(
      height: 110,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (int i = 0; i < inlineCount; i++) ...[
            _PhotoThumb(seed: i),
            const SizedBox(width: MyShopSpacing.md),
          ],
          if (remaining > 0) _MorePhotosTile(remaining: remaining),
        ],
      ),
    );
  }
}

class _PhotoThumb extends StatelessWidget {
  const _PhotoThumb({required this.seed});

  final int seed;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 110,
      height: 110,
      decoration: BoxDecoration(
        color: MyShopColors.surfaceGrey,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MyShopColors.divider),
      ),
      alignment: Alignment.center,
      child: Icon(
        seed.isEven ? Icons.water_drop_outlined : Icons.broken_image_outlined,
        size: 36,
        color: MyShopColors.textSecondary,
      ),
    );
  }
}

class _MorePhotosTile extends StatelessWidget {
  const _MorePhotosTile({required this.remaining});

  final int remaining;

  @override
  Widget build(BuildContext context) {
    return DottedBorderBox(
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
// Location card
// ─────────────────────────────────────────────────────────────────────────────

class _LocationCard extends StatelessWidget {
  const _LocationCard({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MyShopColors.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Map placeholder area
          Container(
            height: 160,
            color: const Color(0xFFE6EAEC),
            alignment: Alignment.center,
            child: const Icon(
              Icons.location_on,
              size: 64,
              color: MyShopColors.error,
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
                    color: MyShopColors.surfaceWhite,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: MyShopColors.divider),
                  ),
                  child: Text(
                    'Tap to Navigate',
                    style: MyShopTypography.body2.copyWith(
                      color: MyShopColors.textPrimary,
                      fontWeight: FontWeight.w700,
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

// ─────────────────────────────────────────────────────────────────────────────
// Bid status card
// ─────────────────────────────────────────────────────────────────────────────

class _BidStatusCard extends StatelessWidget {
  const _BidStatusCard({
    required this.bidsTaken,
    required this.bidsTotal,
    required this.highestBid,
  });

  final int bidsTaken;
  final int bidsTotal;
  final num highestBid;

  @override
  Widget build(BuildContext context) {
    final progress = bidsTotal == 0 ? 0.0 : bidsTaken / bidsTotal;
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
            children: [
              Expanded(
                child: Text(
                  '$bidsTaken out of $bidsTotal spots taken',
                  style: MyShopTypography.body1,
                ),
              ),
              Text(
                'FINAL SPOT!',
                style: MyShopTypography.overline.copyWith(
                  color: MyShopColors.error,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: MyShopSpacing.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: MyShopColors.surfaceGrey,
              valueColor: const AlwaysStoppedAnimation(MyShopColors.error),
            ),
          ),
          const SizedBox(height: MyShopSpacing.md),
          Row(
            children: [
              SizedBox(
                width: 56,
                height: 28,
                child: Stack(
                  children: [
                    _bidder(0),
                    Positioned(
                      left: 22,
                      child: _bidder(1, isCount: true),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Text(
                'Highest Bid: ',
                style: MyShopTypography.body2,
              ),
              Text(
                'GHS $highestBid',
                style: MyShopTypography.body1.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _bidder(int seed, {bool isCount = false}) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: isCount ? MyShopColors.surfaceGrey : MyShopColors.avatarPlaceholder,
        shape: BoxShape.circle,
        border: Border.all(color: MyShopColors.surfaceWhite, width: 2),
      ),
      alignment: Alignment.center,
      child: isCount
          ? Text(
              '+1',
              style: MyShopTypography.caption.copyWith(
                color: MyShopColors.textPrimary,
                fontWeight: FontWeight.w800,
                fontSize: 10,
              ),
            )
          : const Icon(Icons.person, size: 16, color: MyShopColors.textSecondary),
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
