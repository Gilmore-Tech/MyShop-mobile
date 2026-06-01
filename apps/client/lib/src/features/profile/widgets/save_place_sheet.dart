import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../core/di/providers.dart';
import '../../../core/services/google_places_service.dart';
import '../providers/saved_places_provider.dart';

// ── Public entry-point ────────────────────────────────────────────────────────

/// Bottom sheet to save a new place. Walks the user through:
///   1. Choosing a label (Home / Work / Gym / School / Other → custom).
///   2. Searching for a location via Google Places autocomplete.
///   3. Saving — the sheet resolves the suggestion to lat/lng and POSTs.
Future<void> showSavePlaceSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (_) => const _SavePlaceSheet(),
  );
}

// ── Quick-pick label options ──────────────────────────────────────────────────
// Order matters — first three drive the locationType the backend stores
// (home / work / favourite). 'Other' branches to a custom-label text field
// that maps to 'favourite' too.

class _LabelOption {
  final String label;
  final IconData icon;
  final String locationType;
  const _LabelOption(this.label, this.icon, this.locationType);
}

const _kLabelOptions = <_LabelOption>[
  _LabelOption('Home', Icons.home_outlined, 'home'),
  _LabelOption('Work', Icons.work_outline_rounded, 'work'),
  _LabelOption('Gym', Icons.fitness_center_outlined, 'favourite'),
  _LabelOption('School', Icons.school_outlined, 'favourite'),
  _LabelOption('Other', Icons.bookmark_outline_rounded, 'favourite'),
];

// ── Sheet root ────────────────────────────────────────────────────────────────

class _SavePlaceSheet extends ConsumerStatefulWidget {
  const _SavePlaceSheet();

  @override
  ConsumerState<_SavePlaceSheet> createState() => _SavePlaceSheetState();
}

class _SavePlaceSheetState extends ConsumerState<_SavePlaceSheet> {
  final _searchCtrl = TextEditingController();
  final _customLabelCtrl = TextEditingController();
  Timer? _debounce;

  _LabelOption? _selectedLabel;
  PlaceSuggestion? _selectedPlace;
  List<PlaceSuggestion> _suggestions = const [];
  bool _isSearching = false;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void dispose() {
    _searchCtrl.dispose();
    _customLabelCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  // ── Validation ──────────────────────────────────────────────────────────────

  String? get _resolvedLabel {
    final selected = _selectedLabel;
    if (selected == null) return null;
    if (selected.label == 'Other') {
      final custom = _customLabelCtrl.text.trim();
      return custom.isEmpty ? null : custom;
    }
    return selected.label;
  }

  bool get _canSave =>
      !_isSaving && _resolvedLabel != null && _selectedPlace != null;

  // ── Search ──────────────────────────────────────────────────────────────────

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    if (query.trim().isEmpty) {
      setState(() {
        _suggestions = const [];
        _isSearching = false;
      });
      return;
    }
    setState(() => _isSearching = true);
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      final places = ref.read(googlePlacesServiceProvider);
      final results = await places.autocomplete(query.trim());
      if (!mounted) return;
      setState(() {
        _suggestions = results;
        _isSearching = false;
      });
    });
  }

  void _selectSuggestion(PlaceSuggestion s) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _selectedPlace = s;
      _suggestions = const [];
      _searchCtrl.text = s.fullText;
      _errorMessage = null;
    });
  }

  void _clearSelectedPlace() {
    setState(() {
      _selectedPlace = null;
      _searchCtrl.clear();
    });
  }

  // ── Submit ──────────────────────────────────────────────────────────────────

  Future<void> _onSave() async {
    final label = _resolvedLabel;
    final place = _selectedPlace;
    final option = _selectedLabel;
    if (label == null || place == null || option == null) return;

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });
    final error = await ref.read(savedPlacesProvider.notifier).addPlace(
          label: label,
          locationType: option.locationType,
          suggestion: place,
        );
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _isSaving = false;
        _errorMessage = error;
      });
      return;
    }
    Navigator.of(context).pop();
    MyShopToast.show(context, message: 'Place saved');
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final w = size.width;
    final h = size.height;
    final inset = MediaQuery.viewInsetsOf(context).bottom;

    return Container(
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.vertical(top: Radius.circular(w * 0.041)),
      ),
      padding: EdgeInsets.only(bottom: inset),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: h * 0.014),
            _DragHandle(w: w, h: h),
            SizedBox(height: h * 0.019),
            _SheetHeader(title: 'Save a place', w: w, h: h),
            SizedBox(height: h * 0.024),

            // ── 1. Label picker ────────────────────────────────────────────
            _SectionLabel(text: 'WHAT IS THIS PLACE?', w: w, h: h),
            SizedBox(height: h * 0.012),
            _LabelChipGrid(
              options: _kLabelOptions,
              selected: _selectedLabel,
              onTap: (opt) => setState(() {
                _selectedLabel = opt;
                if (opt.label != 'Other') _customLabelCtrl.clear();
              }),
              w: w,
              h: h,
            ),
            if (_selectedLabel?.label == 'Other') ...[
              SizedBox(height: h * 0.014),
              _LabeledTextField(
                controller: _customLabelCtrl,
                hint: "e.g. Mom's House",
                onChanged: (_) => setState(() {}),
                w: w,
                h: h,
              ),
            ],

            SizedBox(height: h * 0.024),

            // ── 2. Location search ─────────────────────────────────────────
            _SectionLabel(text: 'PICK A LOCATION', w: w, h: h),
            SizedBox(height: h * 0.012),
            _SearchField(
              controller: _searchCtrl,
              onChanged: _onSearchChanged,
              hasSelection: _selectedPlace != null,
              onClear: _clearSelectedPlace,
              w: w,
              h: h,
            ),
            if (_selectedPlace == null && _isSearching)
              Padding(
                padding: EdgeInsets.symmetric(vertical: h * 0.014),
                child: const CircularProgressIndicator(
                  color: MyShopColors.primaryGold,
                  strokeWidth: 2,
                ),
              ),
            if (_selectedPlace == null && _suggestions.isNotEmpty) ...[
              SizedBox(height: h * 0.010),
              ..._suggestions.map(
                (s) => _SuggestionTile(
                  suggestion: s,
                  onTap: () => _selectSuggestion(s),
                  w: w,
                  h: h,
                ),
              ),
            ],

            // ── Error + Save ───────────────────────────────────────────────
            if (_errorMessage != null) ...[
              SizedBox(height: h * 0.014),
              _InlineError(message: _errorMessage!, w: w),
            ],
            SizedBox(height: h * 0.024),
            _SaveButton(
              isLoading: _isSaving,
              canSave: _canSave,
              onPressed: _onSave,
              w: w,
              h: h,
            ),
            SizedBox(height: h * 0.014),
            _SkipLink(
              onTap: () => Navigator.of(context).pop(),
              w: w,
              h: h,
            ),
            SizedBox(height: h * 0.028),
          ],
        ),
      ),
    );
  }
}

// ── Reusable bits ─────────────────────────────────────────────────────────────

class _DragHandle extends StatelessWidget {
  final double w, h;
  const _DragHandle({required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: w * 0.103,
      height: h * 0.005,
      decoration: BoxDecoration(
        color: MyShopColors.divider,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

class _SheetHeader extends StatelessWidget {
  final String title;
  final double w, h;
  const _SheetHeader({required this.title, required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: w * 0.041),
      child: Text(
        title,
        style: TextStyle(
          fontSize: w * 0.051,
          fontWeight: FontWeight.w700,
          color: MyShopColors.textPrimary,
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  final double w, h;
  const _SectionLabel({required this.text, required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: w * 0.041),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          style: TextStyle(
            fontSize: w * 0.026,
            fontWeight: FontWeight.w900,
            color: MyShopColors.textSecondary,
            letterSpacing: 0.8,
          ),
        ),
      ),
    );
  }
}

// ── Label chip grid ───────────────────────────────────────────────────────────

class _LabelChipGrid extends StatelessWidget {
  final List<_LabelOption> options;
  final _LabelOption? selected;
  final void Function(_LabelOption) onTap;
  final double w, h;

  const _LabelChipGrid({
    required this.options,
    required this.selected,
    required this.onTap,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: w * 0.041),
      child: Wrap(
        spacing: w * 0.021,
        runSpacing: h * 0.010,
        children: [
          for (final opt in options)
            _LabelChip(
              option: opt,
              isSelected: selected == opt,
              onTap: () => onTap(opt),
              w: w,
            ),
        ],
      ),
    );
  }
}

class _LabelChip extends StatelessWidget {
  final _LabelOption option;
  final bool isSelected;
  final VoidCallback onTap;
  final double w;

  const _LabelChip({
    required this.option,
    required this.isSelected,
    required this.onTap,
    required this.w,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.symmetric(
          horizontal: w * 0.038,
          vertical: w * 0.026,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? MyShopColors.primaryGoldLight
              : MyShopColors.surfaceWhite,
          borderRadius: BorderRadius.circular(w * 0.051),
          border: Border.all(
            color: isSelected ? MyShopColors.primaryGold : MyShopColors.divider,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              option.icon,
              size: w * 0.041,
              color: isSelected
                  ? MyShopColors.primaryGold
                  : MyShopColors.textSecondary,
            ),
            SizedBox(width: w * 0.015),
            Text(
              option.label,
              style: TextStyle(
                fontSize: w * 0.033,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected
                    ? MyShopColors.primaryGold
                    : MyShopColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Search input ──────────────────────────────────────────────────────────────

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final bool hasSelection;
  final VoidCallback onClear;
  final double w, h;

  const _SearchField({
    required this.controller,
    required this.onChanged,
    required this.hasSelection,
    required this.onClear,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: w * 0.041),
      child: Container(
        decoration: BoxDecoration(
          color: MyShopColors.surfaceGrey,
          borderRadius: BorderRadius.circular(w * 0.021),
          border: Border.all(
            color:
                hasSelection ? MyShopColors.primaryGold : MyShopColors.divider,
            width: 1.5,
          ),
        ),
        child: TextField(
          controller: controller,
          onChanged: onChanged,
          enabled: !hasSelection,
          style: TextStyle(
            fontSize: w * 0.036,
            color: MyShopColors.textPrimary,
          ),
          decoration: InputDecoration(
            hintText: 'Search address, building, area…',
            hintStyle: TextStyle(
              fontSize: w * 0.033,
              color: MyShopColors.textHint,
            ),
            prefixIcon: Icon(
              Icons.search_rounded,
              size: w * 0.051,
              color: MyShopColors.textSecondary,
            ),
            suffixIcon: hasSelection
                ? IconButton(
                    icon: Icon(
                      Icons.close_rounded,
                      size: w * 0.046,
                      color: MyShopColors.textSecondary,
                    ),
                    onPressed: onClear,
                  )
                : null,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            disabledBorder: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(
              horizontal: w * 0.020,
              vertical: h * 0.017,
            ),
          ),
        ),
      ),
    );
  }
}

class _LabeledTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final double w, h;
  const _LabeledTextField({
    required this.controller,
    required this.hint,
    required this.onChanged,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: w * 0.041),
      child: Container(
        decoration: BoxDecoration(
          color: MyShopColors.surfaceGrey,
          borderRadius: BorderRadius.circular(w * 0.021),
          border: Border.all(color: MyShopColors.divider, width: 1.5),
        ),
        child: TextField(
          controller: controller,
          onChanged: onChanged,
          autofocus: true,
          style: TextStyle(
            fontSize: w * 0.036,
            color: MyShopColors.textPrimary,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              fontSize: w * 0.033,
              color: MyShopColors.textHint,
            ),
            prefixIcon: Icon(
              Icons.bookmark_outline_rounded,
              size: w * 0.046,
              color: MyShopColors.textSecondary,
            ),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(
              horizontal: w * 0.020,
              vertical: h * 0.017,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Suggestion tile ───────────────────────────────────────────────────────────

class _SuggestionTile extends StatelessWidget {
  final PlaceSuggestion suggestion;
  final VoidCallback onTap;
  final double w, h;

  const _SuggestionTile({
    required this.suggestion,
    required this.onTap,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: w * 0.041,
          vertical: h * 0.014,
        ),
        child: Row(
          children: [
            Container(
              width: w * 0.092,
              height: w * 0.092,
              decoration: const BoxDecoration(
                color: MyShopColors.surfaceGrey,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.location_on_outlined,
                size: w * 0.046,
                color: MyShopColors.textSecondary,
              ),
            ),
            SizedBox(width: w * 0.031),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    suggestion.mainText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: w * 0.036,
                      fontWeight: FontWeight.w600,
                      color: MyShopColors.textPrimary,
                    ),
                  ),
                  SizedBox(height: h * 0.003),
                  Text(
                    suggestion.secondaryText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: w * 0.028,
                      color: MyShopColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Submit button ─────────────────────────────────────────────────────────────

class _SaveButton extends StatelessWidget {
  final bool isLoading;
  final bool canSave;
  final VoidCallback onPressed;
  final double w, h;

  const _SaveButton({
    required this.isLoading,
    required this.canSave,
    required this.onPressed,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: w * 0.041),
      child: SizedBox(
        width: double.infinity,
        height: h * 0.062,
        child: ElevatedButton(
          onPressed: canSave ? onPressed : null,
          style: ElevatedButton.styleFrom(
            backgroundColor:
                canSave ? MyShopColors.darkSlate : MyShopColors.surfaceGrey,
            foregroundColor:
                canSave ? MyShopColors.surfaceWhite : MyShopColors.disabled,
            disabledBackgroundColor: MyShopColors.surfaceGrey,
            disabledForegroundColor: MyShopColors.disabled,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(w * 0.021),
            ),
          ),
          child: isLoading
              ? SizedBox(
                  width: w * 0.051,
                  height: w * 0.051,
                  child: const CircularProgressIndicator(
                    strokeWidth: 2,
                    color: MyShopColors.surfaceWhite,
                  ),
                )
              : Text(
                  'Save Place',
                  style: TextStyle(
                    fontSize: w * 0.036,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
        ),
      ),
    );
  }
}

class _SkipLink extends StatelessWidget {
  final VoidCallback onTap;
  final double w, h;
  const _SkipLink({required this.onTap, required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: EdgeInsets.symmetric(
          vertical: h * 0.009,
          horizontal: w * 0.041,
        ),
        child: Text(
          'Cancel',
          style: TextStyle(
            fontSize: w * 0.033,
            fontWeight: FontWeight.w500,
            color: MyShopColors.textSecondary,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  final String message;
  final double w;
  const _InlineError({required this.message, required this.w});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: w * 0.041),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.error_outline_rounded,
            size: w * 0.041,
            color: MyShopColors.error,
          ),
          SizedBox(width: w * 0.020),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: w * 0.031,
                fontWeight: FontWeight.w500,
                color: MyShopColors.error,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
