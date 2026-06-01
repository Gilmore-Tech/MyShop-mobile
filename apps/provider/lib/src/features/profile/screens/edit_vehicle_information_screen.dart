import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../auth/providers/auth_controller.dart';
import '../../auth/providers/current_user_provider.dart';
import '../../profile/providers/provider_type_provider.dart';

/// Edit Vehicle Information — driver-only screen.
///
/// Loads current vehicle data from the driver profile and saves changes
/// via PUT /users/me. Fields supported by the backend: make, model, year,
/// plate, colour. Specifications (body type, fuel, seats, service class) are
/// kept as local-only UI fields until the backend supports them.
class EditVehicleInformationScreen extends ConsumerStatefulWidget {
  const EditVehicleInformationScreen({super.key});

  @override
  ConsumerState<EditVehicleInformationScreen> createState() =>
      _EditVehicleInformationScreenState();
}

class _EditVehicleInformationScreenState
    extends ConsumerState<EditVehicleInformationScreen> {
  // Vehicle details
  late final TextEditingController _make;
  late final TextEditingController _model;
  late final TextEditingController _year;
  late final TextEditingController _plate;
  late final TextEditingController _colour;
  final _seats = TextEditingController(text: '4');

  // Categorical fields (local-only until backend supports them)
  String _bodyType = 'Sedan';
  String _fuelType = 'Petrol';
  String _serviceClass = 'Standard';

  static const _bodyOptions = ['Sedan', 'Hatchback', 'SUV', 'Pickup', 'Van'];
  static const _fuelOptions = ['Petrol', 'Diesel', 'Hybrid', 'Electric'];
  static const _classOptions = ['Standard', 'Comfort', 'XL', 'Premium'];

  bool _dirty = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final dp = ref.read(currentUserProvider)?.driverProfile;
    _make = TextEditingController(text: dp?.vehicleMake ?? '');
    _model = TextEditingController(text: dp?.vehicleModel ?? '');
    _year = TextEditingController(text: dp?.vehicleYear ?? '');
    _plate = TextEditingController(text: dp?.vehiclePlate ?? '');
    _colour = TextEditingController(text: dp?.vehicleColor ?? '');

    for (final c in [_make, _model, _year, _plate, _colour, _seats]) {
      c.addListener(_markDirty);
    }
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  @override
  void dispose() {
    _make.dispose();
    _model.dispose();
    _year.dispose();
    _plate.dispose();
    _colour.dispose();
    _seats.dispose();
    super.dispose();
  }

  String? _validate() {
    if (_make.text.trim().isEmpty) return 'Vehicle make is required.';
    if (_model.text.trim().isEmpty) return 'Vehicle model is required.';
    if (_year.text.trim().isEmpty) return 'Year is required.';
    if (_plate.text.trim().isEmpty) return 'Number plate is required.';
    final year = int.tryParse(_year.text.trim());
    if (year == null || year < 1990 || year > DateTime.now().year + 1) {
      return 'Enter a valid year.';
    }
    return null;
  }

  Future<void> _save() async {
    final validationError = _validate();
    if (validationError != null) {
      MyShopToast.show(context,
          message: validationError, type: ToastType.error);
      return;
    }

    setState(() => _isSaving = true);

    final error =
        await ref.read(authControllerProvider.notifier).updateDriverProfile(
              UpdateDriverProfileRequest(
                vehicleMake: _make.text.trim(),
                vehicleModel: _model.text.trim(),
                vehicleYear: _year.text.trim(),
                vehiclePlate: _plate.text.trim(),
                vehicleColor: _colour.text.trim(),
              ),
            );

    if (!mounted) return;
    setState(() {
      _isSaving = false;
      if (error == null) _dirty = false;
    });

    if (error != null) {
      MyShopToast.show(context, message: error, type: ToastType.error);
    } else {
      MyShopToast.show(context, message: 'Vehicle info updated');
      if (context.canPop()) context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final providerType = ref.watch(providerTypeProvider);
    // Guard: artisans should never reach this screen.
    if (providerType.isArtisan) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.go('/account');
      });
      return const SizedBox.shrink();
    }

    return Scaffold(
      backgroundColor: MyShopColors.surfaceWhite,
      body: SafeArea(
        child: Column(
          children: [
            _Header(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  MyShopSpacing.md,
                  MyShopSpacing.md,
                  MyShopSpacing.md,
                  MyShopSpacing.lg,
                ),
                children: [
                  _SectionCard(
                    icon: Icons.directions_car_outlined,
                    title: 'Vehicle Details',
                    subtitle:
                        'These details are shown to riders before pickup.',
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _LabelledField(
                              label: 'MAKE',
                              controller: _make,
                              enabled: !_isSaving,
                            ),
                          ),
                          const SizedBox(width: MyShopSpacing.sm),
                          Expanded(
                            child: _LabelledField(
                              label: 'MODEL',
                              controller: _model,
                              enabled: !_isSaving,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _LabelledField(
                              label: 'YEAR',
                              controller: _year,
                              keyboardType: TextInputType.number,
                              maxLength: 4,
                              digitsOnly: true,
                              enabled: !_isSaving,
                            ),
                          ),
                          const SizedBox(width: MyShopSpacing.sm),
                          Expanded(
                            child: _LabelledField(
                              label: 'COLOUR',
                              controller: _colour,
                              enabled: !_isSaving,
                            ),
                          ),
                        ],
                      ),
                      _LabelledField(
                        label: 'NUMBER PLATE',
                        controller: _plate,
                        textCapitalization: TextCapitalization.characters,
                        enabled: !_isSaving,
                      ),
                    ],
                  ),
                  const SizedBox(height: MyShopSpacing.md),
                  _SectionCard(
                    icon: Icons.tune,
                    title: 'Specifications',
                    subtitle: 'Used to match you with the right kind of trip.',
                    children: [
                      _DropdownField(
                        label: 'BODY TYPE',
                        value: _bodyType,
                        options: _bodyOptions,
                        enabled: !_isSaving,
                        onChanged: (v) {
                          setState(() {
                            _bodyType = v;
                            _dirty = true;
                          });
                        },
                      ),
                      _DropdownField(
                        label: 'FUEL TYPE',
                        value: _fuelType,
                        options: _fuelOptions,
                        enabled: !_isSaving,
                        onChanged: (v) {
                          setState(() {
                            _fuelType = v;
                            _dirty = true;
                          });
                        },
                      ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _LabelledField(
                              label: 'PASSENGER SEATS',
                              controller: _seats,
                              keyboardType: TextInputType.number,
                              maxLength: 2,
                              digitsOnly: true,
                              enabled: !_isSaving,
                            ),
                          ),
                          const SizedBox(width: MyShopSpacing.sm),
                          Expanded(
                            child: _DropdownField(
                              label: 'SERVICE CLASS',
                              value: _serviceClass,
                              options: _classOptions,
                              enabled: !_isSaving,
                              onChanged: (v) {
                                setState(() {
                                  _serviceClass = v;
                                  _dirty = true;
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: MyShopSpacing.md),
                  const _DocsRedirectNote(),
                  const SizedBox(height: MyShopSpacing.lg),
                ],
              ),
            ),
            _SaveFooter(
              enabled: _dirty && !_isSaving,
              isLoading: _isSaving,
              onTap: _save,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        MyShopSpacing.sm,
        MyShopSpacing.sm,
        MyShopSpacing.md,
        MyShopSpacing.md,
      ),
      decoration: const BoxDecoration(
        color: MyShopColors.surfaceWhite,
        border: Border(bottom: BorderSide(color: MyShopColors.divider)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: MyShopColors.textPrimary),
            onPressed: () => context.pop(),
          ),
          Text(
            'Vehicle Info',
            style: MyShopTypography.h1.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 18,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Section card
// ---------------------------------------------------------------------------

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(MyShopSpacing.md),
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MyShopColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: MyShopColors.textPrimary),
              const SizedBox(width: MyShopSpacing.sm),
              Text(
                title,
                style: MyShopTypography.h3.copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(subtitle, style: MyShopTypography.body2),
          const SizedBox(height: MyShopSpacing.md),
          ...children,
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Labelled field
// ---------------------------------------------------------------------------

class _LabelledField extends StatelessWidget {
  const _LabelledField({
    required this.label,
    required this.controller,
    this.keyboardType,
    this.maxLength,
    this.digitsOnly = false,
    this.textCapitalization = TextCapitalization.none,
    this.enabled = true,
  });

  final String label;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final int? maxLength;
  final bool digitsOnly;
  final TextCapitalization textCapitalization;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: MyShopSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: MyShopTypography.overline.copyWith(
              color: MyShopColors.textSecondary,
              fontWeight: FontWeight.w800,
              fontSize: 11,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: MyShopSpacing.md,
              vertical: 12,
            ),
            decoration: BoxDecoration(
              color: MyShopColors.offWhite,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: MyShopColors.divider),
            ),
            child: TextField(
              controller: controller,
              enabled: enabled,
              keyboardType: keyboardType,
              maxLength: maxLength,
              textCapitalization: textCapitalization,
              inputFormatters:
                  digitsOnly ? [FilteringTextInputFormatter.digitsOnly] : null,
              style: MyShopTypography.body1.copyWith(
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
              decoration: const InputDecoration(
                border: InputBorder.none,
                isDense: true,
                counterText: '',
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Dropdown field
// ---------------------------------------------------------------------------

class _DropdownField extends StatelessWidget {
  const _DropdownField({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.enabled = true,
  });

  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: MyShopSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: MyShopTypography.overline.copyWith(
              color: MyShopColors.textSecondary,
              fontWeight: FontWeight.w800,
              fontSize: 11,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: MyShopSpacing.md,
              vertical: 4,
            ),
            decoration: BoxDecoration(
              color: MyShopColors.offWhite,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: MyShopColors.divider),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: value,
                isExpanded: true,
                icon: const Icon(
                  Icons.keyboard_arrow_down,
                  color: MyShopColors.textSecondary,
                ),
                style: MyShopTypography.body1.copyWith(
                  color: MyShopColors.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
                items: [
                  for (final o in options)
                    DropdownMenuItem(value: o, child: Text(o)),
                ],
                onChanged: enabled
                    ? (v) {
                        if (v != null) onChanged(v);
                      }
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Docs redirect note
// ---------------------------------------------------------------------------

class _DocsRedirectNote extends StatelessWidget {
  const _DocsRedirectNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(MyShopSpacing.md),
      decoration: BoxDecoration(
        color: MyShopColors.offWhite,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline,
            size: 18,
            color: MyShopColors.textSecondary,
          ),
          const SizedBox(width: MyShopSpacing.sm),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: MyShopTypography.body2.copyWith(height: 1.5),
                children: [
                  const TextSpan(
                    text:
                        "Vehicle documents (driver's license, roadworthiness, insurance, Ghana Card) are managed in ",
                  ),
                  TextSpan(
                    text: 'Documents & Verification',
                    style: MyShopTypography.body2.copyWith(
                      color: MyShopColors.primaryGold,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const TextSpan(text: '.'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Save footer
// ---------------------------------------------------------------------------

class _SaveFooter extends StatelessWidget {
  const _SaveFooter({
    required this.enabled,
    required this.onTap,
    this.isLoading = false,
  });

  final bool enabled;
  final bool isLoading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        MyShopSpacing.md,
        MyShopSpacing.md,
        MyShopSpacing.md,
        MyShopSpacing.md + MediaQuery.of(context).padding.bottom * 0.2,
      ),
      decoration: const BoxDecoration(
        color: MyShopColors.surfaceWhite,
        border: Border(top: BorderSide(color: MyShopColors.divider)),
      ),
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          height: 56,
          width: double.infinity,
          decoration: BoxDecoration(
            color: enabled ? MyShopColors.darkSlate : MyShopColors.surfaceGrey,
            borderRadius: BorderRadius.circular(28),
          ),
          alignment: Alignment.center,
          child: isLoading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                )
              : Text(
                  'Save Changes',
                  style: MyShopTypography.button.copyWith(
                    color: enabled
                        ? MyShopColors.textOnDarkSlate
                        : MyShopColors.disabled,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
        ),
      ),
    );
  }
}
