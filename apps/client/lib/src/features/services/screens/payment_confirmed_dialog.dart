import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../app/router.dart';
import '../../../core/di/providers.dart';
import '../providers/payment_provider.dart';
import '../widgets/rate_job_sheet.dart';

// ── Entry point ───────────────────────────────────────────────────────────────
// PRD 7.2 / EDD § Payment Endpoints
// Called from _PaymentBody via ref.listen when PaymentState.confirmation != null.
// After payment is escrowed the client is prompted to rate the provider and can
// view the receipt or navigate home.  Payment release to the artisan happens
// only after dual confirmation (PRD 4.8.2).

void showPaymentConfirmedDialog(
  BuildContext context,
  PaymentConfirmation confirmation,
) {
  showGeneralDialog(
    context: context,
    barrierDismissible: false,
    barrierLabel: '',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (_, __, ___) =>
        _PaymentConfirmedDialog(confirmation: confirmation),
    transitionBuilder: (_, animation, __, child) {
      final fade = CurvedAnimation(parent: animation, curve: Curves.easeIn);
      final slide =
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: fade,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.06),
            end: Offset.zero,
          ).animate(slide),
          child: child,
        ),
      );
    },
  );
}

// ── Root dialog ───────────────────────────────────────────────────────────────

class _PaymentConfirmedDialog extends StatelessWidget {
  final PaymentConfirmation confirmation;
  const _PaymentConfirmedDialog({required this.confirmation});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final w = size.width;
    final h = size.height;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(
        horizontal: w * 0.041,
        vertical: h * 0.062,
      ),
      child: _DialogSheet(confirmation: confirmation, w: w, h: h),
    );
  }
}

// ── Dialog sheet ──────────────────────────────────────────────────────────────

class _DialogSheet extends ConsumerStatefulWidget {
  final PaymentConfirmation confirmation;
  final double w;
  final double h;
  const _DialogSheet({
    required this.confirmation,
    required this.w,
    required this.h,
  });

  @override
  ConsumerState<_DialogSheet> createState() => _DialogSheetState();
}

class _DialogSheetState extends ConsumerState<_DialogSheet> {
  bool _detailsExpanded = false;
  bool _checkingStatus = false;

  PaymentConfirmation get c => widget.confirmation;
  double get w => widget.w;
  double get h => widget.h;

  /// Tap handler for the "Rate & Review Provider" CTA. Re-fetches the job
  /// before opening the rating sheet so we never present a sheet that's
  /// going to 410 against the backend. When the job isn't yet `completed`
  /// (most often `artisan_marked_complete` for cash payments) we route the
  /// user to Activity with a snackbar — they can rate from the receipt
  /// screen once the artisan settles.
  Future<void> _onRateTapped() async {
    final firstName = c.artisanName.trim().split(RegExp(r'\s+')).first;
    setState(() => _checkingStatus = true);

    String? status;
    try {
      final raw = await ref.read(jobServiceProvider).getJob(c.jobId);
      status = raw['status'] as String?;
    } catch (_) {
      // Network blip — fall through to the generic "still settling" path.
    }
    if (!mounted || !context.mounted) return;
    setState(() => _checkingStatus = false);

    final navigator = Navigator.of(context, rootNavigator: true);
    final rootCtx = navigator.context;

    if (status == 'completed') {
      navigator.maybePop();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!rootCtx.mounted) return;
        showRateJobSheet(
          rootCtx,
          jobId: c.jobId,
          artisanFirstName: firstName,
        );
      });
      return;
    }

    // Not settled yet. Send the user to Activity with a clear note —
    // they can rate from the receipt screen once the job lands as
    // completed (artisan confirms cash, or Paystack webhook fires).
    final messenger = ScaffoldMessenger.of(rootCtx);
    navigator.maybePop();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!rootCtx.mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'The job is still being finalized. You can rate it from '
            'Activity once the artisan confirms payment.',
          ),
        ),
      );
      rootCtx.go(AppRoutes.activity);
    });
  }

  /// Display format: GH¢ X,XXX.XX  (matches design)
  String _fmt(int pesewas) {
    final amount = pesewas / 100;
    // format with comma thousands separator
    final parts = amount.toStringAsFixed(2).split('.');
    final whole = parts[0];
    final dec = parts[1];
    final buf = StringBuffer();
    for (var i = 0; i < whole.length; i++) {
      if (i > 0 && (whole.length - i) % 3 == 0) buf.write(',');
      buf.write(whole[i]);
    }
    return 'GH¢ $buf.$dec';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(w * 0.051),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(w * 0.051),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Close button row ──
              _CloseRow(w: w, h: h),

              // ── Check icon ──
              _CheckCircle(w: w),
              SizedBox(height: h * 0.017),

              // ── Title ──
              Text(
                'Payment Successful',
                style: TextStyle(
                  fontSize: w * 0.056,
                  fontWeight: FontWeight.w800,
                  color: MyShopColors.textPrimary,
                ),
              ),
              SizedBox(height: h * 0.007),

              // ── Subtitle ──
              Padding(
                padding: EdgeInsets.symmetric(horizontal: w * 0.077),
                child: Text(
                  'Your payment to ${c.artisanName} has been processed.',
                  style: TextStyle(
                    fontSize: w * 0.033,
                    fontWeight: FontWeight.w400,
                    color: MyShopColors.textSecondary,
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              SizedBox(height: h * 0.024),

              // ── Amount ──
              Text(
                _fmt(c.amountPesewas),
                style: TextStyle(
                  fontSize: w * 0.082,
                  fontWeight: FontWeight.w900,
                  color: MyShopColors.textPrimary,
                  height: 1.0,
                ),
              ),
              SizedBox(height: h * 0.011),

              // ── Completed badge ──
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: w * 0.041,
                  vertical: h * 0.005,
                ),
                decoration: BoxDecoration(
                  color: MyShopColors.surfaceGrey,
                  borderRadius: BorderRadius.circular(w * 0.051),
                ),
                child: Text(
                  'Completed',
                  style: TextStyle(
                    fontSize: w * 0.031,
                    fontWeight: FontWeight.w500,
                    color: MyShopColors.textSecondary,
                  ),
                ),
              ),
              SizedBox(height: h * 0.022),

              // ── Divider ──
              const Divider(height: 1, color: MyShopColors.divider),

              // ── View Payment Details expandable ──
              _ExpandableDetails(
                confirmation: c,
                expanded: _detailsExpanded,
                onToggle: () =>
                    setState(() => _detailsExpanded = !_detailsExpanded),
                w: w,
                h: h,
                fmt: _fmt,
              ),

              // ── Divider ──
              const Divider(height: 1, color: MyShopColors.divider),
              SizedBox(height: h * 0.019),

              // ── Buttons ──
              Padding(
                padding: EdgeInsets.symmetric(horizontal: w * 0.041),
                child: Column(
                  children: [
                    // Rate & Review Provider — gold CTA. The dialog can
                    // open before the backend has flipped the job to
                    // `completed` (e.g. cash payment still waiting on the
                    // artisan's "I received payment" tap), so we re-fetch
                    // status before opening the sheet. If the job isn't
                    // settled yet, route the user to Activity where they
                    // can rate once it lands as completed.
                    SizedBox(
                      width: double.infinity,
                      height: h * 0.066,
                      child: ElevatedButton(
                        onPressed: _checkingStatus ? null : _onRateTapped,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: MyShopColors.primaryGold,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(w * 0.031),
                          ),
                        ),
                        child: _checkingStatus
                            ? SizedBox(
                                width: w * 0.051,
                                height: w * 0.051,
                                child: const CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: MyShopColors.surfaceWhite,
                                ),
                              )
                            : Text(
                                'Rate & Review Provider',
                                style: TextStyle(
                                  fontSize: w * 0.041,
                                  fontWeight: FontWeight.w700,
                                  color: MyShopColors.surfaceWhite,
                                ),
                              ),
                      ),
                    ),
                    SizedBox(height: h * 0.014),

                    // Receipt | Job Details — outlined pair
                    Row(
                      children: [
                        Expanded(
                          child: _OutlinedActionButton(
                            icon: Icons.receipt_long_outlined,
                            label: 'Receipt',
                            onTap: () {
                              // TODO: navigate to receipt screen
                              Navigator.of(context).maybePop();
                            },
                            w: w,
                            h: h,
                          ),
                        ),
                        SizedBox(width: w * 0.031),
                        Expanded(
                          child: _OutlinedActionButton(
                            icon: Icons.work_outline_rounded,
                            label: 'Job Details',
                            onTap: () {
                              // TODO: navigate to job detail screen
                              Navigator.of(context).maybePop();
                            },
                            w: w,
                            h: h,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: h * 0.019),

                    // Return Home
                    _TextLinkButton(
                      icon: Icons.home_outlined,
                      label: 'Return Home',
                      onTap: () => Navigator.of(context).maybePop(),
                      w: w,
                      h: h,
                    ),
                    SizedBox(height: h * 0.014),

                    // Contact Support
                    _TextLinkButton(
                      icon: Icons.headset_mic_outlined,
                      label: 'Contact Support',
                      onTap: () {
                        // TODO: open support chat
                      },
                      w: w,
                      h: h,
                    ),
                    SizedBox(height: h * 0.022),
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

// ── Close row ─────────────────────────────────────────────────────────────────

class _CloseRow extends StatelessWidget {
  final double w;
  final double h;
  const _CloseRow({required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topRight,
      child: Padding(
        padding: EdgeInsets.only(
          top: h * 0.014,
          right: w * 0.038,
        ),
        child: GestureDetector(
          onTap: () => Navigator.of(context).maybePop(),
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: w * 0.082,
            height: w * 0.082,
            decoration: BoxDecoration(
              color: MyShopColors.surfaceGrey,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.close_rounded,
              size: w * 0.041,
              color: MyShopColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Check circle ──────────────────────────────────────────────────────────────

class _CheckCircle extends StatelessWidget {
  final double w;
  const _CheckCircle({required this.w});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: w * 0.164,
      height: w * 0.164,
      decoration: BoxDecoration(
        color: MyShopColors.successLight,
        shape: BoxShape.circle,
        border: Border.all(color: MyShopColors.success, width: 2.5),
      ),
      child: Icon(
        Icons.check_rounded,
        size: w * 0.082,
        color: MyShopColors.success,
      ),
    );
  }
}

// ── Expandable payment details ────────────────────────────────────────────────

class _ExpandableDetails extends StatelessWidget {
  final PaymentConfirmation confirmation;
  final bool expanded;
  final VoidCallback onToggle;
  final double w;
  final double h;
  final String Function(int) fmt;

  const _ExpandableDetails({
    required this.confirmation,
    required this.expanded,
    required this.onToggle,
    required this.w,
    required this.h,
    required this.fmt,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Toggle row ──
        GestureDetector(
          onTap: onToggle,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: w * 0.051,
              vertical: h * 0.017,
            ),
            child: Row(
              children: [
                Text(
                  'View Payment Details',
                  style: TextStyle(
                    fontSize: w * 0.036,
                    fontWeight: FontWeight.w600,
                    color: MyShopColors.darkSlate,
                  ),
                ),
                const Spacer(),
                AnimatedRotation(
                  turns: expanded ? 0.5 : 0.0,
                  duration: const Duration(milliseconds: 220),
                  child: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: w * 0.056,
                    color: MyShopColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),

        // ── Expanded detail rows ──
        AnimatedCrossFade(
          firstChild: const SizedBox(width: double.infinity),
          secondChild: _DetailRows(
            confirmation: confirmation,
            w: w,
            h: h,
            fmt: fmt,
          ),
          crossFadeState:
              expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 220),
        ),
      ],
    );
  }
}

class _DetailRows extends StatelessWidget {
  final PaymentConfirmation confirmation;
  final double w;
  final double h;
  final String Function(int) fmt;

  const _DetailRows({
    required this.confirmation,
    required this.w,
    required this.h,
    required this.fmt,
  });

  @override
  Widget build(BuildContext context) {
    final c = confirmation;
    return Padding(
      padding: EdgeInsets.only(
        left: w * 0.051,
        right: w * 0.051,
        bottom: h * 0.017,
      ),
      child: Column(
        children: [
          _DetailRow(
            label: 'Transaction Ref',
            value: c.transactionRef,
            w: w,
            h: h,
          ),
          SizedBox(height: h * 0.011),
          _DetailRow(
            label: 'Artisan',
            value: c.artisanName,
            w: w,
            h: h,
          ),
          SizedBox(height: h * 0.011),
          _DetailRow(
            label: 'Job',
            value: c.jobTitle,
            w: w,
            h: h,
          ),
          SizedBox(height: h * 0.011),
          _DetailRow(
            label: 'Method',
            value: c.method.label,
            w: w,
            h: h,
          ),
          SizedBox(height: h * 0.011),
          _DetailRow(
            label: 'Amount',
            value: fmt(c.amountPesewas),
            w: w,
            h: h,
          ),
          SizedBox(height: h * 0.011),
          _DetailRow(
            label: 'Date & Time',
            value: c.dateTimeLabel,
            w: w,
            h: h,
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final double w;
  final double h;
  const _DetailRow({
    required this.label,
    required this.value,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: w * 0.31,
          child: Text(
            label,
            style: TextStyle(
              fontSize: w * 0.031,
              fontWeight: FontWeight.w400,
              color: MyShopColors.textSecondary,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: w * 0.031,
              fontWeight: FontWeight.w600,
              color: MyShopColors.textPrimary,
            ),
            textAlign: TextAlign.end,
          ),
        ),
      ],
    );
  }
}

// ── Outlined action button ────────────────────────────────────────────────────

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
        height: h * 0.060,
        decoration: BoxDecoration(
          color: MyShopColors.surfaceWhite,
          borderRadius: BorderRadius.circular(w * 0.026),
          border: Border.all(color: MyShopColors.divider, width: 1.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: w * 0.041, color: MyShopColors.darkSlate),
            SizedBox(width: w * 0.015),
            Text(
              label,
              style: TextStyle(
                fontSize: w * 0.033,
                fontWeight: FontWeight.w600,
                color: MyShopColors.darkSlate,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Text link button ──────────────────────────────────────────────────────────

class _TextLinkButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final double w;
  final double h;
  const _TextLinkButton({
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
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: h * 0.005),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: w * 0.041, color: MyShopColors.textSecondary),
            SizedBox(width: w * 0.018),
            Text(
              label,
              style: TextStyle(
                fontSize: w * 0.036,
                fontWeight: FontWeight.w500,
                color: MyShopColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
