import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/active_job_provider.dart';
import '../providers/payment_provider.dart';
import '../widgets/otp_entry_sheet.dart';
import 'payment_confirmed_dialog.dart';

/// Pops the OTP entry sheet for a Paystack `send_otp` charge and either
/// forwards the entered code to [PaymentNotifier.submitOtp] or — if the
/// user dismissed without entering — calls [cancelOtp] so the screen
/// drops back to the idle state instead of staying stuck in
/// awaitingOtp with no visible UI.
Future<void> _promptForOtp(
  BuildContext context,
  WidgetRef ref, {
  required PaymentSummary summary,
  String? errorMessage,
}) async {
  final otp = await showOtpEntrySheet(context, errorMessage: errorMessage);
  if (otp == null || !context.mounted) {
    ref
        .read(paymentNotifierProvider.notifier)
        .cancelOtp(bookingId: summary.jobId);
    return;
  }
  ref.read(paymentNotifierProvider.notifier).submitOtp(
        otp,
        jobId: summary.jobId,
        summary: summary,
      );
}

/// Opens the Paystack checkout URL, trying external browser first and
/// falling back to an in-app webview. Clears the URL from state on
/// success so the fallback button disappears; leaves it in place (and
/// shows a snackbar) on failure so the user can try again.
Future<void> _launchCheckout(
  BuildContext context,
  WidgetRef ref,
  String url,
) async {
  final uri = Uri.tryParse(url);
  if (uri == null) {
    developer.log('Checkout URL is unparseable: $url', name: 'Payment');
    return;
  }

  bool launched = false;
  try {
    launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (e) {
    developer.log('externalApplication launch threw: $e', name: 'Payment');
  }
  if (!launched) {
    try {
      launched = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
    } catch (e) {
      developer.log('inAppBrowserView launch threw: $e', name: 'Payment');
    }
  }

  if (launched) {
    ref.read(paymentNotifierProvider.notifier).consumeAuthorizationUrl();
  } else if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          "Couldn't open the checkout page. Tap \"Open Checkout\" below to try again.",
        ),
      ),
    );
  }
}

/// Pops a dialog when /payments/initiate returns 409
/// PAYMENT_ALREADY_INITIATED. Two outcomes:
///   - "Cancel & retry" — calls POST /payments/:id/abandon then re-runs
///     /initiate with the current form values.
///   - "Wait" — dismisses; the backend's stale-payment cron will clear
///     the in-flight charge after retryAfterSeconds and the user can
///     tap Confirm & Pay again.
Future<void> _showStalePaymentDialog(
  BuildContext context,
  WidgetRef ref, {
  required PaymentSummary summary,
  required StalePaymentAttempt stale,
  required String momoPhone,
}) async {
  final size = MediaQuery.sizeOf(context);
  final w = size.width;
  final waitHint = stale.retryAfterSeconds > 0
      ? 'Or wait about ${stale.retryAfterSeconds}s for it to clear automatically.'
      : 'It should clear automatically in a moment.';

  final action = await showDialog<_StalePaymentAction>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      backgroundColor: MyShopColors.surfaceWhite,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(w * 0.041),
      ),
      title: Row(
        children: [
          Container(
            width: w * 0.115,
            height: w * 0.115,
            decoration: const BoxDecoration(
              color: MyShopColors.warningLight,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.hourglass_top_rounded,
              size: w * 0.056,
              color: MyShopColors.warning,
            ),
          ),
          SizedBox(width: w * 0.031),
          Expanded(
            child: Text(
              'Payment in progress',
              style: TextStyle(
                fontSize: w * 0.046,
                fontWeight: FontWeight.w700,
                color: MyShopColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
      content: Text(
        'A payment for this job started ${stale.ageSeconds}s ago and is '
        'still pending. If you missed the prompt or closed the app, '
        'cancel it and try again now. $waitHint',
        style: TextStyle(
          fontSize: w * 0.036,
          color: MyShopColors.textSecondary,
          height: 1.5,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(_StalePaymentAction.wait),
          child: Text(
            'Wait',
            style: TextStyle(
              fontSize: w * 0.036,
              fontWeight: FontWeight.w600,
              color: MyShopColors.textSecondary,
            ),
          ),
        ),
        ElevatedButton(
          onPressed: () =>
              Navigator.of(context).pop(_StalePaymentAction.cancelAndRetry),
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
            'Cancel & retry',
            style: TextStyle(
              fontSize: w * 0.036,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );

  if (!context.mounted) return;
  final notifier = ref.read(paymentNotifierProvider.notifier);
  switch (action ?? _StalePaymentAction.wait) {
    case _StalePaymentAction.cancelAndRetry:
      await notifier.abandonStaleAttemptAndRetry(
        jobId: summary.jobId,
        summary: summary,
        momoPhone: momoPhone.isNotEmpty ? momoPhone : null,
      );
    case _StalePaymentAction.wait:
      notifier.dismissStaleAttempt();
  }
}

enum _StalePaymentAction { wait, cancelAndRetry }

// ── Screen ────────────────────────────────────────────────────────────────────
// PRD 7.2 — client reviews job cost, selects payment method, and confirms.
// Funds are held in micro-escrow via Flutterwave until dual confirmation.
// API: POST /v1/payments/initiate

class PaymentScreen extends ConsumerStatefulWidget {
  final String jobId;

  /// Optional method preselected by an upstream chooser (e.g. the
  /// "How would you like to pay?" bottom sheet on the active-job screen).
  /// When set, the payment notifier is seeded with this method on first
  /// build so the user lands on the payment screen with the right option
  /// already highlighted and just needs to tap "Confirm & Pay".
  final PaymentMethod? initialMethod;

  const PaymentScreen({
    super.key,
    required this.jobId,
    this.initialMethod,
  });

  @override
  ConsumerState<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends ConsumerState<PaymentScreen> {
  /// MoMo number the user enters — lives in widget state because we need
  /// a TextEditingController with proper lifecycle. Passed into
  /// [PaymentNotifier.confirmPayment] when the selected method requires it.
  final TextEditingController _momoPhoneCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final preset = widget.initialMethod;
    if (preset != null) {
      // Seed the notifier's selectedMethod so the method card on the screen
      // reflects what the user picked in the upstream chooser. Deferred to
      // a post-frame callback so we don't mutate a provider during build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(paymentNotifierProvider.notifier).selectMethod(preset);
      });
    }
  }

  @override
  void dispose() {
    _momoPhoneCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final w = size.width;
    final h = size.height;

    final summaryAsync = ref.watch(paymentSummaryProvider(widget.jobId));

    return Scaffold(
      backgroundColor: MyShopColors.offWhite,
      body: summaryAsync.when(
        loading: () => _LoadingSkeleton(w: w, h: h),
        error: (_, __) => MyShopErrorBody(
          message: 'Could not load payment summary',
          onRetry: () => ref.invalidate(paymentSummaryProvider(widget.jobId)),
        ),
        data: (summary) => _PaymentBody(
          summary: summary,
          w: w,
          h: h,
          momoPhoneCtrl: _momoPhoneCtrl,
        ),
      ),
    );
  }
}

// ── Full body ─────────────────────────────────────────────────────────────────

class _PaymentBody extends ConsumerWidget {
  final PaymentSummary summary;
  final double w;
  final double h;

  /// Owned by the parent stateful widget — lives across rebuilds. Used
  /// by the MoMo row to capture the phone number and by the bottom bar
  /// to pass it to [PaymentNotifier.confirmPayment].
  final TextEditingController momoPhoneCtrl;

  const _PaymentBody({
    required this.summary,
    required this.w,
    required this.h,
    required this.momoPhoneCtrl,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ── 1. Payment state transitions ─────────────────────────────────────
    ref.listen<PaymentState>(paymentNotifierProvider, (previous, next) {
      // Paystack returned a checkout URL → launch it externally. Only
      // clear the URL from state after a successful launch — if it fails
      // (blocked intent, no browser, emulator quirk) we keep the URL so
      // the bottom-bar "Open Checkout" fallback button stays available.
      if (next.authorizationUrl != null &&
          next.authorizationUrl != previous?.authorizationUrl) {
        _launchCheckout(context, ref, next.authorizationUrl!);
      }

      // Paystack returned `send_otp` — pop the sheet for the user to
      // type the SMS code. Only fires on the *transition* into
      // awaitingOtp so we don't reopen the sheet on every rebuild while
      // the phase is still awaitingOtp (the notifier flips back here on
      // a wrong-OTP retry, with a fresh errorMessage).
      if (next.phase == PaymentPhase.awaitingOtp &&
          previous?.phase != PaymentPhase.awaitingOtp) {
        _promptForOtp(
          context,
          ref,
          summary: summary,
          // Prefer the inline error (e.g. "Wrong OTP") on a retry; fall
          // back to Paystack's displayText ("Enter the OTP we sent…") on
          // the first open.
          errorMessage: next.errorMessage ?? next.displayText,
        );
      }

      // Settlement landed → show the success dialog.
      if (next.confirmation != null && previous?.confirmation == null) {
        showPaymentConfirmedDialog(context, next.confirmation!);
      }

      // 409 PAYMENT_ALREADY_INITIATED — backend has an in-flight charge
      // for this booking. Pop a dialog with the timing details and let
      // the user cancel-and-retry (POST /payments/:id/abandon then
      // re-initiate) or wait for the backend's stale-payment cron.
      if (next.staleAttempt != null && previous?.staleAttempt == null) {
        _showStalePaymentDialog(
          context,
          ref,
          summary: summary,
          stale: next.staleAttempt!,
          momoPhone: momoPhoneCtrl.text,
        );
      }

      // Surface errors as a snackbar — but skip while we're in awaitingOtp
      // since the sheet renders the error inline.
      if (next.errorMessage != null &&
          next.errorMessage != previous?.errorMessage &&
          next.phase != PaymentPhase.awaitingOtp) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(next.errorMessage!)),
        );
      }
    });

    // ── 2. Drive confirmation off the live job status ────────────────────
    // The backend emits `job:status:changed` when Paystack settles; the
    // socket handler invalidates activeJobProvider, which refetches with
    // the new status. When that lands as `completed` we PATCH /confirm
    // (idempotent) to close the loop. If it reverts to awaitingApproval
    // the charge failed — flag it so the retry CTA appears.
    ref.listen<AsyncValue<ActiveJobData>>(
      activeJobProvider(summary.jobId),
      (previous, next) {
        next.whenData((job) {
          final paymentState = ref.read(paymentNotifierProvider);
          if (job.phase == ActiveJobPhase.completed &&
              paymentState.phase != PaymentPhase.settled) {
            ref.read(paymentNotifierProvider.notifier).confirmCompletion(
                  jobId: summary.jobId,
                  summary: summary,
                );
          } else if (job.phase == ActiveJobPhase.awaitingApproval &&
              paymentState.phase == PaymentPhase.awaitingSettlement) {
            ref.read(paymentNotifierProvider.notifier).markPaymentFailed(
                  'Payment failed — please try again.',
                  bookingId: summary.jobId,
                );
          }
        });
      },
    );

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
                _PaymentMethodCard(
                  summary: summary,
                  w: w,
                  h: h,
                  momoPhoneCtrl: momoPhoneCtrl,
                ),
                SizedBox(height: h * 0.028),
              ],
            ),
          ),
        ),
        _BottomBar(
          summary: summary,
          w: w,
          h: h,
          momoPhoneCtrl: momoPhoneCtrl,
        ),
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
      padding: EdgeInsets.symmetric(horizontal: w * 0.026, vertical: w * 0.010),
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
      padding: EdgeInsets.symmetric(horizontal: w * 0.018, vertical: w * 0.008),
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
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    'Payment Summary',
                    style: TextStyle(
                      fontSize: w * 0.041,
                      fontWeight: FontWeight.w700,
                      color: MyShopColors.textPrimary,
                    ),
                  ),
                  SizedBox(width: w * 0.020),
                  Expanded(
                    child: Text(
                      summary.paymentRef,
                      textAlign: TextAlign.right,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: w * 0.028,
                        fontWeight: FontWeight.w400,
                        color: MyShopColors.textSecondary,
                      ),
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
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Total Amount',
                    style: TextStyle(
                      fontSize: w * 0.038,
                      fontWeight: FontWeight.w700,
                      color: MyShopColors.textPrimary,
                    ),
                  ),
                  SizedBox(width: w * 0.020),
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        summary.totalDisplay,
                        style: TextStyle(
                          fontSize: w * 0.051,
                          fontWeight: FontWeight.w800,
                          color: MyShopColors.textPrimary,
                          height: 1.0,
                        ),
                      ),
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
  final TextEditingController momoPhoneCtrl;
  const _PaymentMethodCard({
    required this.summary,
    required this.w,
    required this.h,
    required this.momoPhoneCtrl,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(paymentNotifierProvider).selectedMethod;

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

          // One row per backend-supported method + cash. Values come from
          // [PaymentMethod.values] so adding a provider on the server
          // surfaces automatically once the enum is updated.
          for (int i = 0; i < PaymentMethod.values.length; i++) ...[
            _PaymentOption(
              method: PaymentMethod.values[i],
              subtitle: PaymentMethod.values[i].subtitle,
              isSelected: selected == PaymentMethod.values[i],
              onTap: () => ref
                  .read(paymentNotifierProvider.notifier)
                  .selectMethod(PaymentMethod.values[i]),
              w: w,
              h: h,
            ),
            if (i < PaymentMethod.values.length - 1)
              SizedBox(height: h * 0.010),
          ],
          // MoMo charges are routed by phone number on the backend. Show
          // a compact input directly under the method grid whenever the
          // selected method needs one — the value is read off the shared
          // controller by the bottom bar when "Confirm & Pay" is tapped.
          if (selected.requiresMomoPhone) ...[
            SizedBox(height: h * 0.017),
            Text(
              'Mobile money number',
              style: TextStyle(
                fontSize: w * 0.031,
                fontWeight: FontWeight.w700,
                color: MyShopColors.textPrimary,
              ),
            ),
            SizedBox(height: h * 0.008),
            TextField(
              controller: momoPhoneCtrl,
              keyboardType: TextInputType.phone,
              style: TextStyle(
                fontSize: w * 0.038,
                color: MyShopColors.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: '024 123 4567',
                hintStyle: TextStyle(
                  color: MyShopColors.textSecondary,
                  fontSize: w * 0.036,
                ),
                prefixIcon: const Icon(
                  Icons.phone_android_rounded,
                  color: MyShopColors.textSecondary,
                ),
                filled: true,
                fillColor: MyShopColors.surfaceGrey,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: w * 0.031,
                  vertical: h * 0.017,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(w * 0.021),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(w * 0.021),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(w * 0.021),
                  borderSide: const BorderSide(
                    color: MyShopColors.primaryGold,
                    width: 1.5,
                  ),
                ),
              ),
            ),
            SizedBox(height: h * 0.006),
            Text(
              "You'll receive a prompt on this number to approve the charge.",
              style: TextStyle(
                fontSize: w * 0.026,
                color: MyShopColors.textSecondary,
                height: 1.4,
              ),
            ),
          ],
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
    final borderColor =
        isSelected ? MyShopColors.primaryGold : MyShopColors.divider;
    final iconBgColor = isSelected
        ? MyShopColors.primaryGold.withValues(alpha: 0.12)
        : MyShopColors.surfaceGrey;
    final iconColor =
        isSelected ? MyShopColors.primaryGold : MyShopColors.textSecondary;

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
              child: Icon(method.icon, size: w * 0.051, color: iconColor),
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
  final TextEditingController momoPhoneCtrl;
  const _BottomBar({
    required this.summary,
    required this.w,
    required this.h,
    required this.momoPhoneCtrl,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(paymentNotifierProvider);
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
          // The label + behaviour both pivot on [PaymentPhase]:
          //   idle / failed        → "Confirm & Pay" (retry when failed)
          //   processing           → spinner (initiate in flight)
          //   awaitingSettlement   → "Open Checkout" when we have a URL,
          //                          "Waiting for payment…" otherwise
          //   settled              → success label; button is inert
          SizedBox(
            width: double.infinity,
            height: h * 0.066,
            child: ElevatedButton(
              onPressed: switch (state.phase) {
                // Failed-phase: try /payments/:id/retry first so the
                // backend's 24h insufficient-balance window (PRD edge
                // case #22) stays alive on the same paymentId. The
                // notifier falls back to abandon-by-booking + fresh
                // /initiate when the window expired or the row is no
                // longer retryable.
                PaymentPhase.failed => () =>
                    ref.read(paymentNotifierProvider.notifier).retryAfterFailure(
                          jobId: summary.jobId,
                          summary: summary,
                          momoPhone: state.selectedMethod.requiresMomoPhone
                              ? momoPhoneCtrl.text
                              : null,
                        ),
                PaymentPhase.idle => () =>
                    ref.read(paymentNotifierProvider.notifier).confirmPayment(
                          jobId: summary.jobId,
                          summary: summary,
                          momoPhone: state.selectedMethod.requiresMomoPhone
                              ? momoPhoneCtrl.text
                              : null,
                        ),
                // Re-launch the checkout if the user dismissed Paystack
                // without finishing, or if the auto-launch was blocked.
                PaymentPhase.awaitingSettlement
                    when state.authorizationUrl != null =>
                  () => _launchCheckout(
                        context,
                        ref,
                        state.authorizationUrl!,
                      ),
                _ => null,
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: state.phase == PaymentPhase.failed
                    ? MyShopColors.error
                    : MyShopColors.darkSlate,
                disabledBackgroundColor: MyShopColors.surfaceGrey,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(w * 0.031),
                ),
              ),
              child: _buildCtaChild(state, w),
            ),
          ),

          // ── Manual "I've paid" fallback ──
          // Shown only during the USSD-push wait (awaitingSettlement with no
          // checkout URL). Lets the user dismiss the spinner and surface the
          // receipt themselves when the webhook → socket chain is slow or
          // outright broken — they've just authorized on their phone, so
          // we trust them. The polling fallback still runs in parallel; this
          // is purely an escape hatch from a stuck UI.
          if (state.phase == PaymentPhase.awaitingSettlement &&
              state.authorizationUrl == null) ...[
            SizedBox(height: h * 0.010),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => ref
                    .read(paymentNotifierProvider.notifier)
                    .markPaymentSettledLocally(summary: summary),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.symmetric(vertical: h * 0.012),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(w * 0.031),
                  ),
                ),
                child: Text(
                  "I've completed the payment",
                  style: TextStyle(
                    fontSize: w * 0.036,
                    fontWeight: FontWeight.w700,
                    color: MyShopColors.primaryGold,
                  ),
                ),
              ),
            ),
          ],

          SizedBox(height: h * 0.010),

          // ── Status / disclaimer ──
          // While we're waiting on the USSD push, prefer Paystack's
          // own message ("A request has been sent…", "Authorize on
          // your MTN line", etc.) over the legal disclaimer. The
          // gateway's wording is the most accurate instruction the
          // user can follow at that moment.
          if (state.phase == PaymentPhase.awaitingSettlement &&
              state.displayText != null &&
              state.displayText!.isNotEmpty)
            Text(
              state.displayText!,
              style: TextStyle(
                fontSize: w * 0.030,
                fontWeight: FontWeight.w600,
                color: MyShopColors.textSecondary,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            )
          else
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

  Widget _buildCtaChild(PaymentState state, double w) {
    // Initiate in flight — spinner only.
    if (state.phase == PaymentPhase.processing) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: w * 0.046,
            height: w * 0.046,
            child: const CircularProgressIndicator(
              strokeWidth: 2,
              color: MyShopColors.surfaceWhite,
            ),
          ),
          SizedBox(width: w * 0.026),
          Text(
            'Starting payment…',
            style: TextStyle(
              fontSize: w * 0.038,
              fontWeight: FontWeight.w600,
              color: MyShopColors.surfaceWhite,
            ),
          ),
        ],
      );
    }

    // Charge is queued. Two sub-states:
    //   - URL still in state → user dismissed Paystack without finishing,
    //     or the auto-launch was blocked. Offer to re-open checkout.
    //   - URL cleared → either it was never returned (MoMo push flow) or
    //     it's been opened once. Show a passive waiting label.
    if (state.phase == PaymentPhase.awaitingSettlement) {
      if (state.authorizationUrl != null) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.open_in_new_rounded,
                size: w * 0.046, color: MyShopColors.surfaceWhite),
            SizedBox(width: w * 0.018),
            Text(
              'Open Checkout',
              style: TextStyle(
                fontSize: w * 0.041,
                fontWeight: FontWeight.w700,
                color: MyShopColors.surfaceWhite,
              ),
            ),
          ],
        );
      }
      // Live Ghana MoMo on Paystack uses a USSD push (not OTP). Label
      // the wait state accordingly so the user looks at their phone for
      // the carrier prompt instead of expecting a code in-app.
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: w * 0.046,
            height: w * 0.046,
            child: const CircularProgressIndicator(
              strokeWidth: 2,
              color: MyShopColors.surfaceWhite,
            ),
          ),
          SizedBox(width: w * 0.026),
          Text(
            'Approve on your phone',
            style: TextStyle(
              fontSize: w * 0.038,
              fontWeight: FontWeight.w600,
              color: MyShopColors.surfaceWhite,
            ),
          ),
        ],
      );
    }

    if (state.phase == PaymentPhase.settled) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle_rounded,
              size: w * 0.046, color: MyShopColors.surfaceWhite),
          SizedBox(width: w * 0.018),
          Text(
            'Payment Complete',
            style: TextStyle(
              fontSize: w * 0.041,
              fontWeight: FontWeight.w700,
              color: MyShopColors.surfaceWhite,
            ),
          ),
        ],
      );
    }

    final label = state.phase == PaymentPhase.failed
        ? 'Retry Payment'
        : 'Confirm & Pay Securely';
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          label,
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
