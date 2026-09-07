import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_ui/shared_ui.dart';

import '../providers/provider_online_intent.dart';
import '../providers/provider_connection_recovery_provider.dart';

class AvailabilityRestoreNoticeBanner extends ConsumerWidget {
  const AvailabilityRestoreNoticeBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final persistentConnectionFailure =
        ref.watch(providerConnectionRecoveryProvider);
    final message = ref.watch(availabilityRestoreNoticeProvider) ??
        (persistentConnectionFailure
            ? 'Your connection is taking longer to recover. We’ll resume '
                'requests automatically when your connection and location are ready.'
            : null);
    if (message == null) return const SizedBox.shrink();

    return Container(
      key: const ValueKey('availability-restore-notice'),
      margin: const EdgeInsets.fromLTRB(
        MyShopSpacing.md,
        MyShopSpacing.sm,
        MyShopSpacing.md,
        0,
      ),
      padding: const EdgeInsets.all(MyShopSpacing.sm),
      decoration: BoxDecoration(
        color: MyShopColors.warningLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MyShopColors.warning),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline,
            color: MyShopColors.warning,
            size: 20,
          ),
          const SizedBox(width: MyShopSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: MyShopTypography.body2.copyWith(
                color: MyShopColors.textPrimary,
              ),
            ),
          ),
          IconButton(
            key: const ValueKey('dismiss-availability-restore-notice'),
            visualDensity: VisualDensity.compact,
            tooltip: 'Dismiss',
            onPressed: () {
              ref.read(availabilityRestoreNoticeProvider.notifier).state = null;
              ref
                  .read(providerConnectionRecoveryProvider.notifier)
                  .dismissNotice();
            },
            icon: const Icon(Icons.close, size: 18),
          ),
        ],
      ),
    );
  }
}
