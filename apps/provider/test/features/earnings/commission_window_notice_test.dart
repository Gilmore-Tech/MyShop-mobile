import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_provider/src/features/earnings/widgets/commission_window_notice.dart';
import 'package:shared_models/shared_models.dart';

void main() {
  testWidgets('shows the configured duration, deadline and full amount owed',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CommissionWindowNotice(
          window: CommissionPaymentWindow(
            windowHours: 72,
            dueAt: DateTime.now().add(const Duration(hours: 72)),
            outstandingPesewas: 1234,
            overdue: false,
          ),
        ),
      ),
    ));
    expect(find.textContaining('Commission payment due:'), findsOneWidget);
    expect(find.textContaining('GH₵ 12.34'), findsOneWidget);
    expect(find.textContaining('72-hour window'), findsOneWidget);
    expect(
        find.textContaining('Partial payments do not extend'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('deadline changes to an overdue message without another fetch',
      (tester) async {
    final dueAt = DateTime.now().add(const Duration(seconds: 1));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CommissionWindowNotice(
          window: CommissionPaymentWindow(
            windowHours: 48,
            dueAt: dueAt,
            outstandingPesewas: 1,
            overdue: false,
          ),
        ),
      ),
    ));
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(seconds: 2)));
    await tester.pump(const Duration(seconds: 2));
    expect(find.textContaining('window has ended'), findsOneWidget);
    expect(find.textContaining('Pay all GH₵ 0.01'), findsOneWidget);
    expect(find.textContaining('before going online'), findsOneWidget);
  });

  test('parses the server window and tolerates older summaries', () {
    final summary = EarningsSummary.fromJson({
      'commissionPaymentWindow': {
        'windowHours': 48,
        'dueAt': '2026-11-15T12:00:00Z',
        'outstandingPesewas': 1,
        'overdue': true,
      },
    });
    expect(summary.commissionPaymentWindow!.windowHours, 48);
    expect(summary.commissionPaymentWindow!.overdue, isTrue);
    expect(EarningsSummary.fromJson({}).commissionPaymentWindow, isNull);
    expect(CommissionPaymentWindow.tryParse({'windowHours': -1}), isNull);
  });
}
