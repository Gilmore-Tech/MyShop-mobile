import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/bid_list_provider.dart';
import '../providers/job_detail_provider.dart';
import '../widgets/bid_list_sheet.dart';

// ── Screen ─────────────────────────────────────────────────────────────────────
// PRD 4.5 — Client views full job request detail, timeline progression,
// reference photos, and triggers bid review.
// API: GET /v1/jobs/:id  |  GET /v1/jobs/:id/bids

class JobDetailScreen extends ConsumerWidget {
  final String jobId;
  const JobDetailScreen({super.key, required this.jobId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final size = MediaQuery.sizeOf(context);
    final w    = size.width;
    final h    = size.height;

    final jobAsync = ref.watch(jobDetailProvider(jobId));

    return Scaffold(
      backgroundColor: MyShopColors.offWhite,
      body: jobAsync.when(
        loading: () => _LoadingSkeleton(w: w, h: h),
        error: (e, _) => _ErrorBody(
          w: w,
          h: h,
          onRetry: () => ref.invalidate(jobDetailProvider(jobId)),
        ),
        data: (job) => _JobDetailBody(job: job, w: w, h: h),
      ),
    );
  }
}

// ── Full body when data is loaded ─────────────────────────────────────────────

class _JobDetailBody extends StatelessWidget {
  final JobDetail job;
  final double w;
  final double h;
  const _JobDetailBody({required this.job, required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _AppBar(job: job, w: w, h: h),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: h * 0.024),
                _JobSummaryCard(job: job, w: w, h: h),
                SizedBox(height: h * 0.033),
                _DescriptionSection(description: job.description, w: w, h: h),
                SizedBox(height: h * 0.033),
                _ReferencePhotosSection(
                  photoCount: job.photoCount,
                  photoColors: job.photoColors,
                  w: w,
                  h: h,
                ),
                SizedBox(height: h * 0.033),
                _TimingSection(
                  isImmediate:  job.isImmediate,
                  scheduledFor: job.scheduledFor,
                  w: w, h: h,
                ),
                SizedBox(height: h * 0.033),
                _TimelineSection(steps: job.timeline, w: w, h: h),
                SizedBox(height: h * 0.033),
              ],
            ),
          ),
        ),
        _BottomActionBar(
          jobId:    job.id,
          jobTitle: job.title,
          bidCount: job.bids.count,
          w: w,
          h: h,
        ),
      ],
    );
  }
}

// ── App Bar ────────────────────────────────────────────────────────────────────

class _AppBar extends StatelessWidget {
  final JobDetail job;
  final double w;
  final double h;
  const _AppBar({required this.job, required this.w, required this.h});

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
              child: Icon(
                Icons.arrow_back,
                size: w * 0.056,
                color: MyShopColors.textPrimary,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Request Details',
                  style: TextStyle(
                    fontSize: w * 0.051, // ~20dp
                    fontWeight: FontWeight.w700,
                    color: MyShopColors.textPrimary,
                    height: 1.2,
                  ),
                ),
                SizedBox(height: h * 0.004),
                Row(
                  children: [
                    Icon(
                      Icons.location_on,
                      size: w * 0.033,
                      color: MyShopColors.primaryGold,
                    ),
                    SizedBox(width: w * 0.010),
                    Text(
                      job.location,
                      style: TextStyle(
                        fontSize: w * 0.028,
                        fontWeight: FontWeight.w400,
                        color: MyShopColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => _showMoreMenu(context),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: EdgeInsets.only(left: w * 0.026),
              child: Icon(
                Icons.more_vert_rounded,
                size: w * 0.056,
                color: MyShopColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showMoreMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _MoreMenuSheet(w: w, h: h),
    );
  }
}

class _MoreMenuSheet extends StatelessWidget {
  final double w;
  final double h;
  const _MoreMenuSheet({required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.paddingOf(context).bottom;
    return Container(
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.vertical(top: Radius.circular(w * 0.041)),
      ),
      padding: EdgeInsets.only(
        top: h * 0.019,
        bottom: bottomPad + h * 0.019,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _MenuRow(
            icon: Icons.cancel_outlined,
            label: 'Cancel Request',
            color: MyShopColors.error,
            onTap: () => Navigator.of(context).pop(),
            w: w,
            h: h,
          ),
          const Divider(height: 1, color: MyShopColors.divider),
          _MenuRow(
            icon: Icons.share_outlined,
            label: 'Share Job Link',
            color: MyShopColors.textPrimary,
            onTap: () => Navigator.of(context).pop(),
            w: w,
            h: h,
          ),
        ],
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final double w;
  final double h;
  const _MenuRow({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: w * 0.041,
          vertical: h * 0.019,
        ),
        child: Row(
          children: [
            Icon(icon, size: w * 0.051, color: color),
            SizedBox(width: w * 0.038),
            Text(
              label,
              style: TextStyle(
                fontSize: w * 0.038,
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Job Summary Card ───────────────────────────────────────────────────────────

class _JobSummaryCard extends StatelessWidget {
  final JobDetail job;
  final double w;
  final double h;
  const _JobSummaryCard({required this.job, required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: w * 0.041),
      padding: EdgeInsets.all(w * 0.046),
      decoration: BoxDecoration(
        color:        MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(w * 0.041),
        boxShadow: [
          BoxShadow(
            color:      Colors.black.withValues(alpha: 0.04),
            blurRadius: w * 0.031,
            offset:     Offset(0, w * 0.005),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icon circle
              Container(
                width: w * 0.113,
                height: w * 0.113,
                decoration: const BoxDecoration(
                  color: MyShopColors.surfaceGrey,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.handyman_rounded,
                  size: w * 0.056,
                  color: MyShopColors.textSecondary,
                ),
              ),
              SizedBox(width: w * 0.038),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      job.title,
                      style: TextStyle(
                        fontSize: w * 0.046,
                        fontWeight: FontWeight.w700,
                        color: MyShopColors.textPrimary,
                        height: 1.2,
                      ),
                    ),
                    SizedBox(height: h * 0.004),
                    Text(
                      job.categoryName,
                      style: TextStyle(
                        fontSize: w * 0.033,
                        fontWeight: FontWeight.w400,
                        color: MyShopColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: w * 0.021),
              // Status badge
              _StatusBadge(status: job.status, w: w),
            ],
          ),
          if (job.bids.count > 0) ...[
            SizedBox(height: h * 0.019),
            const Divider(height: 1, color: MyShopColors.divider),
            SizedBox(height: h * 0.017),
            Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'BIDS RECEIVED',
                      style: TextStyle(
                        fontSize:      w * 0.026,
                        fontWeight:    FontWeight.w900,
                        color:         MyShopColors.textSecondary,
                        letterSpacing: 1.2,
                      ),
                    ),
                    SizedBox(height: h * 0.005),
                    Row(
                      children: [
                        Text(
                          '${job.bids.count} Artisans',
                          style: TextStyle(
                            fontSize:   w * 0.038,
                            fontWeight: FontWeight.w700,
                            color:      MyShopColors.textPrimary,
                          ),
                        ),
                        SizedBox(width: w * 0.021),
                        _AvatarStack(
                          colors: job.bids.avatarColors,
                          w: w,
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final JobStatus status;
  final double w;
  const _StatusBadge({required this.status, required this.w});

  @override
  Widget build(BuildContext context) {
    final color = status.badgeColor;
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
        status.displayLabel,
        style: TextStyle(
          fontSize: w * 0.028,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class _AvatarStack extends StatelessWidget {
  final List<Color> colors;
  final double w;
  const _AvatarStack({required this.colors, required this.w});

  @override
  Widget build(BuildContext context) {
    final size = w * 0.072; // ~28dp
    final overlap = size * 0.35;
    final totalWidth = size + (colors.length - 1) * (size - overlap);

    return SizedBox(
      width: totalWidth,
      height: size,
      child: Stack(
        children: List.generate(colors.length, (i) {
          return Positioned(
            left: i * (size - overlap),
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: colors[i],
                shape: BoxShape.circle,
                border: const Border.fromBorderSide(
                  BorderSide(color: MyShopColors.surfaceWhite, width: 1.5),
                ),
              ),
              child: Icon(
                Icons.person,
                size: size * 0.55,
                color: MyShopColors.surfaceWhite.withValues(alpha: 0.8),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ── Description Section ────────────────────────────────────────────────────────

class _DescriptionSection extends StatelessWidget {
  final String description;
  final double w;
  final double h;
  const _DescriptionSection({
    required this.description,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: w * 0.041),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(label: 'Description', w: w, h: h),
          SizedBox(height: h * 0.012),
          Text(
            description,
            style: TextStyle(
              fontSize: w * 0.036,
              fontWeight: FontWeight.w400,
              color: MyShopColors.textSecondary,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Reference Photos Section ───────────────────────────────────────────────────

class _ReferencePhotosSection extends StatelessWidget {
  final int photoCount;
  final List<Color> photoColors;
  final double w;
  final double h;
  const _ReferencePhotosSection({
    required this.photoCount,
    required this.photoColors,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    final cardWidth = w * 0.475; // ~half screen so the next one peeks in
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: w * 0.041),
          child: Row(
            children: [
              _SectionTitle(label: 'Reference Photos', w: w, h: h),
              const Spacer(),
              if (photoCount > 0)
                Text(
                  '$photoCount PHOTOS',
                  style: TextStyle(
                    fontSize:      w * 0.026,
                    fontWeight:    FontWeight.w700,
                    color:         MyShopColors.primaryGold,
                    letterSpacing: 0.8,
                  ),
                ),
            ],
          ),
        ),
        SizedBox(height: h * 0.014),
        SizedBox(
          height: cardWidth * (11 / 16),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding:         EdgeInsets.symmetric(horizontal: w * 0.041),
            itemCount:       photoColors.length,
            separatorBuilder: (_, __) => SizedBox(width: w * 0.026),
            itemBuilder: (_, i) => SizedBox(
              width: cardWidth,
              child: _PhotoCard(
                color: photoColors[i],
                index: i + 1,
                w: w,
                h: h,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PhotoCard extends StatelessWidget {
  final Color  color;
  final int    index;
  final double w;
  final double h;
  const _PhotoCard({
    required this.color,
    required this.index,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(w * 0.021),
      child: AspectRatio(
        aspectRatio: 16 / 11,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(color: color),
            // Gradient overlay
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.4, 1.0],
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.55),
                  ],
                ),
              ),
            ),
            Positioned(
              bottom: h * 0.012,
              left: 0,
              right: 0,
              child: Center(
                child: Text(
                  'VIEW REFERENCE $index',
                  style: TextStyle(
                    fontSize: w * 0.026,
                    fontWeight: FontWeight.w700,
                    color: MyShopColors.surfaceWhite,
                    letterSpacing: 0.8,
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

// ── Timing Section ─────────────────────────────────────────────────────────────

class _TimingSection extends StatelessWidget {
  final bool      isImmediate;
  final DateTime? scheduledFor;
  final double    w;
  final double    h;

  const _TimingSection({
    required this.isImmediate,
    required this.scheduledFor,
    required this.w,
    required this.h,
  });

  String _valueLabel() {
    if (isImmediate || scheduledFor == null) return 'Now';
    final dt = scheduledFor!;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that  = DateTime(dt.year, dt.month, dt.day);
    final diff  = that.difference(today).inDays;

    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    final time = '$hh:$mm';

    if (diff == 0)  return 'Today, $time';
    if (diff == 1)  return 'Tomorrow, $time';
    const months = ['Jan','Feb','Mar','Apr','May','Jun',
                    'Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${dt.day} ${months[dt.month - 1]}, $time';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: w * 0.041),
      padding: EdgeInsets.symmetric(
        horizontal: w * 0.041,
        vertical:   h * 0.014,
      ),
      decoration: BoxDecoration(
        color:        MyShopColors.surfaceGrey,
        borderRadius: BorderRadius.circular(w * 0.041),
      ),
      child: Row(
        children: [
          Icon(
            Icons.access_time_rounded,
            size:  w * 0.051,
            color: MyShopColors.textPrimary,
          ),
          SizedBox(width: w * 0.026),
          Expanded(
            child: Text(
              'Service Timing',
              style: TextStyle(
                fontSize:   w * 0.036,
                fontWeight: FontWeight.w700,
                color:      MyShopColors.textPrimary,
              ),
            ),
          ),
          SizedBox(width: w * 0.021),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: w * 0.041,
              vertical:   h * 0.009,
            ),
            decoration: BoxDecoration(
              color:        MyShopColors.surfaceWhite,
              borderRadius: BorderRadius.circular(w * 0.026),
              boxShadow: [
                BoxShadow(
                  color:      Colors.black.withValues(alpha: 0.06),
                  blurRadius: w * 0.013,
                  offset:     Offset(0, w * 0.003),
                ),
              ],
            ),
            child: Text(
              _valueLabel(),
              style: TextStyle(
                fontSize:   w * 0.033,
                fontWeight: FontWeight.w700,
                color:      MyShopColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Request Timeline ───────────────────────────────────────────────────────────

class _TimelineSection extends StatelessWidget {
  final List<TimelineStep> steps;
  final double w;
  final double h;
  const _TimelineSection({
    required this.steps,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: w * 0.041),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(label: 'Request Timeline', w: w, h: h),
          SizedBox(height: h * 0.019),
          ...steps.asMap().entries.map((entry) {
            final i    = entry.key;
            final step = entry.value;
            final isLast = i == steps.length - 1;
            return _TimelineRow(
              step: step,
              isLast: isLast,
              w: w,
              h: h,
            );
          }),
        ],
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  final TimelineStep step;
  final bool isLast;
  final double w;
  final double h;
  const _TimelineRow({
    required this.step,
    required this.isLast,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon + connector column
          SizedBox(
            width: w * 0.092,
            child: Column(
              children: [
                _TimelineIcon(status: step.status, w: w),
                if (!isLast)
                  Expanded(
                    child: _DashedVerticalLine(
                      color: step.status == TimelineStepStatus.completed
                          ? MyShopColors.textPrimary
                          : MyShopColors.divider,
                      dashLength: 4,
                      gapLength:  4,
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(width: w * 0.031),
          // Content column
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : h * 0.024),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title + badge row
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          step.title,
                          style: TextStyle(
                            fontSize: w * 0.038,
                            fontWeight: FontWeight.w700,
                            color: step.status == TimelineStepStatus.pending
                                ? MyShopColors.textHint
                                : MyShopColors.textPrimary,
                          ),
                        ),
                      ),
                      if (step.timeLabel != null)
                        Text(
                          step.timeLabel!,
                          style: TextStyle(
                            fontSize: w * 0.028,
                            fontWeight: FontWeight.w400,
                            color: MyShopColors.textSecondary,
                          ),
                        ),
                      if (step.badgeLabel != null)
                        _TimelineBadge(
                          label: step.badgeLabel!,
                          status: step.status,
                          w: w,
                        ),
                    ],
                  ),
                  SizedBox(height: h * 0.006),
                  Text(
                    step.description,
                    style: TextStyle(
                      fontSize: w * 0.031,
                      fontWeight: FontWeight.w400,
                      color: step.status == TimelineStepStatus.pending
                          ? MyShopColors.textHint
                          : MyShopColors.textSecondary,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineIcon extends StatelessWidget {
  final TimelineStepStatus status;
  final double w;
  const _TimelineIcon({required this.status, required this.w});

  @override
  Widget build(BuildContext context) {
    final size = w * 0.082; // ~32dp
    return switch (status) {
      TimelineStepStatus.completed => Container(
          width: size,
          height: size,
          decoration: const BoxDecoration(
            color: MyShopColors.textPrimary,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.check_rounded,
            size: size * 0.6,
            color: MyShopColors.surfaceWhite,
          ),
        ),
      TimelineStepStatus.active => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: MyShopColors.primaryGold.withValues(alpha: 0.15),
            shape: BoxShape.circle,
            border: Border.all(color: MyShopColors.primaryGold, width: 2),
          ),
          child: Center(
            child: Container(
              width: size * 0.38,
              height: size * 0.38,
              decoration: const BoxDecoration(
                color: MyShopColors.primaryGold,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      TimelineStepStatus.pending => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: MyShopColors.surfaceGrey,
            shape: BoxShape.circle,
            border: Border.all(color: MyShopColors.divider, width: 2),
          ),
        ),
    };
  }
}

class _TimelineBadge extends StatelessWidget {
  final String label;
  final TimelineStepStatus status;
  final double w;
  const _TimelineBadge({
    required this.label,
    required this.status,
    required this.w,
  });

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (status) {
      TimelineStepStatus.active  => (MyShopColors.primaryGoldLight, MyShopColors.primaryGold),
      TimelineStepStatus.pending => (MyShopColors.surfaceGrey, MyShopColors.disabled),
      _                          => (MyShopColors.successLight, MyShopColors.success),
    };
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: w * 0.021,
        vertical: w * 0.010,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(w * 0.051),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: w * 0.026,
          fontWeight: FontWeight.w700,
          color: fg,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

// ── Bottom Action Bar ──────────────────────────────────────────────────────────

class _BottomActionBar extends StatelessWidget {
  final String jobId;
  final String jobTitle;
  final int    bidCount;
  final double w;
  final double h;
  const _BottomActionBar({
    required this.jobId,
    required this.jobTitle,
    required this.bidCount,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.paddingOf(context).bottom;
    return Container(
      padding: EdgeInsets.only(
        left: w * 0.041,
        right: w * 0.041,
        top: h * 0.014,
        bottom: h * 0.014 + bottomPad,
      ),
      decoration: const BoxDecoration(
        color: MyShopColors.surfaceWhite,
        border: Border(top: BorderSide(color: MyShopColors.divider)),
      ),
      child: Row(
        children: [
          // Chat button
          _ChatButton(w: w, h: h),
          SizedBox(width: w * 0.031),
          // View bids CTA
          Expanded(
            child: _ViewBidsButton(
              jobId:    jobId,
              jobTitle: jobTitle,
              bidCount: bidCount,
              w: w,
              h: h,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatButton extends StatelessWidget {
  final double w;
  final double h;
  const _ChatButton({required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {}, // TODO: navigate to chat screen
      child: Container(
        height: h * 0.062,
        width: w * 0.231, // ~90dp
        decoration: BoxDecoration(
          color: MyShopColors.surfaceWhite,
          borderRadius: BorderRadius.circular(w * 0.021),
          border: Border.all(color: MyShopColors.divider, width: 1.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.chat_bubble_outline_rounded,
              size: w * 0.046,
              color: MyShopColors.textPrimary,
            ),
            SizedBox(width: w * 0.015),
            Text(
              'Chat',
              style: TextStyle(
                fontSize: w * 0.036,
                fontWeight: FontWeight.w600,
                color: MyShopColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ViewBidsButton extends StatelessWidget {
  final String jobId;
  final String jobTitle;
  final int bidCount;
  final double w;
  final double h;
  const _ViewBidsButton({
    required this.jobId,
    required this.jobTitle,
    required this.bidCount,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => showBidListSheet(
        context,
        job: ActiveJobSummary(
          jobId: jobId,
          title: jobTitle,
          budgetPesewas: 0,
        ),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            height: h * 0.062,
            padding: EdgeInsets.symmetric(horizontal: w * 0.041),
            decoration: BoxDecoration(
              color:        MyShopColors.darkSlate,
              borderRadius: BorderRadius.circular(w * 0.021),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        'ACTION NEEDED',
                        style: TextStyle(
                          fontSize:      w * 0.026,
                          fontWeight:    FontWeight.w700,
                          color:         MyShopColors.surfaceWhite.withValues(alpha: 0.7),
                          letterSpacing: 0.8,
                        ),
                      ),
                      SizedBox(height: h * 0.002),
                      Text(
                        'View $bidCount Bids',
                        style: TextStyle(
                          fontSize:   w * 0.038,
                          fontWeight: FontWeight.w700,
                          color:      MyShopColors.surfaceWhite,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size:  w * 0.056,
                  color: MyShopColors.surfaceWhite,
                ),
              ],
            ),
          ),
          // Bid-count badge (primary gold)
          Positioned(
            top:   -(h * 0.012),
            right: -(w * 0.015),
            child: Container(
              width:  w * 0.077,
              height: w * 0.077,
              decoration: BoxDecoration(
                color: MyShopColors.primaryGold,
                shape: BoxShape.circle,
                border: Border.all(color: MyShopColors.surfaceWhite, width: 2),
              ),
              child: Center(
                child: Text(
                  '$bidCount',
                  style: TextStyle(
                    fontSize:   w * 0.028,
                    fontWeight: FontWeight.w700,
                    color:      MyShopColors.surfaceWhite,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Shared section title ───────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final String label;
  final double w;
  final double h;
  const _SectionTitle({required this.label, required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        fontSize:   w * 0.038,
        fontWeight: FontWeight.w600,
        color:      MyShopColors.textPrimary,
        letterSpacing: -0.2,
      ),
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
        // AppBar skeleton
        Container(
          color: MyShopColors.surfaceWhite,
          padding: EdgeInsets.only(
            top: topPad + h * 0.010,
            bottom: h * 0.017,
            left: w * 0.041,
            right: w * 0.041,
          ),
          child: Row(
            children: [
              _Shimmer(width: w * 0.056, height: w * 0.056, radius: w * 0.056),
              SizedBox(width: w * 0.031),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Shimmer(width: w * 0.41, height: h * 0.024),
                    SizedBox(height: h * 0.006),
                    _Shimmer(width: w * 0.31, height: h * 0.017),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(w * 0.041),
            child: Column(
              children: [
                _ShimmerCard(w: w, h: h * 0.17),
                SizedBox(height: h * 0.019),
                _ShimmerCard(w: w, h: h * 0.14),
                SizedBox(height: h * 0.019),
                _ShimmerCard(w: w, h: h * 0.22),
                SizedBox(height: h * 0.019),
                _ShimmerCard(w: w, h: h * 0.28),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ShimmerCard extends StatelessWidget {
  final double w;
  final double h;
  const _ShimmerCard({required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: h,
      decoration: BoxDecoration(
        color: MyShopColors.divider,
        borderRadius: BorderRadius.circular(w * 0.031),
      ),
    );
  }
}

class _Shimmer extends StatelessWidget {
  final double width;
  final double height;
  final double? radius;
  const _Shimmer({required this.width, required this.height, this.radius});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: MyShopColors.divider,
        borderRadius: BorderRadius.circular(radius ?? 4),
      ),
    );
  }
}

// ── Error body ─────────────────────────────────────────────────────────────────

class _ErrorBody extends StatelessWidget {
  final double w;
  final double h;
  final VoidCallback onRetry;
  const _ErrorBody({required this.w, required this.h, required this.onRetry});

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
              'Could not load request details',
              style: TextStyle(
                fontSize: w * 0.041,
                fontWeight: FontWeight.w700,
                color: MyShopColors.textPrimary,
              ),
              textAlign: TextAlign.center,
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

// ── Dashed vertical line (timeline connector) ─────────────────────────────────

class _DashedVerticalLine extends StatelessWidget {
  final Color  color;
  final double dashLength;
  final double gapLength;

  const _DashedVerticalLine({
    required this.color,
    required this.dashLength,
    required this.gapLength,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 2,
      child: CustomPaint(
        painter: _DashedVerticalLinePainter(
          color:      color,
          dashLength: dashLength,
          gapLength:  gapLength,
        ),
      ),
    );
  }
}

class _DashedVerticalLinePainter extends CustomPainter {
  final Color  color;
  final double dashLength;
  final double gapLength;

  const _DashedVerticalLinePainter({
    required this.color,
    required this.dashLength,
    required this.gapLength,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color       = color
      ..strokeWidth = 2
      ..style       = PaintingStyle.stroke;

    final x = size.width / 2;
    var y = 0.0;
    while (y < size.height) {
      final end = (y + dashLength).clamp(0.0, size.height);
      canvas.drawLine(Offset(x, y), Offset(x, end), paint);
      y = end + gapLength;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedVerticalLinePainter old) =>
      old.color      != color      ||
      old.dashLength != dashLength ||
      old.gapLength  != gapLength;
}
