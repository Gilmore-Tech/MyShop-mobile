import 'package:flutter/material.dart';
import 'package:shared_models/shared_models.dart';

import '../../theme/myshop_colors.dart';
import '../../theme/myshop_spacing.dart';
import '../../theme/myshop_typography.dart';
import 'myshop_support_legal_screen.dart' show SupportLegalAsync;

/// Lists the articles inside a single help category.
class MyShopHelpCategoryScreen extends StatelessWidget {
  const MyShopHelpCategoryScreen({
    super.key,
    required this.title,
    required this.state,
    required this.onArticleTap,
    required this.onRefresh,
  });

  final String title;
  final SupportLegalAsync<List<HelpArticle>> state;
  final void Function(HelpArticle article) onArticleTap;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MyShopColors.offWhite,
      appBar: AppBar(
        backgroundColor: MyShopColors.surfaceWhite,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back,
            color: MyShopColors.textPrimary,
          ),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          title,
          style: MyShopTypography.h1.copyWith(fontSize: 18),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: RefreshIndicator(
        onRefresh: onRefresh,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (state.loading && !state.hasData) {
      return ListView.separated(
        padding: const EdgeInsets.all(MyShopSpacing.md),
        itemCount: 6,
        separatorBuilder: (_, __) => const SizedBox(height: MyShopSpacing.sm),
        itemBuilder: (_, __) => Container(
          height: 64,
          decoration: BoxDecoration(
            color: MyShopColors.surfaceGrey,
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
    if (state.hasError && !state.hasData) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 80),
          const Center(
            child: Icon(
              Icons.error_outline,
              size: 56,
              color: MyShopColors.error,
            ),
          ),
          const SizedBox(height: MyShopSpacing.md),
          Center(
            child: Text(
              "Couldn't load articles",
              style: MyShopTypography.h3.copyWith(fontSize: 16),
            ),
          ),
          const SizedBox(height: MyShopSpacing.md),
          Center(
            child: TextButton(
              onPressed: onRefresh,
              child: Text(
                'Try again',
                style: MyShopTypography.button.copyWith(
                  color: MyShopColors.primaryGold,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      );
    }
    final articles = state.data ?? const [];
    if (articles.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 80),
          const Center(
            child: Text(
              'No articles yet in this category.',
              style: MyShopTypography.body2,
            ),
          ),
        ],
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(MyShopSpacing.md),
      itemCount: articles.length,
      separatorBuilder: (_, __) => const SizedBox(height: MyShopSpacing.sm),
      itemBuilder: (_, i) => _ArticleRow(
        article: articles[i],
        onTap: () => onArticleTap(articles[i]),
      ),
    );
  }
}

class _ArticleRow extends StatelessWidget {
  const _ArticleRow({required this.article, required this.onTap});
  final HelpArticle article;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(MyShopSpacing.md),
        decoration: BoxDecoration(
          color: MyShopColors.surfaceWhite,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: MyShopColors.divider),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    article.title,
                    style: MyShopTypography.h3.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (article.summary != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      article.summary!,
                      style: MyShopTypography.body2,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right,
              color: MyShopColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}
