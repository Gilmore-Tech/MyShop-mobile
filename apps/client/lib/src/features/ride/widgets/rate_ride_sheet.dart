import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/rate_ride_provider.dart';
import '../providers/ride_provider.dart';

// ── Public entry-point ────────────────────────────────────────────────────────

/// Shows the rating bottom sheet over [context].
/// Call from the parent screen's post-frame callback.
///
/// PRD 4.3 — client rates driver after ride completion.
/// API: POST /v1/ratings (EDD § Other REST Endpoints — blind 24h window).
Future<void> showRateRideSheet(BuildContext context, RideReceipt receipt) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (_) => RateRideSheet(receipt: receipt),
  );
}

// ── Sheet root ────────────────────────────────────────────────────────────────

class RateRideSheet extends ConsumerStatefulWidget {
  final RideReceipt receipt;
  const RateRideSheet({super.key, required this.receipt});

  @override
  ConsumerState<RateRideSheet> createState() => _RateRideSheetState();
}

class _RateRideSheetState extends ConsumerState<RateRideSheet> {
  final _noteController = TextEditingController();

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final w = size.width;
    final h = size.height;
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final ratingState = ref.watch(rideRatingProvider);

    return Container(
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(w * 0.041), // ~16dp
        ),
      ),
      // Shift content up when keyboard appears
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: h * 0.014), // ~12dp
            _DragHandle(w: w, h: h),
            SizedBox(height: h * 0.019), // ~16dp
            _SheetHeader(w: w, h: h),
            SizedBox(height: h * 0.024), // ~20dp
            _StarRow(
              selectedStars: ratingState.selectedStars,
              onStarTap: (s) =>
                  ref.read(rideRatingProvider.notifier).setStars(s),
              w: w,
            ),
            SizedBox(height: h * 0.024),
            _TagGrid(
              selectedTags: ratingState.selectedTags,
              onTagTap: (t) =>
                  ref.read(rideRatingProvider.notifier).toggleTag(t),
              w: w,
              h: h,
            ),
            SizedBox(height: h * 0.019),
            _NoteInput(
              controller: _noteController,
              driverFirstName: widget.receipt.driverFirstName,
              onChanged: (t) =>
                  ref.read(rideRatingProvider.notifier).setNote(t),
              w: w,
              h: h,
            ),
            SizedBox(height: h * 0.024),
            _SubmitButton(
              isLoading: ratingState.isSubmitting,
              canSubmit: ratingState.canSubmit,
              onPressed: () => _handleSubmit(ratingState),
              w: w,
              h: h,
            ),
            SizedBox(height: h * 0.014),
            _SkipLink(
              onTap: () => Navigator.of(context).pop(),
              w: w,
              h: h,
            ),
            SizedBox(height: h * 0.014),
            _SafetyDisclaimer(w: w),
            SizedBox(height: h * 0.028), // ~24dp safe bottom pad
          ],
        ),
      ),
    );
  }

  Future<void> _handleSubmit(RideRatingState state) async {
    await ref
        .read(rideRatingProvider.notifier)
        .submit(widget.receipt.rideId);
    if (mounted) {
      Navigator.of(context).pop();
      MyShopToast.show(context, message: 'Thanks for your feedback!');
    }
  }
}

// ── Drag Handle ───────────────────────────────────────────────────────────────

class _DragHandle extends StatelessWidget {
  final double w;
  final double h;
  const _DragHandle({required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: w * 0.103,  // ~40dp
      height: h * 0.005, // ~4dp
      decoration: BoxDecoration(
        color: MyShopColors.divider,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

// ── Header: title + anonymous-window subtitle ─────────────────────────────────

class _SheetHeader extends StatelessWidget {
  final double w;
  final double h;
  const _SheetHeader({required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: w * 0.041),
      child: Column(
        children: [
          Text(
            'Rate your Trip',
            style: TextStyle(
              fontSize: w * 0.051,       // ~20dp
              fontWeight: FontWeight.w700,
              color: MyShopColors.textPrimary,
            ),
          ),
          SizedBox(height: h * 0.007),   // ~6dp
          Text(
            'Your feedback is anonymous for 24 hours',
            style: TextStyle(
              fontSize: w * 0.033,       // ~13dp
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

// ── Interactive 5-star row ─────────────────────────────────────────────────────

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
            padding: EdgeInsets.symmetric(horizontal: w * 0.018), // ~7dp gap
            child: Icon(
              filled ? Icons.star_rounded : Icons.star_border_rounded,
              size: w * 0.092,  // ~36dp
              color: MyShopColors.primaryGold,
            ),
          ),
        );
      }),
    );
  }
}

// ── 2×2 multi-select tag grid ──────────────────────────────────────────────────

class _TagGrid extends StatelessWidget {
  final Set<String> selectedTags;
  final void Function(String) onTagTap;
  final double w;
  final double h;

  const _TagGrid({
    required this.selectedTags,
    required this.onTagTap,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    // Split the 4 tags into two rows of 2
    final rows = [
      rideRatingTags.sublist(0, 2),
      rideRatingTags.sublist(2, 4),
    ];

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: w * 0.041),
      child: Column(
        children: rows
            .map(
              (rowTags) => Padding(
                padding: EdgeInsets.only(bottom: h * 0.009), // ~8dp row gap
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
                    SizedBox(width: w * 0.021), // ~8dp column gap
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
  final double w;
  final double h;

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
        height: h * 0.047,   // ~40dp
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? MyShopColors.primaryGoldLight : MyShopColors.surfaceWhite,
          border: Border.all(
            color: isSelected ? MyShopColors.primaryGold : MyShopColors.divider,
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(w * 0.051), // pill
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: w * 0.033,  // ~13dp
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            color: isSelected ? MyShopColors.primaryGold : MyShopColors.textPrimary,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

// ── Optional note text-area ───────────────────────────────────────────────────

class _NoteInput extends StatelessWidget {
  final TextEditingController controller;
  final String driverFirstName;
  final void Function(String) onChanged;
  final double w;
  final double h;

  const _NoteInput({
    required this.controller,
    required this.driverFirstName,
    required this.onChanged,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: w * 0.041),
      child: Container(
        constraints: BoxConstraints(minHeight: h * 0.107), // ~90dp min
        decoration: BoxDecoration(
          border: Border.all(color: MyShopColors.divider),
          borderRadius: BorderRadius.circular(w * 0.021), // ~8dp
        ),
        child: TextField(
          controller: controller,
          onChanged: onChanged,
          maxLines: null, // expands naturally
          minLines: 3,
          style: TextStyle(
            fontSize: w * 0.033,
            fontWeight: FontWeight.w400,
            color: MyShopColors.textPrimary,
          ),
          decoration: InputDecoration(
            hintText: 'Write a note to $driverFirstName (optional)...',
            hintStyle: TextStyle(
              fontSize: w * 0.033,
              fontWeight: FontWeight.w400,
              color: MyShopColors.disabled,
            ),
            border: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(
              horizontal: w * 0.038, // ~15dp
              vertical: h * 0.017,   // ~14dp
            ),
          ),
        ),
      ),
    );
  }
}

// ── Submit button ─────────────────────────────────────────────────────────────

class _SubmitButton extends StatelessWidget {
  final bool isLoading;
  final bool canSubmit;
  final VoidCallback onPressed;
  final double w;
  final double h;

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
        height: h * 0.062,   // ~52dp
        child: ElevatedButton(
          onPressed: canSubmit ? onPressed : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: canSubmit ? MyShopColors.darkSlate : MyShopColors.surfaceGrey,
            foregroundColor: canSubmit ? MyShopColors.surfaceWhite : MyShopColors.disabled,
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
                    fontSize: w * 0.036,  // ~14dp
                    fontWeight: FontWeight.w600,
                    color: canSubmit ? MyShopColors.surfaceWhite : MyShopColors.disabled,
                    letterSpacing: 0.3,
                  ),
                ),
        ),
      ),
    );
  }
}

// ── Skip / dismiss link ───────────────────────────────────────────────────────

class _SkipLink extends StatelessWidget {
  final VoidCallback onTap;
  final double w;
  final double h;

  const _SkipLink({
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
        padding: EdgeInsets.symmetric(
          vertical: h * 0.009,   // ~8dp touch padding
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

// ── Safety disclaimer ─────────────────────────────────────────────────────────

class _SafetyDisclaimer extends StatelessWidget {
  final double w;
  const _SafetyDisclaimer({required this.w});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.shield_outlined,
          size: w * 0.036,   // ~14dp
          color: MyShopColors.textSecondary,
        ),
        SizedBox(width: w * 0.015),
        Text(
          'Police-monitored safety check complete',
          style: TextStyle(
            fontSize: w * 0.028,   // ~11dp
            fontWeight: FontWeight.w400,
            color: MyShopColors.textSecondary,
          ),
        ),
      ],
    );
  }
}
