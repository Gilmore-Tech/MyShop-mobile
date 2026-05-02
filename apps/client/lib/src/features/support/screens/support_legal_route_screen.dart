import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../app/router.dart';
import '../providers/support_providers.dart';

/// Per-app glue for the lifted `MyShopSupportLegalScreen`.
///
/// Owns the [SupportLegalConfig] (audience, copy, support contact info,
/// nav callbacks) and the `helpCategoriesProvider` watch.
class SupportLegalRouteScreen extends ConsumerWidget {
  const SupportLegalRouteScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(helpCategoriesProvider);
    final ticketsAsync = ref.watch(ticketsListProvider);
    final unread = ticketsAsync.maybeWhen(
      data: (s) =>
          s.tickets.where((t) => t.hasUnread).fold<int>(0, (a, t) => a + 1),
      orElse: () => 0,
    );

    final config = SupportLegalConfig(
      audience: kClientSupportAudience,
      appName: 'MyShop',
      appVersion: 'Version 1.0.0',
      copyright: '© 2026 Gilmore Tech. All rights reserved.',
      supportEmail: 'support@myshop.com.gh',
      supportPhone: '+233 30 000 0000',
      whatsappNumber: '233300000000', // E.164 without leading +
      onOpenTickets: () => context.push(AppRoutes.supportTickets),
      onNewTicket: (preselect) => context.push(
        AppRoutes.supportNewTicket,
        extra: {'preselectedCategory': preselect},
      ),
      onOpenCategory: (slug) =>
          context.push(AppRoutes.supportHelpCategoryPath(slug)),
      onOpenArticle: (slug) =>
          context.push(AppRoutes.supportHelpArticlePath(slug)),
      onOpenSearch: (q) => context.push(
        q == null
            ? AppRoutes.supportHelpSearch
            : '${AppRoutes.supportHelpSearch}?q=${Uri.encodeQueryComponent(q)}',
      ),
      onOpenLegal: (slug) => context.push(AppRoutes.legalDocumentPath(slug)),
      onOpenContactSheet: () => MyShopContactSupportSheet.show(
        context,
        whatsappNumber: '233300000000',
        supportPhone: '+233 30 000 0000',
        supportEmail: 'support@myshop.com.gh',
        onNewTicket: () => context.push(
          AppRoutes.supportNewTicket,
          extra: const <String, Object?>{
            'preselectedCategory': TicketCategory.other,
          },
        ),
      ),
    );

    return MyShopSupportLegalScreen(
      config: config,
      categoriesAsync: asSupportAsync(categoriesAsync),
      openTicketsBadge: unread,
    );
  }
}
