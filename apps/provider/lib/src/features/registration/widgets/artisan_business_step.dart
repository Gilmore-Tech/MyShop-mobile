import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_ui/shared_ui.dart';

import '../providers/categories_provider.dart';
import '../providers/registration_controller.dart';
import 'registration_step_scaffold.dart';

/// Max number of service categories an artisan can pick at signup.
/// Keeps the bid pool focused on tradespeople who actually do the work
/// rather than artisans who tick every box. Server-side gates also enforce
/// this on the registration endpoint.
const kMaxArtisanCategories = 3;

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

  bool _businessTouched = false;
  bool _tradeTouched = false;
  bool _experienceTouched = false;

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

  String? _validateExperience(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null; // optional field
    final years = int.tryParse(trimmed);
    if (years == null) return 'Enter a number.';
    if (years < 0 || years > 60) return 'Must be between 0 and 60.';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final draft = ref.watch(artisanRegistrationProvider);
    final showAll = ref.watch(showRegistrationErrorsProvider);
    final categoriesAsync = ref.watch(categoriesProvider);

    return RegistrationStepCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MyShopTextField(
            label: 'Business name',
            hint: 'e.g. Abena\'s Plumbing Services',
            controller: _businessCtrl,
            errorText: (_businessTouched || showAll)
                ? Validators.required(_businessCtrl.text, 'Business name')
                : null,
            onChanged: (v) {
              _apply((d) => d.copyWith(businessName: v));
              if (_businessTouched || showAll) setState(() {});
            },
            onSubmitted: (_) => setState(() => _businessTouched = true),
          ),
          const SizedBox(height: MyShopSpacing.md),
          MyShopTextField(
            label: 'Primary trade',
            hint: 'e.g. Plumber',
            controller: _tradeCtrl,
            errorText: (_tradeTouched || showAll)
                ? Validators.required(_tradeCtrl.text, 'Primary trade')
                : null,
            onChanged: (v) {
              _apply((d) => d.copyWith(tradeCategory: v));
              if (_tradeTouched || showAll) setState(() {});
            },
            onSubmitted: (_) => setState(() => _tradeTouched = true),
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
            errorText: (_experienceTouched || showAll)
                ? _validateExperience(_experienceCtrl.text)
                : null,
            onChanged: (v) {
              _apply(
                (d) => d.copyWith(yearsOfExperience: int.tryParse(v) ?? 0),
              );
              if (_experienceTouched || showAll) setState(() {});
            },
            onSubmitted: (_) => setState(() => _experienceTouched = true),
          ),
          const SizedBox(height: MyShopSpacing.lg),
          Text('Services you offer', style: MyShopTypography.body1),
          const SizedBox(height: 2),
          Text(
            'Pick up to $kMaxArtisanCategories services you do best '
            '(${draft.serviceCategories.length}/$kMaxArtisanCategories selected).',
            style: MyShopTypography.body2,
          ),
          if (showAll && draft.serviceCategories.isEmpty) ...[
            const SizedBox(height: MyShopSpacing.xs),
            Text(
              'Select at least one service.',
              style:
                  MyShopTypography.caption.copyWith(color: MyShopColors.error),
            ),
          ],
          const SizedBox(height: MyShopSpacing.sm),
          categoriesAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: MyShopSpacing.lg),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
            error: (_, __) => Column(
              children: [
                Text(
                  'Could not load categories.',
                  style: MyShopTypography.body2
                      .copyWith(color: MyShopColors.error),
                ),
                const SizedBox(height: MyShopSpacing.sm),
                TextButton(
                  onPressed: () => ref.invalidate(categoriesProvider),
                  child: const Text('Retry'),
                ),
              ],
            ),
            data: (categories) => _CategoriesChips(
              categories: categories,
              selectedIds: draft.serviceCategories,
              showError: showAll && draft.serviceCategories.isEmpty,
              onChanged: (ids) =>
                  _apply((d) => d.copyWith(serviceCategories: ids)),
            ),
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

/// Renders category chips grouped by parent.
///
/// Top-level categories without children render as a single chip.
/// Categories with children (e.g. "Repairs") render as a section header
/// followed by chips for each subcategory.
class _CategoriesChips extends StatelessWidget {
  const _CategoriesChips({
    required this.categories,
    required this.selectedIds,
    required this.showError,
    required this.onChanged,
  });

  final List<ServiceCategory> categories;
  final List<String> selectedIds;
  final bool showError;
  final ValueChanged<List<String>> onChanged;

  bool get _atCap => selectedIds.length >= kMaxArtisanCategories;

  void _toggle(BuildContext context, String id) {
    final next = List<String>.from(selectedIds);
    if (next.contains(id)) {
      next.remove(id);
    } else {
      if (_atCap) {
        // Visual cap should already prevent this via disabled chips, but
        // guard the data path so an out-of-order tap never sneaks past it.
        MyShopToast.show(
          context,
          message:
              'You can pick up to $kMaxArtisanCategories services. '
              'Remove one to add another.',
          type: ToastType.warning,
        );
        return;
      }
      next.add(id);
    }
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final widgets = <Widget>[];

    for (final cat in categories) {
      if (cat.hasChildren) {
        // Group header + subcategory chips
        widgets.add(Padding(
          padding: const EdgeInsets.only(
            top: MyShopSpacing.md,
            bottom: MyShopSpacing.xs,
          ),
          child: Text(
            cat.name,
            style: MyShopTypography.overline,
          ),
        ));
        widgets.add(Wrap(
          spacing: MyShopSpacing.sm,
          runSpacing: MyShopSpacing.sm,
          children: cat.children
              .map((sub) => _chip(context, sub.id, sub.name))
              .toList(),
        ));
      } else {
        // Leaf category — collect for a single wrap
        widgets.add(_chip(context, cat.id, cat.name));
      }
    }

    // Separate top-level leaf chips from grouped sections.
    // Collect consecutive leaf chips into a single Wrap.
    final result = <Widget>[];
    var leafChips = <Widget>[];

    for (final w in widgets) {
      if (w is FilterChip) {
        leafChips.add(w);
      } else {
        if (leafChips.isNotEmpty) {
          result.add(Wrap(
            spacing: MyShopSpacing.sm,
            runSpacing: MyShopSpacing.sm,
            children: leafChips,
          ));
          leafChips = [];
        }
        result.add(w);
      }
    }
    if (leafChips.isNotEmpty) {
      result.add(Wrap(
        spacing: MyShopSpacing.sm,
        runSpacing: MyShopSpacing.sm,
        children: leafChips,
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: result,
    );
  }

  Widget _chip(BuildContext context, String id, String name) {
    final selected = selectedIds.contains(id);
    // Disabled = at the cap AND not yet selected. The user can always tap a
    // selected chip to deselect, even when at the cap.
    final disabled = _atCap && !selected;
    return FilterChip(
      label: Text(name),
      selected: selected,
      showCheckmark: true,
      labelStyle: MyShopTypography.body2.copyWith(
        color: selected
            ? MyShopColors.primaryGoldDark
            : disabled
                ? MyShopColors.textHint
                : MyShopColors.textPrimary,
        fontWeight: FontWeight.w600,
      ),
      backgroundColor: MyShopColors.surfaceWhite,
      disabledColor: MyShopColors.surfaceGrey,
      selectedColor: MyShopColors.primaryGoldLight,
      checkmarkColor: MyShopColors.primaryGoldDark,
      side: BorderSide(
        color: selected
            ? MyShopColors.primaryGold
            : disabled
                ? MyShopColors.divider
                : showError
                    ? MyShopColors.error
                    : MyShopColors.divider,
      ),
      onSelected: disabled ? null : (_) => _toggle(context, id),
    );
  }
}
