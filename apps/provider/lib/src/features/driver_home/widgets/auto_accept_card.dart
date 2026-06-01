import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_ui/shared_ui.dart';

/// Provider for the auto-accept toggle state.
final autoAcceptProvider = StateProvider<bool>((ref) => true);

/// Card with "Auto-accept Requests" toggle.
///
/// Figma: node 164:10429
/// - surfaceGrey bg, 16dp radius, 71dp height
/// - Zap icon in grey circle, title + subtitle, trailing Switch
class AutoAcceptCard extends ConsumerWidget {
  const AutoAcceptCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isEnabled = ref.watch(autoAcceptProvider);

    return Container(
      height: 71,
      padding: const EdgeInsets.symmetric(horizontal: MyShopSpacing.md),
      decoration: BoxDecoration(
        color: MyShopColors.offWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: MyShopColors.darkSlate.withValues(alpha: 0.1),
        ),
      ),
      child: Row(
        children: [
          // Icon container
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: MyShopColors.darkSlate.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.bolt,
              size: 20,
              color: MyShopColors.darkSlate,
            ),
          ),

          const SizedBox(width: MyShopSpacing.md),

          // Text
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Auto-accept Requests',
                  style: TextStyle(
                    fontFamily: 'Raleway',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: MyShopColors.textPrimary,
                    height: 1.43,
                  ),
                ),
                Text(
                  'Nearby orders added automatically',
                  style: TextStyle(
                    fontFamily: 'Raleway',
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                    color: MyShopColors.textSecondary,
                    height: 1.55,
                  ),
                ),
              ],
            ),
          ),

          // Switch
          Switch(
            value: isEnabled,
            onChanged: (value) =>
                ref.read(autoAcceptProvider.notifier).state = value,
            activeThumbColor: MyShopColors.success,
            activeTrackColor: MyShopColors.successLight,
          ),
        ],
      ),
    );
  }
}
