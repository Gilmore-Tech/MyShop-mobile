import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../app/router.dart';
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
      audience: kClientSupportAudience,
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
            // Replace the new-ticket route with the detail screen so back
            // returns to the tickets list, not the empty form.
            context.pushReplacement(
              AppRoutes.supportTicketDetailPath(ticket.id),
            );
          }
          return false; // We've already navigated; don't pop.
        } catch (e) {
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
