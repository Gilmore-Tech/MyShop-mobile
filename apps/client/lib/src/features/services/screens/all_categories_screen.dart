import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../providers/services_provider.dart';

// ── Screen ─────────────────────────────────────────────────────────────────────
//
// PRD 4.5 — "View All" categories screen reached from the Services tab header.
// Renders the full taxonomy with a search filter; tapping a leaf pushes the
// job form, tapping a parent reveals its children in a bottom sheet (same
// behaviour as the Services tab grid).

class AllCategoriesScreen extends ConsumerStatefulWidget {
  const AllCategoriesScreen({super.key});

  @override
  ConsumerState<AllCategoriesScreen> createState() =>
      _AllCategoriesScreenState();
}

class _AllCategoriesScreenState extends ConsumerState<AllCategoriesScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(serviceCategoriesProvider);
    final h = MediaQuery.sizeOf(context).height;

    return Scaffold(
      backgroundColor: MyShopColors.offWhite,
      body: SafeArea(
        child: Column(
          children: [
            _AppBar(
              controller: _searchController,
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
            ),
            Expanded(
              child: categoriesAsync.when(
                loading: () => const _GridSkeleton(),
                error: (_, __) => const _ErrorState(),
                data: (categories) {
                  final filtered = _filter(categories, _query);
                  if (filtered.isEmpty) {
                    return const _EmptyResults();
                  }
                  return SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(height: h * 0.019),
                        _ResultCount(count: _countLeaves(filtered)),
                        SizedBox(height: h * 0.014),
                        _CategoryGrid(categories: filtered),
                        SizedBox(height: h * 0.028),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Filters the tree by name. A parent matches if its own name matches OR any
  /// child matches; matched parents keep only their matching children (so the
  /// sheet that opens shows just the relevant subset).
  List<ServiceCategory> _filter(List<ServiceCategory> source, String q) {
    if (q.isEmpty) return source;
    final out = <ServiceCategory>[];
    for (final c in source) {
      final selfHit = c.name.toLowerCase().contains(q);
      final matchedChildren = (c.children ?? const <ServiceCategory>[])
          .where((ch) => ch.name.toLowerCase().contains(q))
          .toList();
      if (selfHit) {
        out.add(c);
      } else if (matchedChildren.isNotEmpty) {
        out.add(ServiceCategory(
          id: c.id,
          name: c.name,
          icon: c.icon,
          children: matchedChildren,
        ));
      }
    }
    return out;
  }

  int _countLeaves(List<ServiceCategory> cats) {
    var n = 0;
    for (final c in cats) {
      n += c.hasChildren ? c.children!.length : 1;
    }
    return n;
  }
}

// ── App Bar ────────────────────────────────────────────────────────────────────

class _AppBar extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  const _AppBar({required this.controller, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final w = size.width;
    final h = size.height;

    return Container(
      color: MyShopColors.surfaceWhite,
      padding: EdgeInsets.fromLTRB(
        w * 0.021,
        h * 0.012,
        w * 0.041,
        h * 0.014,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: Icon(
                  Icons.arrow_back_rounded,
                  size: w * 0.062,
                  color: MyShopColors.textPrimary,
                ),
              ),
              SizedBox(width: w * 0.005),
              Expanded(
                child: Text(
                  'All Categories',
                  style: TextStyle(
                    fontSize: w * 0.051,
                    fontWeight: FontWeight.w700,
                    color: MyShopColors.textPrimary,
                    height: 1.2,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: h * 0.012),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: w * 0.020),
            child: _SearchField(controller: controller, onChanged: onChanged),
          ),
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  const _SearchField({required this.controller, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return Container(
      decoration: BoxDecoration(
        color: MyShopColors.surfaceGrey,
        borderRadius: BorderRadius.circular(w * 0.021),
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        style: TextStyle(
          fontSize: w * 0.036,
          color: MyShopColors.textPrimary,
        ),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Search categories',
          hintStyle: TextStyle(
            fontSize: w * 0.036,
            color: MyShopColors.textSecondary,
          ),
          prefixIcon: Icon(
            Icons.search_rounded,
            size: w * 0.051,
            color: MyShopColors.textSecondary,
          ),
          suffixIcon: ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (_, value, __) {
              if (value.text.isEmpty) return const SizedBox.shrink();
              return IconButton(
                icon: Icon(
                  Icons.close_rounded,
                  size: w * 0.046,
                  color: MyShopColors.textSecondary,
                ),
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
              );
            },
          ),
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(vertical: w * 0.036),
        ),
      ),
    );
  }
}

// ── Result count ──────────────────────────────────────────────────────────────

class _ResultCount extends StatelessWidget {
  final int count;
  const _ResultCount({required this.count});

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: w * 0.041),
      child: Text(
        '$count ${count == 1 ? 'category' : 'categories'}',
        style: TextStyle(
          fontSize: w * 0.031,
          fontWeight: FontWeight.w400,
          color: MyShopColors.textSecondary,
        ),
      ),
    );
  }
}

// ── Grid ──────────────────────────────────────────────────────────────────────

class _CategoryGrid extends StatelessWidget {
  final List<ServiceCategory> categories;
  const _CategoryGrid({required this.categories});

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final crossAxisSpacing = w * 0.026;
    final horizontalPad = w * 0.041;
    final itemWidth = (w - horizontalPad * 2 - crossAxisSpacing * 2) / 3;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPad),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: crossAxisSpacing,
          mainAxisSpacing: w * 0.026,
          childAspectRatio: itemWidth / (itemWidth * 1.05),
        ),
        itemCount: categories.length,
        itemBuilder: (context, i) => _CategoryCard(
          category: categories[i],
          onTap: () => _onCategoryTap(context, categories[i]),
        ),
      ),
    );
  }

  void _onCategoryTap(BuildContext context, ServiceCategory category) {
    if (category.hasChildren) {
      _showSubcategorySheet(context, category);
      return;
    }
    _goToJobForm(context, category);
  }

  void _goToJobForm(BuildContext context, ServiceCategory category) {
    context.push(
      AppRoutes.jobNew,
      extra: {
        'categoryId': category.id,
        'categoryName': category.name,
      },
    );
  }

  void _showSubcategorySheet(BuildContext context, ServiceCategory parent) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => _SubcategorySheet(
        parent: parent,
        onSelected: (child) {
          Navigator.of(sheetCtx).pop();
          _goToJobForm(context, child);
        },
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  final ServiceCategory category;
  final VoidCallback onTap;

  const _CategoryCard({required this.category, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final w = size.width;
    final h = size.height;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: MyShopColors.surfaceWhite,
          borderRadius: BorderRadius.circular(w * 0.031),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: w * 0.015,
              offset: Offset(0, w * 0.005),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: w * 0.103,
                  height: w * 0.103,
                  decoration: const BoxDecoration(
                    color: MyShopColors.surfaceGrey,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    category.icon,
                    size: w * 0.056,
                    color: MyShopColors.darkSlate,
                  ),
                ),
                if (category.hasChildren)
                  Positioned(
                    right: -(w * 0.005),
                    bottom: -(w * 0.005),
                    child: Container(
                      padding: EdgeInsets.all(w * 0.005),
                      decoration: BoxDecoration(
                        color: MyShopColors.primaryGold,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: MyShopColors.surfaceWhite,
                          width: 1.5,
                        ),
                      ),
                      child: Icon(
                        Icons.expand_more_rounded,
                        size: w * 0.026,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
            SizedBox(height: h * 0.009),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: w * 0.015),
              child: Text(
                category.name,
                style: TextStyle(
                  fontSize: w * 0.028,
                  fontWeight: FontWeight.w500,
                  color: MyShopColors.textPrimary,
                  height: 1.3,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Subcategory sheet ─────────────────────────────────────────────────────────

class _SubcategorySheet extends StatelessWidget {
  final ServiceCategory parent;
  final ValueChanged<ServiceCategory> onSelected;

  const _SubcategorySheet({required this.parent, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final w = size.width;
    final h = size.height;
    final children = parent.children ?? const [];

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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Choose ${parent.name.toLowerCase()} type',
                  style: TextStyle(
                    fontSize: w * 0.046,
                    fontWeight: FontWeight.w700,
                    color: MyShopColors.textPrimary,
                  ),
                ),
                SizedBox(height: h * 0.005),
                Text(
                  'Select what you need to post your request.',
                  style: TextStyle(
                    fontSize: w * 0.031,
                    fontWeight: FontWeight.w400,
                    color: MyShopColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: h * 0.014),
          const Divider(height: 1, color: MyShopColors.divider),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: children.length,
            separatorBuilder: (_, __) =>
                const Divider(height: 1, color: MyShopColors.divider),
            itemBuilder: (_, i) {
              final child = children[i];
              return InkWell(
                onTap: () => onSelected(child),
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
                        decoration: const BoxDecoration(
                          color: MyShopColors.surfaceGrey,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          child.icon,
                          size: w * 0.046,
                          color: MyShopColors.darkSlate,
                        ),
                      ),
                      SizedBox(width: w * 0.038),
                      Expanded(
                        child: Text(
                          child.name,
                          style: TextStyle(
                            fontSize: w * 0.038,
                            fontWeight: FontWeight.w500,
                            color: MyShopColors.textPrimary,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: w * 0.056,
                        color: MyShopColors.textSecondary,
                      ),
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

// ── States ────────────────────────────────────────────────────────────────────

class _GridSkeleton extends StatelessWidget {
  const _GridSkeleton();

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final h = MediaQuery.sizeOf(context).height;

    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.fromLTRB(w * 0.041, h * 0.024, w * 0.041, h * 0.028),
        child: GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 3,
          crossAxisSpacing: w * 0.026,
          mainAxisSpacing: w * 0.026,
          childAspectRatio: 1.0,
          children: List.generate(
            12,
            (_) => Container(
              decoration: BoxDecoration(
                color: MyShopColors.surfaceGrey,
                borderRadius: BorderRadius.circular(w * 0.031),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyResults extends StatelessWidget {
  const _EmptyResults();

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final w = size.width;
    final h = size.height;

    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: w * 0.082),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: w * 0.180,
              height: w * 0.180,
              decoration: const BoxDecoration(
                color: MyShopColors.surfaceGrey,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.search_off_rounded,
                size: w * 0.092,
                color: MyShopColors.textSecondary,
              ),
            ),
            SizedBox(height: h * 0.019),
            Text(
              'No matches',
              style: TextStyle(
                fontSize: w * 0.046,
                fontWeight: FontWeight.w700,
                color: MyShopColors.textPrimary,
              ),
            ),
            SizedBox(height: h * 0.007),
            Text(
              'Try a different keyword or browse all categories.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: w * 0.033,
                fontWeight: FontWeight.w400,
                color: MyShopColors.textSecondary,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends ConsumerWidget {
  const _ErrorState();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final size = MediaQuery.sizeOf(context);
    final w = size.width;
    final h = size.height;

    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: w * 0.082),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_rounded,
              size: w * 0.123,
              color: MyShopColors.textSecondary,
            ),
            SizedBox(height: h * 0.014),
            Text(
              'Couldn’t load categories',
              style: TextStyle(
                fontSize: w * 0.046,
                fontWeight: FontWeight.w700,
                color: MyShopColors.textPrimary,
              ),
            ),
            SizedBox(height: h * 0.007),
            Text(
              'Check your connection and try again.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: w * 0.033,
                fontWeight: FontWeight.w400,
                color: MyShopColors.textSecondary,
                height: 1.4,
              ),
            ),
            SizedBox(height: h * 0.019),
            TextButton(
              onPressed: () => ref.invalidate(serviceCategoriesProvider),
              child: Text(
                'Retry',
                style: TextStyle(
                  fontSize: w * 0.038,
                  fontWeight: FontWeight.w600,
                  color: MyShopColors.primaryGold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
