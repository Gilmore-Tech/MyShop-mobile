import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';

void main() {
  Widget buildView({
    required bool incomingRinging,
    bool isLoading = false,
    VoidCallback? onAccept,
    VoidCallback? onDecline,
  }) {
    return MaterialApp(
      home: MyShopInAppCallView(
        peerName: 'Abena Bobie',
        statusLabel: incomingRinging ? 'Incoming call' : 'Ringing…',
        contextLabel: 'Ride voice call',
        isLoading: isLoading,
        isEnding: false,
        muted: false,
        speakerOn: false,
        incomingRinging: incomingRinging,
        onAcceptCall: onAccept,
        onDeclineCall: onDecline,
        onToggleMuted: () {},
        onToggleSpeaker: () {},
        onEndCall: () {},
      ),
    );
  }

  testWidgets('shows explicit accept and decline controls for an incoming call',
      (tester) async {
    var accepted = false;
    var declined = false;
    await tester.pumpWidget(
      buildView(
        incomingRinging: true,
        onAccept: () => accepted = true,
        onDecline: () => declined = true,
      ),
    );

    expect(find.text('Accept'), findsOneWidget);
    expect(find.text('Decline'), findsOneWidget);
    expect(find.byTooltip('Mute'), findsNothing);

    await tester.tap(find.byIcon(Icons.call_rounded));
    await tester.pump();
    expect(accepted, isTrue);

    await tester.tap(find.byIcon(Icons.call_end_rounded));
    await tester.pump();
    expect(declined, isTrue);
  });

  testWidgets('shows media controls for an outgoing or connected call',
      (tester) async {
    await tester.pumpWidget(buildView(incomingRinging: false));

    expect(find.text('Accept'), findsNothing);
    expect(find.text('Decline'), findsNothing);
    expect(find.byTooltip('Mute'), findsOneWidget);
    expect(find.byTooltip('Speaker'), findsOneWidget);
    expect(find.byTooltip('End call'), findsOneWidget);
  });

  testWidgets('hides call actions while the session is loading',
      (tester) async {
    await tester.pumpWidget(
      buildView(incomingRinging: false, isLoading: true),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Accept'), findsNothing);
    expect(find.text('Decline'), findsNothing);
    expect(find.byTooltip('Mute'), findsNothing);
    expect(find.byTooltip('End call'), findsNothing);
    expect(find.byTooltip('Speaker'), findsNothing);
  });
}
