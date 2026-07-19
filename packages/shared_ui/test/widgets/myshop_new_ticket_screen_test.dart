import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

void main() {
  testWidgets('BR-61 defaults to a truthful text-only support ticket',
      (tester) async {
    List<File>? submittedAttachments;

    await tester.pumpWidget(
      MaterialApp(
        home: MyShopNewTicketScreen(
          audience: SupportAudience.client,
          onSubmit: ({
            required category,
            required subject,
            required description,
            required attachments,
          }) async {
            submittedAttachments = attachments;
            return false;
          },
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('support-attachments-disabled-notice')),
      findsOneWidget,
    );
    expect(
      find.textContaining('Attachments are temporarily unavailable'),
      findsOneWidget,
    );
    expect(find.text('0/4'), findsNothing);

    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(2));
    await tester.enterText(fields.at(0), 'Payment issue');
    await tester.enterText(fields.at(1), 'The payment status has not updated.');
    await tester.tap(find.text('Submit ticket'));
    await tester.pump();

    expect(submittedAttachments, isEmpty);
  });
}
