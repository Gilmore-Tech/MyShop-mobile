import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/job_summary_provider.dart';

// ── Screen ────────────────────────────────────────────────────────────────────
// Shown after dual confirmation or 3-hour auto-finalization (PRD 4.8.2 / beta).
// Presents transaction receipt, instant payout confirmation, and the blind
// 24-hour rating form (EDD § Rating Module).
// API: GET /v1/jobs/:id  |  POST /v1/ratings

class JobSummaryScreen extends ConsumerWidget {
  final String jobId;
  const JobSummaryScreen({super.key, required this.jobId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final size = MediaQuery.sizeOf(context);
    final w = size.width;
    final h = size.height;

    final summaryAsync = ref.watch(jobSummaryProvider(jobId));

    return Scaffold(
      backgroundColor: MyShopColors.offWhite,
      body: summaryAsync.when(
        loading: () => _LoadingSkeleton(w: w, h: h),
        error: (_, __) => MyShopErrorBody(
          message: 'Could not load job summary',
          onRetry: () => ref.invalidate(jobSummaryProvider(jobId)),
        ),
        data: (summary) => _JobSummaryBody(summary: summary, w: w, h: h),
      ),
    );
  }
}

// ── Full body ─────────────────────────────────────────────────────────────────

class _JobSummaryBody extends ConsumerWidget {
  final JobSummaryData summary;
  final double w;
  final double h;
  const _JobSummaryBody(
      {required this.summary, required this.w, required this.h});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bottomPad = MediaQuery.paddingOf(context).bottom;
    return Column(
      children: [
        _AppBar(w: w, h: h),
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.only(bottom: bottomPad + h * 0.014),
            child: Column(
              children: [
                // ── Hero ──
                SizedBox(height: h * 0.034),
                _HeroSection(w: w, h: h),
                SizedBox(height: h * 0.024),

                // ── Artisan card ──
                _ArtisanCard(artisan: summary.artisan, w: w, h: h),
                SizedBox(height: h * 0.014),

                // ── Transaction summary ──
                _TransactionSummaryCard(summary: summary, w: w, h: h),
                SizedBox(height: h * 0.022),

                // ── Rating section ──
                _RateExperienceSection(summary: summary, w: w, h: h),
                SizedBox(height: h * 0.022),

                // ── Submit button ──
                _SubmitButton(jobId: summary.jobId, w: w, h: h),
                SizedBox(height: h * 0.019),

                // ── Beta guarantee footer ──
                _BetaGuaranteeFooter(w: w, h: h),
                SizedBox(height: h * 0.019),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── App Bar ───────────────────────────────────────────────────────────────────

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
            'Job Summary',
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

// ── Hero Section ──────────────────────────────────────────────────────────────

class _HeroSection extends StatelessWidget {
  final double w;
  final double h;
  const _HeroSection({required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Gold ring circle with checkmark + small lock badge
        SizedBox(
          width: w * 0.205,
          height: w * 0.205,
          child: Stack(
            alignment: Alignment.bottomRight,
            children: [
              // Main circle
              Container(
                width: w * 0.205,
                height: w * 0.205,
                decoration: BoxDecoration(
                  color: MyShopColors.primaryGoldLight,
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: MyShopColors.primaryGold, width: w * 0.008),
                ),
                child: Icon(
                  Icons.check_rounded,
                  size: w * 0.103,
                  color: MyShopColors.primaryGold,
                ),
              ),
              // Lock badge
              Container(
                width: w * 0.067,
                height: w * 0.067,
                decoration: BoxDecoration(
                  color: MyShopColors.darkSlate,
                  shape: BoxShape.circle,
                  border:
                      Border.all(color: MyShopColors.surfaceWhite, width: 2.5),
                ),
                child: Icon(
                  Icons.lock_rounded,
                  size: w * 0.033,
                  color: MyShopColors.primaryGold,
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: h * 0.017),

        Text(
          'Job Completed!',
          style: TextStyle(
            fontSize: w * 0.056,
            fontWeight: FontWeight.w800,
            color: MyShopColors.textPrimary,
          ),
        ),
        SizedBox(height: h * 0.006),

        Text(
          'Funds have been safely released to the provider',
          style: TextStyle(
            fontSize: w * 0.033,
            fontWeight: FontWeight.w400,
            color: MyShopColors.textSecondary,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

// ── Artisan Card ──────────────────────────────────────────────────────────────

class _ArtisanCard extends StatelessWidget {
  final JobSummaryArtisan artisan;
  final double w;
  final double h;
  const _ArtisanCard({required this.artisan, required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return _Card(
      w: w,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Avatar circle
          Container(
            width: w * 0.133,
            height: w * 0.133,
            decoration: BoxDecoration(
              color: artisan.avatarColor,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.person_rounded,
              size: w * 0.072,
              color: MyShopColors.surfaceWhite,
            ),
          ),
          SizedBox(width: w * 0.031),

          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Name + verified badge
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        artisan.name,
                        style: TextStyle(
                          fontSize: w * 0.041,
                          fontWeight: FontWeight.w700,
                          color: MyShopColors.textPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    SizedBox(width: w * 0.015),
                    if (artisan.isVerified) _VerifiedBadge(w: w),
                  ],
                ),
                SizedBox(height: h * 0.004),

                // Role + experience
                Text(
                  '${artisan.role} • ${artisan.experienceLabel}',
                  style: TextStyle(
                    fontSize: w * 0.031,
                    fontWeight: FontWeight.w400,
                    color: MyShopColors.textSecondary,
                  ),
                ),
                SizedBox(height: h * 0.008),

                // Rating + location
                Row(
                  children: [
                    Icon(Icons.star_rounded,
                        size: w * 0.033, color: MyShopColors.primaryGold),
                    SizedBox(width: w * 0.005),
                    Text(
                      '${artisan.rating.toStringAsFixed(1)} '
                      '(${artisan.reviewCount} reviews)',
                      style: TextStyle(
                        fontSize: w * 0.028,
                        fontWeight: FontWeight.w500,
                        color: MyShopColors.textSecondary,
                      ),
                    ),
                    SizedBox(width: w * 0.018),
                    Icon(Icons.location_on_outlined,
                        size: w * 0.028, color: MyShopColors.textHint),
                    SizedBox(width: w * 0.005),
                    Text(
                      artisan.location,
                      style: TextStyle(
                        fontSize: w * 0.028,
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

class _VerifiedBadge extends StatelessWidget {
  final double w;
  const _VerifiedBadge({required this.w});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.verified_rounded,
            size: w * 0.038, color: MyShopColors.success),
        SizedBox(width: w * 0.008),
        Text(
          'verified',
          style: TextStyle(
            fontSize: w * 0.028,
            fontWeight: FontWeight.w600,
            color: MyShopColors.success,
          ),
        ),
      ],
    );
  }
}

// ── Transaction Summary Card ──────────────────────────────────────────────────

class _TransactionSummaryCard extends StatelessWidget {
  final JobSummaryData summary;
  final double w;
  final double h;
  const _TransactionSummaryCard(
      {required this.summary, required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    final a = summary.artisan;
    return _Card(
      w: w,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──
          Row(
            children: [
              Text(
                'Transaction Summary',
                style: TextStyle(
                  fontSize: w * 0.041,
                  fontWeight: FontWeight.w700,
                  color: MyShopColors.textPrimary,
                ),
              ),
              const Spacer(),
              Text(
                summary.jobRef,
                style: TextStyle(
                  fontSize: w * 0.028,
                  fontWeight: FontWeight.w400,
                  color: MyShopColors.textSecondary,
                ),
              ),
            ],
          ),
          SizedBox(height: h * 0.014),
          const Divider(height: 1, color: MyShopColors.divider),
          SizedBox(height: h * 0.014),

          // ── Line items ──
          _TxRow(
            label: 'Labor Charges',
            value: summary.laborChargeDisplay,
            w: w,
            h: h,
          ),
          SizedBox(height: h * 0.011),
          _TxRow(
            label: 'Material Costs',
            value: summary.materialCostDisplay,
            w: w,
            h: h,
          ),
          SizedBox(height: h * 0.014),
          const Divider(height: 1, color: MyShopColors.divider),
          SizedBox(height: h * 0.014),

          // ── Total ──
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                'Total Paid',
                style: TextStyle(
                  fontSize: w * 0.041,
                  fontWeight: FontWeight.w700,
                  color: MyShopColors.textPrimary,
                ),
              ),
              const Spacer(),
              Text(
                summary.totalPaidDisplay,
                style: TextStyle(
                  fontSize: w * 0.051,
                  fontWeight: FontWeight.w800,
                  color: MyShopColors.textPrimary,
                  height: 1.0,
                ),
              ),
            ],
          ),
          SizedBox(height: h * 0.017),

          // ── Instant payout info box ──
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: w * 0.031,
              vertical: h * 0.014,
            ),
            decoration: BoxDecoration(
              color: MyShopColors.surfaceGrey,
              borderRadius: BorderRadius.circular(w * 0.021),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.bolt_rounded,
                    size: w * 0.041, color: MyShopColors.primaryGold),
                SizedBox(width: w * 0.018),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Instant Payout Successful',
                        style: TextStyle(
                          fontSize: w * 0.033,
                          fontWeight: FontWeight.w700,
                          color: MyShopColors.textPrimary,
                        ),
                      ),
                      SizedBox(height: h * 0.004),
                      Text(
                        "Funds arrived in ${a.firstName}'s MoMo wallet "
                        'instantly.'
                        '${summary.tipIncluded ? ' No commission was charged on the artisan\'s tip.' : ''}',
                        style: TextStyle(
                          fontSize: w * 0.028,
                          fontWeight: FontWeight.w400,
                          color: MyShopColors.textSecondary,
                          height: 1.45,
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
    );
  }
}

class _TxRow extends StatelessWidget {
  final String label;
  final String value;
  final double w;
  final double h;
  const _TxRow({
    required this.label,
    required this.value,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: w * 0.033,
              fontWeight: FontWeight.w400,
              color: MyShopColors.textSecondary,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: w * 0.033,
            fontWeight: FontWeight.w600,
            color: MyShopColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

// ── Rate Your Experience Section ──────────────────────────────────────────────
// EDD § Rating Module: blind 24h — both parties must submit before either
// rating is revealed.  Rating only revealed after both submit or window closes.

class _RateExperienceSection extends ConsumerStatefulWidget {
  final JobSummaryData summary;
  final double w;
  final double h;
  const _RateExperienceSection(
      {required this.summary, required this.w, required this.h});

  @override
  ConsumerState<_RateExperienceSection> createState() =>
      _RateExperienceSectionState();
}

class _RateExperienceSectionState
    extends ConsumerState<_RateExperienceSection> {
  late final TextEditingController _controller;

  double get w => widget.w;
  double get h => widget.h;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ratingState = ref.watch(jobRatingProvider);
    final firstName = widget.summary.artisan.firstName;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: w * 0.041),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Title ──
          Text(
            'Rate Your Experience',
            style: TextStyle(
              fontSize: w * 0.046,
              fontWeight: FontWeight.w700,
              color: MyShopColors.textPrimary,
            ),
          ),
          SizedBox(height: h * 0.014),

          // ── Blind-rating info box ──
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: w * 0.031,
              vertical: h * 0.012,
            ),
            decoration: BoxDecoration(
              color: MyShopColors.primaryGoldLight,
              borderRadius: BorderRadius.circular(w * 0.021),
              border: Border.all(
                color: MyShopColors.primaryGold.withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded,
                    size: w * 0.038, color: MyShopColors.primaryGold),
                SizedBox(width: w * 0.018),
                Expanded(
                  child: Text(
                    'Reviews are blind for 24 hours. Your rating will '
                    'only be visible once the artisan also reviews the job.',
                    style: TextStyle(
                      fontSize: w * 0.028,
                      fontWeight: FontWeight.w400,
                      color: MyShopColors.darkSlate,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: h * 0.022),

          // ── Star row ──
          Center(child: _StarRow(selected: ratingState.selectedStars, w: w)),
          SizedBox(height: h * 0.022),

          // ── Optional review input ──
          Text(
            'Share your thoughts (Optional)',
            style: TextStyle(
              fontSize: w * 0.036,
              fontWeight: FontWeight.w600,
              color: MyShopColors.textPrimary,
            ),
          ),
          SizedBox(height: h * 0.011),
          Container(
            decoration: BoxDecoration(
              color: MyShopColors.surfaceGrey,
              borderRadius: BorderRadius.circular(w * 0.026),
            ),
            child: TextField(
              controller: _controller,
              maxLines: 4,
              minLines: 4,
              enabled: !ratingState.isSubmitted,
              onChanged: (v) =>
                  ref.read(jobRatingProvider.notifier).updateReview(v),
              style: TextStyle(
                fontSize: w * 0.033,
                color: MyShopColors.textPrimary,
                height: 1.5,
              ),
              decoration: InputDecoration(
                hintText: 'How was $firstName\'s work? '
                    'Great communication, punctual...',
                hintStyle: TextStyle(
                  fontSize: w * 0.033,
                  color: MyShopColors.textHint,
                  height: 1.5,
                ),
                contentPadding: EdgeInsets.all(w * 0.041),
                border: InputBorder.none,
              ),
            ),
          ),

          // ── Error message ──
          if (ratingState.errorMessage != null) ...[
            SizedBox(height: h * 0.011),
            Text(
              ratingState.errorMessage!,
              style: TextStyle(
                fontSize: w * 0.031,
                color: MyShopColors.error,
              ),
            ),
          ],

          // ── Submitted state ──
          if (ratingState.isSubmitted) ...[
            SizedBox(height: h * 0.014),
            Row(
              children: [
                Icon(Icons.check_circle_rounded,
                    size: w * 0.041, color: MyShopColors.success),
                SizedBox(width: w * 0.015),
                Text(
                  'Rating submitted — visible after the 24h window.',
                  style: TextStyle(
                    fontSize: w * 0.031,
                    fontWeight: FontWeight.w500,
                    color: MyShopColors.success,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _StarRow extends ConsumerWidget {
  final int selected;
  final double w;
  const _StarRow({required this.selected, required this.w});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isSubmitted = ref.watch(jobRatingProvider).isSubmitted;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final filled = i < selected;
        return GestureDetector(
          onTap: isSubmitted
              ? null
              : () => ref.read(jobRatingProvider.notifier).selectStars(i + 1),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: w * 0.015),
            child: Icon(
              filled ? Icons.star_rounded : Icons.star_outline_rounded,
              size: w * 0.082,
              color: filled ? MyShopColors.primaryGold : MyShopColors.textHint,
            ),
          ),
        );
      }),
    );
  }
}

// ── Submit Button ─────────────────────────────────────────────────────────────

class _SubmitButton extends ConsumerWidget {
  final String jobId;
  final double w;
  final double h;
  const _SubmitButton({required this.jobId, required this.w, required this.h});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(jobRatingProvider);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: w * 0.041),
      child: SizedBox(
        width: double.infinity,
        height: h * 0.066,
        child: ElevatedButton(
          onPressed: state.canSubmit
              ? () => ref
                  .read(jobRatingProvider.notifier)
                  .submitRating(jobId: jobId)
              : state.isSubmitted
                  ? () => Navigator.of(context).maybePop()
                  : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: MyShopColors.darkSlate,
            disabledBackgroundColor: MyShopColors.surfaceGrey,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(w * 0.031),
            ),
          ),
          child: state.isSubmitting
              ? SizedBox(
                  width: w * 0.051,
                  height: w * 0.051,
                  child: const CircularProgressIndicator(
                    strokeWidth: 2,
                    color: MyShopColors.surfaceWhite,
                  ),
                )
              : Text(
                  state.isSubmitted ? 'Done' : 'Submit & Finish',
                  style: TextStyle(
                    fontSize: w * 0.041,
                    fontWeight: FontWeight.w700,
                    color: state.canSubmit || state.isSubmitted
                        ? MyShopColors.surfaceWhite
                        : MyShopColors.textHint,
                  ),
                ),
        ),
      ),
    );
  }
}

// ── Beta Guarantee Footer ─────────────────────────────────────────────────────
// Beta: jobs auto-finalize after the 3-hour safe period if no issues are
// reported. Dispute centre remains open for 48 hours after auto-finalization.

class _BetaGuaranteeFooter extends StatelessWidget {
  final double w;
  final double h;
  const _BetaGuaranteeFooter({required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: w * 0.041),
      child: CustomPaint(
        painter: _DashedBorderPainter(
          color: MyShopColors.divider,
          radius: w * 0.026,
        ),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: w * 0.041,
            vertical: h * 0.017,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.shield_outlined,
                size: w * 0.041,
                color: MyShopColors.textHint,
              ),
              SizedBox(width: w * 0.018),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'BETA GUARANTEE',
                      style: TextStyle(
                        fontSize: w * 0.023,
                        fontWeight: FontWeight.w900,
                        color: MyShopColors.primaryGold,
                        letterSpacing: 0.8,
                      ),
                    ),
                    SizedBox(height: h * 0.005),
                    Text(
                      'This job was automatically finalized as no issues '
                      'were reported during the 3-hour safe period. Our '
                      'dispute center remains available for 48 hours.',
                      style: TextStyle(
                        fontSize: w * 0.028,
                        fontWeight: FontWeight.w400,
                        color: MyShopColors.textSecondary,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Dashed border painter ─────────────────────────────────────────────────────

class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double radius;
  const _DashedBorderPainter({required this.color, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    const dash = 5.0;
    const gap = 4.0;
    final rRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rRect);
    final metrics = path.computeMetrics();
    for (final metric in metrics) {
      double d = 0;
      while (d < metric.length) {
        canvas.drawPath(
          metric.extractPath(d, d + dash),
          paint,
        );
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) =>
      old.color != color || old.radius != radius;
}

// ── Shared card wrapper ───────────────────────────────────────────────────────

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

// ── Loading Skeleton ──────────────────────────────────────────────────────────

class _LoadingSkeleton extends StatelessWidget {
  final double w;
  final double h;
  const _LoadingSkeleton({required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.paddingOf(context).top;
    return Column(
      children: [
        // App bar
        Container(
          color: MyShopColors.surfaceWhite,
          padding: EdgeInsets.only(
            top: topPad + h * 0.010,
            bottom: h * 0.017,
            left: w * 0.041,
          ),
          child: Row(children: [
            _Shimmer(w: w * 0.056, h: w * 0.056, r: w * 0.056),
            SizedBox(width: w * 0.031),
            _Shimmer(w: w * 0.33, h: h * 0.026),
          ]),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
                horizontal: w * 0.041, vertical: h * 0.022),
            child: Column(children: [
              _Shimmer(w: w * 0.41, h: w * 0.205, r: w * 0.205 / 2),
              SizedBox(height: h * 0.022),
              _Shimmer(w: double.infinity, h: h * 0.13, r: w * 0.031),
              SizedBox(height: h * 0.014),
              _Shimmer(w: double.infinity, h: h * 0.22, r: w * 0.031),
              SizedBox(height: h * 0.022),
              _Shimmer(w: double.infinity, h: h * 0.26, r: w * 0.021),
              SizedBox(height: h * 0.022),
              _Shimmer(w: double.infinity, h: h * 0.066, r: w * 0.031),
            ]),
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
