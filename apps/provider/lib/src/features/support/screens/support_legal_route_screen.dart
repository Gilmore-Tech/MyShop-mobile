import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

import '../providers/support_providers.dart';

class SupportLegalRouteScreen extends ConsumerWidget {
  const SupportLegalRouteScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(helpCategoriesProvider);
    final ticketsAsync = ref.watch(ticketsListProvider);
    final unread = ticketsAsync.maybeWhen(
      data: (s) =>
          s.tickets.where((t) => t.hasUnread).fold<int>(0, (a, _) => a + 1),
      orElse: () => 0,
    );

    final config = SupportLegalConfig(
      audience: kProviderSupportAudience,
      appName: 'MyShop Provider',
      appVersion: 'Version 1.0.0',
      copyright: '© 2026 Gilmore Tech. All rights reserved.',
      supportEmail: 'support@myshop.com.gh',
      supportPhone: '+233 30 000 0000',
      whatsappNumber: '233300000000',
      onOpenTickets: () => context.push('/account/support/tickets'),
      onNewTicket: (preselect) => context.push(
        '/account/support/tickets/new',
        extra: {'preselectedCategory': preselect},
      ),
      onOpenCategory: (slug) => context.push('/account/support/help/$slug'),
      onOpenArticle: (slug) =>
          context.push('/account/support/help/article/$slug'),
      onOpenSearch: (q) => context.push(
        q == null
            ? '/account/support/search'
            : '/account/support/search?q=${Uri.encodeQueryComponent(q)}',
      ),
      onOpenLegal: (slug) => context.push('/legal/$slug'),
      onOpenContactSheet: () => MyShopContactSupportSheet.show(
        context,
        whatsappNumber: '233300000000',
        supportPhone: '+233 30 000 0000',
        supportEmail: 'support@myshop.com.gh',
        onNewTicket: () => context.push(
          '/account/support/tickets/new',
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
