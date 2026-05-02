import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

import '../providers/support_providers.dart';

class TicketDetailRouteScreen extends ConsumerWidget {
  const TicketDetailRouteScreen({super.key, required this.ticketId});

  final String ticketId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(ticketDetailProvider(ticketId));

    final ticketState = detail.when(
      data: (s) => s.ticket == null
          ? const SupportLegalAsync<SupportTicket>.loading()
          : SupportLegalAsync<SupportTicket>.data(s.ticket!),
      loading: SupportLegalAsync<SupportTicket>.loading,
      error: (e, _) => SupportLegalAsync<SupportTicket>.error(e),
    );

    final messagesState = detail.when(
      data: (s) => SupportLegalAsync<List<TicketMessage>>.data(s.messages),
      loading: SupportLegalAsync<List<TicketMessage>>.loading,
      error: (e, _) => SupportLegalAsync<List<TicketMessage>>.error(e),
    );

    return MyShopTicketDetailScreen(
      ticketState: ticketState,
      messagesState: messagesState,
      onSendMessage: (body) async {
        try {
          await ref
              .read(ticketDetailProvider(ticketId).notifier)
              .sendMessage(body);
        } catch (e) {
          if (context.mounted) {
            MyShopToast.show(
              context,
              message: 'Could not send. Try again.',
            );
          }
        }
      },
      onResolve: () => ref
          .read(ticketDetailProvider(ticketId).notifier)
          .setStatus('resolved'),
      onReopen: () => ref
          .read(ticketDetailProvider(ticketId).notifier)
          .setStatus('reopened'),
    );
  }
}
