import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:shared_models/shared_models.dart';

import '../../theme/myshop_colors.dart';
import '../../theme/myshop_spacing.dart';
import '../../theme/myshop_typography.dart';
import 'myshop_support_legal_screen.dart' show SupportLegalAsync;
import 'support_channels.dart';

/// Renders a single help article as Markdown.
///
/// Footer includes a "Was this helpful?" thumbs row + "Still need help?"
/// CTA. The thumbs delegate to [onFeedback] (per-app provider can fire-
/// and-forget a `POST /v1/support/help/articles/:slug/feedback`); the
/// "Still need help?" button delegates to [onContactSupport] which
/// opens the contact sheet.
class MyShopHelpArticleScreen extends StatelessWidget {
  const MyShopHelpArticleScreen({
    super.key,
    required this.state,
    required this.onContactSupport,
    this.onFeedback,
    this.onRefresh,
  });

  final SupportLegalAsync<HelpArticle> state;
  final VoidCallback onContactSupport;

  /// Optional — called with `true` (helpful) / `false` (not helpful).
  final ValueChanged<bool>? onFeedback;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MyShopColors.surfaceWhite,
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
          state.data?.title ?? 'Article',
          style: MyShopTypography.h1.copyWith(fontSize: 18),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: SafeArea(child: _buildBody(context)),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (state.loading && !state.hasData) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.hasError && !state.hasData) {
      return _ErrorBody(error: state.error!, onRetry: onRefresh);
    }
    final article = state.data;
    if (article == null || !article.hasBody) {
      return const Padding(
        padding: EdgeInsets.all(MyShopSpacing.lg),
        child: Center(
          child: Text(
            'Article not available.',
            style: MyShopTypography.body2,
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(MyShopSpacing.md),
      children: [
        Text(
          article.title,
          style: MyShopTypography.h1.copyWith(fontSize: 22),
        ),
        if (article.updatedAt != null) ...[
          const SizedBox(height: 4),
          Text(
            'Last updated ${_formatDate(article.updatedAt!)}',
            style: MyShopTypography.caption,
          ),
        ],
        const SizedBox(height: MyShopSpacing.md),
        MarkdownBody(
          data: article.bodyMarkdown!,
          selectable: true,
          onTapLink: (_, href, __) {
            if (href != null) SupportChannels.openExternalUrl(href);
          },
          styleSheet: _markdownStyle(),
        ),
        const SizedBox(height: MyShopSpacing.lg),
        if (onFeedback != null) _FeedbackBar(onFeedback: onFeedback!),
        const SizedBox(height: MyShopSpacing.md),
        _StillNeedHelp(onContactSupport: onContactSupport),
        const SizedBox(height: MyShopSpacing.lg),
      ],
    );
  }

  static MarkdownStyleSheet _markdownStyle() {
    return MarkdownStyleSheet(
      p: MyShopTypography.body1.copyWith(
        fontWeight: FontWeight.w400,
        height: 1.55,
        color: MyShopColors.textPrimary,
      ),
      h1: MyShopTypography.h1.copyWith(fontSize: 20),
      h2: MyShopTypography.h2,
      h3: MyShopTypography.h3,
      a: MyShopTypography.body1.copyWith(
        color: MyShopColors.primaryGold,
        decoration: TextDecoration.underline,
        decorationColor: MyShopColors.primaryGold,
        fontWeight: FontWeight.w700,
      ),
      strong: MyShopTypography.body1.copyWith(
        fontWeight: FontWeight.w800,
      ),
      em: MyShopTypography.body1.copyWith(
        fontStyle: FontStyle.italic,
      ),
      listBullet: MyShopTypography.body1,
      blockquote: MyShopTypography.body1.copyWith(
        color: MyShopColors.textSecondary,
        fontStyle: FontStyle.italic,
      ),
      blockquoteDecoration: BoxDecoration(
        color: MyShopColors.offWhite,
        borderRadius: BorderRadius.circular(8),
        border: const Border(
          left: BorderSide(color: MyShopColors.primaryGold, width: 3),
        ),
      ),
      code: const TextStyle(
        fontFamily: 'monospace',
        fontSize: 13,
        backgroundColor: Color(0xFFF3F5F6),
        color: MyShopColors.textPrimary,
      ),
    );
  }

  static String _formatDate(DateTime when) {
    return '${when.year}-${when.month.toString().padLeft(2, '0')}-${when.day.toString().padLeft(2, '0')}';
  }
}

class _FeedbackBar extends StatelessWidget {
  const _FeedbackBar({required this.onFeedback});
  final ValueChanged<bool> onFeedback;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(MyShopSpacing.md),
      decoration: BoxDecoration(
        color: MyShopColors.offWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MyShopColors.divider),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Was this helpful?',
              style: MyShopTypography.body1.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          IconButton(
            onPressed: () => onFeedback(true),
            icon: const Icon(Icons.thumb_up_outlined),
            color: MyShopColors.success,
          ),
          IconButton(
            onPressed: () => onFeedback(false),
            icon: const Icon(Icons.thumb_down_outlined),
            color: MyShopColors.error,
          ),
        ],
      ),
    );
  }
}

class _StillNeedHelp extends StatelessWidget {
  const _StillNeedHelp({required this.onContactSupport});
  final VoidCallback onContactSupport;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onContactSupport,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(MyShopSpacing.md),
        decoration: BoxDecoration(
          color: MyShopColors.primaryGoldLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: MyShopColors.primaryGold),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.headset_mic_outlined,
              color: MyShopColors.primaryGoldDark,
            ),
            const SizedBox(width: MyShopSpacing.sm),
            Expanded(
              child: Text(
                'Still need help? Contact support',
                style: MyShopTypography.body1.copyWith(
                  color: MyShopColors.primaryGoldDark,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const Icon(
              Icons.chevron_right,
              color: MyShopColors.primaryGoldDark,
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.error, required this.onRetry});
  final Object error;
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(MyShopSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline,
              size: 48,
              color: MyShopColors.error,
            ),
            const SizedBox(height: MyShopSpacing.md),
            Text(
              "Couldn't load this article",
              style: MyShopTypography.h3.copyWith(fontSize: 16),
            ),
            const SizedBox(height: MyShopSpacing.md),
            if (onRetry != null)
              TextButton(
                onPressed: onRetry,
                child: Text(
                  'Try again',
                  style: MyShopTypography.button.copyWith(
                    color: MyShopColors.primaryGold,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
