import 'package:flutter/material.dart';
import 'package:shared_models/shared_models.dart' show ChatBookingType;
import 'package:shared_ui/shared_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../providers/active_job_provider.dart';
import '../widgets/job_tracking_map.dart';

/// PRD § 4.6 — Live artisan tracking while en route to job site.
///
/// Map + bottom sheet showing the assigned artisan, ETA, and job address.
/// Data comes from `GET /jobs/:id` via [activeJobProvider]; the live status
/// flips when the backend pushes `job:status:changed` over the socket
/// (handled in `core/providers/socket_provider.dart`, which invalidates
/// this provider — the screen re-fetches and the bottom sheet refreshes).
///
/// Live artisan GPS isn't surfaced here yet — see comment in
/// [JobTrackingMap].
class JobTrackingScreen extends ConsumerWidget {
  const JobTrackingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final size = MediaQuery.sizeOf(context);
    final w = size.width;
    final h = size.height;
    final bot = MediaQuery.paddingOf(context).bottom;
    final jobId = GoRouterState.of(context).pathParameters['jobId'] ?? '';

    final jobAsync = ref.watch(activeJobProvider(jobId));

    return Scaffold(
      backgroundColor: MyShopColors.offWhite,
      body: jobAsync.when(
        loading: () => _LoadingState(
          h: h,
          w: w,
          bot: bot,
          onBack: () => context.pop(),
        ),
        error: (err, _) => _ErrorState(
          message: _friendlyError(err),
          onRetry: () => ref.invalidate(activeJobProvider(jobId)),
          onBack: () => context.pop(),
        ),
        data: (job) => Stack(
          children: [
            JobTrackingMap(
              jobId: jobId,
              jobLat: job.locationLat,
              jobLng: job.locationLng,
            ),
            _TopBar(w: w, onBack: () => context.pop()),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _BottomSheet(
                w: w,
                h: h,
                bot: bot,
                job: job,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _friendlyError(Object err) {
    final msg = err.toString();
    if (msg.contains('404')) {
      return "We couldn't find this job. It may have been removed.";
    }
    return "We couldn't load the job details. Check your connection and try again.";
  }
}

// ── Loading skeleton ──────────────────────────────────────────────────────────

class _LoadingState extends StatelessWidget {
  final double h, w, bot;
  final VoidCallback onBack;
  const _LoadingState(
      {required this.h,
      required this.w,
      required this.bot,
      required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(color: const Color(0xFFE8EDF0)),
        _TopBar(w: w, onBack: onBack),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            decoration: const BoxDecoration(
              color: MyShopColors.surfaceWhite,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            padding: EdgeInsets.fromLTRB(
                w * 0.05, h * 0.020, w * 0.05, bot + h * 0.024),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _shimmerBar(width: w * 0.5, height: 14),
                SizedBox(height: h * 0.022),
                Row(
                  children: [
                    CircleAvatar(
                      radius: w * 0.065,
                      backgroundColor: MyShopColors.surfaceGrey,
                    ),
                    SizedBox(width: w * 0.030),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _shimmerBar(width: w * 0.45, height: 14),
                          const SizedBox(height: 6),
                          _shimmerBar(width: w * 0.30, height: 12),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: h * 0.016),
                _shimmerBar(width: double.infinity, height: 12),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _shimmerBar({required double width, required double height}) =>
      Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: MyShopColors.surfaceGrey,
          borderRadius: BorderRadius.circular(6),
        ),
      );
}

// ── Error state ───────────────────────────────────────────────────────────────

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final VoidCallback onBack;
  const _ErrorState({
    required this.message,
    required this.onRetry,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(color: MyShopColors.offWhite),
        _TopBar(w: MediaQuery.sizeOf(context).width, onBack: onBack),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline_rounded,
                    color: MyShopColors.error, size: 48),
                const SizedBox(height: 12),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    color: MyShopColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: onRetry,
                  child: const Text(
                    'Retry',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: MyShopColors.primaryGold,
                    ),
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

// ── Top bar ────────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final double w;
  final VoidCallback onBack;
  const _TopBar({required this.w, required this.onBack});

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Positioned(
      top: top + 8,
      left: 16,
      right: 16,
      child: Row(
        children: [
          _CircleBtn(icon: Icons.arrow_back, onTap: onBack),
        ],
      ),
    );
  }
}

class _CircleBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CircleBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: MyShopColors.surfaceWhite,
      shape: const CircleBorder(),
      elevation: 4,
      shadowColor: Colors.black26,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: MyShopColors.textPrimary, size: 20),
        ),
      ),
    );
  }
}

// ── Bottom sheet ───────────────────────────────────────────────────────────────

class _BottomSheet extends StatelessWidget {
  final double w, h, bot;
  final ActiveJobData job;
  const _BottomSheet({
    required this.w,
    required this.h,
    required this.bot,
    required this.job,
  });

  @override
  Widget build(BuildContext context) {
    final etaLabel = job.etaLabel ?? job.completionLabel ?? '—';
    final showEtaPill =
        job.phase == ActiveJobPhase.enRoute && job.etaLabel != null;
    // Show the live "Time on job" pill the moment the artisan starts
    // work and through to completion. Uses the backend's `startedAt`
    // timestamp so the client and provider are reading the same clock.
    // Hidden until `startedAt` lands — the early phases (en route /
    // arrived) keep the ETA pill above instead.
    final showElapsedPill = job.startedAt != null &&
        (job.phase == ActiveJobPhase.inProgress ||
            job.phase == ActiveJobPhase.arrived ||
            job.phase == ActiveJobPhase.awaitingApproval ||
            job.phase == ActiveJobPhase.pendingPayment ||
            job.phase == ActiveJobPhase.completed);
    return Container(
      decoration: const BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
              color: Colors.black12, blurRadius: 16, offset: Offset(0, -4)),
        ],
      ),
      padding:
          EdgeInsets.fromLTRB(w * 0.05, h * 0.020, w * 0.05, bot + h * 0.024),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: w * 0.10,
            height: 4,
            decoration: BoxDecoration(
              color: MyShopColors.surfaceGrey,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          SizedBox(height: h * 0.020),
          if (showEtaPill) ...[
            Container(
              padding: EdgeInsets.symmetric(
                  horizontal: w * 0.040, vertical: h * 0.014),
              decoration: BoxDecoration(
                color: MyShopColors.primaryGoldLight,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: MyShopColors.primaryGold.withAlpha(60)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.timer_outlined,
                      color: MyShopColors.primaryGold, size: 20),
                  SizedBox(width: w * 0.024),
                  Text('Artisan arriving in  ',
                      style: TextStyle(
                          color: MyShopColors.textSecondary,
                          fontSize: w * 0.036)),
                  Text(etaLabel,
                      style: TextStyle(
                        color: MyShopColors.textPrimary,
                        fontSize: w * 0.040,
                        fontWeight: FontWeight.w800,
                      )),
                ],
              ),
            ),
            SizedBox(height: h * 0.020),
            const Divider(height: 1, color: MyShopColors.divider),
            SizedBox(height: h * 0.020),
          ] else if (showElapsedPill) ...[
            // Live on-the-job duration. Once the artisan has marked the
            // job complete, [completedAt] freezes the pill at the final
            // duration and switches the label so the client sees how
            // long the work took.
            JobElapsedTime(
              startedAt: job.startedAt,
              endedAt: job.completedAt,
              label: job.completedAt != null
                  ? 'Final duration'
                  : 'Time on job',
            ),
            SizedBox(height: h * 0.020),
            const Divider(height: 1, color: MyShopColors.divider),
            SizedBox(height: h * 0.020),
          ],
          Row(
            children: [
              _ArtisanAvatar(w: w, artisan: job.artisan),
              SizedBox(width: w * 0.030),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(job.artisan.name,
                        style: TextStyle(
                          color: MyShopColors.textPrimary,
                          fontSize: w * 0.040,
                          fontWeight: FontWeight.w700,
                        )),
                    if (job.artisan.specialty.isNotEmpty ||
                        job.artisan.rating > 0) ...[
                      const SizedBox(height: 3),
                      Row(children: [
                        if (job.artisan.rating > 0) ...[
                          const Icon(Icons.star_rounded,
                              color: MyShopColors.primaryGold, size: 14),
                          const SizedBox(width: 3),
                          Text(job.artisan.rating.toStringAsFixed(1),
                              style: TextStyle(
                                  color: MyShopColors.textSecondary,
                                  fontSize: w * 0.032)),
                        ],
                        if (job.artisan.specialty.isNotEmpty) ...[
                          if (job.artisan.rating > 0)
                            Text('  •  ',
                                style: TextStyle(
                                    color: MyShopColors.textSecondary,
                                    fontSize: w * 0.032)),
                          Flexible(
                            child: Text(
                              job.artisan.specialty,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: MyShopColors.textSecondary,
                                  fontSize: w * 0.032),
                            ),
                          ),
                        ],
                      ]),
                    ],
                  ],
                ),
              ),
              // Phone _ContactBtn removed in v1.0 — masked calls deferred
              // to v1.2. Only the chat tile remains as the peer comms channel.
              _ContactBtn(
                icon: Icons.chat_bubble_outline_rounded,
                color: MyShopColors.primaryGold,
                onTap: () => context.push(
                  AppRoutes.chat,
                  extra: <String, Object?>{
                    'bookingType': ChatBookingType.artisanJob,
                    'bookingId': job.jobId,
                    'peerName': job.artisan.name,
                    'peerStatus': 'On your job',
                  },
                ),
                w: w,
              ),
            ],
          ),
          if (job.location.isNotEmpty) ...[
            SizedBox(height: h * 0.016),
            Row(
              children: [
                const Icon(Icons.location_on_rounded,
                    color: MyShopColors.textSecondary, size: 16),
                SizedBox(width: w * 0.016),
                Expanded(
                  child: Text(job.location,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: MyShopColors.textSecondary,
                          fontSize: w * 0.034)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ArtisanAvatar extends StatelessWidget {
  final double w;
  final ActiveJobArtisan artisan;
  const _ArtisanAvatar({required this.w, required this.artisan});

  @override
  Widget build(BuildContext context) {
    final size = w * 0.13;
    if (artisan.photoUrl.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          artisan.photoUrl,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _initialsAvatar(size),
        ),
      );
    }
    return _initialsAvatar(size);
  }

  Widget _initialsAvatar(double size) {
    final initial = artisan.firstName.isNotEmpty
        ? artisan.firstName.substring(0, 1).toUpperCase()
        : '?';
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: artisan.avatarColor,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.45,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ContactBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final double w;

  const _ContactBtn({
    required this.icon,
    required this.color,
    required this.onTap,
    required this.w,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withAlpha(20),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(w * 0.028),
          child: Icon(icon, color: color, size: w * 0.050),
        ),
      ),
    );
  }
}
