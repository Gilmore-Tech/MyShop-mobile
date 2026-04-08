import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

/// State of the artisan's bid for the current job request.
enum BidStatus {
  /// No bid placed yet — show the live "spots taken" + Place Bid CTA.
  none,

  /// Bid submitted, awaiting client decision (countdown visible).
  pending,

  /// Client accepted the bid — artisan can start the job.
  accepted,

  /// Client picked another artisan.
  notSelected,
}

/// Top-of-screen banner that adapts to the [BidStatus]:
///   - pending     → cream/orange card with countdown + Edit / Withdraw / Message
///   - accepted    → green card with "Accept & Start Job" + Message
///   - notSelected → grey card with "Not Selected" pill + helper paragraph
class BidStatusBanner extends StatefulWidget {
  const BidStatusBanner({
    super.key,
    required this.status,
    this.countdown = const Duration(minutes: 5),
    this.onEdit,
    this.onWithdraw,
    this.onMessage,
    this.onAcceptStartJob,
  });

  final BidStatus status;
  final Duration countdown;
  final VoidCallback? onEdit;
  final VoidCallback? onWithdraw;
  final VoidCallback? onMessage;
  final VoidCallback? onAcceptStartJob;

  @override
  State<BidStatusBanner> createState() => _BidStatusBannerState();
}

class _BidStatusBannerState extends State<BidStatusBanner> {
  late Duration _remaining;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _remaining = widget.countdown;
    if (widget.status == BidStatus.pending) {
      _timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) return;
        if (_remaining.inSeconds <= 0) {
          t.cancel();
          return;
        }
        setState(() => _remaining -= const Duration(seconds: 1));
      });
    }
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
    switch (widget.status) {
      case BidStatus.pending:
        return _buildPending();
      case BidStatus.accepted:
        return _buildAccepted();
      case BidStatus.notSelected:
        return _buildNotSelected();
      case BidStatus.none:
        return const SizedBox.shrink();
    }
  }

  // ── Pending ──
  Widget _buildPending() {
    return Container(
      padding: const EdgeInsets.all(MyShopSpacing.md),
      decoration: BoxDecoration(
        color: MyShopColors.warningLight,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: MyShopColors.warning,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: MyShopSpacing.sm),
              Expanded(
                child: Text(
                  'Bid pending — waiting',
                  style: MyShopTypography.h3.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: MyShopColors.surfaceWhite,
                  borderRadius: BorderRadius.circular(20),
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
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: MyShopSpacing.sm),
          Text(
            'The client is currently reviewing all submitted bids. You will be notified instantly if your bid is selected or if further details are needed.',
            style: MyShopTypography.body2.copyWith(
              color: MyShopColors.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: MyShopSpacing.md),
          Row(
            children: [
              Expanded(
                child: _PendingActionTile(
                  icon: Icons.edit_outlined,
                  label: 'Edit Bid',
                  iconColor: MyShopColors.textPrimary,
                  background: MyShopColors.surfaceWhite,
                  onTap: widget.onEdit,
                ),
              ),
              const SizedBox(width: MyShopSpacing.sm),
              Expanded(
                child: _PendingActionTile(
                  icon: Icons.delete_outline,
                  label: 'Withdraw',
                  iconColor: MyShopColors.error,
                  background: MyShopColors.surfaceWhite,
                  onTap: widget.onWithdraw,
                ),
              ),
              const SizedBox(width: MyShopSpacing.sm),
              Expanded(
                child: _PendingActionTile(
                  icon: Icons.chat_bubble_outline,
                  label: 'Message',
                  iconColor: MyShopColors.textOnDarkSlate,
                  labelColor: MyShopColors.textOnDarkSlate,
                  background: MyShopColors.darkSlate,
                  onTap: widget.onMessage,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Accepted ──
  Widget _buildAccepted() {
    return Container(
      padding: const EdgeInsets.all(MyShopSpacing.md),
      decoration: BoxDecoration(
        color: MyShopColors.successLight,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: MyShopColors.warning,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: MyShopSpacing.sm),
              Text(
                'Bid accepted',
                style: MyShopTypography.h3.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: MyShopSpacing.sm),
          Text(
            'The client is currently reviewing all submitted bids. You will be notified instantly if your bid is selected or if further details are needed.',
            style: MyShopTypography.body2.copyWith(
              color: MyShopColors.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: MyShopSpacing.md),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: widget.onAcceptStartJob,
                  child: Container(
                    height: 52,
                    decoration: BoxDecoration(
                      color: MyShopColors.darkSlate,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.check_circle_outline,
                          color: MyShopColors.textOnDarkSlate,
                          size: 20,
                        ),
                        const SizedBox(width: MyShopSpacing.sm),
                        Text(
                          'Accept & Start Job',
                          style: MyShopTypography.button.copyWith(
                            color: MyShopColors.textOnDarkSlate,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: MyShopSpacing.sm),
              GestureDetector(
                onTap: widget.onMessage,
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: MyShopColors.surfaceWhite,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.chat_bubble_outline,
                    color: MyShopColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Not selected ──
  Widget _buildNotSelected() {
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
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: MyShopColors.surfaceGrey,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.priority_high,
                  size: 16,
                  color: MyShopColors.textSecondary,
                ),
              ),
              const SizedBox(width: MyShopSpacing.sm),
              Expanded(
                child: Text(
                  'Bid Status',
                  style: MyShopTypography.h3.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: MyShopColors.surfaceWhite,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: MyShopColors.divider),
                ),
                child: Text(
                  'Not Selected',
                  style: MyShopTypography.body2.copyWith(
                    color: MyShopColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: MyShopSpacing.md),
          Text(
            'The client has chosen another artisan for this request.',
            style: MyShopTypography.h3.copyWith(
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: MyShopSpacing.sm),
          Text(
            "Don't worry! Your profile is still visible for other tasks. You can send a revised bid if the client re-opens the request or message them for feedback.",
            style: MyShopTypography.body2.copyWith(height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _PendingActionTile extends StatelessWidget {
  const _PendingActionTile({
    required this.icon,
    required this.label,
    required this.iconColor,
    required this.background,
    this.labelColor,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final Color iconColor;
  final Color background;
  final Color? labelColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: MyShopSpacing.sm + 2),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: iconColor),
            const SizedBox(height: 4),
            Text(
              label,
              style: MyShopTypography.body2.copyWith(
                color: labelColor ?? MyShopColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
