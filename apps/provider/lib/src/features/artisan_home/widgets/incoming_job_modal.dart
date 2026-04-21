import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

/// Slide-up modal that pops when a new `job:new` event arrives — shows a
/// condensed preview so the artisan can decide at a glance whether to open
/// the full bid screen.
///
/// Minimal surface on purpose: the full [JobRequestScreen] is one tap away
/// via the "View Details" CTA. Dismiss simply closes the sheet — the job
/// stays in the backend and can still be opened from the jobs list later.
class IncomingJobModal extends StatelessWidget {
  const IncomingJobModal({
    super.key,
    required this.job,
    this.distanceKm,
  });

  final Job job;
  final double? distanceKm;

  static Future<void> show(
    BuildContext context, {
    required Job job,
    double? distanceKm,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      isDismissible: true,
      enableDrag: true,
      builder: (_) => IncomingJobModal(job: job, distanceKm: distanceKm),
    );
  }

  String get _title => job.categoryName != null && job.categoryName!.isNotEmpty
      ? '${job.categoryName} request'
      : 'Service Request';
  String get _clientName => job.clientName ?? 'Client';
  String get _address => job.addressText ?? 'Location pending';

  void _viewDetails(BuildContext context) {
    Navigator.of(context).pop();
    context.push('/job-request', extra: job);
  }

  @override
  Widget build(BuildContext context) {
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
                  'NEW JOB REQUEST',
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
                            distanceKm != null
                                ? '$_address  •  ${distanceKm!.toStringAsFixed(1)} km'
                                : _address,
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
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Dismiss',
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
