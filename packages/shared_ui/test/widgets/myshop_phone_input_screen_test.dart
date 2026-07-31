import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:shared_ui/shared_ui.dart';

void main() {
  testWidgets('can lock provider registration to Ghana', (tester) async {
    String? submitted;
    await tester.pumpWidget(
      MaterialApp(
        home: MyShopPhoneInputScreen(
          title: 'Verify your phone',
          subtitle: 'Enter your number',
          ghanaOnly: true,
          phoneValidator: Validators.ghanaE164Phone,
          invalidPhoneMessage: 'Enter a valid Ghana phone number.',
          onSubmit: (phone) => submitted = phone,
        ),
      ),
    );

    final field =
        tester.widget<IntlPhoneField>(find.byType(IntlPhoneField));
    expect(field.countries, hasLength(1));
    expect(field.countries!.single.code, 'GH');
    expect(field.showDropdownIcon, isFalse);

    await tester.enterText(find.byType(TextField), '241234567');
    await tester.tap(find.text('Send code'));
    await tester.pump();

    expect(submitted, '+233241234567');
  });

  testWidgets('rejects a malformed Ghana number before submitting',
      (tester) async {
    var submissions = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: MyShopPhoneInputScreen(
          title: 'Verify your phone',
          subtitle: 'Enter your number',
          ghanaOnly: true,
          phoneValidator: Validators.ghanaE164Phone,
          invalidPhoneMessage: 'Enter a valid Ghana phone number.',
          onSubmit: (_) => submissions += 1,
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), '34123456');
    await tester.pump();
    await tester.tap(find.text('Send code'));
    await tester.pumpAndSettle();

    expect(submissions, 0);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(
      field.decoration?.errorText,
      'Enter a valid Ghana phone number.',
    );
  });
}
