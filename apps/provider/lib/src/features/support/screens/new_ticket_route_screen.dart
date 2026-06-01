import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

import '../providers/support_providers.dart';

class NewTicketRouteScreen extends ConsumerWidget {
  const NewTicketRouteScreen({
    super.key,
    this.preselectedCategory,
    this.referenceType,
    this.referenceId,
  });

  final TicketCategory? preselectedCategory;
  final String? referenceType;
  final String? referenceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MyShopNewTicketScreen(
      audience: kProviderSupportAudience,
      preselectedCategory: preselectedCategory,
      referenceType: referenceType,
      referenceId: referenceId,
      onSubmit: ({
        required category,
        required subject,
        required description,
        required attachments,
      }) async {
        try {
          final ticket = await ref.read(createTicketControllerProvider).submit(
                category: category,
                subject: subject,
                description: description,
                attachments: attachments,
                referenceType: referenceType,
                referenceId: referenceId,
              );
          if (context.mounted) {
            context.pushReplacement(
              '/account/support/tickets/${ticket.id}',
            );
          }
          return false;
        } catch (_) {
          if (context.mounted) {
            MyShopToast.show(
              context,
              message: 'Could not file the ticket. Try again.',
            );
          }
          return false;
        }
      },
    );
  }
}
