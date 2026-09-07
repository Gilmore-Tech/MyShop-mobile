import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_provider/src/core/providers/provider_connection_recovery_provider.dart';

void main() {
  testWidgets('brief repeated interruptions never display a notice',
      (tester) async {
    final recovery = ProviderConnectionRecoveryController();
    addTearDown(recovery.dispose);
    for (var i = 0; i < 5; i++) {
      recovery.interrupted();
      await tester.pump(const Duration(seconds: 45));
      expect(recovery.state, isFalse);
      recovery.recovered();
      await tester.pump(const Duration(seconds: 15));
    }
    expect(recovery.state, isFalse);
  });

  testWidgets('one persistent notice after two minutes, cleared on recovery',
      (tester) async {
    final recovery = ProviderConnectionRecoveryController();
    addTearDown(recovery.dispose);
    recovery.interrupted();
    await tester.pump(const Duration(seconds: 90));
    recovery.interrupted();
    expect(recovery.state, isFalse);
    await tester.pump(const Duration(seconds: 30));
    expect(recovery.state, isTrue);
    recovery.dismissNotice();
    recovery.interrupted();
    await tester.pump(const Duration(minutes: 3));
    expect(recovery.state, isFalse,
        reason: 'do not nag again in the same outage');
    recovery.recovered();
    recovery.interrupted();
    await tester.pump(const Duration(minutes: 2));
    expect(recovery.state, isTrue);
    recovery.recovered();
    expect(recovery.state, isFalse);
  });
}
