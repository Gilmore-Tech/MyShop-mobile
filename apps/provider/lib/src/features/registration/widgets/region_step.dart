import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_ui/shared_ui.dart';

import '../providers/regions_provider.dart';
import '../providers/registration_controller.dart';
import 'registration_step_scaffold.dart';

/// Region step for the driver flow — wires the shared [_RegionStep] to the
/// driver registration draft.
class DriverRegionStep extends ConsumerWidget {
  const DriverRegionStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(driverRegistrationProvider);
    return _RegionStep(
      selectedRegionId: draft.regionId,
      onSelect: (id) {
        final latest = ref.read(driverRegistrationProvider);
        ref
            .read(driverRegistrationProvider.notifier)
            .update(latest.copyWith(regionId: id));
      },
    );
  }
}

/// Region step for the artisan flow — wires the shared [_RegionStep] to the
/// artisan registration draft.
class ArtisanRegionStep extends ConsumerWidget {
  const ArtisanRegionStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(artisanRegistrationProvider);
    return _RegionStep(
      selectedRegionId: draft.regionId,
      onSelect: (id) {
        final latest = ref.read(artisanRegistrationProvider);
        ref
            .read(artisanRegistrationProvider.notifier)
            .update(latest.copyWith(regionId: id));
      },
    );
  }
}

/// Home-region picker, shared by both provider signup flows.
///
/// Single-select. During the Ashanti pilot the list returns one region, which
/// this pre-selects (post-frame) so the step reads as a read-only confirmation
/// — but the same code handles N regions when the platform expands. If the
/// regions endpoint is unavailable, nothing is selected and signup proceeds
/// with no `regionId` (the backend defaults to the pilot region).
class _RegionStep extends ConsumerWidget {
  const _RegionStep({
    required this.selectedRegionId,
    required this.onSelect,
  });

  final String selectedRegionId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final regions = ref.watch(regionsProvider);

    return RegistrationStepCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Where will you operate?',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: MyShopSpacing.xs),
          Text(
            'Pick your home region. This scopes your account to the right '
            'local operations team.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: MyShopSpacing.md),
          regions.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(MyShopSpacing.lg),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.symmetric(vertical: MyShopSpacing.md),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      "Couldn't load regions. Check your connection.",
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  TextButton(
                    onPressed: () => ref.invalidate(regionsProvider),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
            data: (list) {
              if (list.isEmpty) {
                return const Text('No regions are available right now.');
              }
              // Pre-select the sole pilot region once it loads, without
              // clobbering an existing choice. Scheduled post-frame so we
              // never mutate provider state during a build.
              if (list.length == 1 && selectedRegionId.isEmpty) {
                final only = list.first.id;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  onSelect(only);
                });
              }
              return Column(
                children: [
                  for (final r in list)
                    Padding(
                      padding: const EdgeInsets.only(bottom: MyShopSpacing.sm),
                      child: _RegionTile(
                        name: r.name,
                        selected: selectedRegionId == r.id,
                        onTap: () => onSelect(r.id),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _RegionTile extends StatelessWidget {
  const _RegionTile({
    required this.name,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(MyShopSpacing.md),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? MyShopColors.primaryGold : MyShopColors.divider,
            width: selected ? 2 : 1,
          ),
          color: selected
              ? MyShopColors.primaryGold.withValues(alpha: 0.06)
              : MyShopColors.surfaceWhite,
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: selected
                  ? MyShopColors.primaryGold
                  : MyShopColors.textSecondary,
            ),
            const SizedBox(width: MyShopSpacing.md),
            Expanded(
              child: Text(name, style: Theme.of(context).textTheme.titleSmall),
            ),
          ],
        ),
      ),
    );
  }
}
