import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';

import '../providers/support_providers.dart';

class HelpSearchRouteScreen extends ConsumerWidget {
  const HelpSearchRouteScreen({super.key, this.initialQuery});

  final String? initialQuery;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MyShopHelpSearchScreen(
      initialQuery: initialQuery,
      onSearch: (q) => ref.read(helpServiceProvider).searchArticles(
            query: q,
            audience: kProviderSupportAudience,
          ),
      onArticleTap: (a) =>
          context.push('/account/support/help/article/${a.slug}'),
    );
  }
}
