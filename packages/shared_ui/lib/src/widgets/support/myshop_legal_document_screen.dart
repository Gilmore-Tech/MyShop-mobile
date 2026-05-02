import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:shared_models/shared_models.dart';

import '../../theme/myshop_colors.dart';
import '../../theme/myshop_spacing.dart';
import '../../theme/myshop_typography.dart';
import '../myshop_primary_button.dart';
import 'myshop_support_legal_screen.dart' show SupportLegalAsync;
import 'support_channels.dart';

/// Renders a legal document (Markdown) or — when [LegalDocument.externalUrl]
/// is set — a single CTA that opens the URL in the system browser.
///
/// The viewer trusts the backend to ship sanitised Markdown.
/// `flutter_markdown` does not render raw HTML by default, so any tag soup
/// will be inert.
class MyShopLegalDocumentScreen extends StatelessWidget {
  const MyShopLegalDocumentScreen({
    super.key,
    required this.slug,
    required this.state,
    this.onRefresh,
  });

  final String slug;
  final SupportLegalAsync<LegalDocument> state;
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
          state.data?.title ?? LegalSlugs.fallbackTitle(slug),
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
      return _LegalError(error: state.error!, onRetry: onRefresh);
    }
    final doc = state.data;
    if (doc == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(MyShopSpacing.lg),
          child: Text(
            'Document not available.',
            style: MyShopTypography.body2,
          ),
        ),
      );
    }

    if (doc.isExternal) {
      return Padding(
        padding: const EdgeInsets.all(MyShopSpacing.lg),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.open_in_new,
              size: 40,
              color: MyShopColors.textSecondary,
            ),
            const SizedBox(height: MyShopSpacing.md),
            Text(
              doc.title,
              style: MyShopTypography.h3,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: MyShopSpacing.sm),
            const Text(
              'Opens in your default browser.',
              style: MyShopTypography.body2,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: MyShopSpacing.lg),
            MyShopPrimaryButton(
              label: 'Open in browser',
              onPressed: () =>
                  SupportChannels.openExternalUrl(doc.externalUrl!),
            ),
          ],
        ),
      );
    }

    if (!doc.hasBody) {
      return const Padding(
        padding: EdgeInsets.all(MyShopSpacing.lg),
        child: Center(
          child: Text(
            'Document body is empty.',
            style: MyShopTypography.body2,
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(MyShopSpacing.md),
      children: [
        Text(
          doc.title,
          style: MyShopTypography.h1.copyWith(fontSize: 22),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: [
            _MetaChip(label: 'Version ${doc.version}'),
            if (doc.effectiveAt != null)
              _MetaChip(
                label: 'Effective ${_formatDate(doc.effectiveAt!)}',
              ),
          ],
        ),
        const SizedBox(height: MyShopSpacing.md),
        MarkdownBody(
          data: doc.bodyMarkdown!,
          selectable: true,
          onTapLink: (_, href, __) {
            if (href != null) SupportChannels.openExternalUrl(href);
          },
        ),
        const SizedBox(height: MyShopSpacing.xl),
      ],
    );
  }

  static String _formatDate(DateTime when) {
    return '${when.year}-${when.month.toString().padLeft(2, '0')}-${when.day.toString().padLeft(2, '0')}';
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: MyShopColors.surfaceGrey,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: MyShopTypography.caption.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _LegalError extends StatelessWidget {
  const _LegalError({required this.error, required this.onRetry});
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
              "Couldn't load this document",
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
