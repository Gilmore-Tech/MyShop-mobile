import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

import '../providers/support_providers.dart';

class TicketsListRouteScreen extends ConsumerWidget {
  const TicketsListRouteScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(ticketsListProvider);

    final shellState = state.when(
      data: (s) => SupportLegalAsync<List<SupportTicket>>.data(s.tickets),
      loading: SupportLegalAsync<List<SupportTicket>>.loading,
      error: (e, _) => SupportLegalAsync<List<SupportTicket>>.error(e),
    );

    final hasMore = state.maybeWhen(
      data: (s) => s.hasMore,
      orElse: () => false,
    );

    return MyShopTicketsListScreen(
      state: shellState,
      hasMore: hasMore,
      onTicketTap: (t) => context.push('/account/support/tickets/${t.id}'),
      onNewTicket: () => context.push('/account/support/tickets/new'),
      onRefresh: () => ref.read(ticketsListProvider.notifier).refresh(),
      onLoadMore: () => ref.read(ticketsListProvider.notifier).loadMore(),
    );
  }
}
