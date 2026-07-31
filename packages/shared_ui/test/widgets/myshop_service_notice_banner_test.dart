import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';

void main() {
  testWidgets(
    'client active-job and provider active-ride bottom CTAs stay hit-testable',
    (tester) async {
      for (final scenario in const [
        ('client-active-job', 'Confirm artisan completion'),
        ('provider-active-ride', 'End trip'),
      ]) {
        var retries = 0;
        var lifecycleTaps = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: MyShopServiceNoticeOverlay(
              kind: MyShopServiceNoticeKind.offline,
              hasActiveWork: true,
              onRetry: () => retries++,
              topNotices: const [
                SizedBox(
                  key: Key('existing-location-notice'),
                  height: 48,
                  child: ColoredBox(color: Colors.orange),
                ),
              ],
              child: Scaffold(
                body: Stack(
                  children: [
                    const Center(child: TextField(key: Key('existing-form'))),
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 12,
                      child: FilledButton(
                        key: Key('${scenario.$1}-lifecycle-action'),
                        onPressed: () => lifecycleTaps++,
                        child: Text(scenario.$2),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

        await tester.enterText(find.byKey(const Key('existing-form')), 'draft');
        await tester.tap(find.byKey(Key('${scenario.$1}-lifecycle-action')));
        await tester.tap(find.byKey(const Key('service-connectivity-retry')));
        await tester.pump();

        expect(lifecycleTaps, 1);
        expect(retries, 1);
        expect(find.text('draft'), findsOneWidget);
        expect(find.text(scenario.$2), findsOneWidget);
        expect(find.text('No internet connection'), findsOneWidget);
        expect(find.text('Log out'), findsNothing);
        expect(
          tester
              .getTopLeft(find.byKey(const Key('service-connectivity-notice')))
              .dy,
          lessThan(
            tester
                .getTopLeft(find.byKey(Key('${scenario.$1}-lifecycle-action')))
                .dy,
          ),
        );
      }
    },
  );

  testWidgets('uses service copy without exposing an error payload', (
    tester,
  ) async {
    for (final kind in MyShopServiceNoticeKind.values) {
      await tester.pumpWidget(
        MaterialApp(
          home: MyShopServiceNoticeBanner(kind: kind, onRetry: () {}),
        ),
      );

      expect(
        find.text('Connect to the internet and try again.'),
        findsOneWidget,
      );
      expect(find.textContaining('current screen'), findsNothing);
      expect(find.textContaining('Internal Server Error'), findsNothing);
    }
  });

  testWidgets(
    'blocking mode preserves the route but intercepts background taps',
    (tester) async {
      var underlyingTaps = 0;
      var retries = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: MyShopServiceNoticeOverlay(
            kind: MyShopServiceNoticeKind.timeout,
            hasActiveWork: false,
            onRetry: () => retries++,
            child: Scaffold(
              body: TextButton(
                key: const Key('blocked-background-action'),
                onPressed: () => underlyingTaps++,
                child: const Text('Background action'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(
        find.byKey(const Key('blocked-background-action')),
        warnIfMissed: false,
      );
      await tester.tap(find.byKey(const Key('service-connectivity-retry')));
      await tester.pump();

      expect(underlyingTaps, 0);
      expect(retries, 1);
      expect(
        find.byKey(const Key('blocked-background-action')),
        findsOneWidget,
      );
      expect(find.text('Connection timed out'), findsOneWidget);
    },
  );
}
