import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../providers/services_provider.dart';

// ── Screen ─────────────────────────────────────────────────────────────────────
//
// PRD 4.5 — Services Tab: full-screen category grid with featured portfolio
// and recently viewed artisans.
// Tapping a category → job form (job_form_screen.dart).

class CategoriesScreen extends StatelessWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height;

    return Scaffold(
      backgroundColor: MyShopColors.offWhite,
      body: SafeArea(
        child: Column(
          children: [
            const _AppBar(),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: h * 0.019),
                    const _HeroSection(),
                    SizedBox(height: h * 0.024),
                    const _CategoriesSection(),
                    SizedBox(height: h * 0.028),
                    const _FeaturedPortfolioSection(),
                    SizedBox(height: h * 0.028),
                    const _RecentlyViewedSection(),
                    SizedBox(height: h * 0.028),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── App Bar ────────────────────────────────────────────────────────────────────

class _AppBar extends StatelessWidget {
  const _AppBar();

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final w = size.width;
    final h = size.height;
    final topPad = MediaQuery.paddingOf(context).top;

    return Container(
      color: MyShopColors.surfaceWhite,
      padding: EdgeInsets.fromLTRB(
        w * 0.041,
        topPad + h * 0.019,
        w * 0.041,
        h * 0.019,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Artisans',
            style: TextStyle(
              fontSize:   w * 0.062,
              fontWeight: FontWeight.w700,
              color:      MyShopColors.textPrimary,
              height:     1.2,
            ),
          ),
          SizedBox(height: h * 0.005),
          Row(
            children: [
              Icon(Icons.location_on_rounded, size: w * 0.036, color: MyShopColors.primaryGold),
              SizedBox(width: w * 0.010),
              Text(
                'Kumasi, Ashanti Region',
                style: TextStyle(
                  fontSize:   w * 0.031,
                  fontWeight: FontWeight.w400,
                  color:      MyShopColors.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Hero Section ───────────────────────────────────────────────────────────────

class _HeroSection extends StatelessWidget {
  const _HeroSection();

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final w = size.width;
    final h = size.height;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: w * 0.041),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'What do you need done?',
            style: TextStyle(
              fontSize:   w * 0.051,
              fontWeight: FontWeight.w700,
              color:      MyShopColors.textPrimary,
              height:     1.3,
            ),
          ),
          SizedBox(height: h * 0.007),
          Text(
            'Pick a category to post a request — verified artisans will bid.',
            style: TextStyle(
              fontSize:   w * 0.033,
              fontWeight: FontWeight.w400,
              color:      MyShopColors.textSecondary,
              height:     1.4,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Categories Section ─────────────────────────────────────────────────────────

class _CategoriesSection extends ConsumerWidget {
  const _CategoriesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final h = MediaQuery.sizeOf(context).height;

    final categoriesAsync = ref.watch(serviceCategoriesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          title:       'Categories',
          actionLabel: 'View All',
          onActionTap: () {},
        ),
        SizedBox(height: h * 0.014),
        categoriesAsync.when(
          loading: () => const _CategoriesSkeletonGrid(),
          error:   (_, __) => const SizedBox.shrink(),
          data:    (categories) => _CategoryGrid(categories: categories),
        ),
      ],
    );
  }
}

class _CategoryGrid extends StatelessWidget {
  final List<ServiceCategory> categories;
  const _CategoryGrid({required this.categories});

  @override
  Widget build(BuildContext context) {
    final w              = MediaQuery.sizeOf(context).width;
    final crossAxisSpacing = w * 0.026;
    final horizontalPad  = w * 0.041;
    final itemWidth      = (w - horizontalPad * 2 - crossAxisSpacing * 2) / 3;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPad),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount:   3,
          crossAxisSpacing: crossAxisSpacing,
          mainAxisSpacing:  w * 0.026,
          childAspectRatio: itemWidth / (itemWidth * 1.05),
        ),
        itemCount:   categories.length,
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
        'categoryId':   category.id,
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
                    fontSize:   w * 0.046,
                    fontWeight: FontWeight.w700,
                    color:      MyShopColors.textPrimary,
                  ),
                ),
                SizedBox(height: h * 0.005),
                Text(
                  'Select what you need repaired to post your request.',
                  style: TextStyle(
                    fontSize:   w * 0.031,
                    fontWeight: FontWeight.w400,
                    color:      MyShopColors.textSecondary,
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
                    vertical:   h * 0.017,
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
                          child.icon,
                          size:  w * 0.046,
                          color: MyShopColors.darkSlate,
                        ),
                      ),
                      SizedBox(width: w * 0.038),
                      Expanded(
                        child: Text(
                          child.name,
                          style: TextStyle(
                            fontSize:   w * 0.038,
                            fontWeight: FontWeight.w500,
                            color:      MyShopColors.textPrimary,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        size:  w * 0.056,
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

class _CategoryCard extends StatelessWidget {
  final ServiceCategory category;
  final VoidCallback    onTap;

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
          color:        MyShopColors.surfaceWhite,
          borderRadius: BorderRadius.circular(w * 0.031),
          boxShadow: [
            BoxShadow(
              color:      Colors.black.withValues(alpha: 0.05),
              blurRadius: w * 0.015,
              offset:     Offset(0, w * 0.005),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width:  w * 0.103,
              height: w * 0.103,
              decoration: const BoxDecoration(
                color: MyShopColors.surfaceGrey,
                shape: BoxShape.circle,
              ),
              child: Icon(category.icon, size: w * 0.056, color: MyShopColors.darkSlate),
            ),
            SizedBox(height: h * 0.009),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: w * 0.015),
              child: Text(
                category.name,
                style: TextStyle(
                  fontSize:   w * 0.028,
                  fontWeight: FontWeight.w500,
                  color:      MyShopColors.textPrimary,
                  height:     1.3,
                ),
                textAlign: TextAlign.center,
                maxLines:  2,
                overflow:  TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoriesSkeletonGrid extends StatelessWidget {
  const _CategoriesSkeletonGrid();

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: w * 0.041),
      child: GridView.count(
        shrinkWrap: true,
        physics:          const NeverScrollableScrollPhysics(),
        crossAxisCount:   3,
        crossAxisSpacing: w * 0.026,
        mainAxisSpacing:  w * 0.026,
        childAspectRatio: 1.0,
        children: List.generate(
          9,
          (_) => Container(
            decoration: BoxDecoration(
              color:        MyShopColors.surfaceGrey,
              borderRadius: BorderRadius.circular(w * 0.031),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Featured Portfolio Section ─────────────────────────────────────────────────

class _FeaturedPortfolioSection extends ConsumerWidget {
  const _FeaturedPortfolioSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final size = MediaQuery.sizeOf(context);
    final w = size.width;
    final h = size.height;

    final featuredAsync = ref.watch(featuredArtisansProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(
          title:    'Featured Portfolio',
          subtitle: 'Verified top-tier professionals',
        ),
        SizedBox(height: h * 0.014),
        SizedBox(
          height: h * 0.250,
          child: featuredAsync.when(
            loading: () => const _FeaturedSkeletonList(),
            error:   (_, __) => const SizedBox.shrink(),
            data:    (artisans) => ListView.separated(
              scrollDirection: Axis.horizontal,
              padding:         EdgeInsets.symmetric(horizontal: w * 0.041),
              itemCount:       artisans.length,
              separatorBuilder: (_, __) => SizedBox(width: w * 0.031),
              itemBuilder: (_, i) => _PortfolioCard(artisan: artisans[i]),
            ),
          ),
        ),
      ],
    );
  }
}

class _PortfolioCard extends StatelessWidget {
  final FeaturedArtisan artisan;
  const _PortfolioCard({required this.artisan});

  @override
  Widget build(BuildContext context) {
    final size   = MediaQuery.sizeOf(context);
    final w      = size.width;
    final h      = size.height;
    final cardW  = w * 0.440;
    final radius = w * 0.031;

    return GestureDetector(
      onTap: () {
        // TODO: Navigate to artisan profile
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: SizedBox(
          width: cardW,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(color: artisan.cardColor),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin:  Alignment.topCenter,
                      end:    Alignment.bottomCenter,
                      stops:  const [0.35, 1.0],
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.78),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                top:   h * 0.012,
                right: w * 0.026,
                child: _RatingBadge(rating: artisan.rating),
              ),
              Positioned(
                left:   w * 0.031,
                right:  w * 0.031,
                bottom: h * 0.019,
                child:  _PortfolioCardInfo(artisan: artisan),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RatingBadge extends StatelessWidget {
  final double rating;
  const _RatingBadge({required this.rating});

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: w * 0.021,
        vertical:   w * 0.010,
      ),
      decoration: BoxDecoration(
        color:        MyShopColors.primaryGold,
        borderRadius: BorderRadius.circular(w * 0.036),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.star_rounded, size: w * 0.028, color: Colors.white),
          SizedBox(width: w * 0.008),
          Text(
            rating.toStringAsFixed(1),
            style: TextStyle(
              fontSize:   w * 0.028,
              fontWeight: FontWeight.w700,
              color:      Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _PortfolioCardInfo extends StatelessWidget {
  final FeaturedArtisan artisan;
  const _PortfolioCardInfo({required this.artisan});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final w = size.width;
    final h = size.height;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          artisan.tradeTitle,
          style: TextStyle(
            fontSize:   w * 0.028,
            fontWeight: FontWeight.w400,
            color:      Colors.white.withValues(alpha: 0.80),
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        SizedBox(height: h * 0.004),
        Text(
          artisan.name,
          style: TextStyle(
            fontSize:   w * 0.036,
            fontWeight: FontWeight.w700,
            color:      Colors.white,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        SizedBox(height: h * 0.007),
        Row(
          children: [
            Flexible(
              child: Text(
                artisan.minPriceDisplay,
                style: TextStyle(
                  fontSize:   w * 0.028,
                  fontWeight: FontWeight.w400,
                  color:      Colors.white.withValues(alpha: 0.90),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (artisan.isVerified) ...[
              SizedBox(width: w * 0.021),
              _VerifiedChip(),
            ],
          ],
        ),
      ],
    );
  }
}

class _VerifiedChip extends StatelessWidget {
  const _VerifiedChip();

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: w * 0.015,
        vertical:   w * 0.005,
      ),
      decoration: BoxDecoration(
        color:        MyShopColors.successLight,
        borderRadius: BorderRadius.circular(w * 0.015),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_rounded, size: w * 0.026, color: MyShopColors.success),
          SizedBox(width: w * 0.008),
          Text(
            'VERIFIED',
            style: TextStyle(
              fontSize:      w * 0.023,
              fontWeight:    FontWeight.w700,
              color:         MyShopColors.success,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _FeaturedSkeletonList extends StatelessWidget {
  const _FeaturedSkeletonList();

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;

    return ListView.separated(
      scrollDirection:  Axis.horizontal,
      padding:          EdgeInsets.symmetric(horizontal: w * 0.041),
      itemCount:        3,
      separatorBuilder: (_, __) => SizedBox(width: w * 0.031),
      itemBuilder: (_, __) => Container(
        width: w * 0.440,
        decoration: BoxDecoration(
          color:        MyShopColors.surfaceGrey,
          borderRadius: BorderRadius.circular(w * 0.031),
        ),
      ),
    );
  }
}

// ── Recently Viewed Section ────────────────────────────────────────────────────

class _RecentlyViewedSection extends ConsumerWidget {
  const _RecentlyViewedSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final h = MediaQuery.sizeOf(context).height;

    final recentAsync = ref.watch(recentArtisansProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(title: 'Recently Viewed'),
        SizedBox(height: h * 0.009),
        recentAsync.when(
          loading: () => const _RecentSkeletonList(),
          error:   (_, __) => const SizedBox.shrink(),
          data:    (artisans) => Column(
            children: artisans
                .map(
                  (a) => _RecentArtisanRow(
                    artisan:     a,
                    showDivider: artisans.last != a,
                    onTap: () {
                      // TODO: Navigate to artisan profile
                    },
                  ),
                )
                .toList(),
          ),
        ),
      ],
    );
  }
}

class _RecentArtisanRow extends StatelessWidget {
  final RecentArtisan artisan;
  final bool          showDivider;
  final VoidCallback  onTap;

  const _RecentArtisanRow({
    required this.artisan,
    required this.showDivider,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final w = size.width;
    final h = size.height;

    return Column(
      children: [
        InkWell(
          onTap: onTap,
          child: Container(
            color:   MyShopColors.surfaceWhite,
            padding: EdgeInsets.symmetric(
              horizontal: w * 0.041,
              vertical:   h * 0.016,
            ),
            child: Row(
              children: [
                _ArtisanAvatar(artisan: artisan),
                SizedBox(width: w * 0.036),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        artisan.name,
                        style: TextStyle(
                          fontSize:   w * 0.038,
                          fontWeight: FontWeight.w600,
                          color:      MyShopColors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: h * 0.004),
                      Text(
                        artisan.trade,
                        style: TextStyle(
                          fontSize:   w * 0.031,
                          fontWeight: FontWeight.w400,
                          color:      MyShopColors.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: h * 0.005),
                      _StarRating(
                        rating:      artisan.rating,
                        reviewCount: artisan.reviewCount,
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size:  w * 0.056,
                  color: MyShopColors.textSecondary,
                ),
              ],
            ),
          ),
        ),
        if (showDivider)
          Divider(
            height:    1,
            thickness: 1,
            color:     MyShopColors.divider,
            indent:    w * 0.041 + w * 0.123 + w * 0.036,
          ),
      ],
    );
  }
}

class _ArtisanAvatar extends StatelessWidget {
  final RecentArtisan artisan;
  const _ArtisanAvatar({required this.artisan});

  @override
  Widget build(BuildContext context) {
    final w    = MediaQuery.sizeOf(context).width;
    final size = w * 0.123;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width:  size,
          height: size,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: MyShopColors.avatarPlaceholder,
          ),
          child: Icon(
            Icons.person_rounded,
            size:  size * 0.55,
            color: MyShopColors.darkSlate,
          ),
        ),
        if (artisan.unreadCount != null && artisan.unreadCount! > 0)
          Positioned(
            top:   -(w * 0.010),
            right: -(w * 0.010),
            child:  _UnreadBadge(count: artisan.unreadCount!),
          ),
      ],
    );
  }
}

class _UnreadBadge extends StatelessWidget {
  final int count;
  const _UnreadBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;

    return Container(
      constraints: BoxConstraints(
        minWidth:  w * 0.046,
        minHeight: w * 0.046,
      ),
      padding: EdgeInsets.symmetric(horizontal: w * 0.008),
      decoration: BoxDecoration(
        color:        MyShopColors.error,
        borderRadius: BorderRadius.circular(w * 0.023),
      ),
      alignment: Alignment.center,
      child: Text(
        count > 99 ? '99+' : count.toString(),
        style: TextStyle(
          fontSize:   w * 0.026,
          fontWeight: FontWeight.w700,
          color:      Colors.white,
        ),
      ),
    );
  }
}

class _StarRating extends StatelessWidget {
  final double rating;
  final int    reviewCount;
  const _StarRating({required this.rating, required this.reviewCount});

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;

    return Row(
      children: [
        Icon(Icons.star_rounded, size: w * 0.033, color: MyShopColors.primaryGold),
        SizedBox(width: w * 0.008),
        Flexible(
          child: Text(
            '$rating  ($reviewCount reviews)',
            style: TextStyle(
              fontSize:   w * 0.028,
              fontWeight: FontWeight.w400,
              color:      MyShopColors.textSecondary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _RecentSkeletonList extends StatelessWidget {
  const _RecentSkeletonList();

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final h = size.height;

    return Column(
      children: List.generate(
        2,
        (_) => Container(
          height: h * 0.095,
          color:  MyShopColors.surfaceWhite,
          margin: EdgeInsets.only(bottom: h * 0.002),
        ),
      ),
    );
  }
}

// ── Shared Section Header ──────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String  title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onActionTap;

  const _SectionHeader({
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onActionTap,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final w = size.width;
    final h = size.height;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: w * 0.041),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize:   w * 0.046,
                    fontWeight: FontWeight.w700,
                    color:      MyShopColors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (actionLabel != null)
                GestureDetector(
                  onTap:     onActionTap,
                  behavior:  HitTestBehavior.opaque,
                  child: Padding(
                    padding: EdgeInsets.only(left: w * 0.021),
                    child: Text(
                      actionLabel!,
                      style: TextStyle(
                        fontSize:   w * 0.033,
                        fontWeight: FontWeight.w600,
                        color:      MyShopColors.primaryGold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (subtitle != null) ...[
            SizedBox(height: h * 0.005),
            Text(
              subtitle!,
              style: TextStyle(
                fontSize:   w * 0.031,
                fontWeight: FontWeight.w400,
                color:      MyShopColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
