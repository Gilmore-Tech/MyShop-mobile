import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/job_form_provider.dart';
import '../providers/services_provider.dart';

// ── Design Tokens ─────────────────────────────────────────────────────────────
const _surfaceWhite  = Color(0xFFFFFFFF);
const _surfaceGrey   = Color(0xFFF3F5F6);
const _offWhite      = Color(0xFFF6F7F8);
const _textPrimary   = Color(0xFF161A1D);
const _textSecondary = Color(0xFF555E68);
const _textHint      = Color(0xFFBDBDBD);
const _gold          = Color(0xFFF5A623);
const _goldLight     = Color(0xFFFFF8EC);
const _darkSlate     = Color(0xFF46535D);
const _divider       = Color(0xFFE0E0E0);
const _disabled      = Color(0xFFBDBDBD);

// ── Screen ─────────────────────────────────────────────────────────────────────
// PRD 4.5 — Client creates an artisan job request.
// API: POST /v1/jobs (EDD § Marketplace Endpoints)

class JobFormScreen extends ConsumerStatefulWidget {
  /// Optional pre-selected category id + name (passed from CategoriesScreen).
  final String? initialCategoryId;
  final String? initialCategoryName;

  const JobFormScreen({
    super.key,
    this.initialCategoryId,
    this.initialCategoryName,
  });

  @override
  ConsumerState<JobFormScreen> createState() => _JobFormScreenState();
}

class _JobFormScreenState extends ConsumerState<JobFormScreen> {
  final _titleController       = TextEditingController();
  final _descriptionController = TextEditingController();
  final _destinationController = TextEditingController();
  final _landmarkController    = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Pre-fill category if navigated from CategoriesScreen
    if (widget.initialCategoryId != null && widget.initialCategoryName != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(jobFormProvider.notifier).selectCategory(
          widget.initialCategoryId!,
          widget.initialCategoryName!,
        );
      });
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _destinationController.dispose();
    _landmarkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final w    = size.width;
    final h    = size.height;
    final formState = ref.watch(jobFormProvider);

    return Scaffold(
      backgroundColor: _offWhite,
      body: Column(
        children: [
          _AppBar(w: w, h: h),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.only(
                bottom: h * 0.024, // breathing room above bottom nav
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(height: h * 0.019), // ~16dp
                  _SectionLabel(label: 'JOB DETAILS', w: w, h: h),
                  SizedBox(height: h * 0.010),
                  _FormCard(
                    w: w,
                    h: h,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _CategoryDropdown(w: w, h: h, formState: formState),
                        _FieldDivider(w: w),
                        _TitleField(
                          controller: _titleController,
                          w: w, h: h,
                          onChanged: (v) =>
                              ref.read(jobFormProvider.notifier).setTitle(v),
                        ),
                        _FieldDivider(w: w),
                        _DescriptionField(
                          controller: _descriptionController,
                          w: w, h: h,
                          onChanged: (v) =>
                              ref.read(jobFormProvider.notifier).setDescription(v),
                        ),
                        _FieldDivider(w: w),
                        _PhotoUploadField(
                          photoCount: formState.photoCount,
                          onTap: () =>
                              ref.read(jobFormProvider.notifier).incrementPhotos(),
                          w: w, h: h,
                        ),
                      ],
                    ),
                  ),

                  SizedBox(height: h * 0.019),
                  _SectionLabel(label: 'DESTINATION', w: w, h: h),
                  SizedBox(height: h * 0.010),
                  _FormCard(
                    w: w,
                    h: h,
                    child: Column(
                      children: [
                        _DestinationField(
                          controller: _destinationController,
                          w: w, h: h,
                          onChanged: (v) => ref
                              .read(jobFormProvider.notifier)
                              .setDestinationAddress(v),
                        ),
                        _FieldDivider(w: w),
                        _LandmarkField(
                          controller: _landmarkController,
                          w: w, h: h,
                          onChanged: (v) => ref
                              .read(jobFormProvider.notifier)
                              .setLandmarkNote(v),
                        ),
                      ],
                    ),
                  ),

                  SizedBox(height: h * 0.019),
                  _SectionLabel(label: 'SERVICE TIMING', w: w, h: h),
                  SizedBox(height: h * 0.010),
                  _TimingCard(
                    isImmediate:  formState.isImmediate,
                    scheduledFor: formState.scheduledFor,
                    onToggle: (v) =>
                        ref.read(jobFormProvider.notifier).setImmediate(v),
                    onScheduleChanged: (dt) =>
                        ref.read(jobFormProvider.notifier).setScheduledFor(dt),
                    w: w, h: h,
                  ),

                  SizedBox(height: h * 0.019),
                  _BidTimeInfoCard(w: w, h: h),
                  SizedBox(height: h * 0.012),
                  _SafetyInfoCard(w: w, h: h),
                  SizedBox(height: h * 0.024),
                  _SubmitButton(
                    formState: formState,
                    onPressed: () =>
                        ref.read(jobFormProvider.notifier).submit(),
                    w: w, h: h,
                  ),
                  SizedBox(height: h * 0.010),
                  _Disclaimer(w: w, h: h),
                  SizedBox(height: h * 0.012),
                ],
              ),
            ),
          ),
          _BottomNav(w: w, h: h),
        ],
      ),
    );
  }
}

// ── App Bar ────────────────────────────────────────────────────────────────────

class _AppBar extends StatelessWidget {
  final double w;
  final double h;
  const _AppBar({required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.paddingOf(context).top;
    return Container(
      color: _surfaceWhite,
      padding: EdgeInsets.only(
        top: topPad + h * 0.010,
        bottom: h * 0.019,
        left: w * 0.041,
        right: w * 0.041,
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).maybePop(),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: EdgeInsets.only(right: w * 0.031),
              child: Icon(
                Icons.arrow_back,
                size: w * 0.056,
                color: _textPrimary,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Create Request',
                  style: TextStyle(
                    fontSize: w * 0.051, // ~20dp
                    fontWeight: FontWeight.w700,
                    color: _textPrimary,
                    height: 1.2,
                  ),
                ),
                SizedBox(height: h * 0.004),
                Text(
                  'Find the best local artisans',
                  style: TextStyle(
                    fontSize: w * 0.031, // ~12dp
                    fontWeight: FontWeight.w400,
                    color: _textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Section Label ──────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  final double w;
  final double h;
  const _SectionLabel({required this.label, required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: w * 0.041),
      child: Text(
        label,
        style: TextStyle(
          fontSize: w * 0.028, // ~11dp
          fontWeight: FontWeight.w900,
          color: _textSecondary,
          letterSpacing: 1.4,
          height: 1.4,
        ),
      ),
    );
  }
}

// ── White form card wrapper ────────────────────────────────────────────────────

class _FormCard extends StatelessWidget {
  final Widget child;
  final double w;
  final double h;
  const _FormCard({required this.child, required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: w * 0.041),
      decoration: BoxDecoration(
        color: _surfaceWhite,
        borderRadius: BorderRadius.circular(w * 0.031), // ~12dp
        border: Border.all(color: _divider, width: 1),
      ),
      child: child,
    );
  }
}

// ── Thin divider between form rows ────────────────────────────────────────────

class _FieldDivider extends StatelessWidget {
  final double w;
  const _FieldDivider({required this.w});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: w * 0.041),
      child: const Divider(height: 1, thickness: 1, color: _divider),
    );
  }
}

// ── Field label row used inside cards ─────────────────────────────────────────

class _FieldLabel extends StatelessWidget {
  final String text;
  final double w;
  final double h;
  const _FieldLabel({required this.text, required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: w * 0.028,
        fontWeight: FontWeight.w700,
        color: _textSecondary,
        letterSpacing: 0.8,
      ),
    );
  }
}

// ── SERVICE CATEGORY dropdown ──────────────────────────────────────────────────

class _CategoryDropdown extends ConsumerWidget {
  final double w;
  final double h;
  final JobFormState formState;
  const _CategoryDropdown({
    required this.w,
    required this.h,
    required this.formState,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(serviceCategoriesProvider);

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: w * 0.041,
        vertical: h * 0.017,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FieldLabel(text: 'SERVICE CATEGORY', w: w, h: h),
          SizedBox(height: h * 0.010),
          categoriesAsync.when(
            loading: () => _CategorySkeleton(w: w, h: h),
            error: (_, __) => _CategorySkeleton(w: w, h: h),
            data: (categories) => _CategorySelector(
              categories: categories,
              selectedId: formState.selectedCategoryId,
              selectedName: formState.selectedCategoryName,
              onSelected: (id, name) =>
                  ref.read(jobFormProvider.notifier).selectCategory(id, name),
              w: w,
              h: h,
            ),
          ),
        ],
      ),
    );
  }
}

class _CategorySkeleton extends StatelessWidget {
  final double w;
  final double h;
  const _CategorySkeleton({required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: h * 0.054,
      decoration: BoxDecoration(
        color: _surfaceGrey,
        borderRadius: BorderRadius.circular(w * 0.021),
      ),
    );
  }
}

class _CategorySelector extends StatelessWidget {
  final List<ServiceCategory> categories;
  final String? selectedId;
  final String? selectedName;
  final void Function(String id, String name) onSelected;
  final double w;
  final double h;

  const _CategorySelector({
    required this.categories,
    required this.selectedId,
    required this.selectedName,
    required this.onSelected,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    final hasSelection = selectedId != null;
    return GestureDetector(
      onTap: () => _showCategorySheet(context),
      child: Container(
        height: h * 0.054, // ~46dp
        padding: EdgeInsets.symmetric(horizontal: w * 0.038),
        decoration: BoxDecoration(
          color: hasSelection ? _goldLight : _surfaceWhite,
          borderRadius: BorderRadius.circular(w * 0.021),
          border: Border.all(
            color: hasSelection ? _gold : _divider,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.grid_view_rounded,
              size: w * 0.046,
              color: hasSelection ? _gold : _textHint,
            ),
            SizedBox(width: w * 0.026),
            Expanded(
              child: Text(
                selectedName ?? 'Select a service category',
                style: TextStyle(
                  fontSize: w * 0.038,
                  fontWeight: hasSelection ? FontWeight.w600 : FontWeight.w400,
                  color: hasSelection ? _textPrimary : _textHint,
                ),
              ),
            ),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: w * 0.056,
              color: hasSelection ? _gold : _textSecondary,
            ),
          ],
        ),
      ),
    );
  }

  void _showCategorySheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CategorySheet(
        categories: categories,
        selectedId: selectedId,
        onSelected: onSelected,
        w: w,
        h: h,
      ),
    );
  }
}

class _CategorySheet extends StatelessWidget {
  final List<ServiceCategory> categories;
  final String? selectedId;
  final void Function(String id, String name) onSelected;
  final double w;
  final double h;

  const _CategorySheet({
    required this.categories,
    required this.selectedId,
    required this.onSelected,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _surfaceWhite,
        borderRadius: BorderRadius.vertical(top: Radius.circular(w * 0.041)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom + h * 0.028,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(height: h * 0.014),
          // Drag handle
          Container(
            width: w * 0.103,
            height: h * 0.005,
            decoration: BoxDecoration(
              color: _divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          SizedBox(height: h * 0.019),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: w * 0.041),
            child: Text(
              'Select Category',
              style: TextStyle(
                fontSize: w * 0.046,
                fontWeight: FontWeight.w700,
                color: _textPrimary,
              ),
            ),
          ),
          SizedBox(height: h * 0.014),
          const Divider(height: 1, color: _divider),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: categories.length,
            separatorBuilder: (_, __) =>
                const Divider(height: 1, color: _divider),
            itemBuilder: (_, i) {
              final cat = categories[i];
              final isSelected = cat.id == selectedId;
              return InkWell(
                onTap: () {
                  onSelected(cat.id, cat.name);
                  Navigator.of(context).pop();
                },
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: w * 0.041,
                    vertical: h * 0.017,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: w * 0.092,
                        height: w * 0.092,
                        decoration: BoxDecoration(
                          color: isSelected ? _goldLight : _surfaceGrey,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          cat.icon,
                          size: w * 0.046,
                          color: isSelected ? _gold : _textSecondary,
                        ),
                      ),
                      SizedBox(width: w * 0.038),
                      Expanded(
                        child: Text(
                          cat.name,
                          style: TextStyle(
                            fontSize: w * 0.038,
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: isSelected ? _textPrimary : _textSecondary,
                          ),
                        ),
                      ),
                      if (isSelected)
                        Icon(Icons.check_circle_rounded,
                            size: w * 0.056, color: _gold),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ── JOB TITLE field ───────────────────────────────────────────────────────────

class _TitleField extends StatelessWidget {
  final TextEditingController controller;
  final void Function(String) onChanged;
  final double w;
  final double h;
  const _TitleField({
    required this.controller,
    required this.onChanged,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: w * 0.041,
        vertical: h * 0.017,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FieldLabel(text: 'JOB TITLE', w: w, h: h),
          SizedBox(height: h * 0.010),
          TextField(
            controller: controller,
            onChanged: onChanged,
            style: TextStyle(
              fontSize: w * 0.038,
              fontWeight: FontWeight.w400,
              color: _textPrimary,
            ),
            decoration: InputDecoration(
              hintText: 'e.g. Fix electrical wiring in living room',
              hintStyle: TextStyle(
                fontSize: w * 0.036,
                fontWeight: FontWeight.w400,
                color: _textHint,
              ),
              contentPadding: EdgeInsets.symmetric(
                horizontal: w * 0.038,
                vertical: h * 0.015,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(w * 0.021),
                borderSide: const BorderSide(color: _divider),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(w * 0.021),
                borderSide: const BorderSide(color: _divider),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(w * 0.021),
                borderSide: const BorderSide(color: _gold, width: 1.5),
              ),
            ),
          ),
          SizedBox(height: h * 0.007),
          Text(
            'Be specific so artisans know exactly what you need',
            style: TextStyle(
              fontSize: w * 0.028,
              fontWeight: FontWeight.w400,
              color: _textHint,
            ),
          ),
        ],
      ),
    );
  }
}

// ── DESCRIPTION field ──────────────────────────────────────────────────────────

class _DescriptionField extends StatelessWidget {
  final TextEditingController controller;
  final void Function(String) onChanged;
  final double w;
  final double h;
  const _DescriptionField({
    required this.controller,
    required this.onChanged,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: w * 0.041,
        vertical: h * 0.017,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FieldLabel(text: 'DESCRIPTION', w: w, h: h),
          SizedBox(height: h * 0.010),
          TextField(
            controller: controller,
            onChanged: onChanged,
            maxLines: null,
            minLines: 3,
            style: TextStyle(
              fontSize: w * 0.038,
              fontWeight: FontWeight.w400,
              color: _textPrimary,
            ),
            decoration: InputDecoration(
              hintText:
                  'Describe the work in detail — materials needed, current state, etc.',
              hintStyle: TextStyle(
                fontSize: w * 0.036,
                fontWeight: FontWeight.w400,
                color: _textHint,
              ),
              contentPadding: EdgeInsets.symmetric(
                horizontal: w * 0.038,
                vertical: h * 0.015,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(w * 0.021),
                borderSide: const BorderSide(color: _divider),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(w * 0.021),
                borderSide: const BorderSide(color: _divider),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(w * 0.021),
                borderSide: const BorderSide(color: _gold, width: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── WORK SITE PHOTOS upload zone ───────────────────────────────────────────────

class _PhotoUploadField extends StatelessWidget {
  final int photoCount;
  final VoidCallback onTap;
  final double w;
  final double h;
  const _PhotoUploadField({
    required this.photoCount,
    required this.onTap,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: w * 0.041,
        vertical: h * 0.017,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _FieldLabel(text: 'WORK SITE PHOTOS', w: w, h: h),
              SizedBox(width: w * 0.015),
              Text(
                '(optional)',
                style: TextStyle(
                  fontSize: w * 0.028,
                  fontWeight: FontWeight.w400,
                  color: _textHint,
                ),
              ),
            ],
          ),
          SizedBox(height: h * 0.010),
          GestureDetector(
            onTap: onTap,
            child: Container(
              width: double.infinity,
              height: h * 0.119, // ~100dp
              decoration: BoxDecoration(
                color: _surfaceGrey,
                borderRadius: BorderRadius.circular(w * 0.021),
                border: Border.all(
                  color: _divider,
                  width: 1.5,
                  // dashed style via custom painter — approximated with strokeDashArray
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: w * 0.113,
                    height: w * 0.113,
                    decoration: const BoxDecoration(
                      color: _surfaceWhite,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.camera_alt_outlined,
                      size: w * 0.056,
                      color: _textSecondary,
                    ),
                  ),
                  SizedBox(height: h * 0.009),
                  Text(
                    photoCount > 0
                        ? '$photoCount photo${photoCount > 1 ? 's' : ''} added — tap to add more'
                        : 'Tap to add photos',
                    style: TextStyle(
                      fontSize: w * 0.033,
                      fontWeight: FontWeight.w500,
                      color: _textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: h * 0.007),
          Text(
            'Photos help artisans give more accurate bids',
            style: TextStyle(
              fontSize: w * 0.028,
              fontWeight: FontWeight.w400,
              color: _textHint,
            ),
          ),
        ],
      ),
    );
  }
}

// ── DESTINATION address field ──────────────────────────────────────────────────

class _DestinationField extends StatelessWidget {
  final TextEditingController controller;
  final void Function(String) onChanged;
  final double w;
  final double h;
  const _DestinationField({
    required this.controller,
    required this.onChanged,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: w * 0.041,
        vertical: h * 0.017,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FieldLabel(text: 'WORK LOCATION', w: w, h: h),
          SizedBox(height: h * 0.010),
          TextField(
            controller: controller,
            onChanged: onChanged,
            style: TextStyle(
              fontSize: w * 0.038,
              fontWeight: FontWeight.w400,
              color: _textPrimary,
            ),
            decoration: InputDecoration(
              hintText: 'Enter address or drop a pin',
              hintStyle: TextStyle(
                fontSize: w * 0.036,
                fontWeight: FontWeight.w400,
                color: _textHint,
              ),
              prefixIcon: Padding(
                padding: EdgeInsets.only(
                  left: w * 0.038,
                  right: w * 0.026,
                ),
                child: Icon(
                  Icons.location_on,
                  size: w * 0.051,
                  color: _gold,
                ),
              ),
              prefixIconConstraints: BoxConstraints(
                minWidth: w * 0.051 + w * 0.064,
                minHeight: 0,
              ),
              contentPadding: EdgeInsets.symmetric(
                vertical: h * 0.017,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(w * 0.021),
                borderSide: const BorderSide(color: _divider),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(w * 0.021),
                borderSide: const BorderSide(color: _divider),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(w * 0.021),
                borderSide: const BorderSide(color: _gold, width: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── LANDMARK field ─────────────────────────────────────────────────────────────

class _LandmarkField extends StatelessWidget {
  final TextEditingController controller;
  final void Function(String) onChanged;
  final double w;
  final double h;
  const _LandmarkField({
    required this.controller,
    required this.onChanged,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: w * 0.041,
        vertical: h * 0.017,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FieldLabel(text: 'LANDMARK / DIRECTIONS', w: w, h: h),
          SizedBox(height: h * 0.010),
          TextField(
            controller: controller,
            onChanged: onChanged,
            style: TextStyle(
              fontSize: w * 0.038,
              fontWeight: FontWeight.w400,
              color: _textPrimary,
            ),
            decoration: InputDecoration(
              hintText: 'e.g. Near Kejetia Market, blue gate',
              hintStyle: TextStyle(
                fontSize: w * 0.036,
                fontWeight: FontWeight.w400,
                color: _textHint,
              ),
              contentPadding: EdgeInsets.symmetric(
                horizontal: w * 0.038,
                vertical: h * 0.015,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(w * 0.021),
                borderSide: const BorderSide(color: _divider),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(w * 0.021),
                borderSide: const BorderSide(color: _divider),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(w * 0.021),
                borderSide: const BorderSide(color: _gold, width: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── SERVICE TIMING card ────────────────────────────────────────────────────────

class _TimingCard extends StatelessWidget {
  final bool                   isImmediate;
  final DateTime?              scheduledFor;
  final void Function(bool)    onToggle;
  final void Function(DateTime) onScheduleChanged;
  final double w;
  final double h;

  const _TimingCard({
    required this.isImmediate,
    required this.scheduledFor,
    required this.onToggle,
    required this.onScheduleChanged,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: w * 0.041),
      decoration: BoxDecoration(
        color:        _surfaceWhite,
        borderRadius: BorderRadius.circular(w * 0.031),
        border:       Border.all(color: _divider),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Header row ──────────────────────────────────────────────────────
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: w * 0.041,
              vertical:   h * 0.019,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Service Timing',
                        style: TextStyle(
                          fontSize:   w * 0.038,
                          fontWeight: FontWeight.w700,
                          color:      _textPrimary,
                        ),
                      ),
                      SizedBox(height: h * 0.004),
                      Text(
                        'When do you need the help?',
                        style: TextStyle(
                          fontSize:   w * 0.031,
                          fontWeight: FontWeight.w400,
                          color:      _textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: w * 0.026),
                _TimingToggle(
                  isImmediate: isImmediate,
                  onToggle:    onToggle,
                  w: w,
                  h: h,
                ),
              ],
            ),
          ),

          // ── Date + time pickers (Later only) ─────────────────────────────────
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve:    Curves.easeInOut,
            child: isImmediate
                ? const SizedBox.shrink()
                : Column(
                    children: [
                      Divider(height: 1, thickness: 1, color: _divider),
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: w * 0.041,
                          vertical:   h * 0.016,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: _PickerButton(
                                icon:  Icons.calendar_today_outlined,
                                label: _formatDate(scheduledFor),
                                onTap: () => _pickDate(context),
                                w: w,
                                h: h,
                              ),
                            ),
                            SizedBox(width: w * 0.031),
                            Expanded(
                              child: _PickerButton(
                                icon:  Icons.access_time_rounded,
                                label: _formatTime(scheduledFor),
                                onTap: () => _pickTime(context),
                                w: w,
                                h: h,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  String _formatDate(DateTime? dt) {
    if (dt == null) {
      final now = DateTime.now();
      return _isToday(now) ? 'Today' : _dateLabel(now);
    }
    return _isToday(dt) ? 'Today' : _dateLabel(dt);
  }

  String _formatTime(DateTime? dt) {
    if (dt == null) {
      final now = DateTime.now();
      return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    }
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  bool _isToday(DateTime dt) {
    final now = DateTime.now();
    return dt.year == now.year && dt.month == now.month && dt.day == now.day;
  }

  String _dateLabel(DateTime dt) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun',
                    'Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${dt.day} ${months[dt.month - 1]}';
  }

  Future<void> _pickDate(BuildContext context) async {
    final now  = DateTime.now();
    final base = scheduledFor ?? now;
    final picked = await showDatePicker(
      context:      context,
      initialDate:  base,
      firstDate:    now,
      lastDate:     now.add(const Duration(days: 30)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: _gold),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    final merged = DateTime(
      picked.year, picked.month, picked.day,
      base.hour, base.minute,
    );
    onScheduleChanged(merged);
  }

  Future<void> _pickTime(BuildContext context) async {
    final base = scheduledFor ?? DateTime.now();
    final picked = await showTimePicker(
      context:     context,
      initialTime: TimeOfDay(hour: base.hour, minute: base.minute),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: _gold),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    final merged = DateTime(
      base.year, base.month, base.day,
      picked.hour, picked.minute,
    );
    onScheduleChanged(merged);
  }
}

// ── Picker button ──────────────────────────────────────────────────────────────

class _PickerButton extends StatelessWidget {
  final IconData     icon;
  final String       label;
  final VoidCallback onTap;
  final double       w;
  final double       h;

  const _PickerButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: w * 0.036,
          vertical:   h * 0.014,
        ),
        decoration: BoxDecoration(
          color:        _surfaceGrey,
          borderRadius: BorderRadius.circular(w * 0.026),
          border:       Border.all(color: _divider),
        ),
        child: Row(
          children: [
            Icon(icon, size: w * 0.046, color: _textSecondary),
            SizedBox(width: w * 0.021),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize:   w * 0.036,
                  fontWeight: FontWeight.w500,
                  color:      _textPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(Icons.keyboard_arrow_down_rounded,
                size: w * 0.046, color: _textSecondary),
          ],
        ),
      ),
    );
  }
}

class _TimingToggle extends StatelessWidget {
  final bool isImmediate;
  final void Function(bool) onToggle;
  final double w;
  final double h;
  const _TimingToggle({
    required this.isImmediate,
    required this.onToggle,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: h * 0.038, // ~32dp
      decoration: BoxDecoration(
        color: _surfaceGrey,
        borderRadius: BorderRadius.circular(w * 0.051),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ToggleOption(
            label: 'Now',
            isSelected: isImmediate,
            onTap: () => onToggle(true),
            w: w,
            h: h,
          ),
          _ToggleOption(
            label: 'Later',
            isSelected: !isImmediate,
            onTap: () => onToggle(false),
            w: w,
            h: h,
          ),
        ],
      ),
    );
  }
}

class _ToggleOption extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final double w;
  final double h;
  const _ToggleOption({
    required this.label,
    required this.isSelected,
    required this.onTap,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeInOut,
        padding: EdgeInsets.symmetric(
          horizontal: w * 0.046,
          vertical: h * 0.005,
        ),
        decoration: BoxDecoration(
          color: isSelected ? _gold : Colors.transparent,
          borderRadius: BorderRadius.circular(w * 0.051),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: w * 0.033,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            color: isSelected ? _surfaceWhite : _textSecondary,
          ),
        ),
      ),
    );
  }
}

// ── Bid estimate info card ─────────────────────────────────────────────────────

class _BidTimeInfoCard extends StatelessWidget {
  final double w;
  final double h;
  const _BidTimeInfoCard({required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: w * 0.041),
      padding: EdgeInsets.symmetric(
        horizontal: w * 0.041,
        vertical: h * 0.017,
      ),
      decoration: BoxDecoration(
        color: _surfaceWhite,
        borderRadius: BorderRadius.circular(w * 0.031),
        border: Border.all(color: _divider),
      ),
      child: Row(
        children: [
          Icon(
            Icons.bolt_rounded,
            size: w * 0.056,
            color: _gold,
          ),
          SizedBox(width: w * 0.026),
          Expanded(
            child: RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: 'Est. time for first bid: ',
                    style: TextStyle(
                      fontSize: w * 0.033,
                      fontWeight: FontWeight.w400,
                      color: _textSecondary,
                    ),
                  ),
                  TextSpan(
                    text: '~5 mins',
                    style: TextStyle(
                      fontSize: w * 0.033,
                      fontWeight: FontWeight.w700,
                      color: _textPrimary,
                    ),
                  ),
                  TextSpan(
                    text: ' once posted',
                    style: TextStyle(
                      fontSize: w * 0.033,
                      fontWeight: FontWeight.w400,
                      color: _textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Safety / KYC info card ─────────────────────────────────────────────────────

class _SafetyInfoCard extends StatelessWidget {
  final double w;
  final double h;
  const _SafetyInfoCard({required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: w * 0.041),
      padding: EdgeInsets.symmetric(
        horizontal: w * 0.041,
        vertical: h * 0.017,
      ),
      decoration: BoxDecoration(
        color: _goldLight,
        borderRadius: BorderRadius.circular(w * 0.031),
        border: Border.all(color: _gold.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.verified_user_outlined,
            size: w * 0.051,
            color: _gold,
          ),
          SizedBox(width: w * 0.026),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Police Check & KYC Verified',
                  style: TextStyle(
                    fontSize: w * 0.036,
                    fontWeight: FontWeight.w700,
                    color: _textPrimary,
                  ),
                ),
                SizedBox(height: h * 0.004),
                Text(
                  'All artisans on MyShop are background-checked and identity-verified before being listed.',
                  style: TextStyle(
                    fontSize: w * 0.028,
                    fontWeight: FontWeight.w400,
                    color: _textSecondary,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Submit CTA ─────────────────────────────────────────────────────────────────

class _SubmitButton extends StatelessWidget {
  final JobFormState formState;
  final VoidCallback onPressed;
  final double w;
  final double h;
  const _SubmitButton({
    required this.formState,
    required this.onPressed,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    final canSubmit = formState.canSubmit;
    final label     = formState.isImmediate ? 'Post Job Now' : 'Post Job Later';

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: w * 0.041),
      child: SizedBox(
        width:  double.infinity,
        height: h * 0.068,
        child: ElevatedButton(
          onPressed: canSubmit ? onPressed : null,
          style: ElevatedButton.styleFrom(
            backgroundColor:         canSubmit ? _darkSlate : _surfaceGrey,
            disabledBackgroundColor: _surfaceGrey,
            elevation:   0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(w * 0.036),
            ),
          ),
          child: formState.isSubmitting
              ? SizedBox(
                  width:  w * 0.051,
                  height: w * 0.051,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: canSubmit ? _surfaceWhite : _disabled,
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize:   w * 0.044,
                        fontWeight: FontWeight.w700,
                        color:      canSubmit ? _surfaceWhite : _disabled,
                        letterSpacing: 0.2,
                      ),
                    ),
                    SizedBox(width: w * 0.026),
                    Icon(
                      Icons.add_circle_outline_rounded,
                      size:  w * 0.051,
                      color: canSubmit ? _surfaceWhite : _disabled,
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

// ── Disclaimer text ────────────────────────────────────────────────────────────

class _Disclaimer extends StatelessWidget {
  final double w;
  final double h;
  const _Disclaimer({required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: w * 0.082),
      child: Text(
        'By posting you agree to MyShop\'s Terms of Service. '
        'A 20% platform fee applies to the agreed job price.',
        style: TextStyle(
          fontSize: w * 0.028,
          fontWeight: FontWeight.w400,
          color: _textHint,
          height: 1.5,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

// ── Bottom Navigation ──────────────────────────────────────────────────────────

class _BottomNav extends StatelessWidget {
  final double w;
  final double h;
  const _BottomNav({required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.paddingOf(context).bottom;
    return Container(
      height: h * 0.071 + bottomPad,
      decoration: const BoxDecoration(
        color: _surfaceWhite,
        border: Border(top: BorderSide(color: _divider)),
      ),
      padding: EdgeInsets.only(bottom: bottomPad),
      child: Row(
        children: [
          _NavItem(icon: Icons.home_outlined, label: 'Home', isActive: false, w: w, h: h),
          _NavItem(icon: Icons.grid_view_rounded, label: 'Services', isActive: true, w: w, h: h),
          _NavItem(icon: Icons.history_rounded, label: 'Activity', isActive: false, w: w, h: h),
          _NavItem(icon: Icons.person_outline_rounded, label: 'Account', isActive: false, w: w, h: h),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final double w;
  final double h;
  const _NavItem({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    final color = isActive ? _gold : _darkSlate;
    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: w * 0.062, color: color),
          SizedBox(height: h * 0.004),
          Text(
            label,
            style: TextStyle(
              fontSize: w * 0.026,
              fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
