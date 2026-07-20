import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/di/providers.dart';
import '../data/job_cancellation_coordinator.dart';
import '../providers/bid_list_provider.dart';
import '../providers/job_detail_provider.dart';
import '../widgets/bid_list_sheet.dart';

// ── Screen ─────────────────────────────────────────────────────────────────────
// PRD 4.5 — Client views full job request detail, timeline progression,
// reference photos, and triggers bid review.
// API: GET /v1/jobs/:id  |  GET /v1/jobs/:id/bids

/// How often this screen polls the backend for job + bid updates. Acts as
/// a safety net for delayed/missing socket events — the primary path is
/// socket invalidation + the explicit invalidate that runs after the
/// client accepts a bid. 12 s keeps us well under the backend's
/// per-endpoint throttler when polling on top of socket-driven refetches.
const _jobDetailPollInterval = Duration(seconds: 12);

class JobDetailScreen extends ConsumerStatefulWidget {
  final String jobId;
  const JobDetailScreen({super.key, required this.jobId});

  @override
  ConsumerState<JobDetailScreen> createState() => _JobDetailScreenState();
}

class _JobDetailScreenState extends ConsumerState<JobDetailScreen> {
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(_jobDetailPollInterval, (_) {
      if (!mounted) return;
      // Invalidate both the job AND its bids — the timeline-summary card
      // shows the live bid count, and a stale bid list under it is what
      // made new bids feel like they only "arrived" after opening the
      // modal. Refreshing both together keeps the screen self-consistent.
      ref.invalidate(jobDetailProvider(widget.jobId));
      ref.invalidate(bidsForJobProvider(widget.jobId));
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

    final jobAsync = ref.watch(jobDetailProvider(widget.jobId));

    return Scaffold(
      backgroundColor: MyShopColors.offWhite,
      body: jobAsync.when(
        loading: () => _LoadingSkeleton(w: w, h: h),
        error: (e, _) => MyShopErrorBody(
          message: 'Could not load job details',
          onRetry: () => ref.invalidate(jobDetailProvider(widget.jobId)),
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
                  photoUrls: job.photoUrls,
                  w: w,
                  h: h,
                ),
                SizedBox(height: h * 0.033),
                _TimingSection(
                  isImmediate: job.isImmediate,
                  scheduledFor: job.scheduledFor,
                  w: w,
                  h: h,
                ),
                SizedBox(height: h * 0.033),
                _TimelineSection(steps: job.timeline, w: w, h: h),
                SizedBox(height: h * 0.033),
              ],
            ),
          ),
        ),
        _BottomActionBar(
          jobId: job.id,
          jobTitle: job.title,
          selectedArtisanId: job.selectedArtisanId,
          status: job.status,
          isPaymentAcknowledgedPending: job.isPaymentAcknowledgedPending,
          clientPaymentMethod: job.clientPaymentMethod,
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
            onTap: () {
              // After paying + rating we land here via `context.go(...)`
              // which clears the back stack — `maybePop()` then no-ops
              // and the back arrow looks dead. Fall through to the
              // Activity tab so the user always has somewhere to go.
              final nav = Navigator.of(context);
              if (nav.canPop()) {
                nav.pop();
              } else {
                context.go(AppRoutes.activity);
              }
            },
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
            child: Text(
              'Request Details',
              style: TextStyle(
                fontSize: w * 0.051,
                fontWeight: FontWeight.w700,
                color: MyShopColors.textPrimary,
                height: 1.2,
              ),
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
      builder: (_) => _MoreMenuSheet(jobId: job.id, w: w, h: h),
    );
  }
}

class _MoreMenuSheet extends ConsumerStatefulWidget {
  final String jobId;
  final double w;
  final double h;
  const _MoreMenuSheet({
    required this.jobId,
    required this.w,
    required this.h,
  });

  @override
  ConsumerState<_MoreMenuSheet> createState() => _MoreMenuSheetState();
}

class _MoreMenuSheetState extends ConsumerState<_MoreMenuSheet> {
  /// Reentry guard so a slow cancel-API doesn't queue a second request
  /// while the first is in flight.
  bool _cancelling = false;

  Future<void> _handleCancel() async {
    if (_cancelling) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel job request?'),
        content: const Text(
          'The request can be cancelled. Automatic cancellation fees and '
          'penalties are temporarily paused.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep request'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: MyShopColors.error),
            child: const Text('Cancel request'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _cancelling = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final router = GoRouter.of(context);
    final jobService = ref.read(jobServiceProvider);

    final cancellation = await cancelJobWithAuthority(
      jobService: jobService,
      jobId: widget.jobId,
      reason: 'client_cancelled',
    );
    if (!cancellation.confirmedCancelled) {
      if (mounted) {
        setState(() => _cancelling = false);
        messenger.showSnackBar(SnackBar(content: Text(cancellation.message)));
      }
      return;
    }

    final result = cancellation.response;
    final feePesewas = (result['cancellationFeePesewas'] as num?)?.toInt() ?? 0;
    var message = cancellation.message;
    if (result['cancellationConsequencesApplied'] == false) {
      message = result['notice'] as String? ??
          'Request cancelled. Automatic fees and penalties are temporarily paused.';
    } else if (feePesewas > 0) {
      final fee = (feePesewas / 100).toStringAsFixed(2);
      message = 'Request cancelled. Cancellation fee: GHS $fee';
    }

    // Invalidate the screen's data sources so any provider holding a
    // stale "open" job doesn't keep the user looking at the same page.
    // This runs only after authoritative cancellation; failures keep the job
    // visible so the user never sees a false-success navigation.
    // after they navigate away and back.
    ref.invalidate(jobDetailProvider(widget.jobId));
    ref.invalidate(bidsForJobProvider(widget.jobId));

    if (!mounted) return;
    navigator.pop(); // close the menu sheet
    messenger.showSnackBar(SnackBar(content: Text(message)));
    // Land the user on activity so they can see the cancellation
    // reflected (and aren't stuck on the now-cancelled job page).
    router.go(AppRoutes.activity);
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.w;
    final h = widget.h;
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
            label: _cancelling ? 'Cancelling…' : 'Cancel Request',
            color: _cancelling ? MyShopColors.disabled : MyShopColors.error,
            onTap: _cancelling ? () {} : () => _handleCancel(),
            w: w,
            h: h,
          ),
          // "Share Job Link" deferred to v1.2 — no shareable job-link
          // infrastructure on the backend yet (no share_token on jobs,
          // unlike rides). v1.0 ships with cancel-only on this menu.
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

class _JobSummaryCard extends ConsumerWidget {
  final JobDetail job;
  final double w;
  final double h;
  const _JobSummaryCard({required this.job, required this.w, required this.h});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bidsAsync = ref.watch(bidsForJobProvider(job.id));
    final bidCount = bidsAsync.maybeWhen(
      data: (bids) => bids.length,
      orElse: () => job.bids.count,
    );
    return Container(
      margin: EdgeInsets.symmetric(horizontal: w * 0.041),
      padding: EdgeInsets.all(w * 0.046),
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(w * 0.041),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: w * 0.031,
            offset: Offset(0, w * 0.005),
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
                  job.categoryIcon,
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
                    if (job.location.isNotEmpty) ...[
                      SizedBox(height: h * 0.006),
                      Row(
                        children: [
                          Icon(
                            Icons.location_on,
                            size: w * 0.033,
                            color: MyShopColors.primaryGold,
                          ),
                          SizedBox(width: w * 0.010),
                          Expanded(
                            child: Text(
                              job.location,
                              style: TextStyle(
                                fontSize: w * 0.030,
                                fontWeight: FontWeight.w400,
                                color: MyShopColors.textSecondary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(width: w * 0.021),
              // Status badge
              _StatusBadge(status: job.status, w: w),
            ],
          ),
          if (bidCount > 0) ...[
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
                        fontSize: w * 0.026,
                        fontWeight: FontWeight.w900,
                        color: MyShopColors.textSecondary,
                        letterSpacing: 1.2,
                      ),
                    ),
                    SizedBox(height: h * 0.005),
                    Row(
                      children: [
                        Text(
                          '$bidCount Artisans',
                          style: TextStyle(
                            fontSize: w * 0.038,
                            fontWeight: FontWeight.w700,
                            color: MyShopColors.textPrimary,
                          ),
                        ),
                        SizedBox(width: w * 0.021),
                        _AvatarStack(
                          totalCount: bidCount,
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
  final int totalCount;
  final double w;
  const _AvatarStack({required this.totalCount, required this.w});

  // Palette cycled through for avatar backgrounds.
  static const _palette = [
    Color(0xFF5D4037),
    Color(0xFF795548),
    Color(0xFF607D8B),
  ];

  @override
  Widget build(BuildContext context) {
    if (totalCount <= 0) return const SizedBox.shrink();

    // Show up to 3 slots: 3 avatars if count <= 3, else 2 avatars + "+N".
    final avatarSlots = totalCount <= 3 ? totalCount : 2;
    final showOverflow = totalCount > 3;
    final overflowCount = totalCount - avatarSlots;
    final totalSlots = avatarSlots + (showOverflow ? 1 : 0);

    final size = w * 0.072; // ~28dp
    final overlap = size * 0.35;
    final totalWidth = size + (totalSlots - 1) * (size - overlap);

    return SizedBox(
      width: totalWidth,
      height: size,
      child: Stack(
        children: List.generate(totalSlots, (i) {
          final isOverflow = showOverflow && i == totalSlots - 1;
          return Positioned(
            left: i * (size - overlap),
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: isOverflow
                    ? MyShopColors.primaryGold
                    : _palette[i % _palette.length],
                shape: BoxShape.circle,
                border: const Border.fromBorderSide(
                  BorderSide(color: MyShopColors.surfaceWhite, width: 1.5),
                ),
              ),
              alignment: Alignment.center,
              child: isOverflow
                  ? Text(
                      '+$overflowCount',
                      style: TextStyle(
                        fontSize: size * 0.38,
                        fontWeight: FontWeight.w700,
                        color: MyShopColors.surfaceWhite,
                        height: 1.0,
                      ),
                    )
                  : Icon(
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
  final List<String> photoUrls;
  final double w;
  final double h;
  const _ReferencePhotosSection({
    required this.photoUrls,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    if (photoUrls.isEmpty) {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: w * 0.041),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionTitle(label: 'Reference Photos', w: w, h: h),
            SizedBox(height: h * 0.014),
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(vertical: h * 0.028),
              decoration: BoxDecoration(
                color: MyShopColors.surfaceGrey,
                borderRadius: BorderRadius.circular(w * 0.021),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.photo_library_outlined,
                    size: w * 0.072,
                    color: MyShopColors.textHint,
                  ),
                  SizedBox(height: h * 0.007),
                  Text(
                    'No photos attached',
                    style: TextStyle(
                      fontSize: w * 0.033,
                      fontWeight: FontWeight.w400,
                      color: MyShopColors.textHint,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final cardWidth = w * 0.475;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: w * 0.041),
          child: Row(
            children: [
              _SectionTitle(label: 'Reference Photos', w: w, h: h),
              const Spacer(),
              Text(
                '${photoUrls.length} PHOTOS',
                style: TextStyle(
                  fontSize: w * 0.026,
                  fontWeight: FontWeight.w700,
                  color: MyShopColors.primaryGold,
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
            padding: EdgeInsets.symmetric(horizontal: w * 0.041),
            itemCount: photoUrls.length,
            separatorBuilder: (_, __) => SizedBox(width: w * 0.026),
            itemBuilder: (_, i) => SizedBox(
              width: cardWidth,
              child: _PhotoCard(
                url: photoUrls[i],
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
  final String url;
  final int index;
  final double w;
  final double h;
  const _PhotoCard({
    required this.url,
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
            Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                color: MyShopColors.surfaceGrey,
                child: Icon(
                  Icons.broken_image_outlined,
                  size: w * 0.072,
                  color: MyShopColors.textHint,
                ),
              ),
            ),
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
                  'PHOTO $index',
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
  final bool isImmediate;
  final DateTime? scheduledFor;
  final double w;
  final double h;

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
    final that = DateTime(dt.year, dt.month, dt.day);
    final diff = that.difference(today).inDays;

    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    final time = '$hh:$mm';

    if (diff == 0) return 'Today, $time';
    if (diff == 1) return 'Tomorrow, $time';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${dt.day} ${months[dt.month - 1]}, $time';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: w * 0.041),
      padding: EdgeInsets.symmetric(
        horizontal: w * 0.041,
        vertical: h * 0.014,
      ),
      decoration: BoxDecoration(
        color: MyShopColors.surfaceGrey,
        borderRadius: BorderRadius.circular(w * 0.041),
      ),
      child: Row(
        children: [
          Icon(
            Icons.access_time_rounded,
            size: w * 0.051,
            color: MyShopColors.textPrimary,
          ),
          SizedBox(width: w * 0.026),
          Expanded(
            child: Text(
              'Service Timing',
              style: TextStyle(
                fontSize: w * 0.036,
                fontWeight: FontWeight.w700,
                color: MyShopColors.textPrimary,
              ),
            ),
          ),
          SizedBox(width: w * 0.021),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: w * 0.041,
              vertical: h * 0.009,
            ),
            decoration: BoxDecoration(
              color: MyShopColors.surfaceWhite,
              borderRadius: BorderRadius.circular(w * 0.026),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: w * 0.013,
                  offset: Offset(0, w * 0.003),
                ),
              ],
            ),
            child: Text(
              _valueLabel(),
              style: TextStyle(
                fontSize: w * 0.033,
                fontWeight: FontWeight.w700,
                color: MyShopColors.textPrimary,
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
            final i = entry.key;
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
                      gapLength: 4,
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
      TimelineStepStatus.active => (
          MyShopColors.primaryGoldLight,
          MyShopColors.primaryGold
        ),
      TimelineStepStatus.pending => (
          MyShopColors.surfaceGrey,
          MyShopColors.disabled
        ),
      _ => (MyShopColors.successLight, MyShopColors.success),
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
  final String? selectedArtisanId;
  final JobStatus status;

  /// Backend has recorded `clientPaymentAcknowledgedAt` but the job is
  /// still `artisan_marked_complete` (cash flow waiting on the artisan).
  /// Drives the disabled "Awaiting artisan to confirm receipt" tile so
  /// we don't loop the client back through the payment screen.
  final bool isPaymentAcknowledgedPending;

  /// `'cash' | 'momo' | 'card'` — used to tailor the waiting copy.
  final String? clientPaymentMethod;

  final double w;
  final double h;
  const _BottomActionBar({
    required this.jobId,
    required this.jobTitle,
    required this.selectedArtisanId,
    required this.status,
    required this.isPaymentAcknowledgedPending,
    required this.clientPaymentMethod,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.paddingOf(context).bottom;
    final hasSelectedArtisan =
        selectedArtisanId != null && selectedArtisanId!.isNotEmpty;

    final Widget content;
    if (isPaymentAcknowledgedPending) {
      content = _AwaitingPaymentReceiptTile(
        method: clientPaymentMethod,
        w: w,
        h: h,
      );
    } else if (status == JobStatus.artisanMarkedComplete) {
      content = _ConfirmCompletionButton(jobId: jobId, w: w, h: h);
    } else if (status == JobStatus.pendingPayment) {
      // Charge is in flight with Paystack. Happy path: webhook lands in
      // seconds and flips the job to completed. Stuck path: client
      // closed the app or never finished Paystack's USSD/checkout, and
      // Paystack never fires a webhook — job sits here forever. The tile
      // shows the in-flight state plus a "didn't complete it?" retry
      // affordance so the client can recover without waiting on a
      // backend reconciliation cron.
      content = _PendingPaymentTile(jobId: jobId, w: w, h: h);
    } else if (status == JobStatus.completed) {
      content = _JobCompletedTile(w: w, h: h);
    } else if (hasSelectedArtisan) {
      content = _ViewSelectedBidButton(
        jobId: jobId,
        selectedArtisanId: selectedArtisanId!,
        w: w,
        h: h,
      );
    } else {
      content = _ViewBidsButton(
        jobId: jobId,
        jobTitle: jobTitle,
        w: w,
        h: h,
      );
    }

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
      child: content,
    );
  }
}

/// CTA shown when the artisan has marked the job complete and is awaiting
/// the client's final confirmation. Tapping it opens a confirmation dialog;
/// on accept we PATCH /jobs/:id/confirm and the timeline advances to Completed.
class _ConfirmCompletionButton extends ConsumerStatefulWidget {
  final String jobId;
  final double w;
  final double h;
  const _ConfirmCompletionButton({
    required this.jobId,
    required this.w,
    required this.h,
  });

  @override
  ConsumerState<_ConfirmCompletionButton> createState() =>
      _ConfirmCompletionButtonState();
}

class _ConfirmCompletionButtonState
    extends ConsumerState<_ConfirmCompletionButton> {
  bool _submitting = false;

  Future<void> _handleTap() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      // Step 1: satisfaction check. Confirming kicks off the Paystack
      // flow rather than marking the job complete directly. PATCH /confirm
      // only fires after the charge settles (webhook) or the artisan
      // confirms cash receipt, whichever happens first.
      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: true,
        builder: (_) => const _ConfirmCompletionDialog(),
      );
      if (confirmed != true || !mounted) return;

      // Step 2: hand off to the payment screen, which owns method
      // selection (MTN / Telecel / AirtelTigo / Visa / Mastercard /
      // Cash), the MoMo phone input, and the rest of the flow.
      //
      // Refetch on return — the cash flow records
      // `clientPaymentAcknowledgedAt` server-side without flipping
      // job.status, so without this pull the action bar would render
      // "Proceed to Payment" again and loop the client.
      await context.push(AppRoutes.jobPaymentPath(widget.jobId));
      if (mounted) {
        ref.invalidate(jobDetailProvider(widget.jobId));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.w;
    final h = widget.h;
    return SizedBox(
      width: double.infinity,
      height: h * 0.062,
      child: ElevatedButton(
        onPressed: _submitting ? null : _handleTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: MyShopColors.success,
          foregroundColor: MyShopColors.surfaceWhite,
          disabledBackgroundColor: MyShopColors.surfaceGrey,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(w * 0.021),
          ),
        ),
        child: _submitting
            ? SizedBox(
                width: w * 0.051,
                height: w * 0.051,
                child: const CircularProgressIndicator(
                  strokeWidth: 2,
                  color: MyShopColors.surfaceWhite,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.payments_rounded,
                    size: w * 0.051,
                    color: MyShopColors.surfaceWhite,
                  ),
                  SizedBox(width: w * 0.021),
                  Text(
                    'Proceed to Payment',
                    style: TextStyle(
                      fontSize: w * 0.040,
                      fontWeight: FontWeight.w700,
                      color: MyShopColors.surfaceWhite,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Satisfaction-check dialog shown before the client confirms completion.
class _ConfirmCompletionDialog extends StatelessWidget {
  const _ConfirmCompletionDialog();

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final w = size.width;
    return AlertDialog(
      backgroundColor: MyShopColors.surfaceWhite,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(w * 0.041),
      ),
      titlePadding: EdgeInsets.fromLTRB(
        w * 0.051,
        w * 0.051,
        w * 0.051,
        w * 0.021,
      ),
      contentPadding: EdgeInsets.symmetric(
        horizontal: w * 0.051,
        vertical: w * 0.015,
      ),
      actionsPadding: EdgeInsets.fromLTRB(
        w * 0.031,
        0,
        w * 0.031,
        w * 0.031,
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: w * 0.123,
            height: w * 0.123,
            decoration: BoxDecoration(
              color: MyShopColors.successLight,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.verified_user_outlined,
              size: w * 0.062,
              color: MyShopColors.success,
            ),
          ),
          SizedBox(height: w * 0.031),
          Text(
            'Confirm Job Completion',
            style: TextStyle(
              fontSize: w * 0.046,
              fontWeight: FontWeight.w700,
              color: MyShopColors.textPrimary,
            ),
          ),
        ],
      ),
      content: Text(
        'Have you checked the work and are you satisfied with what the '
        "artisan delivered? Tap \"Proceed to Payment\" to pay — the job "
        "is marked complete once payment settles.",
        style: TextStyle(
          fontSize: w * 0.036,
          fontWeight: FontWeight.w400,
          color: MyShopColors.textSecondary,
          height: 1.5,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(
            'Not Yet',
            style: TextStyle(
              fontSize: w * 0.036,
              fontWeight: FontWeight.w600,
              color: MyShopColors.textSecondary,
            ),
          ),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: ElevatedButton.styleFrom(
            backgroundColor: MyShopColors.success,
            foregroundColor: MyShopColors.surfaceWhite,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(w * 0.021),
            ),
            padding: EdgeInsets.symmetric(
              horizontal: w * 0.046,
              vertical: w * 0.026,
            ),
          ),
          child: Text(
            'Yes, Proceed to Payment',
            style: TextStyle(
              fontSize: w * 0.036,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

/// Action-bar button shown when the job is in `pending_payment` — the
/// backend still believes a Paystack charge is in flight. In practice
/// this is also the state a client lands in after killing the app
/// mid-payment, since Paystack's failure webhook can take minutes (or
/// never fires). The tile from before showed "Processing payment…" with
/// a small recovery link beneath it, but in production that reads as
/// "no pay button" — so the retry is now the primary action, with the
/// processing context demoted to a subtitle.
///
/// Distinct gold styling (vs. the green "Proceed to Payment" used for
/// the first attempt) signals "this is a recovery, your previous
/// attempt is still on file." A confirm dialog warns about creating a
/// duplicate charge before navigating to the payment screen.
class _PendingPaymentTile extends StatefulWidget {
  final String jobId;
  final double w;
  final double h;
  const _PendingPaymentTile({
    required this.jobId,
    required this.w,
    required this.h,
  });

  @override
  State<_PendingPaymentTile> createState() => _PendingPaymentTileState();
}

class _PendingPaymentTileState extends State<_PendingPaymentTile> {
  bool _submitting = false;

  Future<void> _handleTap() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: true,
        builder: (_) => const _RestartPaymentDialog(),
      );
      if (confirmed != true || !mounted) return;
      context.push(AppRoutes.jobPaymentPath(widget.jobId));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.w;
    final h = widget.h;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: double.infinity,
          height: h * 0.062,
          child: ElevatedButton(
            onPressed: _submitting ? null : _handleTap,
            style: ElevatedButton.styleFrom(
              backgroundColor: MyShopColors.warning,
              foregroundColor: MyShopColors.surfaceWhite,
              disabledBackgroundColor: MyShopColors.surfaceGrey,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(w * 0.021),
              ),
            ),
            child: _submitting
                ? SizedBox(
                    width: w * 0.051,
                    height: w * 0.051,
                    child: const CircularProgressIndicator(
                      strokeWidth: 2,
                      color: MyShopColors.surfaceWhite,
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.refresh_rounded,
                        size: w * 0.051,
                        color: MyShopColors.surfaceWhite,
                      ),
                      SizedBox(width: w * 0.021),
                      Text(
                        'Resume Payment',
                        style: TextStyle(
                          fontSize: w * 0.040,
                          fontWeight: FontWeight.w700,
                          color: MyShopColors.surfaceWhite,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
        SizedBox(height: h * 0.008),
        Text(
          'Your earlier payment is still pending. Tap to start over.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: w * 0.030,
            fontWeight: FontWeight.w500,
            color: MyShopColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

/// Confirmation dialog shown before restarting a payment that the
/// backend still believes is in flight. Spells out the consequence
/// (previous attempt is replaced) so the client doesn't tap retry
/// while a legitimate USSD prompt is sitting on their phone.
class _RestartPaymentDialog extends StatelessWidget {
  const _RestartPaymentDialog();

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final w = size.width;
    return AlertDialog(
      backgroundColor: MyShopColors.surfaceWhite,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(w * 0.041),
      ),
      titlePadding: EdgeInsets.fromLTRB(
        w * 0.051,
        w * 0.051,
        w * 0.051,
        w * 0.021,
      ),
      contentPadding: EdgeInsets.symmetric(
        horizontal: w * 0.051,
        vertical: w * 0.015,
      ),
      actionsPadding: EdgeInsets.fromLTRB(
        w * 0.031,
        0,
        w * 0.031,
        w * 0.031,
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: w * 0.123,
            height: w * 0.123,
            decoration: const BoxDecoration(
              color: MyShopColors.warningLight,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.refresh_rounded,
              size: w * 0.062,
              color: MyShopColors.warning,
            ),
          ),
          SizedBox(height: w * 0.031),
          Text(
            'Restart payment?',
            style: TextStyle(
              fontSize: w * 0.046,
              fontWeight: FontWeight.w700,
              color: MyShopColors.textPrimary,
            ),
          ),
        ],
      ),
      content: Text(
        "Only restart if you didn't finish the previous attempt. If a "
        "Paystack prompt is still on your phone, please complete it "
        "instead — restarting may create a second charge request.",
        style: TextStyle(
          fontSize: w * 0.036,
          fontWeight: FontWeight.w400,
          color: MyShopColors.textSecondary,
          height: 1.5,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(
            'Keep waiting',
            style: TextStyle(
              fontSize: w * 0.036,
              fontWeight: FontWeight.w600,
              color: MyShopColors.textSecondary,
            ),
          ),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: ElevatedButton.styleFrom(
            backgroundColor: MyShopColors.warning,
            foregroundColor: MyShopColors.surfaceWhite,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(w * 0.021),
            ),
            padding: EdgeInsets.symmetric(
              horizontal: w * 0.046,
              vertical: w * 0.026,
            ),
          ),
          child: Text(
            'Restart payment',
            style: TextStyle(
              fontSize: w * 0.036,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _JobCompletedTile extends StatelessWidget {
  final double w;
  final double h;
  const _JobCompletedTile({required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: h * 0.062,
      decoration: BoxDecoration(
        color: MyShopColors.successLight,
        borderRadius: BorderRadius.circular(w * 0.021),
        border: Border.all(
          color: MyShopColors.success.withValues(alpha: 0.35),
        ),
      ),
      alignment: Alignment.center,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.check_circle_rounded,
            size: w * 0.051,
            color: MyShopColors.success,
          ),
          SizedBox(width: w * 0.021),
          Text(
            'Job Completed',
            style: TextStyle(
              fontSize: w * 0.040,
              fontWeight: FontWeight.w700,
              color: MyShopColors.success,
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown when the client has acknowledged payment (cash or otherwise) but
/// the job hasn't settled yet — the artisan still needs to confirm cash
/// receipt, or the Paystack webhook hasn't landed. Disabled by design:
/// re-prompting the client to "Proceed to Payment" here is what triggered
/// duplicate-payment loops in the original bug.
class _AwaitingPaymentReceiptTile extends StatelessWidget {
  final String? method;
  final double w;
  final double h;
  const _AwaitingPaymentReceiptTile({
    required this.method,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    final isCash = method == 'cash';
    final label =
        isCash ? 'Awaiting artisan to confirm receipt' : 'Processing payment…';
    return Container(
      width: double.infinity,
      height: h * 0.062,
      decoration: BoxDecoration(
        color: MyShopColors.surfaceGrey,
        borderRadius: BorderRadius.circular(w * 0.021),
        border: Border.all(color: MyShopColors.divider),
      ),
      alignment: Alignment.center,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: w * 0.046,
            height: w * 0.046,
            child: const CircularProgressIndicator(
              strokeWidth: 2,
              color: MyShopColors.textSecondary,
            ),
          ),
          SizedBox(width: w * 0.026),
          Text(
            label,
            style: TextStyle(
              fontSize: w * 0.038,
              fontWeight: FontWeight.w600,
              color: MyShopColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Replacement CTA shown once the client has selected a bid. Finds the
/// accepted bid by matching [selectedArtisanId] against the bid list and
/// navigates to that bid's detail screen.
class _ViewSelectedBidButton extends ConsumerWidget {
  final String jobId;
  final String selectedArtisanId;
  final double w;
  final double h;
  const _ViewSelectedBidButton({
    required this.jobId,
    required this.selectedArtisanId,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bidsAsync = ref.watch(bidsForJobProvider(jobId));

    return GestureDetector(
      onTap: () {
        final bids = bidsAsync.asData?.value ?? const [];
        final selected = bids.firstWhere(
          (b) => b.artisanId == selectedArtisanId,
          orElse: () => bids.isNotEmpty
              ? bids.first
              : throw StateError('No bids available'),
        );
        context.push(AppRoutes.jobBidsPath(jobId, selected.bidId));
      },
      child: Container(
        height: h * 0.062,
        padding: EdgeInsets.symmetric(horizontal: w * 0.041),
        decoration: BoxDecoration(
          color: MyShopColors.darkSlate,
          borderRadius: BorderRadius.circular(w * 0.021),
        ),
        child: Row(
          children: [
            Icon(
              Icons.verified_rounded,
              size: w * 0.051,
              color: MyShopColors.primaryGold,
            ),
            SizedBox(width: w * 0.026),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'SELECTED ARTISAN',
                    style: TextStyle(
                      fontSize: w * 0.026,
                      fontWeight: FontWeight.w700,
                      color: MyShopColors.surfaceWhite.withValues(alpha: 0.7),
                      letterSpacing: 0.8,
                    ),
                  ),
                  SizedBox(height: h * 0.002),
                  Text(
                    'View Selected Bid',
                    style: TextStyle(
                      fontSize: w * 0.038,
                      fontWeight: FontWeight.w700,
                      color: MyShopColors.surfaceWhite,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: w * 0.056,
              color: MyShopColors.surfaceWhite,
            ),
          ],
        ),
      ),
    );
  }
}

class _ViewBidsButton extends ConsumerWidget {
  final String jobId;
  final String jobTitle;
  final double w;
  final double h;
  const _ViewBidsButton({
    required this.jobId,
    required this.jobTitle,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bidsAsync = ref.watch(bidsForJobProvider(jobId));
    final bidCount = bidsAsync.maybeWhen(
      data: (bids) => bids.length,
      orElse: () => 0,
    );
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
              color: MyShopColors.darkSlate,
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
                          fontSize: w * 0.026,
                          fontWeight: FontWeight.w700,
                          color:
                              MyShopColors.surfaceWhite.withValues(alpha: 0.7),
                          letterSpacing: 0.8,
                        ),
                      ),
                      SizedBox(height: h * 0.002),
                      Text(
                        'View $bidCount Bids',
                        style: TextStyle(
                          fontSize: w * 0.038,
                          fontWeight: FontWeight.w700,
                          color: MyShopColors.surfaceWhite,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: w * 0.056,
                  color: MyShopColors.surfaceWhite,
                ),
              ],
            ),
          ),
          // Bid-count badge (primary gold)
          Positioned(
            top: -(h * 0.012),
            right: -(w * 0.015),
            child: Container(
              width: w * 0.077,
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
                    fontSize: w * 0.028,
                    fontWeight: FontWeight.w700,
                    color: MyShopColors.surfaceWhite,
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
        fontSize: w * 0.038,
        fontWeight: FontWeight.w600,
        color: MyShopColors.textPrimary,
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

// ── Dashed vertical line (timeline connector) ─────────────────────────────────

class _DashedVerticalLine extends StatelessWidget {
  final Color color;
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
          color: color,
          dashLength: dashLength,
          gapLength: gapLength,
        ),
      ),
    );
  }
}

class _DashedVerticalLinePainter extends CustomPainter {
  final Color color;
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
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

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
      old.color != color ||
      old.dashLength != dashLength ||
      old.gapLength != gapLength;
}
