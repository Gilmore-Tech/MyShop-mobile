import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../providers/job_summary_provider.dart';

// ── Screen ─────────────────────────────────────────────────────────────────────
// PRD § 4.5 / § 4.8 — Post-job completion: rate artisan, leave a comment.
// EDD: POST /v1/ratings  { bookingType: "job", bookingId, rating, comment? }
// Blind 24-hour window — rating not visible until artisan also rates or window closes.

class JobCompleteScreen extends ConsumerWidget {
  const JobCompleteScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final size = MediaQuery.sizeOf(context);
    final w = size.width;
    final h = size.height;
    final jobId =
        GoRouterState.of(context).pathParameters['jobId'] ?? 'JOB-29384';
    final state = ref.watch(jobSummaryProvider(jobId));

    return Scaffold(
      backgroundColor: MyShopColors.offWhite,
      appBar: AppBar(
        backgroundColor: MyShopColors.surfaceWhite,
        automaticallyImplyLeading: false,
        title: Text('Job Complete',
            style: TextStyle(
                color: MyShopColors.textPrimary,
                fontSize: w * 0.044,
                fontWeight: FontWeight.w700)),
        centerTitle: false,
      ),
      body: state.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: MyShopColors.primaryGold)),
        error: (_, __) => Center(
            child: Text('Failed to load.',
                style: TextStyle(
                    color: MyShopColors.textSecondary, fontSize: w * 0.036))),
        data: (summary) => _Body(w: w, h: h, summary: summary),
      ),
    );
  }
}

// ── Body ───────────────────────────────────────────────────────────────────────

class _Body extends ConsumerStatefulWidget {
  final double w, h;
  final JobSummaryData summary;
  const _Body({required this.w, required this.h, required this.summary});

  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState extends ConsumerState<_Body> {
  final _commentController = TextEditingController();

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rating = ref.watch(jobRatingProvider);
    final w = widget.w;
    final h = widget.h;
    final bot = MediaQuery.paddingOf(context).bottom;

    if (rating.isSubmitted) {
      return _ThankYouState(
        w: w,
        h: h,
        bot: bot,
        summary: widget.summary,
        onDone: () => context.go(AppRoutes.activity),
      );
    }

    // Block the rating form until the backend has flipped the job to
    // `completed`. At `artisan_marked_complete` (cash payment still
    // waiting on the artisan's "Yes, I received payment" tap) the rating
    // endpoint will 410. Show a settling notice instead so the client
    // knows what they're waiting on.
    if (!widget.summary.isCompleted) {
      return _StillSettlingState(
        w: w,
        h: h,
        bot: bot,
        summary: widget.summary,
        onDone: () => context.go(AppRoutes.activity),
      );
    }

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(w * 0.05),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(height: h * 0.016),
                // Success icon
                Container(
                  width: w * 0.20,
                  height: w * 0.20,
                  decoration: const BoxDecoration(
                      color: MyShopColors.successLight, shape: BoxShape.circle),
                  child: const Icon(Icons.check_circle_outline_rounded,
                      color: MyShopColors.success, size: 52),
                ),
                SizedBox(height: h * 0.020),
                Text('Job Completed!',
                    style: TextStyle(
                      color: MyShopColors.textPrimary,
                      fontSize: w * 0.056,
                      fontWeight: FontWeight.w800,
                    )),
                SizedBox(height: h * 0.008),
                Text('Payment released from escrow.',
                    style: TextStyle(
                        color: MyShopColors.textSecondary,
                        fontSize: w * 0.036)),
                SizedBox(height: h * 0.028),
                // Summary card
                _SummaryCard(summary: widget.summary, w: w, h: h),
                SizedBox(height: h * 0.028),
                // Rating section
                _RateSection(w: w, stars: rating.selectedStars),
                SizedBox(height: h * 0.020),
                // Comment field
                _CommentField(
                    controller: _commentController,
                    onChanged: (v) =>
                        ref.read(jobRatingProvider.notifier).updateReview(v),
                    w: w,
                    h: h),
              ],
            ),
          ),
        ),
        _SubmitBar(
          canSubmit: rating.canSubmit,
          loading: rating.isSubmitting,
          onSubmit: () => ref
              .read(jobRatingProvider.notifier)
              .submitRating(jobId: widget.summary.jobId),
          onSkip: () => context.go(AppRoutes.activity),
          w: w,
          h: h,
          bot: bot,
        ),
      ],
    );
  }
}

// ── Still-settling state ───────────────────────────────────────────────────────
//
// Replaces the rating form when the backend job hasn't reached
// `completed` yet. Most often hits during cash payments — the artisan
// taps "Mark Complete" (status -> artisan_marked_complete) but hasn't
// yet confirmed receipt of the cash on their side. The client can still
// rate later from Activity once the artisan settles.

class _StillSettlingState extends StatelessWidget {
  final double w, h, bot;
  final JobSummaryData summary;
  final VoidCallback onDone;

  const _StillSettlingState({
    required this.w,
    required this.h,
    required this.bot,
    required this.summary,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        w * 0.08,
        h * 0.04,
        w * 0.08,
        bot + h * 0.040,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: w * 0.22,
            height: w * 0.22,
            decoration: const BoxDecoration(
              color: MyShopColors.surfaceGrey,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.hourglass_top_rounded,
              color: MyShopColors.textSecondary,
              size: 56,
            ),
          ),
          SizedBox(height: h * 0.024),
          Text(
            'Still settling…',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: MyShopColors.textPrimary,
              fontSize: w * 0.052,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: h * 0.012),
          Text(
            "${summary.artisan.firstName} hasn't confirmed payment "
            'receipt yet, so this job is still finalizing on our '
            "end. You'll be able to leave a rating from Activity as "
            'soon as it lands as completed.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: MyShopColors.textSecondary,
              fontSize: w * 0.036,
              height: 1.6,
            ),
          ),
          SizedBox(height: h * 0.040),
          SizedBox(
            width: double.infinity,
            height: h * 0.062,
            child: ElevatedButton(
              onPressed: onDone,
              style: ElevatedButton.styleFrom(
                backgroundColor: MyShopColors.primaryGold,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 0,
              ),
              child: Text(
                'Go to Activity',
                style: TextStyle(
                  fontSize: w * 0.040,
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

// ── Summary card ───────────────────────────────────────────────────────────────

class _SummaryCard extends StatelessWidget {
  final JobSummaryData summary;
  final double w, h;
  const _SummaryCard({required this.summary, required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    final a = summary.artisan;
    return Container(
      padding: EdgeInsets.all(w * 0.04),
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withAlpha(8),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: w * 0.13,
                height: w * 0.13,
                decoration:
                    BoxDecoration(color: a.avatarColor, shape: BoxShape.circle),
                child: Icon(Icons.person_rounded,
                    color: Colors.white, size: w * 0.065),
              ),
              SizedBox(width: w * 0.030),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(a.name,
                        style: TextStyle(
                          color: MyShopColors.textPrimary,
                          fontSize: w * 0.040,
                          fontWeight: FontWeight.w700,
                        )),
                    const SizedBox(height: 2),
                    Text(a.role,
                        style: TextStyle(
                            color: MyShopColors.textSecondary,
                            fontSize: w * 0.032)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(summary.totalPaidDisplay,
                      style: TextStyle(
                        color: MyShopColors.textPrimary,
                        fontSize: w * 0.042,
                        fontWeight: FontWeight.w800,
                      )),
                  const SizedBox(height: 2),
                  Text('Total paid',
                      style: TextStyle(
                          color: MyShopColors.textSecondary,
                          fontSize: w * 0.028)),
                ],
              ),
            ],
          ),
          SizedBox(height: h * 0.014),
          const Divider(height: 1, color: MyShopColors.divider),
          SizedBox(height: h * 0.014),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Labour',
                  style: TextStyle(
                      color: MyShopColors.textSecondary, fontSize: w * 0.032)),
              Text(summary.laborChargeDisplay,
                  style: TextStyle(
                      color: MyShopColors.textPrimary,
                      fontSize: w * 0.032,
                      fontWeight: FontWeight.w600)),
            ],
          ),
          SizedBox(height: h * 0.008),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Materials',
                  style: TextStyle(
                      color: MyShopColors.textSecondary, fontSize: w * 0.032)),
              Text(summary.materialCostDisplay,
                  style: TextStyle(
                      color: MyShopColors.textPrimary,
                      fontSize: w * 0.032,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Rate section ───────────────────────────────────────────────────────────────

class _RateSection extends ConsumerWidget {
  final double w;
  final int stars;
  const _RateSection({required this.w, required this.stars});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        Text('How was your experience?',
            style: TextStyle(
              color: MyShopColors.textPrimary,
              fontSize: w * 0.042,
              fontWeight: FontWeight.w700,
            )),
        SizedBox(height: w * 0.040),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(5, (i) {
            final filled = i < stars;
            return GestureDetector(
              onTap: () =>
                  ref.read(jobRatingProvider.notifier).selectStars(i + 1),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: w * 0.020),
                child: Icon(
                  filled ? Icons.star_rounded : Icons.star_outline_rounded,
                  color: filled
                      ? MyShopColors.primaryGold
                      : const Color(0xFFD0D8DC),
                  size: w * 0.092,
                ),
              ),
            );
          }),
        ),
        SizedBox(height: w * 0.020),
        if (stars > 0)
          Text(_ratingLabel(stars),
              style: TextStyle(
                color: MyShopColors.textSecondary,
                fontSize: w * 0.034,
              )),
      ],
    );
  }

  String _ratingLabel(int s) => switch (s) {
        1 => 'Terrible',
        2 => 'Poor',
        3 => 'Okay',
        4 => 'Good',
        _ => 'Excellent!',
      };
}

// ── Comment field ──────────────────────────────────────────────────────────────

class _CommentField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final double w, h;

  const _CommentField({
    required this.controller,
    required this.onChanged,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MyShopColors.divider),
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        maxLines: 4,
        minLines: 3,
        style: TextStyle(color: MyShopColors.textPrimary, fontSize: w * 0.036),
        decoration: InputDecoration(
          hintText: 'Leave a comment (optional)…',
          hintStyle: TextStyle(
              color: MyShopColors.textSecondary.withAlpha(120),
              fontSize: w * 0.034),
          contentPadding: EdgeInsets.all(w * 0.04),
          border: InputBorder.none,
        ),
      ),
    );
  }
}

// ── Submit bar ─────────────────────────────────────────────────────────────────

class _SubmitBar extends StatelessWidget {
  final bool canSubmit;
  final bool loading;
  final VoidCallback onSubmit;
  final VoidCallback onSkip;
  final double w, h, bot;

  const _SubmitBar({
    required this.canSubmit,
    required this.loading,
    required this.onSubmit,
    required this.onSkip,
    required this.w,
    required this.h,
    required this.bot,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: MyShopColors.surfaceWhite,
      padding:
          EdgeInsets.fromLTRB(w * 0.05, h * 0.016, w * 0.05, bot + h * 0.020),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedOpacity(
            opacity: canSubmit ? 1.0 : 0.45,
            duration: const Duration(milliseconds: 200),
            child: SizedBox(
              width: double.infinity,
              height: h * 0.062,
              child: ElevatedButton(
                onPressed: canSubmit ? onSubmit : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: MyShopColors.primaryGold,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor:
                      MyShopColors.primaryGold.withAlpha(80),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
                child: loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2.5))
                    : Text('Submit Rating',
                        style: TextStyle(
                          fontSize: w * 0.040,
                          fontWeight: FontWeight.w700,
                        )),
              ),
            ),
          ),
          SizedBox(height: h * 0.010),
          TextButton(
            onPressed: onSkip,
            child: Text('Skip for now',
                style: TextStyle(
                    color: MyShopColors.textSecondary, fontSize: w * 0.036)),
          ),
        ],
      ),
    );
  }
}

// ── Thank-you state ────────────────────────────────────────────────────────────

class _ThankYouState extends StatelessWidget {
  final double w, h, bot;
  final JobSummaryData summary;
  final VoidCallback onDone;

  const _ThankYouState({
    required this.w,
    required this.h,
    required this.bot,
    required this.summary,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(w * 0.08),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: w * 0.22,
            height: w * 0.22,
            decoration: const BoxDecoration(
                color: MyShopColors.successLight, shape: BoxShape.circle),
            child: const Icon(Icons.favorite_rounded,
                color: MyShopColors.success, size: 56),
          ),
          SizedBox(height: h * 0.032),
          Text('Thanks for your feedback!',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: MyShopColors.textPrimary,
                fontSize: w * 0.052,
                fontWeight: FontWeight.w800,
              )),
          SizedBox(height: h * 0.012),
          Text(
            'Your rating helps ${summary.artisan.firstName} and '
            'the MyShop community.',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: MyShopColors.textSecondary,
                fontSize: w * 0.036,
                height: 1.6),
          ),
          SizedBox(height: h * 0.048),
          SizedBox(
            width: double.infinity,
            height: h * 0.066,
            child: ElevatedButton(
              onPressed: onDone,
              style: ElevatedButton.styleFrom(
                backgroundColor: MyShopColors.primaryGold,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: Text('Back to Activity',
                  style: TextStyle(
                      fontSize: w * 0.042, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}
