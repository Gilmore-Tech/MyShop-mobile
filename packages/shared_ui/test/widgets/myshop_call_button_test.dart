import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';

void main() {
  Widget buildButton({
    String? phoneNumber,
    VoidCallback? onInAppCall,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: MyShopCallButton(
          phoneNumber: phoneNumber,
          onInAppCall: onInAppCall,
        ),
      ),
    );
  }

  testWidgets('starts an in-app call when no phone number is available',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      buildButton(onInAppCall: () => calls += 1),
    );

    expect(find.byIcon(Icons.call_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.call_rounded));
    await tester.pump();

    expect(calls, 1);
    expect(find.text('Phone call'), findsNothing);
  });

  testWidgets('offers in-app and phone choices when both are available',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      buildButton(
        phoneNumber: '+233 24 123 4567',
        onInAppCall: () => calls += 1,
      ),
    );

    await tester.tap(find.byIcon(Icons.call_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Call in app'), findsOneWidget);
    expect(find.text('Phone call'), findsOneWidget);

    await tester.tap(find.text('Call in app'));
    await tester.pumpAndSettle();
    expect(calls, 1);
  });

  testWidgets('renders nothing when neither call path is available',
      (tester) async {
    await tester.pumpWidget(buildButton());

    expect(find.byIcon(Icons.call_rounded), findsNothing);
  });
}
