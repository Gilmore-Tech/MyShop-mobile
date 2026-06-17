import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../auth/providers/auth_controller.dart';
import '../../profile/providers/loyalty_provider.dart';
import '../domain/loyalty_models.dart';
import '../providers/loyalty_redemption_providers.dart';

/// Opens the redeem-points bottom sheet for [bookingId]. Resolves with the
/// applied [LoyaltyRedemption] on success, or `null` if the client dismisses
/// the sheet without redeeming. On success the per-booking
/// [appliedRedemptionProvider] is already updated, so callers usually don't
/// need the return value — they can just watch that provider.
Future<LoyaltyRedemption?> showRedeemPointsSheet({
  required BuildContext context,
  required RedeemableBookingType bookingType,
  required String bookingId,
  required int farePesewas,
}) {
  return showModalBottomSheet<LoyaltyRedemption>(
    context: context,
    isScrollControlled: true,
    backgroundColor: MyShopColors.surfaceWhite,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => RedeemPointsSheet(
      bookingType: bookingType,
      bookingId: bookingId,
      farePesewas: farePesewas,
    ),
  );
}

/// Bottom sheet that lets a client spend loyalty points for a fare discount on
/// an active booking. Reusable across rides and artisan jobs — the only
/// difference is [bookingType].
class RedeemPointsSheet extends ConsumerStatefulWidget {
  const RedeemPointsSheet({
    super.key,
    required this.bookingType,
    required this.bookingId,
    required this.farePesewas,
  });

  final RedeemableBookingType bookingType;
  final String bookingId;
  final int farePesewas;

  @override
  ConsumerState<RedeemPointsSheet> createState() => _RedeemPointsSheetState();
}

class _RedeemPointsSheetState extends ConsumerState<RedeemPointsSheet> {
  int _points = 0;
  bool _submitting = false;
  String? _error;
  bool _seeded = false;

  /// Points worth one cedi at the current rate — the +/- stepper increment.
  int _step(LoyaltyRate rate) =>
      rate.pointPesewas <= 0 ? 1 : (100 ~/ rate.pointPesewas).clamp(1, 100);

  void _seed(int maxPoints) {
    if (_seeded) return;
    _seeded = true;
    // Default to the maximum redeemable so the saving is immediately visible.
    _points = maxPoints;
  }

  void _setPoints(int value, int maxPoints) {
    setState(() => _points = value.clamp(0, maxPoints));
  }

  Future<void> _confirm(LoyaltyRate rate, int balance) async {
    if (_points <= 0 || _submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final result = await ref.read(loyaltyRepositoryProvider).redeem(
            points: _points,
            bookingType: widget.bookingType,
            bookingId: widget.bookingId,
          );
      // Record the applied redemption for this booking so the fare card shows
      // the discount and disables the control (one per booking).
      ref.read(appliedRedemptionProvider(widget.bookingId).notifier).state =
          result;
      // Reconcile the balance app-wide: re-fetch /users/me so the wallet/home
      // and profile loyalty screen reflect the new balance. The backend also
      // auto-refunds on cancellation; the same refresh restores it later.
      unawaited(
          ref.read(clientAuthControllerProvider.notifier).refreshProfile());
      ref.invalidate(loyaltyProvider);
      if (mounted) Navigator.of(context).pop(result);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = redeemErrorMessage(e, balance: balance);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final balance = ref.watch(loyaltyBalanceProvider);
    final rateAsync = ref.watch(loyaltyRateProvider);

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            // Drag handle.
            Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: MyShopColors.divider,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(height: 16),
            rateAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(40),
                child: CircularProgressIndicator(
                  color: MyShopColors.primaryGold,
                ),
              ),
              error: (_, __) => _RateError(
                onRetry: () => ref.invalidate(loyaltyRateProvider),
              ),
              data: (rate) => _content(rate, balance),
            ),
          ],
        ),
      ),
    );
  }

  Widget _content(LoyaltyRate rate, int balance) {
    final maxPoints = rate.maxRedeemablePoints(widget.farePesewas, balance);
    _seed(maxPoints);
    // Keep the seeded value within bounds if the balance/fare changed.
    final points = _points.clamp(0, maxPoints);
    final previewPesewas = rate.previewDiscountPesewas(points);
    final maxDiscount = rate.maxDiscountPesewas(widget.farePesewas);
    final canConfirm = points > 0 && !_submitting;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.redeem_rounded,
                  color: MyShopColors.primaryGold, size: 22),
              const SizedBox(width: 8),
              Text(
                'Apply loyalty points',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: MyShopColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'You have $balance ${balance == 1 ? 'point' : 'points'}. '
            'Use up to $maxPoints here '
            '(max ${formatGhsFromPesewas(maxDiscount)} off, '
            '${rate.maxRedemptionPercent}% of fare).',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: MyShopColors.textSecondary,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 20),
          if (maxPoints <= 0)
            _TooFewPoints(rate: rate)
          else ...[
            _PointsControl(
              points: points,
              maxPoints: maxPoints,
              step: _step(rate),
              onChanged: (v) => _setPoints(v, maxPoints),
            ),
            const SizedBox(height: 16),
            _SavingPreview(discountPesewas: previewPesewas),
          ],
          if (_error != null) ...[
            const SizedBox(height: 14),
            _InlineError(message: _error!),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: canConfirm ? () => _confirm(rate, balance) : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: MyShopColors.primaryGold,
                disabledBackgroundColor: MyShopColors.disabled,
                foregroundColor: MyShopColors.textOnPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 0,
              ),
              child: _submitting
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: MyShopColors.textOnPrimary,
                      ),
                    )
                  : Text(
                      points > 0
                          ? 'Apply $points ${points == 1 ? 'point' : 'points'}'
                          : 'Apply points',
                      style: const TextStyle(
                        fontSize: 15,
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

// ── Points control (stepper + slider) ────────────────────────────────────────

class _PointsControl extends StatelessWidget {
  const _PointsControl({
    required this.points,
    required this.maxPoints,
    required this.step,
    required this.onChanged,
  });

  final int points;
  final int maxPoints;
  final int step;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _StepButton(
              icon: Icons.remove_rounded,
              semanticLabel: 'Decrease points',
              onTap: points > 0 ? () => onChanged(points - step) : null,
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$points',
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    color: MyShopColors.textPrimary,
                    height: 1.0,
                  ),
                ),
                const Text(
                  'points',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: MyShopColors.textSecondary,
                  ),
                ),
              ],
            ),
            _StepButton(
              icon: Icons.add_rounded,
              semanticLabel: 'Increase points',
              onTap: points < maxPoints ? () => onChanged(points + step) : null,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Semantics(
          slider: true,
          label: 'Loyalty points to redeem',
          value: '$points of $maxPoints points',
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: MyShopColors.primaryGold,
              inactiveTrackColor: MyShopColors.surfaceGrey,
              thumbColor: MyShopColors.primaryGold,
              overlayColor: MyShopColors.primaryGold.withValues(alpha: 0.15),
              trackHeight: 6,
            ),
            child: Slider(
              value: points.toDouble().clamp(0, maxPoints.toDouble()),
              max: maxPoints.toDouble(),
              min: 0,
              divisions: maxPoints > 0 ? maxPoints.clamp(1, 200) : null,
              onChanged: (v) => onChanged(v.round()),
            ),
          ),
        ),
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.semanticLabel,
    required this.onTap,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: semanticLabel,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: enabled
                ? MyShopColors.primaryGoldLight
                : MyShopColors.surfaceGrey,
            border: Border.all(
              color: enabled ? MyShopColors.primaryGold : MyShopColors.divider,
            ),
          ),
          child: Icon(
            icon,
            size: 22,
            color: enabled ? MyShopColors.primaryGold : MyShopColors.disabled,
          ),
        ),
      ),
    );
  }
}

// ── Saving preview ───────────────────────────────────────────────────────────

class _SavingPreview extends StatelessWidget {
  const _SavingPreview({required this.discountPesewas});

  final int discountPesewas;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: MyShopColors.successLight,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.savings_outlined,
              color: MyShopColors.success, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              "You'll save ${formatGhsFromPesewas(discountPesewas)}",
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: MyShopColors.success,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TooFewPoints extends StatelessWidget {
  const _TooFewPoints({required this.rate});

  final LoyaltyRate rate;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: MyShopColors.surfaceGrey,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Text(
        "You don't have enough points to apply a discount to this booking yet.",
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: MyShopColors.textSecondary,
          height: 1.45,
        ),
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: MyShopColors.errorLight,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded,
              color: MyShopColors.error, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 13,
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

class _RateError extends StatelessWidget {
  const _RateError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            "Couldn't load redemption details. Please try again.",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: MyShopColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
