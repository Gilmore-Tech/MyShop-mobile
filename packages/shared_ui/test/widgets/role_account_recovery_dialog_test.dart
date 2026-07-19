import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';

void main() {
  testWidgets(
      'files provider recovery with one stable request key and no rejection action',
      (tester) async {
    var requestCalls = 0;
    final verifyCalls = <(String, String)>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showMyShopRoleAccountRecoveryDialog(
              context: context,
              phone: '+233241234567',
              role: 'driver',
              requestKey: '11111111-1111-4111-8111-111111111111',
              requestOtp: () async => requestCalls += 1,
              verifyOtp: (otp, requestKey) async =>
                  verifyCalls.add((otp, requestKey)),
              errorMessage: (_) => 'Safe error',
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.textContaining('other roles'), findsOneWidget);
    expect(find.textContaining('Reject'), findsNothing);

    await tester.tap(find.byKey(const Key('role-recovery-send-code')));
    await tester.pumpAndSettle();
    expect(requestCalls, 1);

    await tester.enterText(
      find.byKey(const Key('role-recovery-otp')),
      '123456',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('role-recovery-submit')));
    await tester.pumpAndSettle();

    expect(verifyCalls, [
      ('123456', '11111111-1111-4111-8111-111111111111'),
    ]);
    expect(find.textContaining('regional Admin'), findsOneWidget);
    expect(find.textContaining('Regional Manager'), findsOneWidget);
  });

  testWidgets('surfaces only the caller-provided safe error', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showMyShopRoleAccountRecoveryDialog(
              context: context,
              phone: '+233241234567',
              role: 'client',
              requestKey: '11111111-1111-4111-8111-111111111111',
              requestOtp: () => throw StateError('private transport detail'),
              verifyOtp: (_, __) async {},
              errorMessage: (_) => 'Recovery is temporarily unavailable.',
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('role-recovery-send-code')));
    await tester.pumpAndSettle();

    expect(find.text('Recovery is temporarily unavailable.'), findsOneWidget);
    expect(find.textContaining('private transport detail'), findsNothing);
  });
}
