import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';

void main() {
  // Convenience builder to mount the chat shell with minimal fluff.
  Widget mount({
    required List<ChatMessage> messages,
    bool isInputLocked = false,
    String? lockedReason,
    ValueChanged<String>? onRetry,
    ValueChanged<String>? onSend,
  }) {
    return MaterialApp(
      home: MyShopChatScreen(
        peerName: 'Kwame',
        peerStatus: 'Online',
        messages: messages,
        onSend: onSend ?? (_) {},
        onRetry: onRetry,
        isInputLocked: isInputLocked,
        lockedReason: lockedReason,
      ),
    );
  }

  group('rendering', () {
    testWidgets('renders both peer and own bubbles', (tester) async {
      await tester.pumpWidget(mount(messages: const [
        ChatMessage(
          id: '1',
          text: 'Hello there',
          time: '09:00 AM',
          fromMe: false,
        ),
        ChatMessage(
          id: '2',
          text: 'Hi back',
          time: '09:01 AM',
          fromMe: true,
          status: ChatMessageStatus.sent,
        ),
      ],),);

      expect(find.text('Hello there'), findsOneWidget);
      expect(find.text('Hi back'), findsOneWidget);
      // The peer header should also render the name we passed in.
      expect(find.text('Kwame'), findsOneWidget);
    });

    testWidgets('renders the clock icon for a pending own bubble',
        (tester) async {
      await tester.pumpWidget(mount(messages: const [
        ChatMessage(
          id: 'tmp_x',
          text: 'queued',
          time: '09:00 AM',
          fromMe: true,
          status: ChatMessageStatus.pending,
        ),
      ],),);

      expect(find.byIcon(Icons.schedule), findsOneWidget);
    });

    testWidgets('renders the double-check tick for a read own bubble',
        (tester) async {
      await tester.pumpWidget(mount(messages: const [
        ChatMessage(
          id: '1',
          text: 'seen',
          time: '09:00 AM',
          fromMe: true,
          status: ChatMessageStatus.read,
        ),
      ],),);

      expect(find.byIcon(Icons.done_all), findsOneWidget);
    });
  });

  group('failed + retry', () {
    testWidgets(
        'renders the error icon and Retry link for a failed own bubble',
        (tester) async {
      await tester.pumpWidget(mount(
        onRetry: (_) {},
        messages: const [
          ChatMessage(
            id: 'tmp_failed',
            text: 'didn’t send',
            time: '09:00 AM',
            fromMe: true,
            status: ChatMessageStatus.failed,
          ),
        ],
      ),);

      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('tapping Retry forwards the message id to onRetry',
        (tester) async {
      String? tapped;
      await tester.pumpWidget(mount(
        onRetry: (id) => tapped = id,
        messages: const [
          ChatMessage(
            id: 'tmp_failed',
            text: 'didn’t send',
            time: '09:00 AM',
            fromMe: true,
            status: ChatMessageStatus.failed,
          ),
        ],
      ),);

      await tester.tap(find.text('Retry'));
      await tester.pump();

      expect(tapped, 'tmp_failed');
    });

    testWidgets(
        'omits the Retry link when no onRetry callback is wired',
        (tester) async {
      await tester.pumpWidget(mount(messages: const [
        ChatMessage(
          id: 'tmp_failed',
          text: 'didn’t send',
          time: '09:00 AM',
          fromMe: true,
          status: ChatMessageStatus.failed,
        ),
      ],),);

      // Icon still renders so the user knows it failed; no tap target.
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
    });
  });

  group('locked composer', () {
    testWidgets('hides the composer and shows the locked banner '
        'when isInputLocked is true', (tester) async {
      await tester.pumpWidget(mount(
        isInputLocked: true,
        messages: const [
          ChatMessage(
            id: '1',
            text: 'last word',
            time: '09:00 AM',
            fromMe: false,
          ),
        ],
      ),);

      expect(find.byType(TextField), findsNothing);
      expect(
        find.text('This chat is closed because the booking ended.'),
        findsOneWidget,
      );
      // A small lock affordance should be visible too.
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    });

    testWidgets('renders a custom lockedReason verbatim',
        (tester) async {
      await tester.pumpWidget(mount(
        isInputLocked: true,
        lockedReason: 'Cancelled by you',
        messages: const [],
      ),);

      expect(find.text('Cancelled by you'), findsOneWidget);
    });

    testWidgets('keeps the composer visible when not locked',
        (tester) async {
      await tester.pumpWidget(mount(messages: const []));
      expect(find.byType(TextField), findsOneWidget);
    });
  });
}
