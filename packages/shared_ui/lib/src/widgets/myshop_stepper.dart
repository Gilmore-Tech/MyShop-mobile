import 'package:flutter/material.dart';

import '../theme/myshop_colors.dart';
import '../theme/myshop_spacing.dart';
import '../theme/myshop_typography.dart';

/// A single item in a [MyShopStepper].
class MyShopStepItem {
  const MyShopStepItem({required this.label, required this.icon});

  /// Short label shown under the step circle (e.g. "Profile").
  final String label;

  /// Icon rendered inside the circle when the step is upcoming or active.
  /// Completed steps always render a check mark.
  final IconData icon;
}

/// Horizontal progress indicator showing the user's position in a multi-step
/// flow. Steps before [currentIndex] render as completed (gold + check),
/// [currentIndex] renders as active (gold + halo), later steps render as
/// upcoming (grey). The visual matches the MyShop brand language.
class MyShopStepper extends StatelessWidget {
  const MyShopStepper({
    super.key,
    required this.steps,
    required this.currentIndex,
  }) : assert(steps.length > 0, 'MyShopStepper requires at least one step');

  final List<MyShopStepItem> steps;
  final int currentIndex;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: MyShopSpacing.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 44,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                for (var i = 0; i < steps.length; i++) ...[
                  _StepCircle(
                    icon: steps[i].icon,
                    state: _stateFor(i),
                  ),
                  if (i < steps.length - 1)
                    Expanded(child: _Connector(active: i < currentIndex)),
                ],
              ],
            ),
          ),
          const SizedBox(height: MyShopSpacing.sm),
          Row(
            children: [
              for (var i = 0; i < steps.length; i++) ...[
                Expanded(
                  child: Text(
                    steps[i].label,
                    textAlign: _labelAlignFor(i),
                    style: MyShopTypography.caption.copyWith(
                      color: i <= currentIndex
                          ? MyShopColors.textPrimary
                          : MyShopColors.textSecondary,
                      fontWeight:
                          i <= currentIndex ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  _StepState _stateFor(int i) {
    if (i < currentIndex) return _StepState.completed;
    if (i == currentIndex) return _StepState.active;
    return _StepState.upcoming;
  }

  TextAlign _labelAlignFor(int i) {
    if (i == 0) return TextAlign.left;
    if (i == steps.length - 1) return TextAlign.right;
    return TextAlign.center;
  }
}

enum _StepState { completed, active, upcoming }

class _StepCircle extends StatelessWidget {
  const _StepCircle({required this.icon, required this.state});

  final IconData icon;
  final _StepState state;

  @override
  Widget build(BuildContext context) {
    final Color fill;
    final Color iconColor;
    final Border? border;
    final List<BoxShadow>? shadow;
    final IconData glyph;

    switch (state) {
      case _StepState.completed:
        fill = MyShopColors.primaryGold;
        iconColor = MyShopColors.textOnPrimary;
        border = null;
        shadow = null;
        glyph = Icons.check_rounded;
        break;
      case _StepState.active:
        fill = MyShopColors.primaryGold;
        iconColor = MyShopColors.textOnPrimary;
        border = null;
        shadow = [
          BoxShadow(
            color: MyShopColors.primaryGold.withValues(alpha: 0.28),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ];
        glyph = icon;
        break;
      case _StepState.upcoming:
        fill = MyShopColors.surfaceGrey;
        iconColor = MyShopColors.textSecondary;
        border = Border.all(color: MyShopColors.divider);
        shadow = null;
        glyph = icon;
        break;
    }

    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: fill,
        shape: BoxShape.circle,
        border: border,
        boxShadow: shadow,
      ),
      child: Icon(glyph, size: 18, color: iconColor),
    );
  }
}

class _Connector extends StatelessWidget {
  const _Connector({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 2,
      margin: const EdgeInsets.symmetric(horizontal: MyShopSpacing.xs),
      color: active ? MyShopColors.primaryGold : MyShopColors.divider,
    );
  }
}
