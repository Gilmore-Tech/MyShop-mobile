import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_ui/shared_ui.dart';

import '../providers/registration_controller.dart';
import '../providers/ride_categories_provider.dart';
import 'registration_step_scaffold.dart';

/// Step 3 of driver registration — which ride categories the driver will serve.
///
/// Multi-select: a driver may opt into one or more tiers (e.g. Regular and
/// Comfort). Each selection is verified by an admin before the driver can be
/// matched for that tier. The chosen slugs ride along with POST /auth/register.
class DriverCategoriesStep extends ConsumerWidget {
  const DriverCategoriesStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(driverRegistrationProvider);
    final showAll = ref.watch(showRegistrationErrorsProvider);
    final options = ref.watch(rideCategoryOptionsProvider);

    void toggle(String slug) {
      final current = List<String>.from(draft.rideCategories);
      if (current.contains(slug)) {
        current.remove(slug);
      } else {
        current.add(slug);
      }
      ref
          .read(driverRegistrationProvider.notifier)
          .update(draft.copyWith(rideCategories: current));
    }

    return RegistrationStepCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Which ride categories will you serve?',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: MyShopSpacing.xs),
          Text(
            'Pick one or more. Each is verified by our team before you start '
            'receiving those requests.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: MyShopSpacing.md),
          options.when(
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
                      "Couldn't load ride categories. Check your connection.",
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  TextButton(
                    onPressed: () => ref.invalidate(rideCategoryOptionsProvider),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
            data: (cats) {
              if (cats.isEmpty) {
                return const Text('No ride categories are available right now.');
              }
              return Column(
                children: [
                  for (final c in cats)
                    Padding(
                      padding: const EdgeInsets.only(bottom: MyShopSpacing.sm),
                      child: _CategoryTile(
                        name: c.name,
                        description: c.description,
                        selected: draft.rideCategories.contains(c.slug),
                        onTap: () => toggle(c.slug),
                      ),
                    ),
                  if (showAll && draft.rideCategories.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: MyShopSpacing.xs),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Select at least one ride category',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: MyShopColors.error),
                        ),
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

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.name,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final String description;
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
              selected ? Icons.check_circle : Icons.circle_outlined,
              color: selected ? MyShopColors.primaryGold : MyShopColors.textSecondary,
            ),
            const SizedBox(width: MyShopSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: Theme.of(context).textTheme.titleSmall),
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
