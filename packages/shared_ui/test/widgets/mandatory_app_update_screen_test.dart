import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';

void main() {
  testWidgets('opens the exact server-approved HTTPS store URL',
      (tester) async {
    final opened = <Uri>[];
    final storeUrl = Uri.parse('https://store.example.test/myshop');
    await tester.pumpWidget(
      MaterialApp(
        home: MandatoryAppUpdateScreen(
          message: 'Install the latest release to continue.',
          storeUrl: storeUrl,
          launchStore: (uri) async {
            opened.add(uri);
            return true;
          },
        ),
      ),
    );

    expect(find.text('Update required'), findsOneWidget);
    expect(
      find.text('Install the latest release to continue.'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('mandatory-update-button')));
    await tester.pump();

    expect(opened, [storeUrl]);
  });

  testWidgets('remains blocking and explains a missing update link',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MandatoryAppUpdateScreen(
          message: 'Update to continue.',
          storeUrl: null,
        ),
      ),
    );

    final popScope = tester.widget<PopScope>(find.byType(PopScope));
    expect(popScope.canPop, isFalse);
    expect(
      find.byKey(const Key('mandatory-update-missing-link')),
      findsOneWidget,
    );
    final button = tester.widget<FilledButton>(
      find.byKey(const Key('mandatory-update-button')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('shows an actionable error when the store cannot open',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MandatoryAppUpdateScreen(
          message: 'Update to continue.',
          storeUrl: Uri.parse('https://store.example.test/myshop'),
          launchStore: (_) async => false,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('mandatory-update-button')));
    await tester.pump();

    expect(
      find.byKey(const Key('mandatory-update-launch-error')),
      findsOneWidget,
    );
    expect(
      find.text('Could not open the app store. Please try again.'),
      findsOneWidget,
    );
  });
}
