import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_client/src/features/profile/providers/referral_provider.dart';
import 'package:myshop_client/src/features/profile/screens/referral_screen.dart';

const _shareChannel = MethodChannel('dev.fluttercommunity.plus/share');

Future<void> _pumpScreen(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        referralProvider.overrideWith(
          (ref) async => const ReferralData(
            code: 'AMA10',
            totalReferrals: 0,
            pendingPesewas: 0,
            earnedPesewas: 0,
            recentReferrals: [],
          ),
        ),
      ],
      child: const MaterialApp(home: ReferralScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Copy Code writes the referral code to the clipboard',
      (tester) async {
    final clipboardCalls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') clipboardCalls.add(call);
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    await _pumpScreen(tester);
    await tester.ensureVisible(find.text('Copy Code'));
    await tester.tap(find.text('Copy Code'));
    await tester.pump();

    expect(clipboardCalls, isNotEmpty);
    expect(clipboardCalls.first.arguments['text'], 'AMA10');

    // Drain the toast auto-dismiss timer so the test tears down cleanly.
    await tester.pumpAndSettle(const Duration(seconds: 4));
  });

  testWidgets('Share invokes the share_plus platform channel', (tester) async {
    final shareCalls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      _shareChannel,
      (call) async {
        shareCalls.add(call);
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(_shareChannel, null));

    await _pumpScreen(tester);
    await tester.ensureVisible(find.text('Share'));
    await tester.tap(find.text('Share'));
    await tester.pump();

    expect(shareCalls, isNotEmpty,
        reason: 'Share button should call the share_plus channel');
    expect(shareCalls.first.arguments['text'], contains('AMA10'));
  });
}
