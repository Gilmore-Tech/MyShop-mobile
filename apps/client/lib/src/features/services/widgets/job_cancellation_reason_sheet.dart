import 'package:flutter/material.dart';

import '../../../core/widgets/cancellation_reason_sheet.dart';

const clientJobCancellationReasons = <String>[
  'My plans changed',
  'The job details are wrong',
  'The schedule changed',
  'I found another service provider',
  'I have a safety concern',
];

Future<String?> showClientJobCancellationReasonSheet(BuildContext context) {
  return showCancellationReasonSheet(
    context,
    title: 'Why are you cancelling this job?',
    helperText: 'Your reason helps support understand what happened.',
    reasons: clientJobCancellationReasons,
    keepLabel: 'Keep job',
  );
}
