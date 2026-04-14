import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/active_job_provider.dart';

// ── Design tokens ─────────────────────────────────────────────────────────────
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
const _error         = Color(0xFFEB5757);
const _divider       = Color(0xFFE0E0E0);
const _disabled      = Color(0xFFBDBDBD);

// ── Timeline step model ───────────────────────────────────────────────────────

enum _TLStatus { completed, active, pending }

class _TLStep {
  final String title;
  final _TLStatus status;
  final String? timeLabel;
  final String? description;

  /// Non-null only on the "Artisan Assigned" step — shows the artisan's
  /// bid reference as a small red badge overlay on the timeline icon.
  final String? badgeLabel;

  /// Custom icon drawn inside the circle for special active steps.
  /// Null → use the standard pulsing ring indicator.
  final IconData? activeIcon;

  const _TLStep({
    required this.title,
    required this.status,
    this.timeLabel,
    this.description,
    this.badgeLabel,
    this.activeIcon,
  });
}

/// Builds the timeline steps for [job] based on its current phase.
List<_TLStep> _buildSteps(ActiveJobData job) {
  final phase = job.phase;
  final isCompleted = _TLStatus.completed;
  final isActive    = _TLStatus.active;
  final isPending   = _TLStatus.pending;

  _TLStatus s(int stepIndex) {
    const order = [
      ActiveJobPhase.enRoute,       // step 2 (0-indexed after posted/assigned)
      ActiveJobPhase.arrived,
      ActiveJobPhase.inProgress,
      ActiveJobPhase.awaitingApproval,
    ];
    final phaseIdx = order.indexOf(phase);
    if (phaseIdx > stepIndex) return isCompleted;
    if (phaseIdx == stepIndex) return isActive;
    return isPending;
  }

  return [
    _TLStep(
      title: 'Job Posted',
      status: isCompleted,
      timeLabel: job.jobPostedTime,
      description: job.jobDescription,
    ),
    _TLStep(
      title: 'Artisan Assigned',
      status: isCompleted,
      description:
          '${job.artisan.name} (Verified) accepted your job request.',
      badgeLabel: '3',
    ),
    _TLStep(
      title: 'Artisan En Route',
      status: s(0),
      timeLabel: s(0) == isActive ? 'NOW' : null,
      description:
          '${job.artisan.firstName} is currently navigating to your '
          'location in ${job.location.split(',').first}.',
    ),
    _TLStep(
      title: 'Artisan Arrival',
      status: s(1),
      description: 'Waiting for artisan to reach your doorstep.',
    ),
    _TLStep(
      title: 'Work in Progress',
      status: s(2),
      description:
          '${job.artisan.firstName} will upload arrival and progress '
          'photos here.',
    ),
    if (phase == ActiveJobPhase.awaitingApproval)
      _TLStep(
        title: 'Completed, waiting for approval',
        status: isActive,
        description:
            'Artisan has completed the requested job, please inspect '
            'and confirm.',
        activeIcon: Icons.camera_alt_rounded,
      ),
  ];
}

// ── Screen entry ──────────────────────────────────────────────────────────────

class ActiveJobScreen extends ConsumerWidget {
  final String jobId;
  const ActiveJobScreen({super.key, required this.jobId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final size = MediaQuery.sizeOf(context);
    final w    = size.width;
    final h    = size.height;

    final jobAsync = ref.watch(activeJobProvider(jobId));

    return Scaffold(
      backgroundColor: _offWhite,
      body: jobAsync.when(
        loading: () => _LoadingSkeleton(w: w, h: h),
        error: (_, __) => _ErrorBody(
          w: w,
          h: h,
          onRetry: () => ref.invalidate(activeJobProvider(jobId)),
        ),
        data: (job) => _ActiveJobBody(job: job, w: w, h: h),
      ),
    );
  }
}

// ── Full body ─────────────────────────────────────────────────────────────────

class _ActiveJobBody extends ConsumerWidget {
  final ActiveJobData job;
  final double w;
  final double h;
  const _ActiveJobBody({required this.job, required this.w, required this.h});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        _AppBar(w: w, h: h),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: h * 0.014),
                _JobHeaderCard(job: job, w: w, h: h),
                SizedBox(height: h * 0.005),
                _StatsRow(job: job, w: w, h: h),
                SizedBox(height: h * 0.005),
                _MapSection(job: job, w: w, h: h),
                SizedBox(height: h * 0.010),
                _ActionButtonsRow(artisanName: job.artisan.name, w: w, h: h),
                SizedBox(height: h * 0.019),
                _ProgressSection(job: job, w: w, h: h),
                SizedBox(height: h * 0.014),
                _CostCard(job: job, w: w, h: h),
                SizedBox(height: h * 0.014),
                _SafetyCard(w: w, h: h),
                SizedBox(height: h * 0.028),
              ],
            ),
          ),
        ),
        _BottomBar(job: job, w: w, h: h),
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
      color: _surfaceWhite,
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
                  size: w * 0.056, color: _textPrimary),
            ),
          ),
          Expanded(
            child: Text(
              'Job Details',
              style: TextStyle(
                fontSize: w * 0.051,
                fontWeight: FontWeight.w700,
                color: _textPrimary,
              ),
            ),
          ),
          GestureDetector(
            onTap: () {}, // TODO: show job info sheet
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: w * 0.092,
              height: w * 0.092,
              decoration: BoxDecoration(
                color: _surfaceGrey,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.info_outline_rounded,
                  size: w * 0.046, color: _textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Job Header Card ───────────────────────────────────────────────────────────

class _JobHeaderCard extends StatelessWidget {
  final ActiveJobData job;
  final double w;
  final double h;
  const _JobHeaderCard(
      {required this.job, required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: w * 0.041),
      padding: EdgeInsets.all(w * 0.041),
      decoration: BoxDecoration(
        color: _surfaceWhite,
        borderRadius: BorderRadius.circular(w * 0.031),
        border: Border.all(color: _divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Avatar ──
          Container(
            width: w * 0.164,
            height: w * 0.164,
            decoration: BoxDecoration(
              color: job.artisan.avatarColor,
              borderRadius: BorderRadius.circular(w * 0.021),
            ),
            child: Center(
              child: Text(
                job.artisan.name
                    .trim()
                    .split(' ')
                    .take(2)
                    .map((s) => s[0])
                    .join(),
                style: TextStyle(
                  fontSize: w * 0.051,
                  fontWeight: FontWeight.w700,
                  color: _surfaceWhite,
                ),
              ),
            ),
          ),
          SizedBox(width: w * 0.031),
          // ── Info column ──
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        job.title,
                        style: TextStyle(
                          fontSize: w * 0.041,
                          fontWeight: FontWeight.w700,
                          color: _textPrimary,
                          height: 1.25,
                        ),
                      ),
                    ),
                    SizedBox(width: w * 0.021),
                    _StatusBadge(phase: job.phase, w: w),
                  ],
                ),
                SizedBox(height: h * 0.005),
                Text(
                  'Service ID: ${job.serviceId}',
                  style: TextStyle(
                    fontSize: w * 0.028,
                    fontWeight: FontWeight.w400,
                    color: _textSecondary,
                  ),
                ),
                SizedBox(height: h * 0.009),
                Row(
                  children: [
                    _CategoryChip(
                        name: job.categoryName,
                        icon: job.categoryIcon,
                        w: w),
                    SizedBox(width: w * 0.018),
                    Icon(Icons.location_on_rounded,
                        size: w * 0.031, color: _gold),
                    SizedBox(width: w * 0.005),
                    Expanded(
                      child: Text(
                        job.location,
                        style: TextStyle(
                          fontSize: w * 0.028,
                          fontWeight: FontWeight.w400,
                          color: _textSecondary,
                        ),
                        overflow: TextOverflow.ellipsis,
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

class _StatusBadge extends StatelessWidget {
  final ActiveJobPhase phase;
  final double w;
  const _StatusBadge({required this.phase, required this.w});

  @override
  Widget build(BuildContext context) {
    final color = phase.statusColor;
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: w * 0.026, vertical: w * 0.010),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(w * 0.051),
      ),
      child: Text(
        phase.statusLabel,
        style: TextStyle(
          fontSize: w * 0.026,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String name;
  final IconData icon;
  final double w;
  const _CategoryChip(
      {required this.name, required this.icon, required this.w});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: w * 0.018, vertical: w * 0.008),
      decoration: BoxDecoration(
        color: _surfaceGrey,
        borderRadius: BorderRadius.circular(w * 0.041),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: w * 0.028, color: _textSecondary),
          SizedBox(width: w * 0.008),
          Text(
            name,
            style: TextStyle(
              fontSize: w * 0.028,
              fontWeight: FontWeight.w500,
              color: _textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Stats Row ─────────────────────────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  final ActiveJobData job;
  final double w;
  final double h;
  const _StatsRow({required this.job, required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: w * 0.041),
      padding: EdgeInsets.symmetric(
          vertical: h * 0.014, horizontal: w * 0.031),
      decoration: BoxDecoration(
        color: _surfaceWhite,
        borderRadius: BorderRadius.circular(w * 0.031),
        border: Border.all(color: _divider),
      ),
      child: Row(
        children: [
          Expanded(
            child: _StatCell(
              icon: job.phase == ActiveJobPhase.enRoute
                  ? Icons.access_time_rounded
                  : Icons.timer_outlined,
              label: job.phase.statLabel,
              value: job.statValue,
              w: w,
              h: h,
            ),
          ),
          Container(width: 1, height: h * 0.050, color: _divider),
          Expanded(
            child: _StatCell(
              icon: Icons.calendar_today_outlined,
              label: 'SCHEDULE',
              value: job.scheduleLabel,
              w: w,
              h: h,
              align: CrossAxisAlignment.end,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final double w;
  final double h;
  final CrossAxisAlignment align;
  const _StatCell({
    required this.icon,
    required this.label,
    required this.value,
    required this.w,
    required this.h,
    this.align = CrossAxisAlignment.start,
  });

  @override
  Widget build(BuildContext context) {
    final isEnd = align == CrossAxisAlignment.end;
    return Column(
      crossAxisAlignment: align,
      children: [
        Row(
          mainAxisAlignment:
              isEnd ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [
            Icon(icon, size: w * 0.033, color: _textHint),
            SizedBox(width: w * 0.008),
            Text(
              label,
              style: TextStyle(
                fontSize: w * 0.023,
                fontWeight: FontWeight.w900,
                color: _textSecondary,
                letterSpacing: 0.6,
              ),
            ),
          ],
        ),
        SizedBox(height: h * 0.004),
        Text(
          value,
          style: TextStyle(
            fontSize: w * 0.038,
            fontWeight: FontWeight.w700,
            color: _textPrimary,
          ),
        ),
      ],
    );
  }
}

// ── Map Section ───────────────────────────────────────────────────────────────

class _MapSection extends StatelessWidget {
  final ActiveJobData job;
  final double w;
  final double h;
  const _MapSection({required this.job, required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: w * 0.041),
      height: h * 0.178, // ~150dp
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(w * 0.031),
        border: Border.all(color: _divider),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(w * 0.031 - 1),
        child: Stack(
          children: [
            // Map background + route
            Positioned.fill(
              child: CustomPaint(
                painter: _ActiveJobMapPainter(
                  artisanFirstName: job.artisan.firstName,
                ),
              ),
            ),
            // "Expand Map >" button
            Positioned(
              bottom: h * 0.012,
              right: w * 0.031,
              child: GestureDetector(
                onTap: () {}, // TODO: open Mapbox full-screen tracking
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: EdgeInsets.symmetric(
                      horizontal: w * 0.031, vertical: h * 0.007),
                  decoration: BoxDecoration(
                    color: _surfaceWhite,
                    borderRadius: BorderRadius.circular(w * 0.041),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.10),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Expand Map',
                        style: TextStyle(
                          fontSize: w * 0.028,
                          fontWeight: FontWeight.w600,
                          color: _textPrimary,
                        ),
                      ),
                      SizedBox(width: w * 0.010),
                      Icon(Icons.chevron_right_rounded,
                          size: w * 0.036, color: _textSecondary),
                    ],
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

class _ActiveJobMapPainter extends CustomPainter {
  final String artisanFirstName;
  const _ActiveJobMapPainter({required this.artisanFirstName});

  @override
  void paint(Canvas canvas, Size size) {
    // Background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = const Color(0xFFD4E9C8),
    );

    final roadPaint = Paint()
      ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.55)
      ..strokeWidth = 6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Horizontal road
    canvas.drawLine(
      Offset(0, size.height * 0.55),
      Offset(size.width, size.height * 0.55),
      roadPaint,
    );
    // Vertical road
    canvas.drawLine(
      Offset(size.width * 0.45, 0),
      Offset(size.width * 0.45, size.height),
      roadPaint..strokeWidth = 5,
    );
    // Diagonal branch
    canvas.drawLine(
      Offset(size.width * 0.45, size.height * 0.55),
      Offset(size.width * 0.80, size.height * 0.25),
      roadPaint..strokeWidth = 3,
    );

    // Gold route: artisan → client
    final artisanPt = Offset(size.width * 0.20, size.height * 0.72);
    final clientPt  = Offset(size.width * 0.62, size.height * 0.40);
    final ctrlPt    = Offset(size.width * 0.38, size.height * 0.30);

    final routePath = Path()
      ..moveTo(artisanPt.dx, artisanPt.dy)
      ..quadraticBezierTo(ctrlPt.dx, ctrlPt.dy, clientPt.dx, clientPt.dy);

    canvas.drawPath(
      routePath,
      Paint()
        ..color = _gold
        ..strokeWidth = 3.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    // Artisan marker (dark circle + white inner)
    canvas.drawCircle(
        artisanPt, 10, Paint()..color = const Color(0xFF46535D));
    canvas.drawCircle(
        artisanPt, 5, Paint()..color = _surfaceWhite);

    // Client marker (red pin circle)
    canvas.drawCircle(clientPt, 10, Paint()..color = _error);
    canvas.drawCircle(clientPt, 5, Paint()..color = _surfaceWhite);

    // Labels
    _drawLabel(canvas, size, artisanFirstName, artisanPt,
        const Color(0xFF46535D));
    _drawLabel(canvas, size, 'You', clientPt, _error);
  }

  void _drawLabel(Canvas canvas, Size size, String text, Offset anchor,
      Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    // White pill background
    final pillRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(anchor.dx, anchor.dy + 20),
        width: tp.width + 14,
        height: 18,
      ),
      const Radius.circular(9),
    );
    canvas.drawRRect(
        pillRect, Paint()..color = _surfaceWhite.withValues(alpha: 0.9));

    tp.paint(
      canvas,
      Offset(anchor.dx - tp.width / 2, anchor.dy + 11),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}

// ── Action Buttons Row ────────────────────────────────────────────────────────

class _ActionButtonsRow extends StatelessWidget {
  final String artisanName;
  final double w;
  final double h;
  const _ActionButtonsRow(
      {required this.artisanName, required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: w * 0.041),
      child: Row(
        children: [
          Expanded(
            child: _OutlinedActionButton(
              icon: Icons.chat_bubble_outline_rounded,
              label: 'Message',
              onTap: () {}, // TODO: navigate to chat
              w: w,
              h: h,
            ),
          ),
          SizedBox(width: w * 0.026),
          Expanded(
            child: _OutlinedActionButton(
              icon: Icons.phone_outlined,
              label: 'Call Artisan',
              onTap: () {}, // TODO: initiate masked call
              w: w,
              h: h,
            ),
          ),
        ],
      ),
    );
  }
}

class _OutlinedActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final double w;
  final double h;
  const _OutlinedActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: h * 0.054,
        decoration: BoxDecoration(
          color: _surfaceWhite,
          borderRadius: BorderRadius.circular(w * 0.021),
          border: Border.all(color: _divider),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: w * 0.038, color: _textPrimary),
            SizedBox(width: w * 0.015),
            Text(
              label,
              style: TextStyle(
                fontSize: w * 0.033,
                fontWeight: FontWeight.w600,
                color: _textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Progress Section ──────────────────────────────────────────────────────────

class _ProgressSection extends StatelessWidget {
  final ActiveJobData job;
  final double w;
  final double h;
  const _ProgressSection(
      {required this.job, required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    final steps = _buildSteps(job);
    return Container(
      margin: EdgeInsets.symmetric(horizontal: w * 0.041),
      padding: EdgeInsets.all(w * 0.041),
      decoration: BoxDecoration(
        color: _surfaceWhite,
        borderRadius: BorderRadius.circular(w * 0.031),
        border: Border.all(color: _divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Section header ──
          Row(
            children: [
              Container(
                width: w * 0.010,
                height: h * 0.026,
                color: _gold,
              ),
              SizedBox(width: w * 0.021),
              Text(
                'JOB PROGRESS',
                style: TextStyle(
                  fontSize: w * 0.033,
                  fontWeight: FontWeight.w900,
                  color: _textPrimary,
                  letterSpacing: 0.8,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () {}, // TODO: navigate to live tracking map
                behavior: HitTestBehavior.opaque,
                child: Text(
                  'LIVE TRACKING',
                  style: TextStyle(
                    fontSize: w * 0.028,
                    fontWeight: FontWeight.w700,
                    color: _gold,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: h * 0.019),
          // ── Timeline ──
          ...steps.asMap().entries.map((e) {
            return _TimelineRow(
              step: e.value,
              isLast: e.key == steps.length - 1,
              w: w,
              h: h,
            );
          }),
        ],
      ),
    );
  }
}

// ── Timeline Row ──────────────────────────────────────────────────────────────

class _TimelineRow extends StatelessWidget {
  final _TLStep step;
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
    final isActive    = step.status == _TLStatus.active;
    final isCompleted = step.status == _TLStatus.completed;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Icon + connector ──
          SizedBox(
            width: w * 0.082,
            child: Column(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    _TimelineIcon(step: step, w: w),
                    if (step.badgeLabel != null)
                      Positioned(
                        top: -h * 0.005,
                        right: -w * 0.013,
                        child: Container(
                          width: w * 0.054,
                          height: w * 0.054,
                          decoration: const BoxDecoration(
                            color: _error,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              step.badgeLabel!,
                              style: TextStyle(
                                fontSize: w * 0.023,
                                fontWeight: FontWeight.w700,
                                color: _surfaceWhite,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                if (!isLast)
                  Expanded(
                    child: Center(
                      child: Container(
                        width: 2,
                        color: isCompleted
                            ? _success.withValues(alpha: 0.35)
                            : _divider,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(width: w * 0.031),
          // ── Content ──
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                  bottom: isLast ? 0 : h * 0.022),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title + time label row
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          step.title,
                          style: TextStyle(
                            fontSize: w * 0.033,
                            fontWeight: isActive
                                ? FontWeight.w700
                                : FontWeight.w600,
                            color: isActive
                                ? _gold
                                : isCompleted
                                    ? _textPrimary
                                    : _textSecondary,
                          ),
                        ),
                      ),
                      if (step.timeLabel != null) ...[
                        SizedBox(width: w * 0.010),
                        Text(
                          step.timeLabel!,
                          style: TextStyle(
                            fontSize: w * 0.026,
                            fontWeight: FontWeight.w600,
                            color: isActive ? _gold : _textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (step.description != null) ...[
                    SizedBox(height: h * 0.005),
                    Text(
                      step.description!,
                      style: TextStyle(
                        fontSize: w * 0.028,
                        fontWeight: FontWeight.w400,
                        color: _textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Timeline Icon ─────────────────────────────────────────────────────────────

class _TimelineIcon extends StatelessWidget {
  final _TLStep step;
  final double w;
  const _TimelineIcon({required this.step, required this.w});

  @override
  Widget build(BuildContext context) {
    final size = w * 0.082;

    switch (step.status) {
      case _TLStatus.completed:
        return Container(
          width: size,
          height: size,
          decoration: const BoxDecoration(
            color: _success,
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.check_rounded,
              size: size * 0.56, color: _surfaceWhite),
        );

      case _TLStatus.active:
        if (step.activeIcon != null) {
          // Custom icon for special active steps (e.g., awaiting approval)
          return Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: _gold.withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(color: _gold, width: 2),
            ),
            child: Icon(step.activeIcon,
                size: size * 0.50, color: _gold),
          );
        }
        // Standard pulsing ring indicator
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: _goldLight,
            shape: BoxShape.circle,
            border: Border.all(color: _gold, width: 2),
          ),
          child: Center(
            child: Container(
              width: size * 0.35,
              height: size * 0.35,
              decoration: const BoxDecoration(
                color: _gold,
                shape: BoxShape.circle,
              ),
            ),
          ),
        );

      case _TLStatus.pending:
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: _surfaceGrey,
            shape: BoxShape.circle,
            border: Border.all(color: _divider, width: 2),
          ),
        );
    }
  }
}

// ── Cost Card ─────────────────────────────────────────────────────────────────

class _CostCard extends ConsumerWidget {
  final ActiveJobData job;
  final double w;
  final double h;
  const _CostCard({required this.job, required this.w, required this.h});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expanded = ref.watch(activeJobActionProvider).costExpanded;
    final cost     = job.cost;

    return Container(
      margin: EdgeInsets.symmetric(horizontal: w * 0.041),
      decoration: BoxDecoration(
        color: _surfaceWhite,
        borderRadius: BorderRadius.circular(w * 0.031),
        border: Border.all(color: _divider),
      ),
      child: Column(
        children: [
          // ── Header (always visible, tappable) ──
          GestureDetector(
            onTap: () =>
                ref.read(activeJobActionProvider.notifier).toggleCost(),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: EdgeInsets.symmetric(
                  horizontal: w * 0.041, vertical: h * 0.017),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          cost.sectionTitle,
                          style: TextStyle(
                            fontSize: w * 0.038,
                            fontWeight: FontWeight.w700,
                            color: _textPrimary,
                          ),
                        ),
                        if (!cost.isFinalized) ...[
                          SizedBox(height: h * 0.003),
                          Text(
                            'Payment due after completion',
                            style: TextStyle(
                              fontSize: w * 0.028,
                              fontWeight: FontWeight.w400,
                              color: _textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(Icons.keyboard_arrow_down_rounded,
                        size: w * 0.056, color: _textSecondary),
                  ),
                ],
              ),
            ),
          ),
          // ── Expandable breakdown ──
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: EdgeInsets.only(
                left: w * 0.041,
                right: w * 0.041,
                bottom: h * 0.017,
              ),
              child: Column(
                children: [
                  const Divider(height: 1, color: _divider),
                  SizedBox(height: h * 0.014),
                  _CostRow(
                    label: 'Service Fee (Emergency)',
                    value: cost.serviceFeeDisplay,
                    w: w,
                    h: h,
                  ),
                  SizedBox(height: h * 0.010),
                  _CostRow(
                    label: 'Estimated Materials',
                    value: cost.materialsFeeDisplay,
                    w: w,
                    h: h,
                  ),
                  SizedBox(height: h * 0.012),
                  const Divider(height: 1, color: _divider),
                  SizedBox(height: h * 0.012),
                  _CostRow(
                    label: cost.totalLabel,
                    value: cost.totalDisplay,
                    isBold: true,
                    w: w,
                    h: h,
                  ),
                  if (!cost.isFinalized) ...[
                    SizedBox(height: h * 0.012),
                    Container(
                      padding: EdgeInsets.symmetric(
                          horizontal: w * 0.026,
                          vertical: h * 0.010),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3E8),
                        borderRadius:
                            BorderRadius.circular(w * 0.021),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline_rounded,
                              size: w * 0.033,
                              color: const Color(0xFFF2994A)),
                          SizedBox(width: w * 0.013),
                          Expanded(
                            child: Text(
                              'Final material costs may vary based on '
                              'market prices. Artisan will provide receipts.',
                              style: TextStyle(
                                fontSize: w * 0.026,
                                color: const Color(0xFFF2994A),
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            crossFadeState: expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }
}

class _CostRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isBold;
  final double w;
  final double h;
  const _CostRow({
    required this.label,
    required this.value,
    required this.w,
    required this.h,
    this.isBold = false,
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
              fontWeight: isBold ? FontWeight.w700 : FontWeight.w400,
              color: isBold ? _textPrimary : _textSecondary,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: w * 0.033,
            fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
            color: _textPrimary,
          ),
        ),
      ],
    );
  }
}

// ── Safety Card ───────────────────────────────────────────────────────────────

class _SafetyCard extends StatelessWidget {
  final double w;
  final double h;
  const _SafetyCard({required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: w * 0.041),
      padding: EdgeInsets.all(w * 0.041),
      decoration: BoxDecoration(
        color: _surfaceWhite,
        borderRadius: BorderRadius.circular(w * 0.031),
        border: Border.all(color: _divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.shield_outlined, size: w * 0.051, color: _success),
          SizedBox(width: w * 0.026),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Safety First',
                  style: TextStyle(
                    fontSize: w * 0.036,
                    fontWeight: FontWeight.w700,
                    color: _textPrimary,
                  ),
                ),
                SizedBox(height: h * 0.005),
                Text(
                  'For your protection, only pay through the app. All artisans '
                  'are background-verified and monitored via GPS.',
                  style: TextStyle(
                    fontSize: w * 0.028,
                    fontWeight: FontWeight.w400,
                    color: _textSecondary,
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

// ── Bottom Bar ────────────────────────────────────────────────────────────────

class _BottomBar extends ConsumerWidget {
  final ActiveJobData job;
  final double w;
  final double h;
  const _BottomBar({required this.job, required this.w, required this.h});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actionState = ref.watch(activeJobActionProvider);
    final bottomPad   = MediaQuery.paddingOf(context).bottom;
    final phase       = job.phase;

    return Container(
      decoration: const BoxDecoration(
        color: _surfaceWhite,
        border: Border(top: BorderSide(color: _divider)),
      ),
      padding: EdgeInsets.only(
        left: w * 0.041,
        right: w * 0.041,
        top: h * 0.014,
        bottom: bottomPad + h * 0.014,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Status / hint row ──
          Row(
            children: [
              if (phase == ActiveJobPhase.inProgress ||
                  phase == ActiveJobPhase.awaitingApproval)
                Icon(Icons.info_rounded,
                    size: w * 0.036, color: _gold)
              else
                Container(
                  width: w * 0.023,
                  height: w * 0.023,
                  decoration: BoxDecoration(
                    color: _gold,
                    shape: BoxShape.circle,
                  ),
                ),
              SizedBox(width: w * 0.018),
              Expanded(
                child: Text(
                  _statusHint(phase),
                  style: TextStyle(
                    fontSize: w * 0.028,
                    fontWeight: FontWeight.w500,
                    color: _textSecondary,
                  ),
                ),
              ),
              if (phase == ActiveJobPhase.enRoute ||
                  phase == ActiveJobPhase.arrived)
                GestureDetector(
                  onTap: () {}, // TODO: navigate to report issue screen
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: EdgeInsets.only(left: w * 0.026),
                    child: Text(
                      'Report Issue',
                      style: TextStyle(
                        fontSize: w * 0.028,
                        fontWeight: FontWeight.w500,
                        color: _textHint,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(height: h * 0.010),
          // ── Primary CTA ──
          SizedBox(
            width: double.infinity,
            height: h * 0.066,
            child: ElevatedButton(
              onPressed: actionState.isBusy
                  ? null
                  : _isCtaEnabled(phase)
                      ? () => _onCtaTap(ref, job)
                      : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: _ctaBgColor(phase, actionState),
                disabledBackgroundColor: _surfaceGrey,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(w * 0.031),
                ),
              ),
              child: _ctaChild(phase, actionState, w, h),
            ),
          ),
        ],
      ),
    );
  }

  String _statusHint(ActiveJobPhase phase) => switch (phase) {
        ActiveJobPhase.enRoute          => 'Waiting for Arrival...',
        ActiveJobPhase.arrived          => 'Artisan arrived',
        ActiveJobPhase.inProgress       =>
            'Confirm only when the technician has finished all listed tasks.',
        ActiveJobPhase.awaitingApproval =>
            'Confirm only when the technician has finished all listed tasks.',
      };

  bool _isCtaEnabled(ActiveJobPhase phase) => switch (phase) {
        ActiveJobPhase.enRoute    => false,
        ActiveJobPhase.arrived    => true,
        ActiveJobPhase.inProgress => false,
        ActiveJobPhase.awaitingApproval => true,
      };

  Color _ctaBgColor(ActiveJobPhase phase, ActiveJobActionState state) {
    if (state.isBusy) return _surfaceGrey;
    return _isCtaEnabled(phase) ? _darkSlate : _surfaceGrey;
  }

  void _onCtaTap(WidgetRef ref, ActiveJobData job) {
    final notifier = ref.read(activeJobActionProvider.notifier);
    if (job.phase == ActiveJobPhase.arrived) {
      notifier.confirmArrival(jobId: job.jobId);
    } else if (job.phase == ActiveJobPhase.awaitingApproval) {
      notifier.markComplete(jobId: job.jobId);
    }
  }

  Widget _ctaChild(ActiveJobPhase phase, ActiveJobActionState state,
      double w, double h) {
    final isEnabled = _isCtaEnabled(phase);
    final labelColor =
        (state.isBusy || !isEnabled) ? _disabled : _surfaceWhite;

    if (state.isConfirmingArrival || state.isMarkingComplete) {
      return SizedBox(
        width: w * 0.051,
        height: w * 0.051,
        child: const CircularProgressIndicator(
          strokeWidth: 2,
          color: _surfaceWhite,
        ),
      );
    }

    final label = (phase == ActiveJobPhase.enRoute ||
            phase == ActiveJobPhase.arrived)
        ? 'Confirm Arrival'
        : 'Mark Complete';

    return Text(
      label,
      style: TextStyle(
        fontSize: w * 0.038,
        fontWeight: FontWeight.w600,
        color: labelColor,
      ),
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
        Container(
          color: _surfaceWhite,
          padding: EdgeInsets.only(
            top: topPad + h * 0.010,
            bottom: h * 0.017,
            left: w * 0.041,
            right: w * 0.041,
          ),
          child: Row(children: [
            _Shimmer(w: w * 0.056, h: w * 0.056, r: w * 0.056),
            SizedBox(width: w * 0.031),
            _Shimmer(w: w * 0.41, h: h * 0.026),
            const Spacer(),
            _Shimmer(w: w * 0.092, h: w * 0.092, r: w * 0.092),
          ]),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
                horizontal: w * 0.041, vertical: h * 0.014),
            child: Column(
              children: [
                _Shimmer(w: double.infinity, h: h * 0.12, r: w * 0.031),
                SizedBox(height: h * 0.005),
                _Shimmer(w: double.infinity, h: h * 0.07, r: w * 0.031),
                SizedBox(height: h * 0.005),
                _Shimmer(w: double.infinity, h: h * 0.17, r: w * 0.031),
                SizedBox(height: h * 0.010),
                _Shimmer(w: double.infinity, h: h * 0.054, r: w * 0.021),
                SizedBox(height: h * 0.019),
                _Shimmer(w: double.infinity, h: h * 0.40, r: w * 0.031),
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
        color: const Color(0xFFE0E0E0),
        borderRadius: BorderRadius.circular(r),
      ),
    );
  }
}

// ── Error Body ────────────────────────────────────────────────────────────────

class _ErrorBody extends StatelessWidget {
  final double w;
  final double h;
  final VoidCallback onRetry;
  const _ErrorBody(
      {required this.w, required this.h, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: w * 0.082),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline_rounded,
                size: w * 0.154, color: _textHint),
            SizedBox(height: h * 0.019),
            Text(
              'Could not load job details',
              style: TextStyle(
                fontSize: w * 0.041,
                fontWeight: FontWeight.w700,
                color: _textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: h * 0.009),
            Text(
              'Check your connection and try again.',
              style: TextStyle(
                  fontSize: w * 0.033, color: _textSecondary),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: h * 0.028),
            GestureDetector(
              onTap: onRetry,
              child: Container(
                padding: EdgeInsets.symmetric(
                    horizontal: w * 0.077, vertical: h * 0.017),
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
