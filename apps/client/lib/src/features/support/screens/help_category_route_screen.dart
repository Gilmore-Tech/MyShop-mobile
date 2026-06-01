import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../app/router.dart';
import '../providers/support_providers.dart';

class HelpCategoryRouteScreen extends ConsumerWidget {
  const HelpCategoryRouteScreen({super.key, required this.categorySlug});

  final String categorySlug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final articlesAsync = ref.watch(helpArticlesProvider(categorySlug));
    final categoriesAsync = ref.watch(helpCategoriesProvider);

    final title = categoriesAsync.maybeWhen(
          data: (cats) => cats
              .where((c) => c.slug == categorySlug)
              .map((c) => c.title)
              .firstOrNull,
          orElse: () => null,
        ) ??
        'Help';

    return MyShopHelpCategoryScreen(
      title: title,
      state: articlesAsync.when(
        data: SupportLegalAsync<List<HelpArticle>>.data,
        loading: SupportLegalAsync<List<HelpArticle>>.loading,
        error: (e, _) => SupportLegalAsync<List<HelpArticle>>.error(e),
      ),
      onArticleTap: (a) =>
          context.push(AppRoutes.supportHelpArticlePath(a.slug)),
      onRefresh: () async {
        ref.invalidate(helpArticlesProvider(categorySlug));
        await ref.read(helpArticlesProvider(categorySlug).future);
      },
    );
  }
}

extension _IterableFirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
