import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:fake_async/fake_async.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_models/shared_models.dart';
import 'package:test/test.dart';

class _MockChatService extends Mock implements ChatService {}

class _MockChatRealtime extends Mock implements ChatRealtime {}

const _selfId = 'user-self';
const _otherId = 'user-other';
const _bookingId = 'booking-1';

void main() {
  // Mocktail needs registered fallbacks for any non-primitive named arg
  // we match with `any(named: ...)`. These cover the controller's usage.
  setUpAll(() {
    registerFallbackValue(ChatBookingType.ride);
    registerFallbackValue(<String, dynamic>{});
  });

  late _MockChatService rest;
  late _MockChatRealtime realtime;
  late InMemoryChatOutbox outbox;
  late StreamController<ChatMessage> incomingCtrl;
  late StreamController<ChatReadReceipt> readReceiptCtrl;
  late StreamController<ChatChannelClosedEvent> channelClosedCtrl;
  late StreamController<bool> connectionCtrl;
  late StreamController<ChatTypingUpdate> typingCtrl;
  late ChatController controller;

  setUp(() {
    rest = _MockChatService();
    realtime = _MockChatRealtime();
    outbox = InMemoryChatOutbox();
    incomingCtrl = StreamController<ChatMessage>.broadcast();
    readReceiptCtrl = StreamController<ChatReadReceipt>.broadcast();
    channelClosedCtrl = StreamController<ChatChannelClosedEvent>.broadcast();
    connectionCtrl = StreamController<bool>.broadcast();
    typingCtrl = StreamController<ChatTypingUpdate>.broadcast();

    when(() => realtime.incomingMessages)
        .thenAnswer((_) => incomingCtrl.stream);
    when(() => realtime.readReceipts).thenAnswer((_) => readReceiptCtrl.stream);
    when(() => realtime.channelClosed)
        .thenAnswer((_) => channelClosedCtrl.stream);
    when(() => realtime.connectionStream)
        .thenAnswer((_) => connectionCtrl.stream);
    when(() => realtime.typingUpdates).thenAnswer((_) => typingCtrl.stream);
    when(() => realtime.connect()).thenAnswer((_) async {});
    when(() => realtime.joinChannel(any(), any())).thenAnswer((_) async {});
    when(() => realtime.leaveChannel()).thenReturn(null);
    when(() => realtime.sendTyping(isTyping: any(named: 'isTyping')))
        .thenReturn(null);
    when(() => rest.getMessages(any(), any())).thenAnswer((_) async => []);

    controller = ChatController(
      rest: rest,
      realtime: realtime,
      outbox: outbox,
      selfUserId: _selfId,
      selfRole: ChatSenderRole.client,
    );
  });

  tearDown(() async {
    await incomingCtrl.close();
    await readReceiptCtrl.close();
    await channelClosedCtrl.close();
    await connectionCtrl.close();
    await typingCtrl.close();
    await controller.dispose();
  });

  Future<void> openRideChannel() async {
    await controller.openChannel(ChatBookingType.ride, _bookingId);
  }

  ChatMessage serverMessage({
    required String id,
    required String senderId,
    required String text,
    DateTime? createdAt,
    DateTime? readAt,
  }) {
    return ChatMessage(
      id: id,
      senderId: senderId,
      message: text,
      createdAt: createdAt ?? DateTime.now().toUtc(),
      readAt: readAt,
    );
  }

  group('send', () {
    test(
        'optimistic-appends a tmp_, then swaps for the server id when '
        'the socket ack lands first', () async {
      await openRideChannel();
      final saved = serverMessage(
        id: 'srv-1',
        senderId: _selfId,
        text: 'hi',
      );
      when(() => realtime.sendMessage(message: any(named: 'message')))
          .thenAnswer((_) async => saved);

      final result = await controller.send('hi');

      expect(result, equals(saved));
      expect(controller.currentMessages, hasLength(1));
      expect(controller.currentMessages.single.id, 'srv-1');
      // Outbox should be drained once the server-side id is committed.
      expect(await outbox.readForChannel('ride:$_bookingId'), isEmpty);
    });

    test(
        'falls back to REST when the socket ack times out and still '
        'replaces the tmp_ message', () async {
      await openRideChannel();
      when(() => realtime.sendMessage(message: any(named: 'message')))
          .thenThrow(
        const ChatRealtimeException(
          code: ChatErrorCodes.ackTimeout,
          message: 'timed out',
        ),
      );
      final saved = serverMessage(
        id: 'srv-via-rest',
        senderId: _selfId,
        text: 'hi',
      );
      when(
        () => rest.sendMessage(
          any(),
          any(),
          message: any(named: 'message'),
        ),
      ).thenAnswer((_) async => saved);

      final result = await controller.send('hi');

      expect(result?.id, 'srv-via-rest');
      expect(controller.currentMessages.single.id, 'srv-via-rest');
      expect(await outbox.readForChannel('ride:$_bookingId'), isEmpty);
      verify(
        () => rest.sendMessage(
          ChatBookingType.ride,
          _bookingId,
          message: 'hi',
        ),
      ).called(1);
    });

    test(
        'keeps the tmp_ message in the outbox and reports failure when '
        'both the socket and REST fail', () async {
      await openRideChannel();
      when(() => realtime.sendMessage(message: any(named: 'message')))
          .thenThrow(
        const ChatRealtimeException(
          code: ChatErrorCodes.ackTimeout,
          message: 'timed out',
        ),
      );
      when(
        () => rest.sendMessage(
          any(),
          any(),
          message: any(named: 'message'),
        ),
      ).thenThrow(Exception('network'));

      final result = await controller.send('hi');

      expect(result, isNull);
      // The optimistic bubble must remain visible so the user can retry.
      expect(controller.currentMessages, hasLength(1));
      expect(
        controller.currentMessages.single.id.startsWith('tmp_'),
        isTrue,
      );
      // Outbox keeps the failed item with its attempt count bumped.
      final pending = await outbox.readForChannel('ride:$_bookingId');
      expect(pending, hasLength(1));
      expect(pending.single.attemptCount, greaterThanOrEqualTo(1));
    });

    test(
        'treats socket CHAT_CHANNEL_CLOSED as terminal and locks the '
        'channel state', () async {
      await openRideChannel();
      when(() => realtime.sendMessage(message: any(named: 'message')))
          .thenThrow(
        const ChatRealtimeException(
          code: ChatErrorCodes.channelClosed,
          message: 'closed',
        ),
      );

      final result = await controller.send('hi');

      expect(result, isNull);
      expect(controller.currentChannel?.isClosed, isTrue);
      // No REST attempt — backend already rejected.
      verifyNever(
        () => rest.sendMessage(
          any(),
          any(),
          message: any(named: 'message'),
        ),
      );
    });
  });

  group('inbound dedupe', () {
    test('ignores a message id that is already in the list', () async {
      await openRideChannel();
      final m = serverMessage(id: 'srv-1', senderId: _otherId, text: 'hello');

      incomingCtrl.add(m);
      await Future<void>.delayed(Duration.zero);
      incomingCtrl.add(m);
      await Future<void>.delayed(Duration.zero);

      expect(controller.currentMessages, hasLength(1));
    });

    test(
        'matches our own broadcast against a still-pending tmp_ entry '
        'and swaps in place rather than appending a duplicate', () async {
      await openRideChannel();
      // Own send still in-flight (socket "hangs" — no completion).
      final neverComplete = Completer<ChatMessage>();
      when(() => realtime.sendMessage(message: any(named: 'message')))
          .thenAnswer((_) => neverComplete.future);
      final sendFuture = controller.send('hi');
      // The optimistic bubble is in the list now.
      expect(controller.currentMessages, hasLength(1));
      expect(
        controller.currentMessages.single.id.startsWith('tmp_'),
        isTrue,
      );

      // Server broadcasts our own message back to the room before the
      // ack arrives (rare but real — the spec calls it out).
      final broadcast = serverMessage(
        id: 'srv-broadcast',
        senderId: _selfId,
        text: 'hi',
      );
      incomingCtrl.add(broadcast);
      await Future<void>.delayed(Duration.zero);

      expect(controller.currentMessages, hasLength(1));
      expect(controller.currentMessages.single.id, 'srv-broadcast');

      // Tidy up — settle the dangling future so dispose doesn't whine.
      neverComplete.complete(broadcast);
      await sendFuture;
    });
  });

  group('channel close', () {
    test(
        'flips the channel status to closed and clears the outbox when '
        'chat:channel:closed lands', () async {
      await openRideChannel();
      // Drop a stub failed item into the outbox so we can assert the
      // close clears it (any further retry would just 410).
      await outbox.upsert(
        ChatOutboxItem(
          tempId: 'tmp_x',
          channelKey: 'ride:$_bookingId',
          message: 'stuck',
          queuedAt: DateTime.now().toUtc(),
        ),
      );
      expect(await outbox.readForChannel('ride:$_bookingId'), hasLength(1));

      channelClosedCtrl.add(
        const ChatChannelClosedEvent(
          bookingType: ChatBookingType.ride,
          bookingId: _bookingId,
          reason: 'completed',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(controller.currentChannel?.isClosed, isTrue);
      expect(await outbox.readForChannel('ride:$_bookingId'), isEmpty);
    });
  });

  group('markRead', () {
    test('skips own messages', () async {
      await openRideChannel();
      // Pre-populate with our own message.
      final mine = serverMessage(
        id: 'mine-1',
        senderId: _selfId,
        text: 'hi',
      );
      incomingCtrl.add(mine);
      await Future<void>.delayed(Duration.zero);

      await controller.markRead('mine-1');

      verifyNever(() => realtime.markRead(messageId: any(named: 'messageId')));
    });

    test('skips already-read messages', () async {
      await openRideChannel();
      final read = serverMessage(
        id: 'other-1',
        senderId: _otherId,
        text: 'hi',
        readAt: DateTime.now().toUtc(),
      );
      incomingCtrl.add(read);
      await Future<void>.delayed(Duration.zero);

      await controller.markRead('other-1');

      verifyNever(() => realtime.markRead(messageId: any(named: 'messageId')));
    });

    test('fires socket markRead and stamps readAt on success', () async {
      await openRideChannel();
      final unread = serverMessage(
        id: 'other-2',
        senderId: _otherId,
        text: 'hi',
      );
      incomingCtrl.add(unread);
      await Future<void>.delayed(Duration.zero);

      final stamp = DateTime.utc(2026, 1, 1, 12, 30);
      when(() => realtime.markRead(messageId: any(named: 'messageId')))
          .thenAnswer((_) async => stamp);

      await controller.markRead('other-2');

      verify(() => realtime.markRead(messageId: 'other-2')).called(1);
      expect(controller.currentMessages.single.readAt, stamp);
    });

    test('falls back to REST on ackTimeout', () async {
      await openRideChannel();
      final unread = serverMessage(
        id: 'other-3',
        senderId: _otherId,
        text: 'hi',
      );
      incomingCtrl.add(unread);
      await Future<void>.delayed(Duration.zero);

      when(() => realtime.markRead(messageId: any(named: 'messageId')))
          .thenThrow(
        const ChatRealtimeException(
          code: ChatErrorCodes.ackTimeout,
          message: 'timed out',
        ),
      );
      final stamp = DateTime.utc(2026, 1, 1, 12, 31);
      when(() => rest.markRead(any())).thenAnswer((_) async => stamp);

      await controller.markRead('other-3');

      verify(() => rest.markRead('other-3')).called(1);
      expect(controller.currentMessages.single.readAt, stamp);
    });
  });

  group('outbox restore', () {
    test('replays previously-failed sends as ghost bubbles on open', () async {
      // Pre-seed the outbox as if a prior session crashed mid-send.
      await outbox.upsert(
        ChatOutboxItem(
          tempId: 'tmp_persisted',
          channelKey: 'ride:$_bookingId',
          message: 'I will be back',
          queuedAt: DateTime.utc(2026, 1, 1, 9),
          attemptCount: 2,
        ),
      );

      await openRideChannel();

      expect(controller.currentMessages, hasLength(1));
      expect(controller.currentMessages.single.id, 'tmp_persisted');
      expect(controller.currentMessages.single.message, 'I will be back');
    });

    test('dispose preserves account-scoped rows for a replacement controller',
        () async {
      await outbox.upsert(
        ChatOutboxItem(
          tempId: 'tmp_replacement_owned',
          channelKey: 'ride:$_bookingId',
          message: 'keep me',
          queuedAt: DateTime.utc(2026, 1, 1, 10),
        ),
      );
      await openRideChannel();

      await controller.dispose();

      expect(
        (await outbox.readForChannel('ride:$_bookingId'))
            .map((item) => item.tempId),
        ['tmp_replacement_owned'],
      );
    });
  });

  group('typing — outbound notifyTyping', () {
    test('emits chat:typing(true) on the first call from idle', () async {
      await openRideChannel();
      controller.notifyTyping(true);
      verify(() => realtime.sendTyping(isTyping: true)).called(1);
    });

    test('debounces a second true call within the 3 s window', () async {
      await openRideChannel();
      controller.notifyTyping(true);
      controller.notifyTyping(true);
      controller.notifyTyping(true);
      verify(() => realtime.sendTyping(isTyping: true)).called(1);
    });

    test('re-emits chat:typing(true) once the 3 s debounce window elapses', () {
      fakeAsync((async) {
        controller.openChannel(ChatBookingType.ride, _bookingId);
        async.elapse(const Duration(milliseconds: 50));
        controller.notifyTyping(true);
        async.elapse(const Duration(seconds: 1));
        controller.notifyTyping(true); // suppressed (within 3 s)
        async.elapse(const Duration(seconds: 2, milliseconds: 100));
        // Now > 3 s since the first emit; this call extends the idle
        // timer AND is eligible to re-emit because the heartbeat fence
        // has expired.
        controller.notifyTyping(true);
        async.flushTimers();
      });
      verify(() => realtime.sendTyping(isTyping: true)).called(2);
    });

    test('explicit notifyTyping(false) emits chat:typing(false)', () async {
      await openRideChannel();
      controller.notifyTyping(true);
      controller.notifyTyping(false);
      verify(() => realtime.sendTyping(isTyping: true)).called(1);
      verify(() => realtime.sendTyping(isTyping: false)).called(1);
    });

    test(
        'idle timer auto-emits chat:typing(false) 3 s after the '
        'last keystroke', () {
      fakeAsync((async) {
        controller.openChannel(ChatBookingType.ride, _bookingId);
        async.elapse(const Duration(milliseconds: 50));
        controller.notifyTyping(true);
        async.elapse(const Duration(seconds: 4));
      });
      verify(() => realtime.sendTyping(isTyping: true)).called(1);
      verify(() => realtime.sendTyping(isTyping: false)).called(1);
    });

    test('does not emit when notifyTyping(false) is called from idle',
        () async {
      await openRideChannel();
      controller.notifyTyping(false);
      verifyNever(
        () => realtime.sendTyping(isTyping: any(named: 'isTyping')),
      );
    });
  });

  group('typing — inbound peerTypingStream', () {
    test('emits true when the peer starts typing in the active channel',
        () async {
      await openRideChannel();
      final emissions = <bool>[];
      final sub = controller.peerTypingStream.listen(emissions.add);
      addTearDown(sub.cancel);

      typingCtrl.add(
        const ChatTypingUpdate(
          bookingType: ChatBookingType.ride,
          bookingId: _bookingId,
          userId: _otherId,
          isTyping: true,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(emissions, [true]);
    });

    test('ignores updates whose userId matches the local user', () async {
      await openRideChannel();
      final emissions = <bool>[];
      final sub = controller.peerTypingStream.listen(emissions.add);
      addTearDown(sub.cancel);

      typingCtrl.add(
        const ChatTypingUpdate(
          bookingType: ChatBookingType.ride,
          bookingId: _bookingId,
          userId: _selfId,
          isTyping: true,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(emissions, isEmpty);
    });

    test(
        'ignores updates that target a different booking than the '
        'one currently open', () async {
      await openRideChannel();
      final emissions = <bool>[];
      final sub = controller.peerTypingStream.listen(emissions.add);
      addTearDown(sub.cancel);

      typingCtrl.add(
        const ChatTypingUpdate(
          bookingType: ChatBookingType.artisanJob,
          bookingId: 'unrelated',
          userId: _otherId,
          isTyping: true,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(emissions, isEmpty);
    });

    test('emits false when the peer explicitly stops typing', () async {
      await openRideChannel();
      final emissions = <bool>[];
      final sub = controller.peerTypingStream.listen(emissions.add);
      addTearDown(sub.cancel);

      typingCtrl.add(
        const ChatTypingUpdate(
          bookingType: ChatBookingType.ride,
          bookingId: _bookingId,
          userId: _otherId,
          isTyping: true,
        ),
      );
      typingCtrl.add(
        const ChatTypingUpdate(
          bookingType: ChatBookingType.ride,
          bookingId: _bookingId,
          userId: _otherId,
          isTyping: false,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(emissions, [true, false]);
    });

    test(
        'auto-clears when the peer sends a message — they are done '
        'typing if they hit send', () async {
      await openRideChannel();
      final emissions = <bool>[];
      final sub = controller.peerTypingStream.listen(emissions.add);
      addTearDown(sub.cancel);

      typingCtrl.add(
        const ChatTypingUpdate(
          bookingType: ChatBookingType.ride,
          bookingId: _bookingId,
          userId: _otherId,
          isTyping: true,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      incomingCtrl.add(
        serverMessage(
          id: 'srv-final',
          senderId: _otherId,
          text: 'sent',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(emissions, [true, false]);
    });
  });
}
