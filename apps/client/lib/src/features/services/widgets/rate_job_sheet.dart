import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_ui/shared_ui.dart';

import '../providers/job_summary_provider.dart';

// ── Public entry-point ────────────────────────────────────────────────────────
//
// Bottom sheet that lets the client rate the artisan for a completed job.
// Mirrors `rate_ride_sheet.dart` for the rides side. Uses [jobRatingProvider]
// which posts to /v1/ratings with `bookingType: "artisan_job"`.
//
// PRD § 4.8 / EDD § Rating Module — blind 24-hour window: rating only
// reveals once both sides have rated or the window closes.
//
// Decoupled from any specific receipt shape — both the post-payment flow
// (`PaymentConfirmation`) and the receipt-screen flow (`ServiceReceiptData`)
// just hand us the jobId and the artisan's first name.

Future<void> showRateJobSheet(
  BuildContext context, {
  required String jobId,
  required String artisanFirstName,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (_) => RateJobSheet(
      jobId: jobId,
      artisanFirstName: artisanFirstName,
    ),
  );
}

// Lightweight tags surfaced under the star row. Multi-select. Cosmetic only
// for now — backend ignores them. Aligned with the artisan/services context
// (rides use a different set in [rate_ride_provider.dart]).
const _jobRatingTags = [
  'On Time',
  'Quality Work',
  'Polite',
  'Fair Pricing',
];

// ── Sheet root ────────────────────────────────────────────────────────────────

class RateJobSheet extends ConsumerStatefulWidget {
  final String jobId;
  final String artisanFirstName;
  const RateJobSheet({
    super.key,
    required this.jobId,
    required this.artisanFirstName,
  });

  @override
  ConsumerState<RateJobSheet> createState() => _RateJobSheetState();
}

class _RateJobSheetState extends ConsumerState<RateJobSheet> {
  final _noteController = TextEditingController();
  final Set<String> _selectedTags = {};

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  String get _artisanFirstName {
    final trimmed = widget.artisanFirstName.trim();
    return trimmed.isEmpty ? 'the artisan' : trimmed;
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final w = size.width;
    final h = size.height;
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final ratingState = ref.watch(jobRatingProvider);

    return Container(
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.vertical(top: Radius.circular(w * 0.041)),
      ),
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: h * 0.014),
            _DragHandle(w: w, h: h),
            SizedBox(height: h * 0.019),
            _SheetHeader(artisanFirstName: _artisanFirstName, w: w, h: h),
            SizedBox(height: h * 0.024),
            _StarRow(
              selectedStars: ratingState.selectedStars,
              onStarTap: (s) =>
                  ref.read(jobRatingProvider.notifier).selectStars(s),
              w: w,
            ),
            SizedBox(height: h * 0.024),
            _TagGrid(
              selectedTags: _selectedTags,
              onTagTap: (t) => setState(() {
                if (_selectedTags.contains(t)) {
                  _selectedTags.remove(t);
                } else {
                  _selectedTags.add(t);
                }
              }),
              w: w,
              h: h,
            ),
            SizedBox(height: h * 0.019),
            _NoteInput(
              controller: _noteController,
              artisanFirstName: _artisanFirstName,
              onChanged: (t) =>
                  ref.read(jobRatingProvider.notifier).updateReview(t),
              w: w,
              h: h,
            ),
            if (ratingState.errorMessage != null) ...[
              SizedBox(height: h * 0.014),
              _ErrorText(message: ratingState.errorMessage!, w: w),
            ],
            SizedBox(height: h * 0.024),
            _SubmitButton(
              isLoading: ratingState.isSubmitting,
              canSubmit: ratingState.canSubmit,
              onPressed: _handleSubmit,
              w: w,
              h: h,
            ),
            SizedBox(height: h * 0.014),
            _SkipLink(
              onTap: () => Navigator.of(context).pop(),
              w: w,
              h: h,
            ),
            SizedBox(height: h * 0.028),
          ],
        ),
      ),
    );
  }

  Future<void> _handleSubmit() async {
    final ok = await ref
        .read(jobRatingProvider.notifier)
        .submitRating(jobId: widget.jobId);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
      MyShopToast.show(context, message: 'Thanks for your feedback!');
    }
  }
}

// ── Drag Handle ───────────────────────────────────────────────────────────────

class _DragHandle extends StatelessWidget {
  final double w, h;
  const _DragHandle({required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: w * 0.103,
      height: h * 0.005,
      decoration: BoxDecoration(
        color: MyShopColors.divider,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

// ── Header ────────────────────────────────────────────────────────────────────

class _SheetHeader extends StatelessWidget {
  final String artisanFirstName;
  final double w, h;
  const _SheetHeader({
    required this.artisanFirstName,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: w * 0.041),
      child: Column(
        children: [
          Text(
            'Rate $artisanFirstName',
            style: TextStyle(
              fontSize: w * 0.051,
              fontWeight: FontWeight.w700,
              color: MyShopColors.textPrimary,
            ),
          ),
          SizedBox(height: h * 0.007),
          Text(
            'Your feedback is anonymous for 24 hours',
            style: TextStyle(
              fontSize: w * 0.033,
              fontWeight: FontWeight.w400,
              color: MyShopColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ── Star Row ──────────────────────────────────────────────────────────────────

class _StarRow extends StatelessWidget {
  final int selectedStars;
  final void Function(int) onStarTap;
  final double w;
  const _StarRow({
    required this.selectedStars,
    required this.onStarTap,
    required this.w,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(5, (i) {
        final starIndex = i + 1;
        final filled = starIndex <= selectedStars;
        return GestureDetector(
          onTap: () => onStarTap(starIndex),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: w * 0.018),
            child: Icon(
              filled ? Icons.star_rounded : Icons.star_border_rounded,
              size: w * 0.092,
              color: MyShopColors.primaryGold,
            ),
          ),
        );
      }),
    );
  }
}

// ── Tag Grid ──────────────────────────────────────────────────────────────────

class _TagGrid extends StatelessWidget {
  final Set<String> selectedTags;
  final void Function(String) onTagTap;
  final double w, h;
  const _TagGrid({
    required this.selectedTags,
    required this.onTagTap,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    final rows = [
      _jobRatingTags.sublist(0, 2),
      _jobRatingTags.sublist(2, 4),
    ];

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: w * 0.041),
      child: Column(
        children: rows
            .map(
              (rowTags) => Padding(
                padding: EdgeInsets.only(bottom: h * 0.009),
                child: Row(
                  children: [
                    Expanded(
                      child: _TagChip(
                        label: rowTags[0],
                        isSelected: selectedTags.contains(rowTags[0]),
                        onTap: () => onTagTap(rowTags[0]),
                        w: w,
                        h: h,
                      ),
                    ),
                    SizedBox(width: w * 0.021),
                    Expanded(
                      child: _TagChip(
                        label: rowTags[1],
                        isSelected: selectedTags.contains(rowTags[1]),
                        onTap: () => onTagTap(rowTags[1]),
                        w: w,
                        h: h,
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final double w, h;
  const _TagChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeInOut,
        height: h * 0.047,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected
              ? MyShopColors.primaryGoldLight
              : MyShopColors.surfaceWhite,
          border: Border.all(
            color: isSelected ? MyShopColors.primaryGold : MyShopColors.divider,
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(w * 0.051),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: w * 0.033,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            color: isSelected ? MyShopColors.primaryGold : MyShopColors.textPrimary,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

// ── Note Input ────────────────────────────────────────────────────────────────

class _NoteInput extends StatelessWidget {
  final TextEditingController controller;
  final String artisanFirstName;
  final void Function(String) onChanged;
  final double w, h;

  const _NoteInput({
    required this.controller,
    required this.artisanFirstName,
    required this.onChanged,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: w * 0.041),
      child: Container(
        constraints: BoxConstraints(minHeight: h * 0.107),
        decoration: BoxDecoration(
          border: Border.all(color: MyShopColors.divider),
          borderRadius: BorderRadius.circular(w * 0.021),
        ),
        child: TextField(
          controller: controller,
          onChanged: onChanged,
          maxLines: null,
          minLines: 3,
          style: TextStyle(
            fontSize: w * 0.033,
            fontWeight: FontWeight.w400,
            color: MyShopColors.textPrimary,
          ),
          decoration: InputDecoration(
            hintText: 'Write a note to $artisanFirstName (optional)...',
            hintStyle: TextStyle(
              fontSize: w * 0.033,
              fontWeight: FontWeight.w400,
              color: MyShopColors.disabled,
            ),
            border: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(
              horizontal: w * 0.038,
              vertical: h * 0.017,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Submit Button ─────────────────────────────────────────────────────────────

class _SubmitButton extends StatelessWidget {
  final bool isLoading;
  final bool canSubmit;
  final VoidCallback onPressed;
  final double w, h;
  const _SubmitButton({
    required this.isLoading,
    required this.canSubmit,
    required this.onPressed,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: w * 0.041),
      child: SizedBox(
        width: double.infinity,
        height: h * 0.062,
        child: ElevatedButton(
          onPressed: canSubmit ? onPressed : null,
          style: ElevatedButton.styleFrom(
            backgroundColor:
                canSubmit ? MyShopColors.darkSlate : MyShopColors.surfaceGrey,
            foregroundColor:
                canSubmit ? MyShopColors.surfaceWhite : MyShopColors.disabled,
            disabledBackgroundColor: MyShopColors.surfaceGrey,
            disabledForegroundColor: MyShopColors.disabled,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(w * 0.021),
            ),
          ),
          child: isLoading
              ? SizedBox(
                  width: w * 0.051,
                  height: w * 0.051,
                  child: const CircularProgressIndicator(
                    strokeWidth: 2,
                    color: MyShopColors.surfaceWhite,
                  ),
                )
              : Text(
                  'Submit Rating',
                  style: TextStyle(
                    fontSize: w * 0.036,
                    fontWeight: FontWeight.w600,
                    color: canSubmit
                        ? MyShopColors.surfaceWhite
                        : MyShopColors.disabled,
                    letterSpacing: 0.3,
                  ),
                ),
        ),
      ),
    );
  }
}

// ── Skip Link ─────────────────────────────────────────────────────────────────

class _SkipLink extends StatelessWidget {
  final VoidCallback onTap;
  final double w, h;
  const _SkipLink({required this.onTap, required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: EdgeInsets.symmetric(
          vertical: h * 0.009,
          horizontal: w * 0.041,
        ),
        child: Text(
          'No Thanks, just finish',
          style: TextStyle(
            fontSize: w * 0.033,
            fontWeight: FontWeight.w500,
            color: MyShopColors.textSecondary,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

// ── Inline error text ─────────────────────────────────────────────────────────

class _ErrorText extends StatelessWidget {
  final String message;
  final double w;
  const _ErrorText({required this.message, required this.w});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: w * 0.041),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.error_outline_rounded,
            size: w * 0.041,
            color: MyShopColors.error,
          ),
          SizedBox(width: w * 0.020),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: w * 0.031,
                fontWeight: FontWeight.w500,
                color: MyShopColors.error,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
