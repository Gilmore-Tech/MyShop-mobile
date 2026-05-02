import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

import '../providers/support_providers.dart';

class HelpArticleRouteScreen extends ConsumerWidget {
  const HelpArticleRouteScreen({super.key, required this.slug});

  final String slug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final articleAsync = ref.watch(helpArticleProvider(slug));

    return MyShopHelpArticleScreen(
      state: articleAsync.when(
        data: SupportLegalAsync<HelpArticle>.data,
        loading: SupportLegalAsync<HelpArticle>.loading,
        error: (e, _) => SupportLegalAsync<HelpArticle>.error(e),
      ),
      onContactSupport: () => MyShopContactSupportSheet.show(
        context,
        whatsappNumber: '233300000000',
        supportPhone: '+233 30 000 0000',
        supportEmail: 'support@myshop.com.gh',
        onNewTicket: () => Navigator.of(context).maybePop(),
      ),
      onRefresh: () async {
        ref.invalidate(helpArticleProvider(slug));
        await ref.read(helpArticleProvider(slug).future);
      },
    );
  }
}
