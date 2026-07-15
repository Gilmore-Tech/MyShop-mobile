import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:shared_utils/shared_utils.dart';

import '../../../core/services/local_notification_service.dart';
import '../../../core/services/incoming_request_overlay_presenter.dart';
import '../../../core/di/providers.dart';
import '../../artisan_jobs/providers/pending_incoming_jobs_provider.dart';

/// Safety fallback for legacy socket payloads that predate `expiresAt`.
/// Current backend payloads always carry an absolute deadline.
const Duration _kIncomingJobFallbackTimeout = Duration(seconds: 45);

/// Slide-up modal that pops when a new `job:new` event arrives — shows a
/// condensed preview so the artisan can decide at a glance whether to open
/// the full bid screen.
///
/// Minimal surface on purpose: the full [JobRequestScreen] is one tap away
/// via the "View Details" CTA. Dismiss simply closes the sheet — the job
/// stays in the backend and can still be opened from the jobs list later.
class IncomingJobModal extends ConsumerStatefulWidget {
  const IncomingJobModal({
    super.key,
    required this.job,
    this.distanceKm,
    this.etaMinutes,
  });

  final Job job;
  final double? distanceKm;

  /// Straight-line ETA from the artisan's last GPS fix to the job
  /// location, in whole minutes. Computed by the caller (the incoming
  /// request listener) so the modal doesn't need a Riverpod scope.
  final int? etaMinutes;

  static Future<void> show(
    BuildContext context, {
    required Job job,
    double? distanceKm,
    int? etaMinutes,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      // Render on the root navigator so the sheet stays on top even when the
      // artisan has pushed a full-screen route (job request, account edit,
      // earnings reports, etc.) above the shell.
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      isDismissible: true,
      enableDrag: true,
      builder: (_) => IncomingJobModal(
        job: job,
        distanceKm: distanceKm,
        etaMinutes: etaMinutes,
      ),
    );
  }

  @override
  ConsumerState<IncomingJobModal> createState() => _IncomingJobModalState();
}

class _IncomingJobModalState extends ConsumerState<IncomingJobModal> {
  Timer? _autoDismissTimer;
  Timer? _countdownTicker;
  late Duration _remaining;
  bool _skipping = false;

  @override
  void initState() {
    super.initState();
    final deadline = DateTime.tryParse(widget.job.expiresAt ?? '')?.toUtc();
    _remaining = deadline == null
        ? _kIncomingJobFallbackTimeout
        : deadline.difference(DateTime.now().toUtc());
    if (_remaining <= Duration.zero) {
      _remaining = Duration.zero;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
      return;
    }
    // Start the looping ringtone the moment the modal mounts. The
    // [LocalNotificationService] is a singleton so the ride flow shares
    // the same timer — both call sites are no-ops when one is already
    // ringing, which is fine because we never have a job and ride
    // request open at the same time.
    LocalNotificationService.instance.startIncomingRingtone();
    // Auto-dismiss at the server-authored deadline so a buried phone never
    // keeps ringing after the backend bid window has closed.
    _autoDismissTimer = Timer(_remaining, () {
      if (!mounted) return;
      Navigator.of(context).maybePop();
    });
    _countdownTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final next = deadline == null
          ? _remaining - const Duration(seconds: 1)
          : deadline.difference(DateTime.now().toUtc());
      setState(() {
        _remaining = next > Duration.zero ? next : Duration.zero;
      });
    });
  }

  @override
  void dispose() {
    // Both paths off this modal — accept, dismiss, swipe-down, OR the
    // auto-dismiss timer above — converge on dispose, so this is the
    // single place we silence the ring + cancel the timer. Without
    // this, the ringtone would keep firing from the singleton even
    // after the sheet was gone.
    _autoDismissTimer?.cancel();
    _countdownTicker?.cancel();
    LocalNotificationService.instance.stopIncomingRingtone();
    super.dispose();
  }

  String get _title =>
      widget.job.categoryName != null && widget.job.categoryName!.isNotEmpty
          ? '${widget.job.categoryName} request'
          : 'Service Request';
  String get _clientName => widget.job.clientName ?? 'Client';
  String get _address => widget.job.addressText ?? 'Location pending';

  String get _countdownLabel {
    final totalSeconds = _remaining.inSeconds.clamp(0, 99 * 60 + 59);
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  /// Address with optional distance + ETA suffix, e.g.
  /// "12 Maple St  •  3.2 km · ~7 min away".
  String get _locationLine {
    final parts = <String>[_address];
    final distanceKm = widget.distanceKm;
    final etaMinutes = widget.etaMinutes;
    if (distanceKm != null) {
      final tail = StringBuffer('${distanceKm.toStringAsFixed(1)} km');
      if (etaMinutes != null && etaMinutes > 0) {
        tail.write(' · ~${formatEtaLabel(etaMinutes)} away');
      }
      parts.add(tail.toString());
    }
    return parts.join('  •  ');
  }

  void _viewDetails(BuildContext context) {
    Navigator.of(context).pop();
    context.push('/job-request', extra: widget.job);
  }

  Future<void> _skip() async {
    if (_skipping) return;
    setState(() => _skipping = true);
    try {
      await ref.read(jobServiceProvider).declineJobRequest(
            widget.job.id,
            reason: 'provider_skipped',
          );
      ref.read(pendingIncomingJobsProvider.notifier).remove(widget.job.id);
      await clearIncomingRequestAlert(
        type: NotificationPayload.typeJobRequest,
        requestId: widget.job.id,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _skipping = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Could not skip this request. Try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final job = widget.job;
    return Container(
      decoration: const BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(
        MyShopSpacing.md,
        MyShopSpacing.sm,
        MyShopSpacing.md,
        MyShopSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 48,
              height: 5,
              margin: const EdgeInsets.only(bottom: MyShopSpacing.md),
              decoration: BoxDecoration(
                color: MyShopColors.divider,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),

          // Urgency banner
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 8,
            ),
            decoration: BoxDecoration(
              color: MyShopColors.error,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.notifications_active,
                  color: Colors.white,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  'NEW JOB REQUEST  ·  $_countdownLabel',
                  style: MyShopTypography.overline.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                    letterSpacing: 1.0,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: MyShopSpacing.md),

          // Title
          Text(
            _title,
            style: MyShopTypography.h2.copyWith(
              fontWeight: FontWeight.w800,
              fontSize: 20,
            ),
          ),
          const SizedBox(height: MyShopSpacing.sm),

          // Client row
          Row(
            children: [
              _Avatar(url: job.clientPhotoUrl),
              const SizedBox(width: MyShopSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _clientName,
                      style: MyShopTypography.h3.copyWith(fontSize: 15),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(
                          Icons.location_on,
                          size: 13,
                          color: MyShopColors.primaryGold,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            _locationLine,
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
            ],
          ),
          const SizedBox(height: MyShopSpacing.md),

          // Description preview
          if (job.description.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(MyShopSpacing.md),
              decoration: BoxDecoration(
                color: MyShopColors.offWhite,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                job.description,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: MyShopTypography.body1.copyWith(height: 1.4),
              ),
            ),

          // Meta chips
          if (job.photos.isNotEmpty) ...[
            const SizedBox(height: MyShopSpacing.sm),
            Row(
              children: [
                _MetaChip(
                  icon: Icons.photo_library_outlined,
                  label: '${job.photos.length} photo'
                      '${job.photos.length == 1 ? '' : 's'}',
                ),
                if (job.artisansNotified != null &&
                    job.artisansNotified! > 0) ...[
                  const SizedBox(width: MyShopSpacing.sm),
                  _MetaChip(
                    icon: Icons.group_outlined,
                    label: '${job.artisansNotified} artisans notified',
                    color: MyShopColors.primaryGold,
                  ),
                ],
              ],
            ),
          ],

          const SizedBox(height: MyShopSpacing.lg),

          // View details button
          _PrimaryButton(
            label: 'VIEW DETAILS',
            onTap: () => _viewDetails(context),
          ),
          const SizedBox(height: MyShopSpacing.sm),

          // Dismiss
          Center(
            child: TextButton(
              onPressed: _skipping ? null : _skip,
              child: Text(
                _skipping ? 'Skipping…' : 'Skip / Ignore',
                style: MyShopTypography.body1.copyWith(
                  color: MyShopColors.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    if (url != null && url!.isNotEmpty) {
      return ClipOval(
        child: CachedNetworkImage(
          imageUrl: url!,
          width: 44,
          height: 44,
          fit: BoxFit.cover,
          memCacheWidth: 132,
          memCacheHeight: 132,
          placeholder: (_, __) => _placeholder(),
          errorWidget: (_, __, ___) => _placeholder(),
        ),
      );
    }
    return _placeholder();
  }

  Widget _placeholder() => Container(
        width: 44,
        height: 44,
        decoration: const BoxDecoration(
          color: MyShopColors.avatarPlaceholder,
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.person,
          color: MyShopColors.textSecondary,
          size: 22,
        ),
      );
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({
    required this.icon,
    required this.label,
    this.color,
  });

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? MyShopColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: MyShopColors.surfaceGrey,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: c),
          const SizedBox(width: 5),
          Text(
            label,
            style: MyShopTypography.body2.copyWith(
              color: c,
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.label, required this.onTap});

  final String label;
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
          label,
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
