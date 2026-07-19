import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_ui/shared_ui.dart';

import '../models/vehicle_form_state.dart';

const vehicleSubmitFailureMessage =
    'Something went wrong while saving this vehicle. Please try again or contact support.';

class VehicleCategoryChoice {
  const VehicleCategoryChoice({
    required this.id,
    required this.name,
    required this.description,
  });

  final String id;
  final String name;
  final String description;
}

class VehicleFormBody extends StatefulWidget {
  const VehicleFormBody({
    super.key,
    required this.initialValue,
    required this.categories,
    required this.submitLabel,
    required this.onSubmit,
  });

  final VehicleFormState initialValue;
  final List<VehicleCategoryChoice> categories;
  final String submitLabel;
  final Future<String?> Function(VehicleFormState value) onSubmit;

  @override
  State<VehicleFormBody> createState() => _VehicleFormBodyState();
}

class _VehicleFormBodyState extends State<VehicleFormBody> {
  late final TextEditingController _makeController;
  late final TextEditingController _modelController;
  late final TextEditingController _yearController;
  late final TextEditingController _plateController;
  late final TextEditingController _colorController;
  late Set<String> _categoryIds;
  Map<String, String> _errors = const {};
  String? _submitError;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialValue;
    _makeController = TextEditingController(text: initial.make);
    _modelController = TextEditingController(text: initial.model);
    _yearController = TextEditingController(text: initial.year);
    _plateController = TextEditingController(text: initial.plate);
    _colorController = TextEditingController(text: initial.color);
    _categoryIds = Set<String>.from(initial.rideCategoryIds);
  }

  @override
  void dispose() {
    _makeController.dispose();
    _modelController.dispose();
    _yearController.dispose();
    _plateController.dispose();
    _colorController.dispose();
    super.dispose();
  }

  VehicleFormState get _draft => VehicleFormState(
        make: _makeController.text,
        model: _modelController.text,
        year: _yearController.text,
        plate: _plateController.text.trim().toUpperCase(),
        color: _colorController.text,
        rideCategoryIds: Set<String>.unmodifiable(_categoryIds),
      );

  void _clearError(String key) {
    if (!_errors.containsKey(key) && _submitError == null) return;
    setState(() {
      _errors = Map<String, String>.from(_errors)..remove(key);
      _submitError = null;
    });
  }

  Future<void> _submit() async {
    final draft = _draft;
    final errors = draft.validate();
    if (errors.isNotEmpty) {
      setState(() {
        _errors = errors;
        _submitError = null;
      });
      return;
    }

    setState(() {
      _submitting = true;
      _submitError = null;
    });
    String? error;
    try {
      error = await widget.onSubmit(draft);
    } catch (_) {
      // The API layer deliberately rejects malformed or newly incompatible
      // responses instead of treating them as a successful save. Keep that
      // strict behaviour, but recover the form so the driver is not trapped in
      // a permanent loading state.
      error = vehicleSubmitFailureMessage;
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
          _submitError = error;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(MyShopSpacing.md),
      children: [
        Text(
          'Vehicle details',
          style: MyShopTypography.h3,
        ),
        const SizedBox(height: MyShopSpacing.xs),
        Text(
          'Use the details printed on the vehicle records. The plate is checked across the platform.',
          style: MyShopTypography.body2,
        ),
        const SizedBox(height: MyShopSpacing.lg),
        MyShopTextField(
          controller: _makeController,
          label: 'Make',
          hint: 'e.g. Toyota',
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          errorText: _errors['make'],
          onChanged: (_) => _clearError('make'),
        ),
        const SizedBox(height: MyShopSpacing.md),
        MyShopTextField(
          controller: _modelController,
          label: 'Model',
          hint: 'e.g. Corolla',
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          errorText: _errors['model'],
          onChanged: (_) => _clearError('model'),
        ),
        const SizedBox(height: MyShopSpacing.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: MyShopTextField(
                controller: _yearController,
                label: 'Year',
                hint: '2024',
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                maxLength: 4,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                errorText: _errors['year'],
                onChanged: (_) => _clearError('year'),
              ),
            ),
            const SizedBox(width: MyShopSpacing.md),
            Expanded(
              child: MyShopTextField(
                controller: _colorController,
                label: 'Colour',
                hint: 'Silver',
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                errorText: _errors['color'],
                onChanged: (_) => _clearError('color'),
              ),
            ),
          ],
        ),
        const SizedBox(height: MyShopSpacing.md),
        MyShopTextField(
          controller: _plateController,
          label: 'Registration plate',
          hint: 'GR-1234-25',
          textCapitalization: TextCapitalization.characters,
          textInputAction: TextInputAction.done,
          maxLength: 32,
          errorText: _errors['plate'],
          onChanged: (_) => _clearError('plate'),
        ),
        const SizedBox(height: MyShopSpacing.lg),
        Text('Ride categories', style: MyShopTypography.h3),
        const SizedBox(height: MyShopSpacing.xs),
        Text(
          'Select every category this vehicle should serve. Each category is reviewed for this vehicle.',
          style: MyShopTypography.body2,
        ),
        const SizedBox(height: MyShopSpacing.sm),
        for (final category in widget.categories)
          Padding(
            padding: const EdgeInsets.only(bottom: MyShopSpacing.sm),
            child: _VehicleCategoryTile(
              category: category,
              selected: _categoryIds.contains(category.id),
              onChanged: (selected) {
                setState(() {
                  if (selected) {
                    _categoryIds.add(category.id);
                  } else {
                    _categoryIds.remove(category.id);
                  }
                  _errors = Map<String, String>.from(_errors)
                    ..remove('rideCategoryIds');
                  _submitError = null;
                });
              },
            ),
          ),
        if (_errors['rideCategoryIds'] case final categoryError?)
          Padding(
            padding: const EdgeInsets.only(bottom: MyShopSpacing.md),
            child: Text(
              categoryError,
              style: MyShopTypography.caption.copyWith(
                color: MyShopColors.error,
              ),
            ),
          ),
        if (_submitError case final submitError?) ...[
          Container(
            padding: const EdgeInsets.all(MyShopSpacing.md),
            decoration: BoxDecoration(
              color: MyShopColors.errorLight,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              submitError,
              style: MyShopTypography.body2.copyWith(
                color: MyShopColors.error,
              ),
            ),
          ),
          const SizedBox(height: MyShopSpacing.md),
        ],
        MyShopPrimaryButton(
          label: widget.submitLabel,
          onPressed: _submitting ? null : _submit,
          isLoading: _submitting,
        ),
        const SizedBox(height: MyShopSpacing.xxl),
      ],
    );
  }
}

class _VehicleCategoryTile extends StatelessWidget {
  const _VehicleCategoryTile({
    required this.category,
    required this.selected,
    required this.onChanged,
  });

  final VehicleCategoryChoice category;
  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      checked: selected,
      label: category.name,
      child: InkWell(
        onTap: () => onChanged(!selected),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.all(MyShopSpacing.md),
          decoration: BoxDecoration(
            color: selected
                ? MyShopColors.primaryGoldLight
                : MyShopColors.surfaceWhite,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? MyShopColors.primaryGold : MyShopColors.divider,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected ? Icons.check_circle : Icons.circle_outlined,
                color: selected
                    ? MyShopColors.primaryGold
                    : MyShopColors.textSecondary,
              ),
              const SizedBox(width: MyShopSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(category.name, style: MyShopTypography.body1),
                    if (category.description.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        category.description,
                        style: MyShopTypography.body2,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
