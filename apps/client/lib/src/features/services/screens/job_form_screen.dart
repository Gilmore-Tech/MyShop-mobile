import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/router.dart';
import '../../../app/widgets/app_bottom_nav.dart';
import '../../activity/providers/activity_provider.dart';
import '../providers/job_detail_provider.dart';
import '../providers/job_form_provider.dart';
import '../providers/services_provider.dart';

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
      backgroundColor: MyShopColors.offWhite,
      body: Column(
        children: [
          _AppBar(w: w, h: h),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.only(bottom: h * 0.024),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(height: h * 0.024),
                  _SectionHeading(
                    title: 'Job Details',
                    subtitle: 'What service do you need today?',
                    w: w,
                    h: h,
                  ),
                  SizedBox(height: h * 0.022),
                  _CategoryDropdown(w: w, h: h, formState: formState),
                  SizedBox(height: h * 0.022),
                  _TitleField(
                    controller: _titleController,
                    w: w, h: h,
                    onChanged: (v) =>
                        ref.read(jobFormProvider.notifier).setTitle(v),
                  ),
                  SizedBox(height: h * 0.022),
                  _DescriptionField(
                    controller: _descriptionController,
                    w: w, h: h,
                    onChanged: (v) =>
                        ref.read(jobFormProvider.notifier).setDescription(v),
                  ),
                  SizedBox(height: h * 0.022),
                  _PhotoUploadField(
                    photos:   formState.photoPaths,
                    onAdd:    (paths) =>
                        ref.read(jobFormProvider.notifier).addPhotos(paths),
                    onRemove: (index) => ref
                        .read(jobFormProvider.notifier)
                        .removePhotoAt(index),
                    w: w, h: h,
                  ),
                  SizedBox(height: h * 0.022),
                  _DestinationField(w: w, h: h),
                  SizedBox(height: h * 0.014),
                  _LandmarkField(
                    controller: _landmarkController,
                    w: w, h: h,
                    onChanged: (v) => ref
                        .read(jobFormProvider.notifier)
                        .setLandmarkNote(v),
                  ),
                  SizedBox(height: h * 0.022),
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
                  SizedBox(height: h * 0.014),
                  _SafetyInfoCard(w: w, h: h),
                  SizedBox(height: h * 0.024),
                  _SubmitButton(
                    formState: formState,
                    onPressed: () async {
                      final jobId = await ref
                          .read(jobFormProvider.notifier)
                          .submit();
                      if (jobId == null || !context.mounted) return;

                      // Drop any stale activity list + job-detail cache so
                      // the next watch re-fetches from the backend. Without
                      // this the user wouldn't see their newly posted job
                      // until a hot reload.
                      ref.invalidate(activityNotifierProvider);
                      ref.invalidate(jobDetailProvider(jobId));

                      context.pushReplacement(
                        AppRoutes.jobDetailPath(jobId),
                      );
                    },
                    w: w, h: h,
                  ),
                  SizedBox(height: h * 0.014),
                  _Disclaimer(w: w, h: h),
                  SizedBox(height: h * 0.014),
                ],
              ),
            ),
          ),
          AppBottomNav.routing(
            context:   context,
            activeTab: AppTab.services,
          ),
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
      decoration: const BoxDecoration(
        color: MyShopColors.surfaceWhite,
        border: Border(bottom: BorderSide(color: MyShopColors.divider)),
      ),
      padding: EdgeInsets.only(
        top: topPad + h * 0.012,
        bottom: h * 0.016,
        left: w * 0.041,
        right: w * 0.041,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).maybePop(),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: EdgeInsets.only(right: w * 0.031),
              child: Icon(
                Icons.arrow_back,
                size: w * 0.056,
                color: MyShopColors.textPrimary,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Create Request',
                  style: TextStyle(
                    fontSize:   w * 0.046,
                    fontWeight: FontWeight.w700,
                    color:      MyShopColors.textPrimary,
                    height:     1.2,
                  ),
                ),
                SizedBox(height: h * 0.004),
                Text(
                  'Find the best local artisans',
                  style: TextStyle(
                    fontSize:   w * 0.031,
                    fontWeight: FontWeight.w400,
                    color:      MyShopColors.textSecondary,
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

// ── Section Heading (top of form) ──────────────────────────────────────────────

class _SectionHeading extends StatelessWidget {
  final String title;
  final String subtitle;
  final double w;
  final double h;
  const _SectionHeading({
    required this.title,
    required this.subtitle,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: w * 0.041),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize:   w * 0.051, // ~20dp
              fontWeight: FontWeight.w700,
              color:      MyShopColors.textPrimary,
              height:     1.2,
            ),
          ),
          SizedBox(height: h * 0.005),
          Text(
            subtitle,
            style: TextStyle(
              fontSize:   w * 0.033,
              fontWeight: FontWeight.w400,
              color:      MyShopColors.textSecondary,
            ),
          ),
        ],
      ),
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
        color: MyShopColors.textSecondary,
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
      padding: EdgeInsets.symmetric(horizontal: w * 0.041),
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
        color: MyShopColors.surfaceGrey,
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
          color: hasSelection ? MyShopColors.primaryGoldLight : MyShopColors.surfaceWhite,
          borderRadius: BorderRadius.circular(w * 0.021),
          border: Border.all(
            color: hasSelection ? MyShopColors.primaryGold : MyShopColors.divider,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.grid_view_rounded,
              size: w * 0.046,
              color: hasSelection ? MyShopColors.primaryGold : MyShopColors.textHint,
            ),
            SizedBox(width: w * 0.026),
            Expanded(
              child: Text(
                selectedName ?? 'Select a service category',
                style: TextStyle(
                  fontSize: w * 0.038,
                  fontWeight: hasSelection ? FontWeight.w600 : FontWeight.w400,
                  color: hasSelection ? MyShopColors.textPrimary : MyShopColors.textHint,
                ),
              ),
            ),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: w * 0.056,
              color: hasSelection ? MyShopColors.primaryGold : MyShopColors.textSecondary,
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
        color: MyShopColors.surfaceWhite,
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
              color: MyShopColors.divider,
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
                color: MyShopColors.textPrimary,
              ),
            ),
          ),
          SizedBox(height: h * 0.014),
          const Divider(height: 1, color: MyShopColors.divider),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: categories.length,
            separatorBuilder: (_, __) =>
                const Divider(height: 1, color: MyShopColors.divider),
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
                          color: isSelected ? MyShopColors.primaryGoldLight : MyShopColors.surfaceGrey,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          cat.icon,
                          size: w * 0.046,
                          color: isSelected ? MyShopColors.primaryGold : MyShopColors.textSecondary,
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
                            color: isSelected ? MyShopColors.textPrimary : MyShopColors.textSecondary,
                          ),
                        ),
                      ),
                      if (isSelected)
                        Icon(Icons.check_circle_rounded,
                            size: w * 0.056, color: MyShopColors.primaryGold),
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
      padding: EdgeInsets.symmetric(horizontal: w * 0.041),
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
              color: MyShopColors.textPrimary,
            ),
            decoration: InputDecoration(
              hintText: 'e.g. Master Carpenter for Wardrobe',
              hintStyle: TextStyle(
                fontSize: w * 0.036,
                fontWeight: FontWeight.w400,
                color: MyShopColors.textHint,
              ),
              contentPadding: EdgeInsets.symmetric(
                horizontal: w * 0.038,
                vertical: h * 0.015,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(w * 0.021),
                borderSide: const BorderSide(color: MyShopColors.divider),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(w * 0.021),
                borderSide: const BorderSide(color: MyShopColors.divider),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(w * 0.021),
                borderSide: const BorderSide(color: MyShopColors.primaryGold, width: 1.5),
              ),
            ),
          ),
          SizedBox(height: h * 0.007),
          Text(
            'Be specific to get better bids',
            style: TextStyle(
              fontSize: w * 0.028,
              fontWeight: FontWeight.w400,
              color: MyShopColors.textHint,
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
      padding: EdgeInsets.symmetric(horizontal: w * 0.041),
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
              color: MyShopColors.textPrimary,
            ),
            decoration: InputDecoration(
              hintText: 'Describe your requirements in detail...',
              hintStyle: TextStyle(
                fontSize: w * 0.036,
                fontWeight: FontWeight.w400,
                color: MyShopColors.textHint,
              ),
              contentPadding: EdgeInsets.symmetric(
                horizontal: w * 0.038,
                vertical: h * 0.015,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(w * 0.021),
                borderSide: const BorderSide(color: MyShopColors.divider),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(w * 0.021),
                borderSide: const BorderSide(color: MyShopColors.divider),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(w * 0.021),
                borderSide: const BorderSide(color: MyShopColors.primaryGold, width: 1.5),
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
  final List<String>            photos;
  final void Function(List<String>) onAdd;
  final void Function(int)      onRemove;
  final double w;
  final double h;

  const _PhotoUploadField({
    required this.photos,
    required this.onAdd,
    required this.onRemove,
    required this.w,
    required this.h,
  });

  int  get _slotsLeft => kMaxJobPhotos - photos.length;
  bool get _canAdd    => _slotsLeft > 0;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: w * 0.041),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _FieldLabel(text: 'WORK SITE PHOTOS', w: w, h: h),
              SizedBox(width: w * 0.015),
              Text(
                '(Optional)',
                style: TextStyle(
                  fontSize:   w * 0.028,
                  fontWeight: FontWeight.w400,
                  color:      MyShopColors.textHint,
                ),
              ),
              const Spacer(),
              Text(
                '${photos.length}/$kMaxJobPhotos',
                style: TextStyle(
                  fontSize:   w * 0.028,
                  fontWeight: FontWeight.w500,
                  color:      MyShopColors.textSecondary,
                ),
              ),
            ],
          ),
          SizedBox(height: h * 0.010),
          if (photos.isEmpty)
            _EmptyUploadZone(
              onTap: () => _openPickerSheet(context),
              w: w, h: h,
            )
          else
            _PhotoGrid(
              photos:   photos,
              canAdd:   _canAdd,
              onAddTap: () => _openPickerSheet(context),
              onRemove: onRemove,
              w: w, h: h,
            ),
          SizedBox(height: h * 0.007),
          Text(
            'Upload up to $kMaxJobPhotos photos for a better bid',
            style: TextStyle(
              fontSize:   w * 0.028,
              fontWeight: FontWeight.w400,
              color:      MyShopColors.textHint,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openPickerSheet(BuildContext context) async {
    if (!_canAdd) return;
    final source = await showModalBottomSheet<_PhotoSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => _PhotoSourceSheet(w: w, h: h),
    );
    if (source == null || !context.mounted) return;
    final paths = await _pickPhotos(source);
    if (paths.isNotEmpty) onAdd(paths);
  }

  Future<List<String>> _pickPhotos(_PhotoSource source) async {
    final picker = ImagePicker();
    try {
      switch (source) {
        case _PhotoSource.camera:
          final shot = await picker.pickImage(
            source: ImageSource.camera,
            imageQuality: 80,
          );
          return shot == null ? const [] : [shot.path];
        case _PhotoSource.gallery:
          final shots = await picker.pickMultiImage(
            imageQuality: 80,
            limit: _slotsLeft,
          );
          return shots.take(_slotsLeft).map((x) => x.path).toList();
      }
    } catch (_) {
      return const [];
    }
  }
}

enum _PhotoSource { camera, gallery }

class _EmptyUploadZone extends StatelessWidget {
  final VoidCallback onTap;
  final double w;
  final double h;
  const _EmptyUploadZone({
    required this.onTap,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: CustomPaint(
        painter: _DashedBorderPainter(
          color: MyShopColors.divider,
          radius: w * 0.021,
          strokeWidth: 1.5,
          dashLength: w * 0.018,
          gapLength: w * 0.012,
        ),
        child: Container(
          width: double.infinity,
          height: h * 0.119,
          decoration: BoxDecoration(
            color: MyShopColors.surfaceWhite,
            borderRadius: BorderRadius.circular(w * 0.021),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.camera_alt_outlined,
                size:  w * 0.072,
                color: MyShopColors.textSecondary,
              ),
              SizedBox(height: h * 0.009),
              Text(
                'Upload images',
                style: TextStyle(
                  fontSize:   w * 0.036,
                  fontWeight: FontWeight.w500,
                  color:      MyShopColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhotoGrid extends StatelessWidget {
  final List<String>        photos;
  final bool                canAdd;
  final VoidCallback        onAddTap;
  final void Function(int)  onRemove;
  final double w;
  final double h;

  const _PhotoGrid({
    required this.photos,
    required this.canAdd,
    required this.onAddTap,
    required this.onRemove,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    const spacing = 8.0;
    // Fit up to 4 tiles across the available row width.
    final columns = kMaxJobPhotos;
    return LayoutBuilder(
      builder: (_, cons) {
        final tile = (cons.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing:     spacing,
          runSpacing:  spacing,
          children: [
            for (var i = 0; i < photos.length; i++)
              _PhotoTile(
                path:  photos[i],
                size:  tile,
                onRemove: () => onRemove(i),
                w: w,
              ),
            if (canAdd)
              _AddMoreTile(
                size:  tile,
                onTap: onAddTap,
                w:     w,
              ),
          ],
        );
      },
    );
  }
}

class _PhotoTile extends StatelessWidget {
  final String       path;
  final double       size;
  final VoidCallback onRemove;
  final double       w;

  const _PhotoTile({
    required this.path,
    required this.size,
    required this.onRemove,
    required this.w,
  });

  @override
  Widget build(BuildContext context) {
    final radius = w * 0.021;
    return SizedBox(
      width:  size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: Image.file(
              File(path),
              width:  size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                color: MyShopColors.surfaceGrey,
                alignment: Alignment.center,
                child: Icon(
                  Icons.broken_image_outlined,
                  size:  w * 0.056,
                  color: MyShopColors.textHint,
                ),
              ),
            ),
          ),
          Positioned(
            top:   -w * 0.015,
            right: -w * 0.015,
            child: GestureDetector(
              onTap: onRemove,
              behavior: HitTestBehavior.opaque,
              child: Container(
                width:  w * 0.056,
                height: w * 0.056,
                decoration: const BoxDecoration(
                  color: MyShopColors.textPrimary,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.close_rounded,
                  size:  w * 0.038,
                  color: MyShopColors.surfaceWhite,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddMoreTile extends StatelessWidget {
  final double       size;
  final VoidCallback onTap;
  final double       w;

  const _AddMoreTile({
    required this.size,
    required this.onTap,
    required this.w,
  });

  @override
  Widget build(BuildContext context) {
    final radius = w * 0.021;
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width:  size,
        height: size,
        child: CustomPaint(
          painter: _DashedBorderPainter(
            color: MyShopColors.divider,
            radius: radius,
            strokeWidth: 1.5,
            dashLength: w * 0.018,
            gapLength:  w * 0.012,
          ),
          child: Container(
            decoration: BoxDecoration(
              color:        MyShopColors.surfaceWhite,
              borderRadius: BorderRadius.circular(radius),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.add_rounded,
              size:  w * 0.062,
              color: MyShopColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _PhotoSourceSheet extends StatelessWidget {
  final double w;
  final double h;
  const _PhotoSourceSheet({required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.vertical(top: Radius.circular(w * 0.041)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom + h * 0.024,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(height: h * 0.014),
          Container(
            width: w * 0.103,
            height: h * 0.005,
            decoration: BoxDecoration(
              color: MyShopColors.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          SizedBox(height: h * 0.019),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: w * 0.041),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Add photos',
                style: TextStyle(
                  fontSize:   w * 0.046,
                  fontWeight: FontWeight.w700,
                  color:      MyShopColors.textPrimary,
                ),
              ),
            ),
          ),
          SizedBox(height: h * 0.014),
          const Divider(height: 1, color: MyShopColors.divider),
          _PhotoSourceTile(
            icon:  Icons.camera_alt_outlined,
            label: 'Take photo',
            onTap: () => Navigator.of(context).pop(_PhotoSource.camera),
            w: w, h: h,
          ),
          const Divider(height: 1, color: MyShopColors.divider),
          _PhotoSourceTile(
            icon:  Icons.photo_library_outlined,
            label: 'Choose from gallery',
            onTap: () => Navigator.of(context).pop(_PhotoSource.gallery),
            w: w, h: h,
          ),
        ],
      ),
    );
  }
}

class _PhotoSourceTile extends StatelessWidget {
  final IconData     icon;
  final String       label;
  final VoidCallback onTap;
  final double       w;
  final double       h;

  const _PhotoSourceTile({
    required this.icon,
    required this.label,
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
          vertical:   h * 0.019,
        ),
        child: Row(
          children: [
            Container(
              width:  w * 0.092,
              height: w * 0.092,
              decoration: const BoxDecoration(
                color: MyShopColors.surfaceGrey,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size:  w * 0.046,
                color: MyShopColors.textSecondary,
              ),
            ),
            SizedBox(width: w * 0.038),
            Text(
              label,
              style: TextStyle(
                fontSize:   w * 0.038,
                fontWeight: FontWeight.w500,
                color:      MyShopColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── DESTINATION address field (tappable — opens location search) ──────────────

class _DestinationField extends ConsumerWidget {
  final double w;
  final double h;
  const _DestinationField({
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final formState = ref.watch(jobFormProvider);
    final hasLocation = formState.destinationAddress.isNotEmpty &&
        formState.latitude != null;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: w * 0.041),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FieldLabel(text: 'DESTINATION', w: w, h: h),
          SizedBox(height: h * 0.010),
          GestureDetector(
            onTap: () => context.push('/services/job/location'),
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(
                horizontal: w * 0.038,
                vertical: h * 0.017,
              ),
              decoration: BoxDecoration(
                color: MyShopColors.surfaceWhite,
                borderRadius: BorderRadius.circular(w * 0.021),
                border: Border.all(
                  color: hasLocation
                      ? MyShopColors.primaryGold
                      : MyShopColors.divider,
                  width: hasLocation ? 1.5 : 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.location_on,
                    size: w * 0.051,
                    color: hasLocation
                        ? MyShopColors.primaryGold
                        : MyShopColors.textHint,
                  ),
                  SizedBox(width: w * 0.026),
                  Expanded(
                    child: Text(
                      hasLocation
                          ? formState.destinationAddress
                          : 'Search or pick a location',
                      style: TextStyle(
                        fontSize: w * 0.038,
                        fontWeight:
                            hasLocation ? FontWeight.w500 : FontWeight.w400,
                        color: hasLocation
                            ? MyShopColors.textPrimary
                            : MyShopColors.textHint,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: w * 0.051,
                    color: MyShopColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: h * 0.007),
          Text(
            'Tap to search or drop a pin on the map',
            style: TextStyle(
              fontSize: w * 0.028,
              fontWeight: FontWeight.w400,
              color: MyShopColors.textHint,
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
      padding: EdgeInsets.symmetric(horizontal: w * 0.041),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: controller,
            onChanged: onChanged,
            style: TextStyle(
              fontSize: w * 0.038,
              fontWeight: FontWeight.w400,
              color: MyShopColors.textPrimary,
            ),
            decoration: InputDecoration(
              hintText: 'Enter specific landmark or street',
              hintStyle: TextStyle(
                fontSize: w * 0.036,
                fontWeight: FontWeight.w400,
                color: MyShopColors.textHint,
              ),
              contentPadding: EdgeInsets.symmetric(
                horizontal: w * 0.038,
                vertical: h * 0.015,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(w * 0.021),
                borderSide: const BorderSide(color: MyShopColors.divider),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(w * 0.021),
                borderSide: const BorderSide(color: MyShopColors.divider),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(w * 0.021),
                borderSide: const BorderSide(color: MyShopColors.primaryGold, width: 1.5),
              ),
            ),
          ),
          SizedBox(height: h * 0.007),
          Text(
            "Add any closest landmark to help artisans (optional)",
            style: TextStyle(
              fontSize:   w * 0.028,
              fontWeight: FontWeight.w400,
              color:      MyShopColors.textHint,
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
        color:        MyShopColors.surfaceGrey,
        borderRadius: BorderRadius.circular(w * 0.041),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Header row ──────────────────────────────────────────────────────
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: w * 0.031,
              vertical:   h * 0.014,
            ),
            child: Row(
              children: [
                Container(
                  width:  w * 0.100,
                  height: w * 0.100,
                  decoration: BoxDecoration(
                    color:        MyShopColors.surfaceWhite,
                    borderRadius: BorderRadius.circular(w * 0.026),
                    boxShadow: [
                      BoxShadow(
                        color:      Colors.black.withValues(alpha: 0.04),
                        blurRadius: w * 0.010,
                        offset:     Offset(0, w * 0.002),
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.access_time_rounded,
                    size:  w * 0.046,
                    color: MyShopColors.textPrimary,
                  ),
                ),
                SizedBox(width: w * 0.031),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Service Timing',
                        style: TextStyle(
                          fontSize:   w * 0.032,
                          fontWeight: FontWeight.w700,
                          color:      MyShopColors.textPrimary,
                        ),
                      ),
                      SizedBox(height: h * 0.004),
                      Text(
                        'When do you need the help?',
                        style: TextStyle(
                          fontSize:   w * 0.024,
                          fontWeight: FontWeight.w400,
                          color:      MyShopColors.textSecondary,
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
                      Divider(height: 1, thickness: 1, color: MyShopColors.divider),
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
          colorScheme: const ColorScheme.light(primary: MyShopColors.primaryGold),
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
          colorScheme: const ColorScheme.light(primary: MyShopColors.primaryGold),
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
          color:        MyShopColors.surfaceGrey,
          borderRadius: BorderRadius.circular(w * 0.026),
          border:       Border.all(color: MyShopColors.divider),
        ),
        child: Row(
          children: [
            Icon(icon, size: w * 0.046, color: MyShopColors.textSecondary),
            SizedBox(width: w * 0.021),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize:   w * 0.036,
                  fontWeight: FontWeight.w500,
                  color:      MyShopColors.textPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(Icons.keyboard_arrow_down_rounded,
                size: w * 0.046, color: MyShopColors.textSecondary),
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
    return Padding(
      padding: EdgeInsets.all(w * 0.010),
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
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeInOut,
        padding: EdgeInsets.symmetric(
          horizontal: w * 0.051,
          vertical:   h * 0.009,
        ),
        decoration: BoxDecoration(
          color: isSelected ? MyShopColors.surfaceWhite : Colors.transparent,
          borderRadius: BorderRadius.circular(w * 0.031),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color:      Colors.black.withValues(alpha: 0.06),
                    blurRadius: w * 0.013,
                    offset:     Offset(0, w * 0.003),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize:   w * 0.038,
            fontWeight: FontWeight.w700,
            color:      MyShopColors.textPrimary,
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
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: w * 0.041),
      child: Column(
        children: [
          _DashedLine(color: MyShopColors.divider, dashLength: w * 0.010, gapLength: w * 0.008),
          SizedBox(height: h * 0.014),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.timer_outlined,
                size:  w * 0.046,
                color: MyShopColors.textPrimary,
              ),
              SizedBox(width: w * 0.021),
              RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: 'Est. time for first bid: ',
                      style: TextStyle(
                        fontSize:   w * 0.036,
                        fontWeight: FontWeight.w400,
                        color:      MyShopColors.textPrimary,
                      ),
                    ),
                    TextSpan(
                      text: '~5 mins',
                      style: TextStyle(
                        fontSize:   w * 0.036,
                        fontWeight: FontWeight.w700,
                        color:      MyShopColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: h * 0.014),
          _DashedLine(color: MyShopColors.divider, dashLength: w * 0.010, gapLength: w * 0.008),
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
        color: MyShopColors.primaryGoldLight,
        borderRadius: BorderRadius.circular(w * 0.031),
        border: Border.all(color: MyShopColors.primaryGold.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.verified_user_outlined,
            size: w * 0.056,
            color: MyShopColors.primaryGold,
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
                    color: MyShopColors.textPrimary,
                  ),
                ),
                SizedBox(height: h * 0.004),
                Text(
                  'All bidders are screened via Ghana Police background checks and Smile Identity KYC.',
                  style: TextStyle(
                    fontSize: w * 0.028,
                    fontWeight: FontWeight.w400,
                    color: MyShopColors.textSecondary,
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
    final label     = 'Post Job Post Now';

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: w * 0.041),
      child: SizedBox(
        width:  double.infinity,
        height: h * 0.068,
        child: ElevatedButton(
          onPressed: canSubmit ? onPressed : null,
          style: ElevatedButton.styleFrom(
            backgroundColor:         canSubmit ? MyShopColors.darkSlate : MyShopColors.surfaceGrey,
            disabledBackgroundColor: MyShopColors.surfaceGrey,
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
                    color: canSubmit ? MyShopColors.surfaceWhite : MyShopColors.disabled,
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
                        color:      canSubmit ? MyShopColors.surfaceWhite : MyShopColors.disabled,
                        letterSpacing: 0.2,
                      ),
                    ),
                    SizedBox(width: w * 0.026),
                    Icon(
                      Icons.add_circle_outline_rounded,
                      size:  w * 0.051,
                      color: canSubmit ? MyShopColors.surfaceWhite : MyShopColors.disabled,
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
        'BY POSTING, YOU AGREE TO OUR ESCROW & SAFETY TERMS',
        style: TextStyle(
          fontSize:      w * 0.026,
          fontWeight:    FontWeight.w600,
          color:         MyShopColors.textHint,
          letterSpacing: 0.8,
          height:        1.5,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

// ── Horizontal dashed line (used above/below bid-time row) ─────────────────────

class _DashedLine extends StatelessWidget {
  final Color  color;
  final double dashLength;
  final double gapLength;

  const _DashedLine({
    required this.color,
    required this.dashLength,
    required this.gapLength,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 1,
      child: CustomPaint(
        painter: _DashedLinePainter(
          color: color,
          dashLength: dashLength,
          gapLength: gapLength,
        ),
      ),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  final Color  color;
  final double dashLength;
  final double gapLength;

  const _DashedLinePainter({
    required this.color,
    required this.dashLength,
    required this.gapLength,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color       = color
      ..strokeWidth = 1
      ..style       = PaintingStyle.stroke;

    var x = 0.0;
    final y = size.height / 2;
    while (x < size.width) {
      final end = (x + dashLength).clamp(0.0, size.width);
      canvas.drawLine(Offset(x, y), Offset(end, y), paint);
      x = end + gapLength;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedLinePainter old) =>
      old.color      != color      ||
      old.dashLength != dashLength ||
      old.gapLength  != gapLength;
}

// ── Dashed rounded-rect border painter (used by photo upload zone) ─────────────

class _DashedBorderPainter extends CustomPainter {
  final Color  color;
  final double radius;
  final double strokeWidth;
  final double dashLength;
  final double gapLength;

  const _DashedBorderPainter({
    required this.color,
    required this.radius,
    required this.strokeWidth,
    required this.dashLength,
    required this.gapLength,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);

    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = (distance + dashLength).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + gapLength;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter old) =>
      old.color       != color       ||
      old.radius      != radius      ||
      old.strokeWidth != strokeWidth ||
      old.dashLength  != dashLength  ||
      old.gapLength   != gapLength;
}
