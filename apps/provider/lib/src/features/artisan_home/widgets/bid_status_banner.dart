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

  /// Job finished and the client's payment settled. Banner shows a
  /// "Completed" success card — no CTA, earnings live under /earnings.
  completed,

  /// Client kicked off the Paystack escrow charge, webhook hasn't settled
  /// yet. Banner is informational: "Client is paying — earnings release
  /// automatically once the charge clears."
  awaitingPayment,

  /// Job was cancelled (by client or platform). Banner explains the state.
  cancelled,
}

/// Top-of-screen banner that adapts to the [BidStatus]:
///   - pending     → cream/orange card with countdown + Edit / Withdraw / Message
///   - accepted    → green card with "Accept & Start Job" + Message
///   - notSelected → grey card with "Not Selected" pill + helper paragraph
class BidStatusBanner extends StatefulWidget {
  const BidStatusBanner({
    super.key,
    required this.status,
    this.expiresAt,
    this.showCountdown = true,
    this.directedAssignment = false,
    this.onEdit,
    this.onWithdraw,
    this.onMessage,
    this.onAcceptStartJob,
  });

  final BidStatus status;

  /// When the bidding window closes. The countdown shown for a pending bid
  /// is `expiresAt - now`, so it decreases in real time and is consistent
  /// across navigations and app restarts. Falls back to 5 minutes from
  /// now if null (e.g. pre-backend-integration callers).
  final DateTime? expiresAt;

  /// Whether to render the countdown pill in the pending-state banner.
  /// Admin-assigned jobs have no bid window — the artisan can quote at
  /// their own pace — so we hide the timer and show a "Quote when ready"
  /// hint instead.
  final bool showCountdown;

  /// The bid is the quote requested from a specifically assigned artisan.
  /// After submission it waits for the client; it is not ready to start yet.
  final bool directedAssignment;

  final VoidCallback? onEdit;
  final VoidCallback? onWithdraw;
  final VoidCallback? onMessage;
  final VoidCallback? onAcceptStartJob;

  @override
  State<BidStatusBanner> createState() => _BidStatusBannerState();
}

class _BidStatusBannerState extends State<BidStatusBanner> {
  Timer? _timer;
  late DateTime _deadline;

  @override
  void initState() {
    super.initState();
    _deadline =
        widget.expiresAt ?? DateTime.now().add(const Duration(minutes: 5));
    if (widget.status == BidStatus.pending && widget.showCountdown) {
      _timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) return;
        if (_remaining.inSeconds <= 0) {
          t.cancel();
          return;
        }
        setState(() {});
      });
    }
  }

  @override
  void didUpdateWidget(covariant BidStatusBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.expiresAt != oldWidget.expiresAt) {
      _deadline =
          widget.expiresAt ?? DateTime.now().add(const Duration(minutes: 5));
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Duration get _remaining {
    final diff = _deadline.difference(DateTime.now());
    return diff.isNegative ? Duration.zero : diff;
  }

  String get _countdownLabel {
    final r = _remaining;
    final m = r.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = r.inSeconds.remainder(60).toString().padLeft(2, '0');
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
      case BidStatus.completed:
        return _buildCompleted();
      case BidStatus.awaitingPayment:
        return _buildAwaitingPayment();
      case BidStatus.cancelled:
        return _buildCancelled();
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
                  widget.showCountdown
                      ? 'Bid pending — waiting'
                      : widget.directedAssignment
                          ? 'Waiting for client'
                          : 'Quote submitted',
                  style: MyShopTypography.h3.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (widget.showCountdown)
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
            widget.showCountdown
                ? 'The client is currently reviewing all submitted bids. You will be notified instantly if your bid is selected or if further details are needed.'
                : widget.directedAssignment
                    ? 'Your quote was sent to the client. You will be notified when they accept it; do not start work before confirmation.'
                    : 'Your quote has been submitted and is waiting for review.',
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

  // ── Completed ──
  Widget _buildCompleted() {
    return _OutcomeBanner(
      accentColor: MyShopColors.success,
      surfaceColor: MyShopColors.successLight,
      icon: Icons.check_circle_rounded,
      pillLabel: 'Completed',
      title: 'Job complete',
      body: 'The client has confirmed the work and your earnings have been '
          'released. You can review the payout under Earnings.',
    );
  }

  // ── Awaiting payment ──
  // Client tapped confirm but Paystack hasn't settled yet (pending_payment).
  // Informational only — the status flips to completed automatically when
  // the webhook fires; no CTA needed.
  Widget _buildAwaitingPayment() {
    return _OutcomeBanner(
      accentColor: MyShopColors.primaryGold,
      surfaceColor: MyShopColors.warningLight,
      icon: Icons.payments_outlined,
      pillLabel: 'Awaiting Payment',
      title: 'Client is paying',
      body: "The escrow charge is settling. Your earnings will release "
          'automatically the moment the payment clears.',
    );
  }

  // ── Cancelled ──
  Widget _buildCancelled() {
    return _OutcomeBanner(
      accentColor: MyShopColors.error,
      surfaceColor: MyShopColors.surfaceWhite,
      border: true,
      icon: Icons.cancel_outlined,
      pillLabel: 'Cancelled',
      title: 'Job cancelled',
      body: 'This job was cancelled. Automatic cancellation fees, transfers, '
          'and penalties are temporarily paused.',
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

/// Shared layout for terminal-ish banners (completed / awaiting payment /
/// cancelled). Takes a pill label, icon, title, and body paragraph — no
/// action buttons, because the artisan has nothing left to do in these
/// states beyond monitoring.
class _OutcomeBanner extends StatelessWidget {
  const _OutcomeBanner({
    required this.accentColor,
    required this.surfaceColor,
    required this.icon,
    required this.pillLabel,
    required this.title,
    required this.body,
    this.border = false,
  });

  final Color accentColor;
  final Color surfaceColor;
  final IconData icon;
  final String pillLabel;
  final String title;
  final String body;
  final bool border;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(MyShopSpacing.md),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: border ? Border.all(color: MyShopColors.divider) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 18, color: accentColor),
              ),
              const SizedBox(width: MyShopSpacing.sm),
              Expanded(
                child: Text(
                  title,
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
                  border: Border.all(color: accentColor.withValues(alpha: 0.4)),
                ),
                child: Text(
                  pillLabel,
                  style: MyShopTypography.body2.copyWith(
                    color: accentColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: MyShopSpacing.sm),
          Text(
            body,
            style: MyShopTypography.body2.copyWith(
              color: MyShopColors.textSecondary,
              height: 1.5,
            ),
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
