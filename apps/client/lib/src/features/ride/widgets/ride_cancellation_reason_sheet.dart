import 'package:flutter/material.dart';

import '../../../core/widgets/cancellation_reason_sheet.dart';

const clientRideCancellationReasonsBeforeMatch = <String>[
  'I no longer need a ride',
  'The pickup point is wrong',
  'The search is taking too long',
  'I booked by mistake',
];

const clientRideCancellationReasonsAfterMatch = <String>[
  'My plans changed',
  'The driver is taking too long',
  'The driver asked me to cancel',
  'The pickup point is wrong',
  'I have a safety concern',
];

Future<String?> showClientRideCancellationReasonSheet(
  BuildContext context, {
  required bool driverAssigned,
}) {
  return showCancellationReasonSheet(
    context,
    title: 'Why are you cancelling?',
    helperText: 'Your reason helps support understand what happened.',
    reasons: driverAssigned
        ? clientRideCancellationReasonsAfterMatch
        : clientRideCancellationReasonsBeforeMatch,
    keepLabel: 'Keep ride',
  );
}
