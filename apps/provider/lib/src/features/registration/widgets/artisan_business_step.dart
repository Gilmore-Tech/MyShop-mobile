import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_ui/shared_ui.dart';

import '../providers/registration_controller.dart';
import 'registration_step_scaffold.dart';

/// Ordered list of artisan categories shown on the business step. Kept here
/// (rather than pulled from the PRD's 11-category master list) so the field
/// surface stays scoped to what today's payload supports.
const artisanCategories = <String>[
  'Plumbing',
  'Electrical',
  'Carpentry',
  'Painting',
  'Cleaning',
  'Masonry',
  'AC Repair',
  'Appliance Repair',
];

/// Step 2 of artisan registration — business details, services, radius.
class ArtisanBusinessStep extends ConsumerStatefulWidget {
  const ArtisanBusinessStep({super.key});

  @override
  ConsumerState<ArtisanBusinessStep> createState() =>
      _ArtisanBusinessStepState();
}

class _ArtisanBusinessStepState extends ConsumerState<ArtisanBusinessStep>
    with AutomaticKeepAliveClientMixin {
  late final TextEditingController _businessCtrl;
  late final TextEditingController _tradeCtrl;
  late final TextEditingController _experienceCtrl;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    final draft = ref.read(artisanRegistrationProvider);
    _businessCtrl = TextEditingController(text: draft.businessName);
    _tradeCtrl = TextEditingController(text: draft.tradeCategory);
    _experienceCtrl = TextEditingController(
      text: draft.yearsOfExperience == 0
          ? ''
          : draft.yearsOfExperience.toString(),
    );
  }

  @override
  void dispose() {
    _businessCtrl.dispose();
    _tradeCtrl.dispose();
    _experienceCtrl.dispose();
    super.dispose();
  }

  void _apply(
    ArtisanRegistrationDraft Function(ArtisanRegistrationDraft) update,
  ) {
    final notifier = ref.read(artisanRegistrationProvider.notifier);
    notifier.update(update(ref.read(artisanRegistrationProvider)));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final draft = ref.watch(artisanRegistrationProvider);

    return RegistrationStepCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MyShopTextField(
            label: 'Business name',
            hint: 'e.g. Abena\'s Plumbing Services',
            controller: _businessCtrl,
            onChanged: (v) => _apply((d) => d.copyWith(businessName: v)),
          ),
          const SizedBox(height: MyShopSpacing.md),
          MyShopTextField(
            label: 'Primary trade',
            hint: 'e.g. Plumber',
            controller: _tradeCtrl,
            onChanged: (v) => _apply((d) => d.copyWith(tradeCategory: v)),
          ),
          const SizedBox(height: MyShopSpacing.md),
          MyShopTextField(
            label: 'Years of experience',
            hint: '0',
            keyboardType: TextInputType.number,
            controller: _experienceCtrl,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(2),
            ],
            onChanged: (v) => _apply(
              (d) => d.copyWith(yearsOfExperience: int.tryParse(v) ?? 0),
            ),
          ),
          const SizedBox(height: MyShopSpacing.lg),
          Text('Services you offer', style: MyShopTypography.body1),
          const SizedBox(height: 2),
          Text(
            'Pick everything you can do well.',
            style: MyShopTypography.body2,
          ),
          const SizedBox(height: MyShopSpacing.sm),
          Wrap(
            spacing: MyShopSpacing.sm,
            runSpacing: MyShopSpacing.sm,
            children: artisanCategories.map((cat) {
              final selected = draft.serviceCategories.contains(cat);
              return FilterChip(
                label: Text(cat),
                selected: selected,
                showCheckmark: true,
                labelStyle: MyShopTypography.body2.copyWith(
                  color: selected
                      ? MyShopColors.primaryGoldDark
                      : MyShopColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
                backgroundColor: MyShopColors.surfaceWhite,
                selectedColor: MyShopColors.primaryGoldLight,
                checkmarkColor: MyShopColors.primaryGoldDark,
                side: BorderSide(
                  color: selected
                      ? MyShopColors.primaryGold
                      : MyShopColors.divider,
                ),
                onSelected: (v) {
                  final next = List<String>.from(draft.serviceCategories);
                  if (v) {
                    next.add(cat);
                  } else {
                    next.remove(cat);
                  }
                  _apply((d) => d.copyWith(serviceCategories: next));
                },
              );
            }).toList(),
          ),
          const SizedBox(height: MyShopSpacing.lg),
          Text('Service radius', style: MyShopTypography.body1),
          const SizedBox(height: 2),
          Text(
            'How far from your base will you travel? '
            '${draft.serviceRadiusKm.toStringAsFixed(0)} km',
            style: MyShopTypography.body2,
          ),
          Slider(
            value: draft.serviceRadiusKm,
            min: 1,
            max: 30,
            divisions: 29,
            activeColor: MyShopColors.primaryGold,
            inactiveColor: MyShopColors.divider,
            label: '${draft.serviceRadiusKm.toStringAsFixed(0)} km',
            onChanged: (v) => _apply((d) => d.copyWith(serviceRadiusKm: v)),
          ),
        ],
      ),
    );
  }
}
