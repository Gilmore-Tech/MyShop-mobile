import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/payment_provider.dart';
import 'payment_confirmed_dialog.dart';

// ── Screen ────────────────────────────────────────────────────────────────────
// PRD 7.2 — client reviews job cost, selects payment method, and confirms.
// Funds are held in micro-escrow via Flutterwave until dual confirmation.
// API: POST /v1/payments/initiate

class PaymentScreen extends ConsumerWidget {
  final String jobId;
  const PaymentScreen({super.key, required this.jobId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final size = MediaQuery.sizeOf(context);
    final w    = size.width;
    final h    = size.height;

    final summaryAsync = ref.watch(paymentSummaryProvider(jobId));

    return Scaffold(
      backgroundColor: MyShopColors.offWhite,
      body: summaryAsync.when(
        loading: () => _LoadingSkeleton(w: w, h: h),
        error: (_, __) => MyShopErrorBody(
          message: 'Could not load payment summary',
          onRetry: () => ref.invalidate(paymentSummaryProvider(jobId)),
        ),
        data: (summary) => _PaymentBody(summary: summary, w: w, h: h),
      ),
    );
  }
}

// ── Full body ─────────────────────────────────────────────────────────────────

class _PaymentBody extends ConsumerWidget {
  final PaymentSummary summary;
  final double w;
  final double h;
  const _PaymentBody(
      {required this.summary, required this.w, required this.h});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<PaymentState>(paymentNotifierProvider, (previous, next) {
      if (next.confirmation != null &&
          previous?.confirmation == null) {
        showPaymentConfirmedDialog(context, next.confirmation!);
      }
    });

    return Column(
      children: [
        _AppBar(w: w, h: h),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: h * 0.014),
                _JobSummaryCard(summary: summary, w: w, h: h),
                SizedBox(height: h * 0.014),
                _PaymentSummaryCard(summary: summary, w: w, h: h),
                SizedBox(height: h * 0.014),
                _PaymentMethodCard(summary: summary, w: w, h: h),
                SizedBox(height: h * 0.028),
              ],
            ),
          ),
        ),
        _BottomBar(summary: summary, w: w, h: h),
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
              child: Icon(Icons.arrow_back,
                  size: w * 0.056, color: MyShopColors.textPrimary),
            ),
          ),
          Text(
            'Payment',
            style: TextStyle(
              fontSize: w * 0.051,
              fontWeight: FontWeight.w700,
              color: MyShopColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Job Summary Card ──────────────────────────────────────────────────────────

class _JobSummaryCard extends StatelessWidget {
  final PaymentSummary summary;
  final double w;
  final double h;
  const _JobSummaryCard(
      {required this.summary, required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return _Card(
      w: w,
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Avatar
              Container(
                width: w * 0.128,
                height: w * 0.128,
                decoration: BoxDecoration(
                  color: summary.artisanAvatarColor,
                  borderRadius: BorderRadius.circular(w * 0.018),
                ),
                child: Center(
                  child: Text(
                    summary.artisanName
                        .trim()
                        .split(' ')
                        .take(2)
                        .map((s) => s[0])
                        .join(),
                    style: TextStyle(
                      fontSize: w * 0.041,
                      fontWeight: FontWeight.w700,
                      color: MyShopColors.surfaceWhite,
                    ),
                  ),
                ),
              ),
              SizedBox(width: w * 0.031),
              // Info column
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            summary.jobTitle,
                            style: TextStyle(
                              fontSize: w * 0.038,
                              fontWeight: FontWeight.w700,
                              color: MyShopColors.textPrimary,
                              height: 1.25,
                            ),
                          ),
                        ),
                        SizedBox(width: w * 0.018),
                        _CompletedBadge(w: w),
                      ],
                    ),
                    SizedBox(height: h * 0.004),
                    Text(
                      summary.serviceId,
                      style: TextStyle(
                        fontSize: w * 0.026,
                        color: MyShopColors.textSecondary,
                      ),
                    ),
                    SizedBox(height: h * 0.008),
                    Row(
                      children: [
                        _CategoryChip(
                          name: summary.categoryName,
                          icon: summary.categoryIcon,
                          w: w,
                        ),
                        SizedBox(width: w * 0.015),
                        Icon(Icons.location_on_rounded,
                            size: w * 0.028, color: MyShopColors.primaryGold),
                        SizedBox(width: w * 0.005),
                        Expanded(
                          child: Text(
                            summary.location,
                            style: TextStyle(
                              fontSize: w * 0.026,
                              color: MyShopColors.textSecondary,
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
          SizedBox(height: h * 0.014),
          const Divider(height: 1, color: MyShopColors.divider),
          SizedBox(height: h * 0.014),
          // Stats row
          Row(
            children: [
              Icon(Icons.timer_outlined,
                  size: w * 0.033, color: MyShopColors.textHint),
              SizedBox(width: w * 0.010),
              Text(
                'EST. COMPLETION',
                style: TextStyle(
                  fontSize: w * 0.023,
                  fontWeight: FontWeight.w900,
                  color: MyShopColors.textSecondary,
                  letterSpacing: 0.6,
                ),
              ),
              SizedBox(width: w * 0.026),
              Text(
                summary.completionLabel,
                style: TextStyle(
                  fontSize: w * 0.036,
                  fontWeight: FontWeight.w700,
                  color: MyShopColors.textPrimary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CompletedBadge extends StatelessWidget {
  final double w;
  const _CompletedBadge({required this.w});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: w * 0.026, vertical: w * 0.010),
      decoration: BoxDecoration(
        color: MyShopColors.surfaceGrey,
        borderRadius: BorderRadius.circular(w * 0.051),
      ),
      child: Text(
        'Completed',
        style: TextStyle(
          fontSize: w * 0.026,
          fontWeight: FontWeight.w600,
          color: MyShopColors.textSecondary,
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
        color: MyShopColors.surfaceGrey,
        borderRadius: BorderRadius.circular(w * 0.041),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: w * 0.026, color: MyShopColors.textSecondary),
          SizedBox(width: w * 0.008),
          Text(
            name,
            style: TextStyle(
              fontSize: w * 0.026,
              fontWeight: FontWeight.w500,
              color: MyShopColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Payment Summary Card ──────────────────────────────────────────────────────

class _PaymentSummaryCard extends StatelessWidget {
  final PaymentSummary summary;
  final double w;
  final double h;
  const _PaymentSummaryCard(
      {required this.summary, required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        _Card(
          w: w,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header row ──
              Row(
                children: [
                  Text(
                    'Payment Summary',
                    style: TextStyle(
                      fontSize: w * 0.041,
                      fontWeight: FontWeight.w700,
                      color: MyShopColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    summary.paymentRef,
                    style: TextStyle(
                      fontSize: w * 0.028,
                      fontWeight: FontWeight.w400,
                      color: MyShopColors.textSecondary,
                    ),
                  ),
                ],
              ),
              SizedBox(height: h * 0.014),

              // ── Job title + description ──
              Text(
                summary.jobTitle,
                style: TextStyle(
                  fontSize: w * 0.041,
                  fontWeight: FontWeight.w700,
                  color: MyShopColors.textPrimary,
                ),
              ),
              SizedBox(height: h * 0.006),
              Text(
                summary.paymentDescription,
                style: TextStyle(
                  fontSize: w * 0.031,
                  fontWeight: FontWeight.w400,
                  color: MyShopColors.textSecondary,
                  height: 1.45,
                ),
              ),
              SizedBox(height: h * 0.017),
              const Divider(height: 1, color: MyShopColors.divider),
              SizedBox(height: h * 0.017),

              // ── Line items ──
              _LineItem(
                label: 'Service Fee',
                value: summary.serviceFeeDisplay,
                w: w,
                h: h,
              ),
              SizedBox(height: h * 0.012),
              _LineItem(
                label: 'Materials (Estimated)',
                value: summary.materialsFeeDisplay,
                w: w,
                h: h,
              ),
              SizedBox(height: h * 0.017),
              const Divider(height: 1, color: MyShopColors.divider),
              SizedBox(height: h * 0.017),

              // ── Total ──
              Row(
                children: [
                  Text(
                    'Total Amount',
                    style: TextStyle(
                      fontSize: w * 0.038,
                      fontWeight: FontWeight.w700,
                      color: MyShopColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    summary.totalDisplay,
                    style: TextStyle(
                      fontSize: w * 0.051,
                      fontWeight: FontWeight.w800,
                      color: MyShopColors.textPrimary,
                      height: 1.0,
                    ),
                  ),
                ],
              ),
              SizedBox(height: h * 0.017),

              // ── Escrow info box ──
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: w * 0.031,
                  vertical: h * 0.012,
                ),
                decoration: BoxDecoration(
                  color: MyShopColors.surfaceGrey,
                  borderRadius: BorderRadius.circular(w * 0.021),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.lock_outline_rounded,
                      size: w * 0.041,
                      color: MyShopColors.textSecondary,
                    ),
                    SizedBox(width: w * 0.018),
                    Expanded(
                      child: Text(
                        'Your money is safe. Payment is only released to '
                        '${summary.artisanFirstName} once you mark the job '
                        "as 'Completed'.",
                        style: TextStyle(
                          fontSize: w * 0.028,
                          fontWeight: FontWeight.w400,
                          color: MyShopColors.textSecondary,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // ── Artisan reference badge ──
        Positioned(
          bottom: -h * 0.022,
          right: w * 0.077,
          child: Container(
            width: w * 0.118,
            height: w * 0.118,
            decoration: BoxDecoration(
              color: MyShopColors.error,
              shape: BoxShape.circle,
              border: Border.all(color: MyShopColors.surfaceWhite, width: 2.5),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.verified_user_outlined,
                    size: w * 0.038, color: MyShopColors.surfaceWhite),
                Text(
                  'ESC',
                  style: TextStyle(
                    fontSize: w * 0.020,
                    fontWeight: FontWeight.w800,
                    color: MyShopColors.surfaceWhite,
                    letterSpacing: 0.5,
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

class _LineItem extends StatelessWidget {
  final String label;
  final String value;
  final double w;
  final double h;
  const _LineItem({
    required this.label,
    required this.value,
    required this.w,
    required this.h,
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
              fontWeight: FontWeight.w400,
              color: MyShopColors.textSecondary,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: w * 0.033,
            fontWeight: FontWeight.w500,
            color: MyShopColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

// ── Payment Method Card ───────────────────────────────────────────────────────

class _PaymentMethodCard extends ConsumerWidget {
  final PaymentSummary summary;
  final double w;
  final double h;
  const _PaymentMethodCard(
      {required this.summary, required this.w, required this.h});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected =
        ref.watch(paymentNotifierProvider).selectedMethod;

    return _Card(
      w: w,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Payment Method',
            style: TextStyle(
              fontSize: w * 0.041,
              fontWeight: FontWeight.w700,
              color: MyShopColors.textPrimary,
            ),
          ),
          SizedBox(height: h * 0.005),
          Text(
            'Select your preferred local option',
            style: TextStyle(
              fontSize: w * 0.031,
              fontWeight: FontWeight.w400,
              color: MyShopColors.textSecondary,
            ),
          ),
          SizedBox(height: h * 0.017),

          // ── Platform Payment ──
          _PaymentOption(
            method: PaymentMethod.platformPayment,
            subtitle: PaymentMethod.platformPayment.subtitle,
            isSelected: selected == PaymentMethod.platformPayment,
            onTap: () => ref
                .read(paymentNotifierProvider.notifier)
                .selectMethod(PaymentMethod.platformPayment),
            w: w,
            h: h,
          ),
          SizedBox(height: h * 0.012),

          // ── Cash ──
          _PaymentOption(
            method: PaymentMethod.cash,
            subtitle: 'Balance: ${summary.walletBalanceDisplay}',
            isSelected: selected == PaymentMethod.cash,
            onTap: () => ref
                .read(paymentNotifierProvider.notifier)
                .selectMethod(PaymentMethod.cash),
            w: w,
            h: h,
          ),
        ],
      ),
    );
  }
}

class _PaymentOption extends StatelessWidget {
  final PaymentMethod method;
  final String subtitle;
  final bool isSelected;
  final VoidCallback onTap;
  final double w;
  final double h;
  const _PaymentOption({
    required this.method,
    required this.subtitle,
    required this.isSelected,
    required this.onTap,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = isSelected ? MyShopColors.primaryGold : MyShopColors.divider;
    final iconBgColor = isSelected
        ? MyShopColors.primaryGold.withValues(alpha: 0.12)
        : MyShopColors.surfaceGrey;
    final iconColor   = isSelected ? MyShopColors.primaryGold : MyShopColors.textSecondary;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.symmetric(
          horizontal: w * 0.038,
          vertical: h * 0.017,
        ),
        decoration: BoxDecoration(
          color: MyShopColors.surfaceWhite,
          borderRadius: BorderRadius.circular(w * 0.031),
          border: Border.all(
            color: borderColor,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            // Icon circle
            Container(
              width: w * 0.115,
              height: w * 0.115,
              decoration: BoxDecoration(
                color: iconBgColor,
                shape: BoxShape.circle,
              ),
              child: Icon(method.icon,
                  size: w * 0.051, color: iconColor),
            ),
            SizedBox(width: w * 0.031),
            // Labels
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    method.label,
                    style: TextStyle(
                      fontSize: w * 0.036,
                      fontWeight: FontWeight.w700,
                      color: MyShopColors.textPrimary,
                    ),
                  ),
                  SizedBox(height: h * 0.003),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: w * 0.028,
                      fontWeight: FontWeight.w400,
                      color: MyShopColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            // Radio button
            _RadioDot(isSelected: isSelected, w: w),
          ],
        ),
      ),
    );
  }
}

class _RadioDot extends StatelessWidget {
  final bool isSelected;
  final double w;
  const _RadioDot({required this.isSelected, required this.w});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: w * 0.051,
      height: w * 0.051,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: isSelected ? MyShopColors.primaryGold : MyShopColors.divider,
          width: 2,
        ),
        color: isSelected
            ? MyShopColors.primaryGold.withValues(alpha: 0.10)
            : MyShopColors.surfaceWhite,
      ),
      child: isSelected
          ? Center(
              child: Container(
                width: w * 0.023,
                height: w * 0.023,
                decoration: const BoxDecoration(
                  color: MyShopColors.primaryGold,
                  shape: BoxShape.circle,
                ),
              ),
            )
          : null,
    );
  }
}

// ── Bottom Bar ────────────────────────────────────────────────────────────────

class _BottomBar extends ConsumerWidget {
  final PaymentSummary summary;
  final double w;
  final double h;
  const _BottomBar(
      {required this.summary, required this.w, required this.h});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state     = ref.watch(paymentNotifierProvider);
    final bottomPad = MediaQuery.paddingOf(context).bottom;

    return Container(
      decoration: const BoxDecoration(
        color: MyShopColors.surfaceWhite,
        border: Border(top: BorderSide(color: MyShopColors.divider)),
      ),
      padding: EdgeInsets.only(
        left: w * 0.041,
        right: w * 0.041,
        top: h * 0.017,
        bottom: bottomPad + h * 0.010,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Amount row ──
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'AMOUNT TO PAY',
                    style: TextStyle(
                      fontSize: w * 0.023,
                      fontWeight: FontWeight.w900,
                      color: MyShopColors.textSecondary,
                      letterSpacing: 0.8,
                    ),
                  ),
                  SizedBox(height: h * 0.003),
                  Text(
                    summary.totalDisplay,
                    style: TextStyle(
                      fontSize: w * 0.056,
                      fontWeight: FontWeight.w800,
                      color: MyShopColors.textPrimary,
                      height: 1.0,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Row(
                children: [
                  Icon(Icons.verified_rounded,
                      size: w * 0.038, color: MyShopColors.success),
                  SizedBox(width: w * 0.010),
                  Text(
                    'Guaranteed',
                    style: TextStyle(
                      fontSize: w * 0.031,
                      fontWeight: FontWeight.w600,
                      color: MyShopColors.success,
                    ),
                  ),
                ],
              ),
            ],
          ),
          SizedBox(height: h * 0.014),

          // ── CTA button ──
          SizedBox(
            width: double.infinity,
            height: h * 0.066,
            child: ElevatedButton(
              onPressed: state.isProcessing
                  ? null
                  : () => ref
                      .read(paymentNotifierProvider.notifier)
                      .confirmPayment(
                        jobId: summary.jobId,
                        summary: summary,
                      ),
              style: ElevatedButton.styleFrom(
                backgroundColor: MyShopColors.darkSlate,
                disabledBackgroundColor: MyShopColors.surfaceGrey,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(w * 0.031),
                ),
              ),
              child: state.isProcessing
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
                        Text(
                          'Confirm & Pay Securely',
                          style: TextStyle(
                            fontSize: w * 0.041,
                            fontWeight: FontWeight.w600,
                            color: MyShopColors.surfaceWhite,
                          ),
                        ),
                        SizedBox(width: w * 0.018),
                        Icon(Icons.arrow_forward_rounded,
                            size: w * 0.046, color: MyShopColors.surfaceWhite),
                      ],
                    ),
            ),
          ),
          SizedBox(height: h * 0.010),

          // ── Disclaimer ──
          Text(
            "By clicking 'Confirm & Pay', you agree to the Escrow Terms of "
            'Service. Funds are held by GhanaMobile Marketplace.',
            style: TextStyle(
              fontSize: w * 0.026,
              fontWeight: FontWeight.w400,
              color: MyShopColors.textHint,
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ── Shared card wrapper ───────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  final Widget child;
  final double w;
  const _Card({required this.child, required this.w});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: w * 0.041),
      padding: EdgeInsets.all(w * 0.041),
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(w * 0.031),
        border: Border.all(color: MyShopColors.divider),
      ),
      child: child,
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
          color: MyShopColors.surfaceWhite,
          padding: EdgeInsets.only(
            top: topPad + h * 0.010,
            bottom: h * 0.017,
            left: w * 0.041,
          ),
          child: Row(children: [
            _Shimmer(w: w * 0.056, h: w * 0.056, r: w * 0.056),
            SizedBox(width: w * 0.031),
            _Shimmer(w: w * 0.33, h: h * 0.026),
          ]),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
                horizontal: w * 0.041, vertical: h * 0.014),
            child: Column(
              children: [
                _Shimmer(w: double.infinity, h: h * 0.14, r: w * 0.031),
                SizedBox(height: h * 0.014),
                _Shimmer(w: double.infinity, h: h * 0.30, r: w * 0.031),
                SizedBox(height: h * 0.014),
                _Shimmer(w: double.infinity, h: h * 0.20, r: w * 0.031),
              ],
            ),
          ),
        ),
        Container(
          color: MyShopColors.surfaceWhite,
          padding: EdgeInsets.all(w * 0.041),
          child: Column(
            children: [
              _Shimmer(w: double.infinity, h: h * 0.066, r: w * 0.031),
            ],
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
        color: MyShopColors.divider,
        borderRadius: BorderRadius.circular(r),
      ),
    );
  }
}

