import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/categories_provider.dart';
import '../providers/registration_controller.dart';
import 'review_section_card.dart';

/// Step 3 of artisan registration — review and confirm.
class ArtisanReviewStep extends ConsumerWidget {
  const ArtisanReviewStep({super.key, required this.onEditStep});

  final ValueChanged<int> onEditStep;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(artisanRegistrationProvider);

    final allCategories = ref.watch(categoriesProvider).valueOrNull ?? [];
    final nameMap = <String, String>{};
    for (final cat in allCategories) {
      nameMap[cat.id] = cat.name;
      for (final sub in cat.children) {
        nameMap[sub.id] = sub.name;
      }
    }
    final services = draft.serviceCategories.isEmpty
        ? ''
        : draft.serviceCategories.map((id) => nameMap[id] ?? id).join(', ');
    final experience = draft.yearsOfExperience == 0
        ? 'Less than a year'
        : '${draft.yearsOfExperience} years';
    final radius = '${draft.serviceRadiusKm.toStringAsFixed(0)} km';

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
              ReviewRow(label: 'Email', value: draft.email),
              ReviewRow(label: 'Ghana Card', value: draft.ghanaCardNumber),
            ],
          ),
          const SizedBox(height: MyShopSpacing.md),
          ReviewSectionCard(
            icon: Icons.work_outline,
            title: 'Your business',
            onEdit: () => onEditStep(1),
            rows: [
              ReviewRow(label: 'Business', value: draft.businessName),
              ReviewRow(label: 'Primary trade', value: draft.tradeCategory),
              ReviewRow(label: 'Experience', value: experience),
              ReviewRow(label: 'Services', value: services),
              ReviewRow(label: 'Service radius', value: radius),
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
                    'Next, we\'ll verify your phone number. After that, you can upload your trade certificate, National ID, and portfolio photos from your profile.',
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
          _PolicyCheckbox(),
        ],
      ),
    );
  }
}

class _PolicyCheckbox extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accepted = ref.watch(policyAcceptedProvider);
    final showErrors = ref.watch(showRegistrationErrorsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () =>
              ref.read(policyAcceptedProvider.notifier).state = !accepted,
          borderRadius: BorderRadius.circular(8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: Checkbox(
                  value: accepted,
                  onChanged: (v) => ref
                      .read(policyAcceptedProvider.notifier)
                      .state = v ?? false,
                  activeColor: MyShopColors.primaryGold,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                  side: BorderSide(
                    color: (showErrors && !accepted)
                        ? MyShopColors.error
                        : MyShopColors.divider,
                    width: 1.5,
                  ),
                ),
              ),
              const SizedBox(width: MyShopSpacing.sm),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    style: MyShopTypography.caption.copyWith(
                      color: MyShopColors.textPrimary,
                      height: 1.4,
                    ),
                    children: [
                      const TextSpan(text: 'I agree to the '),
                      TextSpan(
                        text: 'Terms of Service',
                        style: const TextStyle(
                          color: MyShopColors.primaryGoldDark,
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.underline,
                        ),
                        recognizer: TapGestureRecognizer()
                          ..onTap = () => launchUrl(
                                Uri.parse('https://myshop.com.gh/terms'),
                                mode: LaunchMode.externalApplication,
                              ),
                      ),
                      const TextSpan(text: ' and '),
                      TextSpan(
                        text: 'Privacy Policy',
                        style: const TextStyle(
                          color: MyShopColors.primaryGoldDark,
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.underline,
                        ),
                        recognizer: TapGestureRecognizer()
                          ..onTap = () => launchUrl(
                                Uri.parse('https://myshop.com.gh/privacy'),
                                mode: LaunchMode.externalApplication,
                              ),
                      ),
                      const TextSpan(text: '.'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        if (showErrors && !accepted) ...[
          const SizedBox(height: MyShopSpacing.xs),
          Padding(
            padding: const EdgeInsets.only(left: 32),
            child: Text(
              'You must accept the terms to continue.',
              style: MyShopTypography.caption.copyWith(
                color: MyShopColors.error,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
