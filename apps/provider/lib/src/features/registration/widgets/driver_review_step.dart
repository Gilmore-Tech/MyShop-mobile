import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_ui/shared_ui.dart';

import '../providers/regions_provider.dart';
import '../providers/registration_controller.dart';
import '../providers/ride_categories_provider.dart';
import 'review_section_card.dart';
import 'legal_acceptance_checklist.dart';
import '../../profile/providers/provider_type_provider.dart';

/// Step 3 of driver registration — review and confirm.
class DriverReviewStep extends ConsumerWidget {
  const DriverReviewStep({super.key, required this.onEditStep});

  final ValueChanged<int> onEditStep;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(driverRegistrationProvider);
    final vehicle = [
      draft.vehicleColor,
      draft.vehicleMake,
      draft.vehicleModel,
      if (draft.vehicleYear.isNotEmpty) '(${draft.vehicleYear})',
    ].where((s) => s.isNotEmpty).join(' ');

    // Resolve ride-category slugs to display names (falls back to the slug
    // until the options list loads).
    final rideCatOptions = ref.watch(rideCategoryOptionsProvider).valueOrNull;
    final rideCatNames = {
      for (final o in rideCatOptions ?? const []) o.slug: o.name,
    };
    final rideCategories =
        draft.rideCategories.map((s) => rideCatNames[s] ?? s).join(', ');

    // Resolve the home-region id to its display name.
    final regions = ref.watch(regionsProvider).valueOrNull ?? const [];
    var regionName = '';
    for (final r in regions) {
      if (r.id == draft.regionId) {
        regionName = r.name;
        break;
      }
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        MyShopSpacing.lg,
        0,
        MyShopSpacing.lg,
        MyShopSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(
                  color: MyShopColors.successLight,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_rounded,
                  color: MyShopColors.success,
                  size: 30,
                ),
              ),
              const SizedBox(width: MyShopSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Almost done!', style: MyShopTypography.h3),
                    const SizedBox(height: 2),
                    Text(
                      'Review your details and tap Create Account to continue.',
                      style: MyShopTypography.body2,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: MyShopSpacing.lg),
          ReviewSectionCard(
            icon: Icons.person_outline,
            title: 'Your profile',
            onEdit: () => onEditStep(0),
            rows: [
              ReviewRow(label: 'Full name', value: draft.fullName),
              ReviewRow(
                label: 'Email',
                value: draft.email.trim().isEmpty
                    ? 'Not provided'
                    : draft.email.trim(),
              ),
            ],
          ),
          const SizedBox(height: MyShopSpacing.md),
          ReviewSectionCard(
            icon: Icons.directions_car_outlined,
            title: 'Vehicle details',
            onEdit: () => onEditStep(1),
            rows: [
              ReviewRow(label: 'Vehicle', value: vehicle),
              ReviewRow(label: 'License plate', value: draft.vehiclePlate),
            ],
          ),
          const SizedBox(height: MyShopSpacing.md),
          ReviewSectionCard(
            icon: Icons.local_taxi_outlined,
            title: 'Ride categories',
            onEdit: () => onEditStep(2),
            rows: [
              ReviewRow(label: 'Categories', value: rideCategories),
            ],
          ),
          const SizedBox(height: MyShopSpacing.md),
          ReviewSectionCard(
            icon: Icons.location_on_outlined,
            title: 'Your region',
            onEdit: () => onEditStep(3),
            rows: [
              ReviewRow(label: 'Region', value: regionName),
            ],
          ),
          const SizedBox(height: MyShopSpacing.md),
          Container(
            padding: const EdgeInsets.all(MyShopSpacing.md),
            decoration: BoxDecoration(
              color: MyShopColors.primaryGoldLight,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: MyShopColors.primaryGold.withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  size: 18,
                  color: MyShopColors.primaryGoldDark,
                ),
                const SizedBox(width: MyShopSpacing.sm),
                Expanded(
                  child: Text(
                    'Next, we\'ll verify your phone number. After that, you can upload your driver\'s licence, roadworthiness certificate, and National ID from your profile.',
                    style: MyShopTypography.caption.copyWith(
                      color: MyShopColors.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: MyShopSpacing.md),
          const LegalAcceptanceChecklist(role: ProviderType.driver),
        ],
      ),
    );
  }
}
