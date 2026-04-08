import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

/// High-priority emergency job request shown as a barrier dialog over the
/// artisan home. Auto-dismisses when the countdown reaches zero.
///
/// PRD Reference: PRD 5.3 — high-priority artisan job dispatch.
class EmergencyRequestModal extends StatefulWidget {
  const EmergencyRequestModal({
    super.key,
    required this.clientName,
    required this.clientRating,
    required this.jobTitle,
    required this.locationLabel,
    required this.distanceKm,
    required this.countdown,
    this.isKycVerified = true,
    this.avatarUrl,
    this.onQuickBid,
    this.onViewDetails,
    this.onExpire,
  });

  final String clientName;
  final double clientRating;
  final String jobTitle;
  final String locationLabel;
  final double distanceKm;
  final Duration countdown;
  final bool isKycVerified;
  final String? avatarUrl;
  final VoidCallback? onQuickBid;
  final VoidCallback? onViewDetails;
  final VoidCallback? onExpire;

  /// Convenience launcher — pushes the modal as a non-dismissible dialog and
  /// renders the red "IMMEDIATE ACTION REQUIRED!" pill above it.
  static Future<void> show(
    BuildContext context, {
    required String clientName,
    required double clientRating,
    required String jobTitle,
    required String locationLabel,
    required double distanceKm,
    Duration countdown = const Duration(minutes: 5),
    bool isKycVerified = true,
    String? avatarUrl,
    VoidCallback? onQuickBid,
    VoidCallback? onViewDetails,
  }) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Emergency request',
      barrierColor: Colors.black.withValues(alpha: 0.55),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (ctx, _, __) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: MyShopSpacing.md),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Floating red action banner
                _ImmediateActionBanner(
                  onTap: () => Navigator.of(ctx).maybePop(),
                ),
                const SizedBox(height: MyShopSpacing.md),

                // Modal card
                EmergencyRequestModal(
                  clientName: clientName,
                  clientRating: clientRating,
                  jobTitle: jobTitle,
                  locationLabel: locationLabel,
                  distanceKm: distanceKm,
                  countdown: countdown,
                  isKycVerified: isKycVerified,
                  avatarUrl: avatarUrl,
                  onQuickBid: () {
                    Navigator.of(ctx).pop();
                    onQuickBid?.call();
                  },
                  onViewDetails: () {
                    Navigator.of(ctx).pop();
                    onViewDetails?.call();
                  },
                  onExpire: () {
                    if (Navigator.of(ctx).canPop()) Navigator.of(ctx).pop();
                  },
                ),
              ],
            ),
          ),
        );
      },
      transitionBuilder: (_, anim, __, child) {
        return FadeTransition(
          opacity: anim,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1).animate(
              CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
            ),
            child: child,
          ),
        );
      },
    );
  }

  @override
  State<EmergencyRequestModal> createState() => _EmergencyRequestModalState();
}

class _EmergencyRequestModalState extends State<EmergencyRequestModal> {
  late Duration _remaining;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _remaining = widget.countdown;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() {
        _remaining -= const Duration(seconds: 1);
      });
      if (_remaining.inSeconds <= 0) {
        t.cancel();
        widget.onExpire?.call();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _countdownLabel {
    final m = _remaining.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = _remaining.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(MyShopSpacing.md),
        decoration: BoxDecoration(
          color: MyShopColors.darkSlate,
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [
            BoxShadow(
              color: Color(0x40000000),
              blurRadius: 30,
              offset: Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header row: priority + countdown ──
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(
                    color: MyShopColors.error,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.priority_high,
                    color: MyShopColors.textOnPrimary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: MyShopSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'NEW HIGH PRIORITY',
                        style: MyShopTypography.overline.copyWith(
                          color: MyShopColors.textOnDarkSlate
                              .withValues(alpha: 0.7),
                          fontWeight: FontWeight.w700,
                          fontSize: 10,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'EMERGENCY REQUEST',
                        style: MyShopTypography.h3.copyWith(
                          color: MyShopColors.textOnDarkSlate,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: MyShopColors.darkSlate,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: MyShopColors.primaryGold,
                      width: 1.2,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.access_time,
                        size: 14,
                        color: MyShopColors.primaryGold,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _countdownLabel,
                        style: MyShopTypography.body1.copyWith(
                          color: MyShopColors.primaryGold,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: MyShopSpacing.md),

            // ── Inner client card ──
            Container(
              padding: const EdgeInsets.all(MyShopSpacing.md),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.12),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Avatar
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: MyShopColors.avatarPlaceholder,
                          shape: BoxShape.circle,
                          image: widget.avatarUrl != null
                              ? DecorationImage(
                                  image: NetworkImage(widget.avatarUrl!),
                                  fit: BoxFit.cover,
                                )
                              : null,
                        ),
                        child: widget.avatarUrl == null
                            ? const Icon(Icons.person,
                                color: MyShopColors.textSecondary, size: 28)
                            : null,
                      ),
                      const SizedBox(width: MyShopSpacing.sm),

                      // Name + title + location
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    widget.clientName,
                                    style: MyShopTypography.body1.copyWith(
                                      color: MyShopColors.textOnDarkSlate,
                                      fontSize: 15,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        widget.clientRating.toStringAsFixed(1),
                                        style: MyShopTypography.body2.copyWith(
                                          color: MyShopColors.textOnDarkSlate,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(width: 3),
                                      const Icon(
                                        Icons.star,
                                        size: 12,
                                        color: MyShopColors.ratingStar,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              widget.jobTitle,
                              style: MyShopTypography.h3.copyWith(
                                color: MyShopColors.textOnDarkSlate,
                                fontSize: 17,
                                height: 1.3,
                              ),
                            ),
                            const SizedBox(height: 6),
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
                                    '${widget.locationLabel}  •  ${widget.distanceKm.toStringAsFixed(1)} km away',
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
                  Divider(
                    height: 1,
                    color: Colors.white.withValues(alpha: 0.12),
                  ),
                  const SizedBox(height: MyShopSpacing.sm),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.verified,
                            size: 12,
                            color: MyShopColors.info,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            widget.isKycVerified
                                ? 'KYC Verified'
                                : 'Not Verified',
                            style: MyShopTypography.body2.copyWith(
                              color: MyShopColors.textOnDarkSlate,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: MyShopSpacing.md),

            // ── Action buttons ──
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: widget.onQuickBid,
                    child: Container(
                      height: 52,
                      decoration: BoxDecoration(
                        color: MyShopColors.primaryGold,
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: [
                          BoxShadow(
                            color:
                                MyShopColors.primaryGold.withValues(alpha: 0.4),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        'QUICK BID',
                        style: MyShopTypography.button.copyWith(
                          color: MyShopColors.textPrimary,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: MyShopSpacing.sm),
                Expanded(
                  child: GestureDetector(
                    onTap: widget.onViewDetails,
                    child: Container(
                      height: 52,
                      decoration: BoxDecoration(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color: MyShopColors.textOnDarkSlate
                              .withValues(alpha: 0.6),
                          width: 1.4,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        'VIEW DETAILS',
                        style: MyShopTypography.button.copyWith(
                          color: MyShopColors.textOnDarkSlate,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
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

/// Red "IMMEDIATE ACTION REQUIRED!" pill banner that hovers above the modal.
class _ImmediateActionBanner extends StatelessWidget {
  const _ImmediateActionBanner({this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: MyShopSpacing.md,
            vertical: 14,
          ),
          decoration: BoxDecoration(
            color: MyShopColors.error,
            borderRadius: BorderRadius.circular(32),
            boxShadow: [
              BoxShadow(
                color: MyShopColors.error.withValues(alpha: 0.45),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.priority_high,
                  size: 14,
                  color: MyShopColors.textOnPrimary,
                ),
              ),
              const SizedBox(width: MyShopSpacing.sm),
              Text(
                'IMMEDIATE ACTION REQUIRED!',
                style: MyShopTypography.button.copyWith(
                  color: MyShopColors.textOnPrimary,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
